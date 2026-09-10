# Salidas útiles tras el apply

output "app_url" {
  description = "URL pública de la app (frontend en / y API en /api/*)"
  value       = "http://${aws_lb.main.dns_name}"
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

# --- Usados por el script de seed (tarea Fargate dentro de la VPC) ---
output "cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "public_subnet_ids" {
  description = "IDs de las subredes públicas"
  value       = local.public_subnet_ids
}

output "app_sg_id" {
  description = "ID del Security Group de la capa App (permite 3306 → RDS)"
  value       = aws_security_group.app.id
}
