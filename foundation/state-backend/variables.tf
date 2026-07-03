variable "project" {
  description = "Project name, applied as a tag to every resource."
  type        = string
  default     = "aws-agentic-infra"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "shared"
}

variable "region" {
  description = "Default AWS region."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket that stores Terraform state."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly account spend limit in USD that triggers budget alerts."
  type        = string
  default     = "50"
}

variable "budget_alert_email" {
  description = "Email address that receives budget alerts."
  type        = string
}
