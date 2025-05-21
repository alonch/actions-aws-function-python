locals {
  function_name       = var.name
  lambda_handler      = "${replace(var.entrypoint_file, ".py", "")}.${var.entrypoint_function}"
  runtime             = "python${var.python_version}"
  lambda_architecture = var.arm ? ["arm64"] : ["x86_64"]

  # Parse environment variables from YAML
  env_vars = length(var.env) > 0 ? yamldecode(var.env) : {}

  # Parse permissions from YAML
  permissions = length(var.permissions) > 0 ? yamldecode(var.permissions) : {}

  # Determine if we should create a function URL
  create_function_url = length(var.allow_public_access) > 0
}

# Create a zip archive from the artifacts directory or from the entrypoint file
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  dynamic "source" {
    for_each = length(var.artifacts) > 0 ? [1] : []
    content {
      dir = var.artifacts
    }
  }

  dynamic "source" {
    for_each = length(var.artifacts) == 0 ? [1] : []
    content {
      filename = basename(var.entrypoint_file)
      content  = file(var.entrypoint_file)
    }
  }
}

# Create the IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.function_name}-role"

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

  environment {
    variables = local.env_vars
  }
}

# Create function URL if public access is allowed
resource "aws_lambda_function_url" "function_url" {
  count              = local.create_function_url ? 1 : 0
  function_name      = aws_lambda_function.function.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
    max_age       = 86400
  }
}