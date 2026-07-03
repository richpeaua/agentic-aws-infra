output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "read_role_arn" {
  description = "Role ARN for PR plan jobs (read-only). Store as GitHub secret READ_ROLE_ARN."
  value       = aws_iam_role.read.arn
}

output "dev_apply_role_arn" {
  description = "Role ARN for dev applies. Store as GitHub secret DEV_APPLY_ROLE_ARN."
  value       = aws_iam_role.dev_apply.arn
}

output "prod_apply_role_arn" {
  description = "Role ARN for prod applies. Store as GitHub secret PROD_APPLY_ROLE_ARN."
  value       = aws_iam_role.prod_apply.arn
}
