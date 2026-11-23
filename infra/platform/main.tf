# The platform layer: everything `make up` creates and `make down` destroys (ADR-0007). Later phases add the front
# door, Aurora, DMS and the functions here, behind legacy_enabled and replication_enabled.

data "aws_caller_identity" "current" {}

locals {
  # Named by the bootstrap layer; built here so the account ID never appears in the repo.
  artifact_bucket = "${var.project}-artifacts-${data.aws_caller_identity.current.account_id}-${var.region}"
}

module "network" {
  source = "../modules/network"

  name                  = var.project
  region                = var.region
  vpc_cidr              = var.vpc_cidr
  availability_zone_ids = var.availability_zone_ids

  # Phase 4 needs only what the legacy server uses: S3 for the release, Systems Manager for administration,
  # Parameter Store and the boot association. SSM Agent 3.3.40+ needs no ec2messages endpoint (ADR-0011).
  gateway_endpoints   = ["s3", "dynamodb"]
  interface_endpoints = ["ssm", "ssmmessages"]
}

# ---------------------------------------------------------------- the release the legacy server runs (ADR-0010)

# releases/legacy-latest.json names the newest release, unless legacy_release_commit pins one.
data "aws_s3_object" "legacy_latest" {
  count = var.legacy_enabled && var.legacy_release_commit == "" ? 1 : 0

  bucket = local.artifact_bucket
  key    = "releases/legacy-latest.json"
}

locals {
  legacy_release_commit = var.legacy_release_commit != "" ? var.legacy_release_commit : try(jsondecode(data.aws_s3_object.legacy_latest[0].body).commit, "")
}

# Terraform reads the manifest itself and hands the zips' SHA-256 to the boot script, so the plan shows exactly what
# will be deployed and the server checks the downloads against it.
data "aws_s3_object" "legacy_manifest" {
  count = var.legacy_enabled ? 1 : 0

  bucket = local.artifact_bucket
  key    = "releases/${local.legacy_release_commit}/manifest.json"
}

module "legacy" {
  source = "../modules/legacy"
  count  = var.legacy_enabled ? 1 : 0

  name              = var.project
  region            = var.region
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  subnet_id         = module.network.private_subnet_ids[0] # the zone with the interface endpoints
  s3_prefix_list_id = module.network.s3_prefix_list_id

  instance_type     = var.legacy_instance_type
  sql_max_memory_mb = var.legacy_sql_max_memory_mb

  artifact_bucket   = local.artifact_bucket
  release_commit    = local.legacy_release_commit
  release_files     = { for name, file in jsondecode(data.aws_s3_object.legacy_manifest[0].body).files : name => file.sha256 }
  api_key_parameter = var.legacy_api_key_parameter

  # The endpoints must exist before the server boots, and on destroy the server goes first.
  depends_on = [module.network]
}
