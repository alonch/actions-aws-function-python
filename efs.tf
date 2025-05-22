# Get default VPC and subnets - still needed for Lambda VPC configuration
data "aws_vpc" "default" {
  count   = local.create_efs ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = local.create_efs ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Create security group for Lambda
resource "aws_security_group" "lambda" {
  count       = local.create_efs ? 1 : 0
  name        = "${var.name}-lambda-sg-${random_id.suffix.hex}"
  description = "Allow Lambda to access EFS"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-lambda-sg-${random_id.suffix.hex}"
  }
}

# Add necessary permissions to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  count      = local.create_efs ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Add EFS policy to Lambda role
resource "aws_iam_policy" "lambda_efs_access" {
  count       = local.create_efs ? 1 : 0
  name        = "${var.name}-efs-access-${random_id.suffix.hex}"
  description = "Allow Lambda to access EFS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "elasticfilesystem:AccessPointArn" = "arn:aws:elasticfilesystem:*:*:access-point/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_efs_access" {
  count      = local.create_efs ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_efs_access[0].arn
}