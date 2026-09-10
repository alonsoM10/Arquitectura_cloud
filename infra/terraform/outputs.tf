# Salidas útiles tras el apply

output "cloudfront_url" {
  description = "URL pública del sitio (frontend + API vía /api)"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "alb_dns" {
  description = "DNS del ALB (para pruebas directas del API)"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS MySQL"
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "ARN del secreto con las credenciales de la BD"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "ecr_repositories" {
  description = "URLs de los repositorios ECR para hacer push"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}
