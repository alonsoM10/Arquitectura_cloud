# =====================================================================
#  FRONTEND — S3 (estático privado) + CloudFront (CDN/HTTPS) + WAF
#  Reemplaza al contenedor Nginx. CloudFront sirve el sitio y reenvía
#  /api/* al ALB → un solo dominio, HTTPS y sin problemas de CORS.
# =====================================================================

# --- Bucket S3 privado (solo accesible vía CloudFront) ---
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.name_prefix}-frontend-${local.account_id}"
  force_destroy = true
  tags          = { Name = "${var.name_prefix}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sube todos los archivos del frontend al bucket
locals {
  frontend_dir = "${path.module}/../../app/microservicioFrontend"
  content_types = {
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "svg"  = "image/svg+xml"
    "ico"  = "image/x-icon"
    "json" = "application/json"
  }
}

resource "aws_s3_object" "frontend" {
  for_each = fileset(local.frontend_dir, "**")

  bucket       = aws_s3_bucket.frontend.id
  key          = each.value
  source       = "${local.frontend_dir}/${each.value}"
  etag         = filemd5("${local.frontend_dir}/${each.value}")
  content_type = lookup(local.content_types, lower(reverse(split(".", each.value))[0]), "application/octet-stream")
}

# --- Origin Access Control: solo CloudFront puede leer el bucket ---
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- WAF (opcional: algunos Learner Lab restringen WAFv2) ---
resource "aws_wafv2_web_acl" "cf" {
  count = var.enable_waf ? 1 : 0

  name  = "${var.name_prefix}-waf"
  scope = "CLOUDFRONT" # requiere provider en us-east-1 (ya lo estamos)

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommon"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
    sampled_requests_enabled   = true
  }
}

# --- CloudFront: 2 orígenes (S3 estático + ALB para /api/*) ---
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} - FreshBox EP1"
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.cf[0].arn : null

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb-api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Sitio estático → S3
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # API → ALB (sin caché, reenvía todos los métodos)
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # HTTPS con el dominio *.cloudfront.net
  }

  tags = { Name = "${var.name_prefix}-cf" }
}

# --- Política del bucket: permite lectura solo a esta distribución ---
data "aws_iam_policy_document" "s3_cf" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.s3_cf.json
}
