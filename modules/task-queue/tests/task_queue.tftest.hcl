# Native `terraform test` for the task-queue module.
# Mocked AWS provider so it runs offline in CI. Assertions target values known
# at plan time (mock_provider makes computed attributes deterministic).
# Run: terraform -chdir=modules/task-queue test

mock_provider "aws" {}

variables {
  project     = "test"
  stack       = "task-queue"
  environment = "dev"
}

run "naming_follows_convention" {
  command = plan

  assert {
    condition     = aws_sqs_queue.main.name == "test-task-queue-dev"
    error_message = "main queue name must be <project>-<stack>-<environment>"
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "test-task-queue-dev-dlq"
    error_message = "dead-letter queue name must append -dlq"
  }
}

run "encryption_at_rest" {
  command = plan

  assert {
    condition     = aws_sqs_queue.main.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    error_message = "both queues must have SSE-SQS enabled"
  }
}

run "redrive_targets_dlq" {
  # apply (offline via the mock provider) so the DLQ's computed ARN, which is
  # embedded in the redrive policy, is resolved.
  command = apply

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq.arn
    error_message = "main queue redrive policy must point at the dead-letter queue"
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.main.redrive_policy).maxReceiveCount == 5
    error_message = "maxReceiveCount must be 5"
  }
}
