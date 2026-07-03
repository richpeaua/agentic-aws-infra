output "website_endpoint" {
  description = "URL of the static website."
  value       = module.static_site.website_endpoint
}

output "bucket_name" {
  description = "Name of the website bucket."
  value       = module.static_site.bucket_name
}
