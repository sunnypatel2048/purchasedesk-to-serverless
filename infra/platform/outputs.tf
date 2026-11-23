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
