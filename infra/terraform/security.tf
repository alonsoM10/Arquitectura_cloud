# =====================================================================
#  SECURITY GROUPS — firewalls encadenados por capa (mínimo privilegio)
#  Flujo:  Internet → SG-ALB → SG-APP (Fargate) → SG-DATA (RDS)
# =====================================================================

# --- SG-ALB: recibe tráfico web desde Internet/CloudFront ---
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-sg-alb"
  description = "ALB: HTTP/HTTPS desde Internet (idealmente solo CloudFront)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Hardening: restringir a prefix list de CloudFront
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-alb" }
}

# --- SG-APP: tareas Fargate. Solo aceptan tráfico DESDE el ALB ---
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-sg-app"
  description = "Fargate: puertos de microservicios solo desde SG-ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Frontend HTTP 80 desde el ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Puertos backend 3001-3004 desde el ALB"
    from_port       = 3001
    to_port         = 3004
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-app" }
}

# --- SG-DATA: RDS MySQL. Solo acepta 3306 DESDE las tareas Fargate ---
resource "aws_security_group" "data" {
  name        = "${var.name_prefix}-sg-data"
  description = "RDS MySQL: 3306 solo desde SG-APP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL desde la capa App"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-data" }
}

# --- Regla opcional: acceso temporal a RDS desde tu IP para cargar init.sql ---
# Se activa solo si enable_db_public_seeding = true (ver variables.tf)
resource "aws_security_group_rule" "data_seeding" {
  count             = var.enable_db_public_seeding ? 1 : 0
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip_cidr]
  security_group_id = aws_security_group.data.id
  description       = "TEMPORAL: seeding de la BD desde mi IP"
}
