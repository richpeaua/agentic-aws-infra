# Thin per-environment root for the task-queue stack, dev environment.
# It supplies the provider (with default_tags) and calls the shared module.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "task-queue"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "task_queue" {
  source = "../../../modules/task-queue"

  project     = var.project
  stack       = "task-queue"
  environment = "dev"
}
