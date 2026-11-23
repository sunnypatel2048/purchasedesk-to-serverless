# The platform layer: everything `make up` creates and `make down` destroys (ADR-0007). Later phases add the legacy
# server, the front door, Aurora, DMS and the functions here, behind legacy_enabled and replication_enabled.

module "network" {
  source = "../modules/network"

  name                  = var.project
  region                = var.region
  vpc_cidr              = var.vpc_cidr
  availability_zone_ids = var.availability_zone_ids

  # Phase 4 needs only what the legacy server uses: S3 for the release, Systems Manager for administration,
  # Parameter Store and the ready signal. SSM Agent 3.3.40+ needs no ec2messages endpoint (ADR-0011).
  gateway_endpoints   = ["s3", "dynamodb"]
  interface_endpoints = ["ssm", "ssmmessages"]
}
