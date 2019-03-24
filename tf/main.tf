data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid = "PublicReadForGetBucketObjects"
    actions = [
      "s3:GetObject"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${var.bucket}/*",
    ]
  }
}

# Create the bucket
resource "aws_s3_bucket" "blog_bucket"  {
  bucket = "${var.bucket}"
  region = "${var.region}"
  acl    = "public-read"
  policy = "${data.aws_iam_policy_document.bucket_policy.json}"
  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  tags = {
    Name        = "${var.bucket}"
    Environment = "${var.env}"
  }
}

resource "aws_iam_role" "build_role" {
  name               = "roryhow-blog-codebuild-role-${var.env}"
  assume_role_policy = "${data.aws_iam_policy_document.role.json}"
}

data "aws_iam_policy_document" "role" {
  statement {
    sid = "WriteToS3ForCodeBuildService"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_policy" "build_policy" {
  name        = "roryhow-blog-codebuild-policy-${var.env}"
  description = "A policy to manage Hugo builds and syncing with S3 buckets"
  path        = "/service-role/"
  policy      = "${data.aws_iam_policy_document.permissions.json}"
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid = "WriteToS3ForCodeBuildService"

    actions = [
      "iam:PassRole",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ssm:GetParameters",
      "s3:*"
    ]

    effect = "Allow"

    resources = [
      "*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  policy_arn = "${aws_iam_policy.build_policy.arn}"
  role       = "${aws_iam_role.build_role.id}"
}

resource "aws_codebuild_project" "build" {
  name          = "roryhow-blog-${var.env}"
  service_role  = "${aws_iam_role.build_role.arn}"
  badge_enabled = true
  build_timeout = "60"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/ubuntu-base:14.04"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable = [
      {
        "name"  = "STAGE"
        "value" = "${var.env}"
      },
      {
        "name"  = "GITHUB_TOKEN"
        "value" = "${var.gh_token}"
      },
      {
        "name"  = "BUCKET_NAME"
        "value" = "${var.bucket}"
      }
    ]
  }

  source {
    type                = "GITHUB"
    location            = "${var.gh_repo}"
    report_build_status = true
  }
}

resource "aws_codebuild_webhook" "blog_hook" {
  project_name = "${aws_codebuild_project.build.name}"
  branch_filter = "${var.branch_filter}"
}

# Create cloudfront distribution
resource "aws_cloudfront_distribution" "blog_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.blog_bucket.website_endpoint}"
    origin_id   = "${var.bucket}-${var.env}"
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Rory How - Blog"
  default_root_object = "index.html"

  aliases = "${var.site_aliases}"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${var.bucket}-${var.env}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "${var.env}"
  }

  viewer_certificate {
    # sorry this will need to be static for now
    acm_certificate_arn = "${var.site_cert_arn}"
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}
