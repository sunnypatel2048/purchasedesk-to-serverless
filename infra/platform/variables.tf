variable "region" {
  description = "AWS region for everything in this project."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix and Project tag for all resources."
  type        = string
  default     = "purchasedesk"
}

variable "vpc_cidr" {
  description = "Address range of the VPC. Distinct from the other project in the account (10.0.0.0/16)."
  type        = string
  default     = "10.60.0.0/16"
}

# use1-az3 is avoided: CloudFront VPC origins are not supported there, and it offers no t3 instances.
variable "availability_zone_ids" {
  description = "The two zones, by zone ID. The interface endpoints go in the first."
  type        = list(string)
  default     = ["use1-az1", "use1-az2"]
}

# ---------------------------------------------------------------- legacy server (ADR-0012)

# Decommissioning (ADR-0007) is an apply with this set to false.
variable "legacy_enabled" {
  description = "Run the legacy Windows server."
  type        = bool
  default     = true
}

variable "legacy_instance_type" {
  description = "Instance type of the legacy server: t3.medium (4 GB), or t3.large if memory runs short."
  type        = string
  default     = "t3.medium"
}

variable "legacy_sql_max_memory_mb" {
  description = "SQL Server's memory cap on the legacy server; the rest is left to Windows and IIS."
  type        = number
  default     = 1536
}

variable "legacy_release_commit" {
  description = "Pin a release by commit; empty means the newest (releases/legacy-latest.json)."
  type        = string
  default     = ""

  validation {
    condition     = var.legacy_release_commit == "" || can(regex("^[0-9a-f]{40}$", var.legacy_release_commit))
    error_message = "Empty, or a full 40-character commit SHA."
  }
}

variable "legacy_api_key_parameter" {
  description = "SecureString parameter with the legacy API key, created by make secrets."
  type        = string
  default     = "/purchasedesk/secrets/legacy-api-key"
}
