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
