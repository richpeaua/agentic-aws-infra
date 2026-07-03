# Partial backend configuration. The sensitive `bucket` value is supplied at
# init time and kept out of version control:
#   terraform init -backend-config=backend.tfbackend
# The git-ignored backend.tfbackend file holds: bucket = "<state-bucket-name>"
terraform {
  backend "s3" {
    key          = "foundation/github-oidc/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
