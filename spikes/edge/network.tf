# The smallest network a VPC origin accepts: one private subnet, no NAT, no route to the internet.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # the VPC origin addresses the instance by its private DNS name

  tags = { Name = local.name }
}

# Required by CloudFront VPC origins to mark the VPC as reachable from the internet.
# Nothing routes through it: the private subnet has no route to it.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = local.name }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-private" }
}
