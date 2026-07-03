locals {
  # Base name for this stack's resources. Include the environment to avoid
  # collisions between dev and prod in the shared account. SQS queue names are
  # unique per account and region, so no account-id suffix is needed.
  name = "${var.project}-${var.stack}-${var.environment}"
}

# A dead-letter queue captures messages that fail processing repeatedly.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name}-dlq"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days
}

# The main work queue. Messages that exceed maxReceiveCount are moved to the DLQ.
resource "aws_sqs_queue" "main" {
  name                       = local.name
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 345600 # 4 days
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}
