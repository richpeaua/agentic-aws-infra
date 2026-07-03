terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "static-site"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# ---------------------------------------------------------------------------
# Static website bucket
#
# This intentionally allows public read access so the site is reachable at
# the S3 website endpoint. This is a demo/proof-of-loop stack; for anything
# real, front it with CloudFront + Origin Access Control instead.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = var.site_bucket_name
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.public_read.json

  # The policy cannot be applied until public access is allowed.
  depends_on = [aws_s3_bucket_public_access_block.site]
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid       = "PublicReadGetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content      = "<!doctype html><html><head><meta charset=\"utf-8\"><title>${var.project}</title></head><body><h1>It works.</h1><p>Provisioned by the agentic AWS infra workflow.</p></body></html>"
  content_type = "text/html"
}
