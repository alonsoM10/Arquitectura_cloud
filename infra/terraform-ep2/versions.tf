# =====================================================================
#  EP2 — Proveedor y versiones
#  El Learner Lab entrega credenciales temporales (~4 h). Terraform las
#  toma del entorno; aquí solo fijamos región y tags por defecto.
# =====================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "FreshBox-EP2"
      ManagedBy = "Terraform"
      Owner     = "AlonsoMieres"
    }
  }
}
