output "queue_url" {
  description = "URL of the main work queue."
  value       = module.task_queue.queue_url
}

output "queue_arn" {
  description = "ARN of the main work queue."
  value       = module.task_queue.queue_arn
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = module.task_queue.dlq_arn
}
