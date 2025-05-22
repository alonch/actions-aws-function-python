locals {
  function_name       = "${var.name}-${random_id.suffix.hex}"
  lambda_handler      = "${replace(replace(var.entrypoint_file, "/", "."), ".py", "")}.${var.entrypoint_function}"
  runtime             = "python${var.python_version}"
  lambda_architecture = var.arm ? ["arm64"] : ["x86_64"]

  # EFS configuration
  create_efs = length(var.volume) > 0
  mount_path = length(var.volume_path) > 0 ? var.volume_path : "/mnt/${var.volume}"

  # Parse environment variables from YAML
  env_vars = length(var.env) > 0 ? yamldecode(var.env) : {}

  # Parse permissions from YAML
  permissions = length(var.permissions) > 0 ? yamldecode(var.permissions) : {}

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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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
  depends_on       = [aws_iam_role_policy_attachment.lambda_basic,
                     aws_iam_role_policy_attachment.lambda_vpc_access]

  environment {
    variables = local.env_vars
  }

  # VPC configuration for EFS
  dynamic "vpc_config" {
    for_each = local.create_efs ? [1] : []
    content {
      subnet_ids         = data.aws_subnets.default[0].ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  # EFS configuration
  dynamic "file_system_config" {
    for_each = local.create_efs ? [1] : []
    content {
      # arn is provided directly from GitHub Action output via TF_VAR
      arn              = var.efs_access_point_arn
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