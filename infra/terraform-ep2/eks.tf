# =====================================================================
#  EP2 — AMAZON EKS: plano de control gestionado + Node Group
#
#  Notas del Learner Lab:
#   · No se pueden crear roles IAM → se reutiliza LabRole en ambos roles.
#   · Sin OIDC/IRSA, los Pods que necesitan permisos de AWS (el AWS Load
#     Balancer Controller) usan las credenciales del rol del nodo vía IMDS.
#     Por eso el launch template fija http_put_response_hop_limit = 2: con
#     el valor por defecto (1) los Pods NO alcanzan IMDS y el controller
#     falla silenciosamente al crear el ALB.
# =====================================================================

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.lab.arn
  version  = var.k8s_version

  vpc_config {
    # El plano de control necesita ENIs en las subredes públicas y privadas
    subnet_ids              = concat(local.public_subnet_ids, local.app_subnet_ids)
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Quien crea el clúster queda como administrador de Kubernetes.
  # Imprescindible en el lab: el workflow usa esas mismas credenciales.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = { Name = var.cluster_name }
}

# ---------------------------------------------------------------------
#  Launch template de los nodos
#  Aporta dos cosas que el Node Group por defecto no da:
#   1) volumen EBS cifrado con la llave KMS del proyecto (exigido por la pauta)
#   2) hop limit 2 en IMDSv2 para que los Pods accedan al rol del nodo
#  No se fija image_id: EKS inyecta la AMI optimizada que corresponda.
# ---------------------------------------------------------------------

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.name_prefix}-ng-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.node_disk_size
      volume_type = "gp3"

      # Cifrado con la llave gestionada por AWS (aws/ebs), NO con la llave
      # propia del proyecto. El grupo de Auto Scaling que lanza los nodos
      # necesita un grant explícito sobre una llave de cliente, y el
      # Learner Lab no permite otorgarlo: las instancias fallaban con
      # Client.InvalidKMSKey.InvalidState y nunca se unían al clúster.
      # La llave de cliente sí se usa en la RDS, que no tiene esa
      # restricción (ver rds.tf).
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 2          # permite el acceso desde Pods
  }

  # Además del SG propio, los nodos llevan el "cluster security group" que
  # crea EKS. Sin él la comunicación nodo <-> plano de control depende solo
  # de reglas manuales y es una fuente clásica de nodos que nunca llegan a
  # Ready.
  vpc_security_group_ids = [
    aws_security_group.nodes.id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}-eks-node" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-ng"
  node_role_arn   = data.aws_iam_role.lab.arn

  # Los nodos viven en la capa privada de aplicación, repartidos en 2 AZ
  subnet_ids = local.app_subnet_ids

  # t4g = Graviton (ARM64). Las imágenes Docker DEBEN compilarse para
  # linux/arm64, no linux/amd64 como en EP1 (Fargate X86_64).
  instance_types = [var.node_instance_type]
  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = { Name = "${var.name_prefix}-ng" }

  # El Node Group no debe crearse antes que la red tenga salida por NAT
  depends_on = [
    aws_route.private_nat,
    aws_nat_gateway.main,
  ]

  lifecycle {
    # El HPA y el Cluster Autoscaler modifican desired_size en caliente
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------
#  Addons gestionados del clúster
#  Se instalan después del Node Group para que tengan dónde ejecutarse.
# ---------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

# NOTA sobre metrics-server:
# Sin metrics-server el HPA no obtiene métricas de CPU y queda en
# <unknown>/70%, sin escalar nunca. NO se instala aquí como addon
# gestionado a propósito: si la versión de EKS del laboratorio no lo
# ofreciera, el `terraform apply` fallaría recién al final, después de
# haber creado el clúster y los nodos (~20 min perdidos). Se instala desde
# el workflow con el manifiesto oficial, que funciona en cualquier versión.
