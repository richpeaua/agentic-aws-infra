variable "project" {
  description = "Project name, applied as a tag to every resource."
  type        = string
  default     = "aws-agentic-infra"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region for the stack."
  type        = string
  default     = "us-east-1"
}

variable "site_bucket_name" {
  description = "Globally unique name for the website S3 bucket."
  type        = string
}
