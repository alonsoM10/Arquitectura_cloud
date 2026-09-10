# =====================================================================
#  MÓDULO 1 — RED (VPC Multi-AZ, 3 capas, sin NAT)
#  Diagrama B: la salida privada se hace por VPC Endpoints, no por NAT.
# =====================================================================

# --- Definición de las 6 subredes (2 por capa, 1 por AZ) ---
# Usamos bloques /26 (64 IPs c/u) dentro de la VPC /22.
locals {
  subnets = {
    public-a = { cidr = "10.0.0.0/26", az = var.az_a, tier = "public" }
    public-b = { cidr = "10.0.0.64/26", az = var.az_b, tier = "public" }
    app-a    = { cidr = "10.0.1.0/26", az = var.az_a, tier = "app" }
    app-b    = { cidr = "10.0.1.64/26", az = var.az_b, tier = "app" }
    data-a   = { cidr = "10.0.2.0/26", az = var.az_a, tier = "data" }
    data-b   = { cidr = "10.0.2.64/26", az = var.az_b, tier = "data" }
  }
}

# --- VPC ---
# DNS habilitado: obligatorio para VPC Endpoints y RDS.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# --- Internet Gateway (solo da salida a la capa pública) ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# --- Subredes (for_each sobre el mapa de arriba) ---
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # Solo las públicas asignan IP pública automática
  map_public_ip_on_launch = each.value.tier == "public"

  tags = {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.value.tier
  }
}

# --- Tabla de rutas PÚBLICA → Internet Gateway ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  for_each = { for k, s in local.subnets : k => s if s.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# --- Tabla de rutas PRIVADA (app + data) ---
# Sin ruta a Internet: el tráfico sale por VPC Endpoints (ver endpoints.tf).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-private" }
}

resource "aws_route_table_association" "private" {
  for_each = { for k, s in local.subnets : k => s if s.tier != "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private.id
}
