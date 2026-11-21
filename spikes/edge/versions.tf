# Phase 0.5 spike: CloudFront Function + KeyValueStore splitting traffic between a private EC2
# instance (VPC origin) and API Gateway. Throwaway; local state, gitignored.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "purchasedesk"
      Spike   = "0.5"
    }
  }
}

locals {
  name = "purchasedesk-spike"
}
