output "lambda_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.function.arn
}

output "lambda_url" {
  description = "URL of the Lambda function (if public access is enabled)"
  value       = local.create_function_url ? aws_lambda_function_url.function_url[0].function_url : ""
}

output "efs_filesystem_id" {
  description = "ID of the EFS file system (if using EFS)"
  value       = local.use_efs ? local.file_system_id : ""
}

output "efs_access_point_id" {
  description = "ID of the EFS access point (if using EFS)"
  value       = local.use_efs ? local.access_point_id : ""
}

output "efs_mount_path" {
  description = "Path where the EFS volume is mounted (if using EFS)"
  value       = local.use_efs ? local.volume_path : ""
}

output "efs_is_reused" {
  description = "Whether an existing EFS file system was reused"
  value       = local.has_existing_efs
}