# Partial backend configuration. Supply the sensitive bucket at init time:
#   terraform init -backend-config=backend.tfbackend
# backend.tfbackend is git-ignored (the bucket name contains the account ID).
terraform {
  backend "s3" {
    key          = "stacks/task-queue/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
