output "instance_id" {
  description = "The legacy server, for Systems Manager sessions and commands."
  value       = aws_instance.legacy.id
}

output "private_dns" {
  description = "The server's private DNS name (the VPC origin's target in 4.3)."
  value       = aws_instance.legacy.private_dns
}

output "security_group_id" {
  description = "The server's security group (DMS gets a rule here in Phase 5)."
  value       = aws_security_group.legacy.id
}

output "image_id" {
  description = "The image the server was launched from."
  value       = data.aws_ami.legacy.id
}

output "boot_association_id" {
  description = "The boot association, for reading the boot script's output."
  value       = aws_ssm_association.boot.association_id
}
