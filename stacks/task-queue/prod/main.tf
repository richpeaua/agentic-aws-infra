# Thin per-environment root for the task-queue stack, prod environment.
# It supplies the provider (with default_tags); the module call is removed for
# teardown (see issue #80) and restored in the redeploy.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Stack       = "task-queue"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# The task_queue module call has been removed to destroy the prod SQS resources
# (main work queue and DLQ) through the pipeline (see issue #80). Emptying the
# root turns the plan into a destroy that CI applies on merge. The root
# scaffolding (backend, versions, variables) is kept intact for the redeploy.
