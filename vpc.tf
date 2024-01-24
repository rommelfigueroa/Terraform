terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = var.default_tags
  }
}

# create VPC : CIDR 10.0.0.0/16
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true
  tags = {
    "Name" = "${var.default_tags.username}-vpc" # rfigueroa-vpc
  }
}

# Public Subnet : 10.0.0.0/24
resource "aws_subnet" "public" {
  count  = var.public_subnet_count
  vpc_id = aws_vpc.main.id
  # cidr_block = cidrsubnet(prefix, newbits. netnum)
  # 10.0.1.0/24
  # 10.0.2.0/24
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index) # 1 # 2 # 3
  #   ipv6_cidr_block = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index)

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.default_tags.username}-public-${data.aws_availability_zones.availability_zone.names[count.index]}" # rfigueroa-vpc
  }
  availability_zone = data.aws_availability_zones.availability_zone.names[count.index]
}

# Private Subnet : 10.0.1.0/24
resource "aws_subnet" "private" {
  count      = var.private_subnet_count
  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + var.public_subnet_count)
  tags = {
    "Name" = "${var.default_tags.username}-private-${data.aws_availability_zones.availability_zone.names[count.index]}"
  }
  availability_zone = data.aws_availability_zones.availability_zone.names[count.index]
}

# IGW 
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.username}-IGW"
  }
}

# NGW 
resource "aws_eip" "NAT_EIP" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main_NAT" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.NAT_EIP.id
  tags = {
    "Name" = "${var.default_tags.username}-NAT"
  }
}

# Pub/private route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.username}-publicRT"
  }
}

# Pub/private route
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id        # Route table we are adding to
  destination_cidr_block = "0.0.0.0/0"                      # Destination
  gateway_id             = aws_internet_gateway.main_igw.id # Target
}
# Public route table association
resource "aws_route_table_association" "public" {
  count = var.public_subnet_count
  # Element is a function that retrieves a single item from a list
  # We created two public subnets with the exact same name, so we made a list of subnets.connection {
  # In order to associate this RT with both subnets, we use a wild card and the count.index
  # to indicate both subnets.connection {
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}


# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    "Name" = "${var.default_tags.username}-privateRT"
  }
}

# Privare route
resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main_NAT.id
}

# Private route table association
resource "aws_route_table_association" "private" {
  count          = var.private_subnet_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}