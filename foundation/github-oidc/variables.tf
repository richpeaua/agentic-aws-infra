variable "project" {
  description = "Project name, applied as a tag to every resource."
  type        = string
  default     = "aws-agentic-infra"
}

variable "environment" {
  description = "Environment tag value for these shared foundational resources."
  type        = string
  default     = "shared"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repo."
  type        = string
  default     = "richpeaua"
}

variable "github_repo" {
  description = "GitHub repository name that CI runs from."
  type        = string
  default     = "agentic-aws-infra"
}
