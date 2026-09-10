# =====================================================================
#  VPC ENDPOINTS — reemplazan al NAT Gateway (más barato + más seguro)
#  - S3 (Gateway): descarga de capas de imágenes ECR (gratis)
#  - ECR api/dkr (Interface): pull de imágenes Docker sin salir a Internet
#  - Logs (Interface): logs de Fargate a CloudWatch
#  - Secrets Manager (Interface): credenciales de RDS
# =====================================================================

# SG para los endpoints de tipo Interface: permite HTTPS desde la VPC
resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-sg-endpoints"
  description = "Permite HTTPS (443) hacia los VPC Endpoints desde la VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS desde la VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-endpoints" }
}

# --- Endpoint S3 (tipo Gateway) → se asocia a la tabla de rutas privada ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

# --- Endpoints de tipo Interface (uno por servicio) ---
locals {
  interface_endpoints = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
  # local.app_subnet_ids se define en locals.tf
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.endpoints.id]
  subnet_ids          = local.app_subnet_ids

  tags = { Name = "${var.name_prefix}-vpce-${each.value}" }
}
