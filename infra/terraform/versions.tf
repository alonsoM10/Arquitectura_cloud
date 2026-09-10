# Versiones y proveedor AWS
# El Learner Lab entrega credenciales temporales (~/.aws/credentials).
# Terraform las toma automáticamente; aquí solo fijamos región y tags.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Tags aplicados a TODOS los recursos (buena práctica: trazabilidad)
  default_tags {
    tags = {
      Project   = "FreshBox-EP1"
      ManagedBy = "Terraform"
      Owner     = "AlonsoMieres"
    }
  }
}
