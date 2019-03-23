---
title: "Deploying a wicked-fast static site with Terraform, S3, CodeBuild & CloudFront"
date: 2019-03-23T20:21:30+02:00
tags: [ "aws", "terraform", "s3", "codebuild", "cloudfront"]
---

# How We Got Here
I come from a background of trying to shoehorn functional programming into everything that I do. So naturally, the previous iteration of this site was a vastly overcomplex clojure(script) monorepo that served a client side rendered [re-frame](https://github.com/Day8/re-frame) application. You can actually find the codebase [here, if you're interested](https://github.com/roryhow/arg-homepage).

Don't get me wrong, I love re-frame and the Clojure ecosystem, but it meant I ended up creating a site that became far too irritating to turn into a proper blog. So, I made the decision to retire that site, and start fresh.

This leads me into what I wanted to learn from creating a new site.

# Requirements
- Use AWS. I come from an Azure & Heroku background, so I felt it was about time to bring my head out from the sand and acknowledge AWS as a popular PaaS.
- Manage as much of the infra as possible using IaC (I chose [Terraform](https://terraform.io) for this, but I'm sure there are alternatives that would be just as fine).
  - In addition to this, make it as easy as possible to spin off a new variable by changing a single environment variable (i.e `var.env`)
- Avoid React. I usually do some level of React development on a daily basis, so I don't really want to bring that into my spare time. I decided to go with Hugo to solve this, but I won't go into the details of using Hugo in this post.
- Keep everything as cheap as possible, ideally in the free-tier of AWS.

# Implementation
## S3
First, I wanted to create an S3 bucket that has website hosting capabilities. This is pretty easy using the `aws_s3_bucket` data source.

```ruby
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
```

Here we simply enable our bucket as a website and allow public reads with a policy.
If you were ok with not having a custom domain (with this configuration), you could build your static site (for my site, using the command `hugo`), and sync the generated static files with the s3 bucket using the aws cli on your local machine (for me, this would be `aws s3 sync --sse --delete ./public/ s3://${bucket_name}` where `${bucket_name}` is the name of the generated S3 bucket).

But... this is a bit too easy for my liking.

## Codebuild
Next, we want to trigger a Hugo build, and sync to our S3 bucket every time there is a change to the repository, on a specific branch. For this, I created a fork of a Terraform module named [terraform-aws-codebuild](https://github.com/roryhow/terraform-aws-codebuild). My use of the module is given below:

```ruby
module "build" {
  source = "git::https://github.com/roryhow/terraform-aws-codebuild.git?ref=master"
  namespace = "roryhow-blog"
  name = "ci"
  stage = "${var.env}"
  build_image = "aws/codebuild/ubuntu-base:14.04"
  artifact_type = "NO_ARTIFACTS"
  aws_region = "eu-central-1"
  source_type = "GITHUB"
  github_token = "${var.gh_token}"
  badge_enabled = true
  cache_bucket_suffix_enabled = "false"
  cache_enabled = "false"
  source_location = "${var.gh_repo}"
}

resource "aws_codebuild_webhook" "blog_hook" {
  project_name = "${module.build.project_name}"
  branch_filter = "${var.branch_filter}"
}
```

Here the heavy lifting of the resource creation is done entirely by the module. So I'd thoroughly recommend that you go through the source code (linked above). In summary, this creates a codebuild service that pulls from a given Github repository, with a supplied auth token.

Here, we are relying on the static site having a `buildspec.yaml` file defined in the repository root, so that the service knows what to do when it tries to build. You can find mine in the [repository for this blog](https://github.com/roryhow/blog).

One thing to note here is that I do not specify a build artifact. This is for the reason that after building, I run a command to sync the repository with my existing S3 bucket, therefore eliminating the need for a build artifact to be generated. Of course, this is fine for a small project, but we lose the ability to track build outputs through this method (so this might be something you want to keep in mind for your project).

Pne notable part of this snippet is the codebuild webhook, which pulls the project name from `module.build`, and attaches an environment variable which tells us what branch to listen for changes in.

Next, we want to roll this out over a CDN.

## Cloudfront
We want to make the site as capable as we can to deal with large amounts of traffic, as well as making it accessible on a global scale, _and_ minimising request times. Here, we use the `aws_cloudfront_distribution` module for the `aws` provider.

```ruby
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
```

There's a few notable parts of this snippet, so lets go over them:
- First, we define the origin domain name as the domain name of the bucket that we created earlier. We also define an origin ID for this (NOTE: your `default_cache_behavior.target_origin_id` *must* equal your `origin.origin_id`, otherwise when you run `terraform apply`, it will fail).
- Next, we define some aliases for your site (that is, these domains will point to this CDN). Here, I've defined these as environment variables, as my domains are held with a third party.
- Then, I want for my sites to be accessible over HTTPs, so I need to supply a valid certificate. For AWS, your cetificates need to be held in the `us-east-1` region. For this reason and the fact that my domains are held elsewhere, I decided to do this using the AWS console directly, and then reference the ARN as an environment variable (sorry, I know this is cheating... a little bit).
- Finally, I set my `ssl_support_method` as `"sni-only"`. This is because we don't need a dedicated IP for our CloudFront distribution (and it is also eyewateringly expensive at $600 per month).

Once this is done, you can run `terraform apply`, type `yes` and (hopefully) see lots of green texts showing you that your resources have been created. If this is the case, then congratulations, you made it! 🎉🎉🎉

## Some Extra Leg-work
Once this is done, you won't (yet) be able to access your site using your defined aliases. This is because you need to create a CNAME record for your domain, pointing to the domain name of your created AWS cloudfront CDN. Once some time has passed and the DNS has resolved, then you should be able to access your site from your very own domain.

# Future Options

This was a ton of fun for me to work out, and I'm really happy with the result. This site is fast, deploys automatically from my git repository, and I can spin off a new environment by tweaking some environment variables.

So... how can I do this better?

- Of course, this still requires a little bit of leg work from me if I want to make a new environment (in the form of editing DNS records). Of course, I could import my domains into AWS route 53, and manage things this way, but this introduces some headaches that I decided to not bother with right now.
- I also cut some corners by having the `buildspec.yml` live inside the code repository, rather than living within the terraform setup. This meams our build process is a little bit more tricky to set up.
- I also should define some environment variables for the codebuild process - so that we know which bucket to sync with after the build completes. Currently this would need to be done manually.

# Conclusion

And there you have it! A completely overkill infrastructure for a very simple static site, managed (almost) entirely via Terraform, and it all stays within the free tier of AWS (as long as the CDN isn't too busy 😉) You can find the [full source code of this site, here](https://github.com/roryhow/blog). If you have any tips or suggestions, please feel free to get in contact with my on [my twitter](https://twitter.com/roryhow)

