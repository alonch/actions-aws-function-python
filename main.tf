locals {
  function_name       = "${var.name}-${random_id.suffix.hex}"
  lambda_handler      = "${replace(replace(var.entrypoint_file, "/", "."), ".py", "")}.${var.entrypoint_function}"
  runtime             = "python${var.python_version}"
  lambda_architecture = var.arm ? ["arm64"] : ["x86_64"]

  # EFS configuration
  create_efs = length(var.volume) > 0
  mount_path = length(var.volume_path) > 0 ? var.volume_path : "/mnt/${var.volume}"

  # Network configuration - use provided network or fall back to default
  use_custom_network = length(var.vpc_id) > 0 && length(var.subnet_private_ids) > 0
  vpc_id = local.use_custom_network ? var.vpc_id : (local.create_efs ? data.aws_vpc.default[0].id : "")
  subnet_ids = local.use_custom_network ? split(",", var.subnet_private_ids) : (local.create_efs ? data.aws_subnets.default[0].ids : [])

  # Debug output - will show in Terraform logs
  debug_arn_received = "EFS Access Point ARN received: ${var.efs_access_point_arn}"

  # Fix ARN format that's missing region and account
  # Example of malformed: arn:aws:elasticfilesystem::12345:access-point/fsap-123
  # Example of correct: arn:aws:elasticfilesystem:us-west-2:12345:access-point/fsap-123
  formatted_arn = length(var.efs_access_point_arn) > 0 ? (
    # Check common malformation pattern with :: (missing region)
    can(regex("arn:aws:elasticfilesystem::\\d+:access-point/fsap-[a-f0-9]+", var.efs_access_point_arn)) ?
      replace(var.efs_access_point_arn, "arn:aws:elasticfilesystem::", "arn:aws:elasticfilesystem:${data.aws_region.current.name}:") :
      var.efs_access_point_arn
  ) : ""

  # Debug output - will show in Terraform logs
  debug_arn_formatted = "EFS Access Point ARN formatted: ${local.formatted_arn}"

  # Parse environment variables from YAML
  env_vars = length(var.env) > 0 ? yamldecode(var.env) : {}

  # Parse permissions from YAML
  permissions_map = length(var.permissions) > 0 ? yamldecode(var.permissions) : {}

  # Services and their corresponding policies
  services = {
    s3 = {
      read  = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
    }
    dynamodb = {
      read  = ["arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"]
    }
    sqs = {
      read  = ["arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"]
      write = ["arn:aws:iam::aws:policy/AmazonSQSFullAccess"]
    }
  }

  # Base policies to always include - removed from dynamic attachment
  # base_policies = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]

  # SQS policy for worker mode
  worker_policies = var.worker == "true" ? ["arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"] : []

  # Process permissions to get list of policy ARNs
  service_policies = length(var.permissions) > 0 ? flatten([
    for service, access_level in local.permissions_map :
    lookup(local.services, service, null) != null ?
      lookup(lookup(local.services, service, {}), access_level, []) : []
  ]) : []

  # Combine all policies EXCEPT the basic execution role
  policy_arns = distinct(concat(local.worker_policies, local.service_policies))

  # Determine if we should create a function URL
  create_function_url = length(var.allow_public_access) > 0
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Create a zip archive from the artifacts directory or from the entrypoint file
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source_dir  = length(var.artifacts) > 0 ? var.artifacts : null
  source_file = length(var.artifacts) == 0 ? var.entrypoint_file : null
}

# Create the IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.name}-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Keep the basic Lambda execution policy as a separate attachment
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Dynamic policy attachments for additional policies
resource "aws_iam_role_policy_attachment" "lambda_policies" {
  for_each = { for idx, arn in local.policy_arns : idx => arn }

  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
}

# Create the Lambda function
resource "aws_lambda_function" "function" {
  function_name    = local.function_name
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  role             = aws_iam_role.lambda_role.arn
  handler          = local.lambda_handler
  runtime          = local.runtime
  memory_size      = var.memory
  timeout          = var.timeout
  architectures    = local.lambda_architecture
  depends_on       = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_policies,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]

  environment {
    variables = local.env_vars
  }

  # VPC configuration for EFS
  dynamic "vpc_config" {
    for_each = local.create_efs ? [1] : []
    content {
      subnet_ids         = local.subnet_ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  # EFS configuration
  dynamic "file_system_config" {
    for_each = local.create_efs && length(local.formatted_arn) > 0 ? [1] : []
    content {
      # arn is provided directly from GitHub Action output via TF_VAR
      arn              = local.formatted_arn
      local_mount_path = local.mount_path
    }
  }

  # Increase timeout for functions with EFS to at least 10 seconds
  # as Lambda cold starts with EFS can take longer
  lifecycle {
    precondition {
      condition     = !local.create_efs || var.timeout >= 10
      error_message = "When using EFS volumes, timeout must be at least 10 seconds to accommodate for potential cold starts."
    }
  }
}

# Create function URL if public access is allowed
resource "aws_lambda_function_url" "function_url" {
  count              = local.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.function.function_name
  authorization_type = "NONE"

  # cors {
  #  allow_origins = ["*"]
  #  allow_methods = ["GET", "POST"]
  #  allow_headers = ["*"]
  #  max_age       = 86400
  #}
}

# VPC and subnet data sources for fallback to default VPC
data "aws_vpc" "default" {
  count   = local.create_efs && !local.use_custom_network ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = local.create_efs && !local.use_custom_network ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get current region
data "aws_region" "current" {}