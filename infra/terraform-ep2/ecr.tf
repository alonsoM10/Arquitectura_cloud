# =====================================================================
#  EP2 — AMAZON ECR: 5 repositorios (1 frontend Nginx + 4 backend Node.js)
#
#  Diferencia con EP1: en EP1 el frontend iba a S3/CloudFront y luego a un
#  contenedor Fargate, con 4 repos. En EP2 los 5 componentes son Pods del
#  clúster, por lo que el frontend también tiene su propia imagen.
# =====================================================================

resource "aws_ecr_repository" "svc" {
  for_each = toset(local.images)

  name                 = "${var.name_prefix}-${each.key}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}
