---
title: "Deploying a Wicked-Fast Static Site with Terraform, S3, Codebuild & Cloudfront"
date: 2019-03-24
tags: [ "aws", "terraform", "s3", "codebuild", "cloudfront"]
---

# How We Got Here
I come from a background of trying to shoehorn functional programming into everything that I do. So naturally, the previous iteration of this site was a vastly overcomplex Clojure(Script) monorepo that served a client side rendered [re-frame](https://github.com/Day8/re-frame) application. You can actually find the codebase [here, if you're interested](https://github.com/roryhow/arg-homepage).

Don't get me wrong, I love re-frame and the Clojure ecosystem, but it meant I ended up creating a site that became far too irritating to turn into a proper blog. So, I made the decision to retire that site, and start fresh.

This leads me into what I wanted to learn from creating a new site.

# Requirements
- Use AWS. I come from an Azure & Heroku background, so I felt it was about time to bring my head out from the sand and acknowledge AWS as a popular PaaS.
- Manage as much of the infrastructure as possible using IaC (I chose [Terraform](https://terraform.io) for this, but I'm sure there are alternatives that would be just as fine).
  - In addition to this, make it as easy as possible to spin off an entirely new environment by changing a single environment variable (i.e `var.env`)
- Avoid React. I usually do some level of React development on a daily basis, so I don't really want to bring that into my spare time. I decided to go with Hugo to solve this, but I won't go into the details of using Hugo in this post.
- Keep everything as cheap as possible, ideally in the free-tier of AWS.

# Implementation
## S3
First, I wanted to create an S3 bucket that has website hosting capabilities. This is pretty easy using the `aws_s3_bucket` data source.

```ruby
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

```

Here we enable our bucket as a website and allow public reads with a given policy.
If you were ok with not having a custom domain (with this configuration), you could build your static site (for my site, using the command `hugo`), and sync the generated static files with the s3 bucket using the aws cli on your local machine (for me, this would be `aws s3 sync --sse --delete ./public/ s3://${bucket_name}` where `${bucket_name}` is the name of the generated S3 bucket).

But... this is a bit too easy for my liking. I don't want to have to build the site manually on my machine and sync it with the bucket afterwards (oh, the horror!). Thankfully [AWS CodeBuild](https://aws.amazon.com/codebuild/) can solve this problem neatly for me.

## CodeBuild
Here is where things start to get a little bit tricky. I decided to base my approach from a Terraform module called [terraform-aws-codebuild](https://github.com/cloudposse/terraform-aws-codebuild). However, I didn't need all of it's functionality so I spliced the bits that I needed and threw them directly into my own config.

```ruby
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
  name   = "roryhow-blog-codebuild-policy-${var.env}"
  path   = "/service-role/"
  policy = "${data.aws_iam_policy_document.permissions.json}"
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

```
I'll summarise the functionality of this code snippet:

- In my `buildspec.yaml`, I sync with the bucket as a post-install script, so I need to ensure that our CodeBuild service has the correct permissions to be able to do this.
  - So, we create a new policy that allows us access to the S3 bucket that we would like to sync with, and assign this to our CodeBuild service role. This means that when our `buildspec.yaml` runs a command such as `aws s3 sync --sse --delete ./public/ s3://$BUCKET_NAME`, this happens successfully.
  - We then link this to our `aws_codebuild_project` by supplying the role ARN in the `service_role` field.
  - Due to this approach, we don't actually need any artifacts to be created by our CodeBuild service, so we can specify `NO_ARTIFACTS` as our artifact type.
- Then, we need to ensure that our codebuild service has the correct access rights to the GitHub project (you'll need to do this if your repository is private). Here, we do this by supplying the GitHub token as an environment variable to the `aws_codebuild_project.build` resource.
  - We then specify the repository URL as a source location, and we should be good to go.
- Finally, we want our codebuild to run _only_ on changes to a specific given branch (here specified by the `branch_filter` environment variable).
  - This is done by creating a `aws_codebuild_webhook` resource, which ties together the codebuild project name, and the branch that we want to filter over.

Phew - I'm glad that's over. Now, we just need to make this s3 bucket publicly available via a CDN, using [CloudFront!](https://aws.amazon.com/cloudfront/)

## CloudFront
We want to make the site as capable as we can to deal with large amounts of traffic, as well as making it accessible on a global scale, _and_ minimising request times. Here, we use the `aws_cloudfront_distribution` module for the `aws` provider.

```ruby
resource "aws_cloudfront_distribution" "blog_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.blog_bucket.website_endpoint}"
    origin_id   = "${var.bucket}-${var.env}"
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "https-only"
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
```

There's a few notable parts of this snippet, so lets go over them:

- First, we define the origin domain name as the domain name of the bucket that we created earlier. We also define an origin ID for this (NOTE: your `default_cache_behavior.target_origin_id` *must* equal your `origin.origin_id`, otherwise when you run `terraform apply`, it will fail).
- Next, we define some aliases for your site (that is, these domains will point to this CDN). Here, I've defined these as environment variables, as my domains are held with a third party.
- Then, I want for my sites to be accessible over HTTPS, so I need to supply a valid certificate. For AWS, your cetificates need to be held in the `us-east-1` region. For this reason and the fact that my domains are held elsewhere, I decided to do this using the AWS console directly, and then reference the ARN as an environment variable (sorry, I know this is cheating, but only a little bit).
- Finally, I set my `ssl_support_method` as `"sni-only"`. This is because we don't need a dedicated IP for our CloudFront distribution (and it is also eyewateringly expensive at $600 per month).

Once this is done, you can run `terraform apply`, type `yes` when prompted and (hopefully) see lots of lines of green text showing you that your resources have been created. If this is the case, then congratulations, you made it! 🎉🎉🎉

## Some Extra Legwork (...sorry)
Once this is done, you won't (yet) be able to access your site using your defined aliases. This is because you need to create a CNAME record for your domain, pointing to the domain name of your created CloudFront resource. Once some time has passed and the DNS has resolved, then you should be able to access your site from your very own domain.

# Future Options

This was a ton of fun for me to work out, and I'm really happy with the result. This site is fast, deploys automatically from my git repository, and I can spin off a new environment by tweaking some environment variables.

So... how can I do this better?

- Of course, this still requires a little bit of legwork from me if I want to make a new environment (in the form of editing DNS records). Of course, I could import my domains into [AWS Route 53](https://aws.amazon.com/route53/), and manage things this way, but this introduces some headaches that I decided to not bother with right now.
- I could manage the SSL certificate creation via Terraform also, but this is unavoidably manual, as we need to be able to verify ownership of the domain through some non-Terraform means (since my domains are held elsewhere).
- My management of variables passed in is a bit haphazard, so there's still a couple steps that need to be taken before I can really claim that you can spin off a new environment by changing a single enviroment variable.
- Right now I'm running Terraform locally. Of course, this wouldn't fly in a _proper_ production environment, so it would be nice to sort out an approach of running my Terraform script automatically on changes to my git repository. This way, the `tf/` folder of my master branch can act as a "living" version of the infrastructure that is currently deployed.


# Conclusion

And there you have it! A completely overkill infrastructure for a very simple static site, managed (almost) entirely via Terraform, and it all stays within the free tier of AWS (as long as the CDN isn't too busy 😉) You can find the [full source code of this site, here](https://github.com/roryhow/blog). 

If you have any tips or suggestions (I'm still pretty new to Terraform and AWS as a whole), please feel free to get in contact with me on [my twitter](https://twitter.com/roryhow). Thanks for reading!

