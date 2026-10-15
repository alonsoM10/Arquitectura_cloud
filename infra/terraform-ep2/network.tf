# =====================================================================
#  EP2 — RED: VPC Multi-AZ de 3 capas + NAT Gateway
#
#  Diferencia con EP1: aquí SÍ hay NAT Gateway. Los nodos de EKS viven en
#  subredes privadas y necesitan salida a Internet para registrarse contra
#  el endpoint público del plano de control, descargar los addons y aplicar
#  actualizaciones. Los VPC Endpoints de EP1 cubrían ECR/S3/logs, pero no
#  el tráfico del kubelet hacia la API de EKS.
# =====================================================================

locals {
  subnets = {
    public-a = { cidr = "10.0.0.0/26", az = var.az_a, tier = "public" }
    public-b = { cidr = "10.0.0.64/26", az = var.az_b, tier = "public" }
    app-a    = { cidr = "10.0.1.0/26", az = var.az_a, tier = "app" }
    app-b    = { cidr = "10.0.1.64/26", az = var.az_b, tier = "app" }
    data-a   = { cidr = "10.0.2.0/26", az = var.az_a, tier = "data" }
    data-b   = { cidr = "10.0.2.64/26", az = var.az_b, tier = "data" }
  }

  # Etiquetas que el AWS Load Balancer Controller necesita para descubrir
  # automáticamente dónde crear el ALB del Ingress.
  subnet_discovery_tags = {
    public = { "kubernetes.io/role/elb" = "1" }
    app    = { "kubernetes.io/role/internal-elb" = "1" }
    data   = {}
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(
    {
      Name = "${var.name_prefix}-${each.key}"
      Tier = each.value.tier
      # Permite que el controller y el CNI asocien la subred al clúster
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    },
    local.subnet_discovery_tags[each.value.tier],
  )
}

# ---------------------------------------------------------------------
#  NAT Gateway (uno solo, en la subred pública AZ-a)
#  Trade-off documentado en el informe: un único NAT abarata el laboratorio
#  pero es un punto único de falla para la salida a Internet. En producción
#  se despliega uno por AZ. No afecta la disponibilidad del tráfico entrante
#  (ALB) ni de la base de datos (RDS Multi-AZ).
# ---------------------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-eip-nat" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public-a"].id

  tags = { Name = "${var.name_prefix}-nat" }

  depends_on = [aws_internet_gateway.igw]
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

# --- Tabla de rutas PRIVADA (app + data) → NAT Gateway ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-private" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  for_each = { for k, s in local.subnets : k => s if s.tier != "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private.id
}
