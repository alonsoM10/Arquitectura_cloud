# Datos existentes en la cuenta / Learner Lab

data "aws_caller_identity" "current" {}

# Rol preexistente del Learner Lab (NO se pueden crear roles IAM en el lab).
# Se usa como execution_role y task_role de ECS.
data "aws_iam_role" "lab" {
  name = "LabRole"
}
# Nota: las políticas administradas de CloudFront NO se consultan por data
# source porque el rol del Learner Lab no tiene cloudfront:ListCachePolicies.
# Se usan sus IDs globales fijos (ver locals.tf).
