output "website_endpoint" {
  description = "URL of the static website."
  value       = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}

output "bucket_name" {
  description = "Name of the website bucket."
  value       = aws_s3_bucket.site.id
}
