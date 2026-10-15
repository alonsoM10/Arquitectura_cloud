# =====================================================================
#  EP2 — SEGURIDAD: KMS + Security Groups encadenados por capa
#
#  Cadena:  Internet → SG-ALB → SG-EKS-NODES → SG-RDS-DATA
#  El SG del ALB lo consume el Ingress vía anotación en el manifiesto
#  (alb.ingress.kubernetes.io/security-groups).
# =====================================================================

# --- Llave KMS: cifra los volúmenes EBS de los nodos y la RDS ---
resource "aws_kms_key" "main" {
  description             = "FreshBox EP2 - cifrado de EBS (nodos EKS) y RDS"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = { Name = "${var.name_prefix}-kms" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}-ep2"
  target_key_id = aws_kms_key.main.key_id
}

# --- SG-ALB: única puerta de entrada desde Internet ---
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-sg-alb"
  description = "ALB Ingress: HTTP/HTTPS desde Internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# --- SG del plano de control de EKS ---
resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-sg-eks-cluster"
  description = "Plano de control EKS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-eks-cluster" }
}

# --- SG de los nodos EKS: reciben tráfico SOLO desde el ALB ---
resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-sg-eks-nodes"
  description = "Nodos EKS: trafico de aplicacion unicamente desde el ALB"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg-eks-nodes"
    # Requerido por el CNI de EKS para reconocer el SG del Node Group
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# El ALB entrega el tráfico a los Pods en el rango de puertos efímeros
# (target-type ip). Se abre ese rango SOLO desde el SG del ALB.
resource "aws_security_group_rule" "nodes_from_alb" {
  type                     = "ingress"
  description              = "Trafico del ALB hacia los Pods (NodePort / target ip)"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.alb.id
}

# Comunicación entre nodos (CoreDNS, kube-proxy, tráfico pod a pod)
resource "aws_security_group_rule" "nodes_self" {
  type              = "ingress"
  description       = "Comunicacion entre nodos del cluster"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.nodes.id
  self              = true
}

# Plano de control → kubelet de los nodos
resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  description              = "Plano de control EKS hacia el kubelet"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
}

# Nodos → plano de control (443)
resource "aws_security_group_rule" "cluster_from_nodes" {
  type                     = "ingress"
  description              = "Nodos hacia la API del plano de control"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
}

# --- SG-DATA: RDS MySQL. Solo 3306 desde los nodos EKS ---
resource "aws_security_group" "data" {
  name        = "${var.name_prefix}-sg-data"
  description = "RDS MySQL: 3306 solo desde los nodos EKS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL desde la capa de aplicacion (EKS)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-sg-data" }
}
