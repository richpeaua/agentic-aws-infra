variable "project" {
  description = "Project name; applied as a tag."
  type        = string
  default     = "aws-agentic-infra"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}
