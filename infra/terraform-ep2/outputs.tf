# =====================================================================
#  EP2 — Salidas consumidas por el workflow y por los scripts
# =====================================================================

output "cluster_name" {
  description = "Nombre del clúster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes"
  value       = aws_eks_cluster.main.endpoint
}

output "region" {
  description = "Región desplegada"
  value       = var.region
}

output "account_id" {
  description = "ID de la cuenta (para construir las URIs de ECR)"
  value       = local.account_id
}

output "ecr_registry" {
  description = "Registro ECR de la cuenta"
  value       = local.ecr_registry
}

output "ecr_repositories" {
  description = "URLs de los 5 repositorios ECR"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "rds_endpoint" {
  description = "Host de la base de datos RDS MySQL Multi-AZ"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Puerto de la base de datos"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Usuario administrador de la base de datos"
  value       = aws_db_instance.main.username
}

output "db_secret_arn" {
  description = "ARN del secreto gestionado con la contraseña de la BD"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "alb_security_group_id" {
  description = "SG que el Ingress debe asociar al ALB"
  value       = aws_security_group.alb.id
}

output "public_subnet_ids" {
  description = "Subredes públicas donde se crea el ALB"
  value       = local.public_subnet_ids
}

output "app_subnet_ids" {
  description = "Subredes privadas de aplicación (nodos EKS)"
  value       = local.app_subnet_ids
}

output "node_security_group_id" {
  description = "SG de los nodos EKS"
  value       = aws_security_group.nodes.id
}
