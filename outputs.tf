output "lambda_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.function.arn
}

output "lambda_url" {
  description = "URL of the Lambda function (if public access is enabled)"
  value       = local.create_function_url ? aws_lambda_function_url.function_url[0].function_url : ""
}