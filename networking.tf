resource "aws_vpc" "dev" {
  count = var.create_dev_network ? 1 : 0

  cidr_block           = var.dev_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "dev" {
  count = var.create_dev_network ? 1 : 0

  vpc_id = aws_vpc.dev[0].id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  for_each = var.create_dev_network ? {
    for i, cidr in var.dev_public_subnet_cidrs : i => cidr
  } : {}

  vpc_id                  = aws_vpc.dev[0].id
  cidr_block              = each.value
  availability_zone       = local.azs[tonumber(each.key)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${tonumber(each.key) + 1}"
  })
}

resource "aws_subnet" "private" {
  for_each = var.create_dev_network ? {
    for i, cidr in var.dev_private_subnet_cidrs : i => cidr
  } : {}

  vpc_id            = aws_vpc.dev[0].id
  cidr_block        = each.value
  availability_zone = local.azs[tonumber(each.key)]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${tonumber(each.key) + 1}"
  })
}

resource "aws_eip" "nat" {
  count  = var.create_dev_network ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "dev" {
  count = var.create_dev_network ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id

  depends_on = [aws_internet_gateway.dev]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })
}

resource "aws_route_table" "public" {
  count = var.create_dev_network ? 1 : 0

  vpc_id = aws_vpc.dev[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev[0].id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table" "private" {
  count = var.create_dev_network ? 1 : 0

  vpc_id = aws_vpc.dev[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dev[0].id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "public" {
  for_each = var.create_dev_network ? aws_subnet.public : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  for_each = var.create_dev_network ? aws_subnet.private : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[0].id
}

locals {
  enable_vpc_endpoints = var.create_dev_network && var.enable_private_aws_endpoints
  interface_endpoint_map = local.enable_vpc_endpoints ? {
    for svc in var.interface_endpoint_services : svc => "com.amazonaws.${data.aws_region.current.name}.${svc}"
  } : {}
}

resource "aws_security_group" "vpc_endpoints" {
  count = local.enable_vpc_endpoints ? 1 : 0

  name        = "${local.name_prefix}-vpce-sg"
  description = "Allow HTTPS from ECS tasks to interface VPC endpoints"
  vpc_id      = aws_vpc.dev[0].id

  ingress {
    description     = "HTTPS from ECS tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-sg" })
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count = local.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.dev[0].id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private[0].id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-s3-gateway-vpce" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_map

  vpc_id              = aws_vpc.dev[0].id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in values(aws_subnet.private) : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${replace(each.key, ".", "-")}-vpce"
  })
}
