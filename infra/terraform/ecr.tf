# =====================================================================
#  ECR — 1 repositorio por microservicio backend (4 imágenes Docker)
#  El frontend ya NO es contenedor (va a S3), por eso son 4 y no 5.
# =====================================================================

resource "aws_ecr_repository" "svc" {
  for_each = local.services

  name                 = "${var.name_prefix}-${each.key}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # buena práctica: escaneo de vulnerabilidades
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}
