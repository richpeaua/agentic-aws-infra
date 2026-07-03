# Partial backend configuration. Supply the sensitive bucket at init time:
#   terraform init -backend-config=backend.tfbackend
# In CI the bucket is passed via -backend-config="bucket=${STATE_BUCKET}".
terraform {
  backend "s3" {
    key          = "stacks/static-site/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
