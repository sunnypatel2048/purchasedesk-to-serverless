# A private network with no NAT gateway (ADR-0011): two zones, private subnets for the servers and functions,
# database subnets for Aurora, free gateway endpoints for S3 and DynamoDB, and a few interface endpoints in one zone.
# Nothing here accepts traffic from the internet; CloudFront reaches the legacy server through a VPC origin.

locals {
  # 10.60.0.0/24, 10.60.1.0/24 and 10.60.10.0/24, 10.60.11.0/24 for a /16.
  private_cidrs  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  database_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, 10 + i)]
}

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:No flow logs in a single-user demo; production would send them to CloudWatch Logs (ADR-0011)
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # the VPC origin and the interface endpoints' private DNS need it

  tags = { Name = var.name }
}

# Required by CloudFront VPC origins, which only accept a VPC with an internet gateway attached (ADR-0004).
# Nothing routes through it: no route table here has a route to it.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

# The VPC's default security group, with every rule removed, so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}

# ---------------------------------------------------------------- subnets: no public subnets at all

resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.private_cidrs[count.index]
  availability_zone_id    = var.availability_zone_ids[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-private-${var.availability_zone_ids[count.index]}" }
}

resource "aws_subnet" "database" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.database_cidrs[count.index]
  availability_zone_id    = var.availability_zone_ids[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-database-${var.availability_zone_ids[count.index]}" }
}

# ---------------------------------------------------------------- route tables: local routes and gateway endpoints

# Shared by both private subnets: with no NAT gateway their routes are identical.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Aurora needs nothing outside the VPC: local routes only.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-database" }
}

resource "aws_route_table_association" "database" {
  count = 2

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ---------------------------------------------------------------- endpoints

# Free. The default endpoint policy stays: one limited to this project's buckets would also block the SSM agent's
# own downloads from AWS-owned buckets (ADR-0011).
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoints)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name}-${each.key}" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-endpoints"
  description = "Interface endpoints: HTTPS from inside the VPC only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from anything in the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block
}

# About $0.01 an hour each, per zone: one zone only. Instances in the other zone reach them across zones.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true # clients use the normal service hostname

  tags = { Name = "${var.name}-${each.key}" }
}
