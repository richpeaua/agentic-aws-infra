# Native `terraform test` for the static-site module.
# Uses a mocked AWS provider so it runs offline in CI (no credentials, no real
# resources). Assertions target values known at plan time.
# Run: terraform -chdir=modules/static-site test

mock_provider "aws" {}

variables {
  project     = "test"
  stack       = "static-site"
  environment = "dev"
  account_id  = "123456789012"
}

run "naming_follows_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.site.bucket == "test-static-site-dev-123456789012"
    error_message = "bucket name must be <project>-<stack>-<environment>-<account_id>"
  }
}

run "website_and_content" {
  command = plan

  assert {
    condition     = aws_s3_bucket_website_configuration.site.index_document[0].suffix == "index.html"
    error_message = "website index document must be index.html"
  }

  assert {
    condition     = aws_s3_object.index.content_type == "text/html"
    error_message = "index object must be served as text/html"
  }
}

run "encryption_at_rest" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "bucket must have SSE-S3 (AES256) encryption at rest"
  }
}

run "public_access_is_intentional" {
  command = plan

  # This module is a deliberately public demo site; the public-access block is
  # permissive by design. The test documents that intent so a future tightening
  # is a conscious, test-breaking change rather than a silent one.
  assert {
    condition     = aws_s3_bucket_public_access_block.site.block_public_policy == false
    error_message = "public access block is expected to be permissive for this public demo site"
  }
}
