locals {
  create_efs = length(var.volume) > 0
  mount_path = "/mnt/${var.volume}"
}

# Get default VPC and subnets
data "aws_vpc" "default" {
  count      = local.create_efs ? 1 : 0
  default    = true
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

# Create security group for EFS
resource "aws_security_group" "efs" {
  count       = local.create_efs ? 1 : 0
  name        = "${var.name}-efs-sg"
  description = "Allow NFS traffic from Lambda to EFS"
  vpc_id      = data.aws_vpc.default[0].id

  ingress {
    description     = "NFS from Lambda"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-efs-sg"
  }
}

# Create security group for Lambda
resource "aws_security_group" "lambda" {
  count       = local.create_efs ? 1 : 0
  name        = "${var.name}-lambda-sg"
  description = "Allow Lambda to access EFS"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-lambda-sg"
  }
}

# Create EFS file system
resource "aws_efs_file_system" "this" {
  count          = local.create_efs ? 1 : 0
  creation_token = "${var.name}-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.name}-efs"
  }
}

# Create mount targets in all available subnets
resource "aws_efs_mount_target" "this" {
  count           = local.create_efs ? length(data.aws_subnets.default[0].ids) : 0
  file_system_id  = aws_efs_file_system.this[0].id
  subnet_id       = data.aws_subnets.default[0].ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# Create access point with proper directory permissions
resource "aws_efs_access_point" "this" {
  count          = local.create_efs ? 1 : 0
  file_system_id = aws_efs_file_system.this[0].id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/${var.volume}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.name}-access-point"
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
  name        = "${var.name}-efs-access"
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
        Resource = aws_efs_file_system.this[0].arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.this[0].arn
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