variable "name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "python_version" {
  description = "Python runtime version"
  type        = string
  default     = "3.11"

  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11", "3.12"], var.python_version)
    error_message = "Python version must be one of: 3.8, 3.9, 3.10, 3.11, 3.12"
  }
}

variable "arm" {
  description = "Use ARM architecture"
  type        = bool
  default     = true
}

variable "entrypoint_file" {
  description = "Path to the entrypoint file"
  type        = string
}

variable "entrypoint_function" {
  description = "Name of the handler function in the entrypoint file"
  type        = string
}

variable "memory" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.memory >= 128 && var.memory <= 10240
    error_message = "Memory must be between 128MB and 10,240MB"
  }
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 3

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds"
  }
}

variable "env" {
  description = "Environment variables for the Lambda function"
  type        = string
  default     = "CREATE_BY: alonch/actions-aws-function-python"
}

variable "permissions" {
  description = "IAM permissions for the Lambda function"
  type        = string
  default     = ""
}

variable "artifacts" {
  description = "Directory containing artifacts to be included in the Lambda deployment package"
  type        = string
  default     = ""
}

variable "allow_public_access" {
  description = "Whether to create a public URL for the Lambda function"
  type        = string
  default     = ""
}

variable "volume_name" {
  description = "Name of the EFS volume to create or reuse. If an EFS with this name (as a tag) exists, it will be reused."
  type        = string
  default     = ""
}

variable "volume_path" {
  description = "Path where the EFS volume should be mounted (e.g., /mnt/data). Defaults to /mnt/{volume_name} if not specified."
  type        = string
  default     = ""
}

variable "existing_efs_id" {
  description = "ID of an existing EFS file system to use. If provided, a new EFS will not be created."
  type        = string
  default     = ""
}

variable "existing_mount_target_id" {
  description = "ID of an existing mount target for the EFS file system. Used to determine if mount targets already exist."
  type        = string
  default     = ""
}