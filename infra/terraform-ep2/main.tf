# =====================================================================
#  EP2 — Datos existentes y valores calculados
# =====================================================================

data "aws_caller_identity" "current" {}

# El Learner Lab NO permite crear roles IAM (iam:CreateRole denegado por la
# SCP). Se reutiliza el rol preexistente LabRole como:
#   - rol del plano de control de EKS  (AmazonEKSClusterPolicy)
#   - rol de los nodos del Node Group  (WorkerNode + CNI + ECR ReadOnly)
# Es la misma estrategia usada en EP1 para los roles de ECS.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  ecr_registry = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  # Listas de subredes por capa (derivadas del mapa aws_subnet.this)
  public_subnet_ids = [for k, s in aws_subnet.this : s.id if startswith(k, "public")]
  app_subnet_ids    = [for k, s in aws_subnet.this : s.id if startswith(k, "app")]
  data_subnet_ids   = [for k, s in aws_subnet.this : s.id if startswith(k, "data")]

  # Los 5 contenedores del caso: 1 frontend Nginx + 4 microservicios Node.js.
  # A diferencia de EP1, el frontend TAMBIÉN vive en el clúster, por lo que
  # se crean 5 repositorios ECR y no 4.
  images = [
    "frontend",
    "get-products",
    "create-product",
    "update-product",
    "delete-product",
  ]
}
