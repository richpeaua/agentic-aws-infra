locals {
  # Base name for this stack's resources; environment included to avoid
  # dev/prod collisions in the shared account.
  name        = "${var.project}-${var.stack}-${var.environment}"
  bucket_name = "${local.name}-${var.account_id}"
}

# Static website bucket.
#
# This bucket is intentionally public: it serves a demo website directly from
# the S3 website endpoint. That intent is why the public-access checks below are
# waived. For anything non-demo, front a private bucket with CloudFront + OAC.
resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
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

# Public access is required for a public website. Waived deliberately.
resource "aws_s3_bucket_public_access_block" "site" {
  #checkov:skip=CKV_AWS_53:Intentionally public demo website served from S3
  #checkov:skip=CKV_AWS_54:Intentionally public demo website served from S3
  #checkov:skip=CKV_AWS_55:Intentionally public demo website served from S3
  #checkov:skip=CKV_AWS_56:Intentionally public demo website served from S3
  bucket = aws_s3_bucket.site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_read" {
  #checkov:skip=CKV_AWS_283:Intentionally public demo website; grants read-only s3:GetObject to anonymous users, consistent with the public-access-block waiver above
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

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.public_read.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content      = "<!doctype html><html><head><meta charset=\"utf-8\"><title>${local.name}</title></head><body><h1>It works.</h1><p>Stack ${var.stack}, environment ${var.environment}, provisioned through the GitOps pipeline.</p></body></html>"
  content_type = "text/html"
}
