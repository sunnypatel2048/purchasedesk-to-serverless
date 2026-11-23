variable "name" {
  description = "Name prefix for the legacy server's resources."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  description = "The platform VPC."
  type        = string
}

variable "vpc_cidr" {
  description = "The VPC's address range: the server reaches the interface endpoints inside it."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the server, in the same zone as the interface endpoints."
  type        = string
}

variable "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint, for the server's outbound rule."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium (4 GB) is the default; t3.large if memory runs short."
  type        = string
}

variable "sql_max_memory_mb" {
  description = "SQL Server's max server memory, leaving the rest for Windows and IIS."
  type        = number

  validation {
    condition     = var.sql_max_memory_mb >= 512
    error_message = "At least 512 MB."
  }
}

variable "artifact_bucket" {
  description = "The release artifact bucket (ADR-0010)."
  type        = string
}

variable "release_commit" {
  description = "Commit of the release to deploy: releases/<commit>/ in the artifact bucket."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.release_commit))
    error_message = "A full 40-character commit SHA."
  }
}

variable "release_files" {
  description = "The release's zip files and their SHA-256, from its manifest.json."
  type        = map(string)
}

variable "api_key_parameter" {
  description = "SecureString parameter holding the legacy API key, created by make secrets (never by Terraform)."
  type        = string
}

variable "data_volume_gb" {
  description = "Size of the D: drive, where the legacy app logs and exports."
  type        = number
  default     = 5
}

variable "boot_timeout_seconds" {
  description = "How long Terraform waits for the boot script to succeed."
  type        = number
  default     = 1800
}
