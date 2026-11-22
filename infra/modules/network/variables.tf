variable "name" {
  description = "Name prefix for the network's resources."
  type        = string
}

variable "region" {
  description = "AWS region, for the endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "Address range of the VPC. The subnets are carved from it."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be an IPv4 CIDR block of /20 or larger."
  }
}

# Zone IDs (use1-az1), not names (us-east-1a): names map to different physical zones in each account.
variable "availability_zone_ids" {
  description = "Exactly two zone IDs. The interface endpoints go in the first."
  type        = list(string)

  validation {
    condition     = length(var.availability_zone_ids) == 2
    error_message = "Exactly two zone IDs: Aurora and DMS need two zones."
  }
}

variable "interface_endpoints" {
  description = "AWS services reached through interface endpoints (in one zone), e.g. ssm."
  type        = list(string)
}

variable "gateway_endpoints" {
  description = "AWS services reached through free gateway endpoints on the private route table: s3, dynamodb."
  type        = list(string)

  validation {
    condition     = alltrue([for s in var.gateway_endpoints : contains(["s3", "dynamodb"], s)])
    error_message = "Only s3 and dynamodb have gateway endpoints."
  }
}
