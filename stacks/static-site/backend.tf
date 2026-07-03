# ---------------------------------------------------------------------------
# Remote state backend for the static-site stack.
#
# Partial configuration. The sensitive `bucket` value is supplied at init time
# and kept out of version control:
#   terraform init -backend-config=backend.tfbackend
# The git-ignored backend.tfbackend file holds: bucket = "<state-bucket-name>"
#
# NOTE: this stack is refactored into modules/static-site + stacks/static-site/{dev,prod}
# in a later build phase.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    key          = "stacks/static-site/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
