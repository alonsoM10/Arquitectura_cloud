# Variables de entrada del proyecto
# Puedes sobreescribirlas creando un archivo terraform.tfvars

variable "region" {
  description = "Región AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "freshbox"
}

variable "vpc_cidr" {
  description = "Rango de red de la VPC (Multi-AZ). /22 = 1024 IPs"
  type        = string
  default     = "10.0.0.0/22"
}

variable "az_a" {
  description = "Primera zona de disponibilidad"
  type        = string
  default     = "us-east-1a"
}

variable "az_b" {
  description = "Segunda zona de disponibilidad"
  type        = string
  default     = "us-east-1b"
}

variable "db_instance_class" {
  description = "Tipo de instancia RDS (Learner Lab permite db.t3.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "enable_waf" {
  description = "Crear WAF sobre CloudFront (apagar si el lab lo bloquea)"
  type        = bool
  default     = true
}

variable "enable_db_public_seeding" {
  description = "Exponer RDS temporalmente para cargar init.sql desde tu IP"
  type        = bool
  default     = false
}

variable "my_ip_cidr" {
  description = "Tu IP publica en formato CIDR (solo para seeding). Ej: 190.1.2.3/32"
  type        = string
  default     = "0.0.0.0/0"
}
