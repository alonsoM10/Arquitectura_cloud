# Datos existentes en la cuenta / Learner Lab

data "aws_caller_identity" "current" {}

# Rol preexistente del Learner Lab (NO se pueden crear roles IAM en el lab).
# Se usa como execution_role y task_role de ECS.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

# Políticas administradas de CloudFront (cache / origin request)
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewerExceptHostHeader"
}
