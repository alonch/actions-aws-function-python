locals {
  # Handle volume name specification
  volume_name = var.volume_name

  # Check if volume name is specified
  has_volume = local.volume_name != ""
}

# Find existing EFS file systems with matching volume-name tag
data "aws_efs_file_systems" "existing_efs" {
  count = local.has_volume ? 1 : 0

  tags = {
    "volume-name" = local.volume_name
  }
}

locals {
  # Check if matching EFS exists
  existing_efs_count = local.has_volume ? length(data.aws_efs_file_systems.existing_efs[0].ids) : 0
  # Check if we need to create a new EFS volume
  create_new_efs = local.has_volume && local.existing_efs_count == 0
  # Flag to determine if EFS mounting is needed (either new or existing)
  use_efs = local.has_volume
  # Set volume path based on volume name
  volume_path = var.volume_path != "" ? var.volume_path : (local.has_volume ? "/mnt/${local.volume_name}" : "")
}

# Get the first matched EFS file system (if any)
data "aws_efs_file_system" "selected" {
  count     = local.has_volume && local.existing_efs_count > 0 ? 1 : 0
  file_system_id = tolist(data.aws_efs_file_systems.existing_efs[0].ids)[0]
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

# Create EFS file system (only if no matching one exists)
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

# Get existing mount targets if using existing EFS
data "aws_efs_mount_targets" "existing" {
  count = local.use_efs && !local.create_new_efs ? 1 : 0
  file_system_id = data.aws_efs_file_system.selected[0].id
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

# Create access point with proper directory permissions
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
  count          = local.use_efs && !local.create_new_efs ? 1 : 0
  file_system_id = data.aws_efs_file_system.selected[0].id

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
  access_point_id = local.create_new_efs ? aws_efs_access_point.new[0].id : (local.use_efs && !local.create_new_efs ? aws_efs_access_point.existing[0].id : "")
  access_point_arn = local.create_new_efs ? aws_efs_access_point.new[0].arn : (local.use_efs && !local.create_new_efs ? aws_efs_access_point.existing[0].arn : "")
  file_system_id = local.create_new_efs ? aws_efs_file_system.this[0].id : (local.use_efs && !local.create_new_efs ? data.aws_efs_file_system.selected[0].id : "")
  file_system_arn = local.create_new_efs ? aws_efs_file_system.this[0].arn : (local.use_efs && !local.create_new_efs ? data.aws_efs_file_system.selected[0].arn : "")
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