output "vpc_id" {
  description = "The VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The VPC's address range."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnets, one per zone, in availability_zone_ids order: servers, functions, DMS."
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Database subnets, one per zone: Aurora."
  value       = aws_subnet.database[*].id
}

output "private_route_table_id" {
  description = "Route table of the private subnets (holds the gateway endpoints)."
  value       = aws_route_table.private.id
}

output "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint, for security group rules (null without an S3 endpoint)."
  value       = try(aws_vpc_endpoint.gateway["s3"].prefix_list_id, null)
}

output "endpoint_security_group_id" {
  description = "Security group of the interface endpoints."
  value       = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs by service."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}
