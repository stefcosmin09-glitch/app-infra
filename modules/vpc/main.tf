# VPC with public + private subnets across 2 AZs.
# Public: ALB, NAT Gateway
# Private: ECS tasks, RDS

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ── Internet Gateway ───────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-igw"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ── Subnets ────────────────────────────────────────────
# CIDR split: /20 VPC -> 4 x /22 subnets (1024 IPs each)
# public-1a: 10.0.0.0/22, public-1b: 10.0.4.0/22
# private-1a: 10.0.8.0/22, private-1b: 10.0.12.0/22

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 2, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-${var.azs[count.index]}"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "public"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 2, count.index + 2)
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-${var.azs[count.index]}"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "private"
  }
}

# ── NAT Gateway (single, cost-controlled) ──────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-${var.environment}-nat-eip"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # single NAT in first AZ

  tags = {
    Name        = "${var.project_name}-${var.environment}-nat"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.this]
}

# ── Route Tables ───────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}