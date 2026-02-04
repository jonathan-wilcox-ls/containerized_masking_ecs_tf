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
