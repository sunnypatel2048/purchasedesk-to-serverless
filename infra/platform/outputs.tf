output "vpc_id" {
  description = "The platform VPC."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets, one per zone."
  value       = module.network.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Database subnets, one per zone."
  value       = module.network.database_subnet_ids
}

output "legacy_instance_id" {
  description = "The legacy server (null when legacy_enabled is false)."
  value       = try(module.legacy[0].instance_id, null)
}

output "legacy_release_commit" {
  description = "The release the legacy server runs."
  value       = var.legacy_enabled ? local.legacy_release_commit : null
}

output "legacy_boot_association_id" {
  description = "The boot association, for reading the boot script's output."
  value       = try(module.legacy[0].boot_association_id, null)
}
