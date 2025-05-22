locals {
  # Handle volume name specification
  volume_name = var.volume_name

  # Check if volume name is specified and if we have an existing EFS ID
  has_volume = local.volume_name != ""
  has_existing_efs = var.existing_efs_id != ""

  # Determine if we need to create a new EFS or use existing
  create_new_efs = local.has_volume && !local.has_existing_efs
  use_efs = local.has_volume

  # Set volume path based on volume name
  volume_path = var.volume_path != "" ? var.volume_path : (local.has_volume ? "/mnt/${local.volume_name}" : "")

  # Set file system ID based on whether we're using existing or new
  file_system_id = local.has_existing_efs ? var.existing_efs_id : (local.create_new_efs ? aws_efs_file_system.this[0].id : "")
  file_system_arn = local.has_existing_efs ? "arn:aws:elasticfilesystem:${data.aws_region.current[0].name}:${data.aws_caller_identity.current[0].account_id}:file-system/${var.existing_efs_id}" : (local.create_new_efs ? aws_efs_file_system.this[0].arn : "")

  # Use AWS CLI to get mount target ID, passed as environment variable
  mount_target_id = var.existing_mount_target_id
  has_mount_target = local.has_existing_efs && var.existing_mount_target_id != ""
}

# Get AWS region and account ID for ARN construction
data "aws_region" "current" {
  count = local.use_efs ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.use_efs ? 1 : 0
}

# Get existing EFS details if we're using an existing EFS
data "aws_efs_file_system" "existing" {
  count = local.has_existing_efs ? 1 : 0
  file_system_id = var.existing_efs_id
}

# Get default VPC and subnets
data "aws_vpc" "default" {
  count      = local.use_efs ? 1 : 0
  default    = true
}

data "aws_subnets" "default" {
  count = local.use_efs ? 1 : 0
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
  count       = local.create_new_efs ? 1 : 0
  name        = "${var.name}-efs-sg-${random_id.suffix.hex}"
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
    Name = "${var.name}-efs-sg-${random_id.suffix.hex}"
    "volume-name" = local.volume_name
  }
}

# Create security group for Lambda
resource "aws_security_group" "lambda" {
  count       = local.use_efs ? 1 : 0
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
    "volume-name" = local.volume_name
  }
}

# Create EFS file system (only if no existing one is provided)
resource "aws_efs_file_system" "this" {
  count          = local.create_new_efs ? 1 : 0
  creation_token = "${var.name}-efs-${random_id.suffix.hex}"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.name}-efs-${random_id.suffix.hex}"
    "volume-name" = local.volume_name
  }
}

# Find a mount target in the first availability zone
# This will help us determine if the mount targets exist already
data "aws_efs_file_system" "existing" {
  count = local.has_existing_efs ? 1 : 0
  file_system_id = var.existing_efs_id
}

# Look up a specific mount target if we have one
data "aws_efs_mount_target" "existing" {
  count = local.has_mount_target ? 1 : 0
  mount_target_id = local.mount_target_id
}

# Create mount targets in all available subnets (only for new EFS)
resource "aws_efs_mount_target" "this" {
  count           = local.create_new_efs ? length(data.aws_subnets.default[0].ids) : 0
  file_system_id  = aws_efs_file_system.this[0].id
  subnet_id       = data.aws_subnets.default[0].ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# Wait for EFS mount targets to become fully available
# This prevents the "not all are in the available life cycle state yet" error
resource "time_sleep" "wait_for_efs_mount_targets" {
  count           = local.create_new_efs ? 1 : 0
  depends_on      = [aws_efs_mount_target.this]
  create_duration = "90s"
}

# Create access point with proper directory permissions for new EFS
resource "aws_efs_access_point" "new" {
  count          = local.create_new_efs ? 1 : 0
  file_system_id = aws_efs_file_system.this[0].id
  depends_on     = [time_sleep.wait_for_efs_mount_targets]

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/${local.volume_name}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.name}-access-point-${random_id.suffix.hex}"
    "volume-name" = local.volume_name
  }
}

# Create access point for existing EFS
resource "aws_efs_access_point" "existing" {
  count          = local.has_existing_efs ? 1 : 0
  file_system_id = var.existing_efs_id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/${local.volume_name}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.name}-access-point-${random_id.suffix.hex}"
    "volume-name" = local.volume_name
  }
}

# Local to determine which access point to use
locals {
  access_point_id = local.create_new_efs ? aws_efs_access_point.new[0].id : (local.has_existing_efs ? aws_efs_access_point.existing[0].id : "")
  access_point_arn = local.create_new_efs ? aws_efs_access_point.new[0].arn : (local.has_existing_efs ? aws_efs_access_point.existing[0].arn : "")
}

# Add necessary permissions to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  count      = local.use_efs ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Add EFS policy to Lambda role
resource "aws_iam_policy" "lambda_efs_access" {
  count       = local.use_efs ? 1 : 0
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
        Resource = local.file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = local.access_point_arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_efs_access" {
  count      = local.use_efs ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_efs_access[0].arn
}