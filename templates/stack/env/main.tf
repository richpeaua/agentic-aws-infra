# Thin per-environment root for the __STACK__ stack, __ENV__ environment.
# It supplies the provider (with default_tags) and calls the shared module.

data "aws_caller_identity" "current" {}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "__STACK__"
      Environment = "__ENV__"
      ManagedBy   = "terraform"
    }
  }
}

module "__STACK__" {
  source = "../../../modules/__STACK__"

  project     = var.project
  stack       = "__STACK__"
  environment = "__ENV__"
  account_id  = data.aws_caller_identity.current.account_id
}
