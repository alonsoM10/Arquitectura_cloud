# =====================================================================
#  EP2 — Variables de entrada
#  Sobreescribibles con terraform.tfvars o -var
# =====================================================================

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

variable "cluster_name" {
  description = "Nombre del clúster EKS (el docente espera 'freshbox-cluster')"
  type        = string
  default     = "freshbox-cluster"
}

variable "k8s_version" {
  description = "Versión de Kubernetes del clúster EKS"
  type        = string
  default     = "1.31"
}

# --- Red ---

variable "vpc_cidr" {
  description = "Rango de la VPC Multi-AZ. /22 = 1024 IPs"
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

# --- Node Group ---

variable "node_instance_type" {
  description = "Tipo de instancia de los nodos EKS (t4g = Graviton/ARM64)"
  type        = string
  default     = "t4g.small"
}

variable "node_min_size" {
  description = "Mínimo de nodos del Node Group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Máximo de nodos del Node Group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Nodos iniciales del Node Group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Tamaño del volumen EBS de cada nodo (GiB)"
  type        = number
  default     = 20
}

# --- Base de datos ---

variable "db_instance_class" {
  description = "Clase de instancia RDS exigida por la pauta EP2"
  type        = string
  default     = "db.t4g.small"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "freshbox"
}

variable "db_username" {
  description = "Usuario administrador de la base de datos"
  type        = string
  default     = "admin"
}

variable "db_backup_retention" {
  description = "Días de retención de snapshots automáticos"
  type        = number
  default     = 7
}
