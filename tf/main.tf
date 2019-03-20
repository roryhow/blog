# Create the bucket
resource "aws_s3_bucket" "blog_bucket"  {
  bucket = "${var.bucket}"
  region = "${var.region}"
  acl    = "public-read"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadForGetBucketObjects",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${var.bucket}/*"
  }]
}
EOF
  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  tags = {
    Name        = "${var.bucket}"
    Environment = "${var.env}"
  }
}

# create the codebuild setup
module "build" {
  source = "git::https://github.com/roryhow/terraform-aws-codebuild.git?ref=master"
  namespace = "roryhow-blog"
  name = "ci"
  stage = "${var.env}"

  # https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-available.html
  build_image = "aws/codebuild/ubuntu-base:14.04"

  artifact_type = "NO_ARTIFACTS"
  aws_region = "eu-central-1"
  source_type = "GITHUB"
  github_token = "${var.gh_token}"
  badge_enabled = true
  cache_bucket_suffix_enabled = "false"
  cache_enabled = "false"
  source_location = "https://github.com/roryhow/blog"
}

resource "aws_codebuild_webhook" "blog_hook" {
  project_name = "${module.build.project_name}"
  branch_filter = "${var.branch_filter}"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "cloudfront origin access identity"
}

# Create cloudfront distribution
resource "aws_cloudfront_distribution" "blog_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.blog_bucket.bucket_domain_name}"
    origin_id   = "${var.bucket}-${var.env}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
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
