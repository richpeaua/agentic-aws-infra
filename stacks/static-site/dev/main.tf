# Thin per-environment root for the static-site stack, dev environment.
# Supplies the provider (with default_tags) and calls the shared module.

data "aws_caller_identity" "current" {}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "static-site"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "static_site" {
  source = "../../../modules/static-site"

  project     = var.project
  stack       = "static-site"
  environment = "dev"
  account_id  = data.aws_caller_identity.current.account_id
}
