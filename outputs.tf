output "lambda_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.function.arn
}

output "lambda_url" {
  description = "URL of the Lambda function (if public access is enabled)"
  value       = local.create_function_url ? aws_lambda_function_url.function_url[0].function_url : ""
}

output "queue_arn" {
  description = "ARN of the SQS queue (if worker mode is enabled)"
  value       = local.create_queue ? aws_sqs_queue.worker_queue[0].arn : ""
}

output "queue_name" {
  description = "Name of the SQS queue (if worker mode is enabled)"
  value       = local.create_queue ? aws_sqs_queue.worker_queue[0].name : ""
}