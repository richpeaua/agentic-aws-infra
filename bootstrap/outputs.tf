output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Use this as the backend bucket for every stack."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_region" {
  description = "Region of the state bucket."
  value       = var.region
}

output "budget_name" {
  description = "Name of the monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}
