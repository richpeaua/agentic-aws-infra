variable "project" {
  description = "Project name; applied as a tag."
  type        = string
}

variable "stack" {
  description = "Stack name; applied as a tag and used as the base for resource names."
  type        = string
}

variable "environment" {
  description = "Environment (dev or prod); in tags and resource names."
  type        = string
}
