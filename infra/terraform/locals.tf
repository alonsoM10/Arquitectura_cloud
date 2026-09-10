# Valores calculados reutilizados por varios archivos

locals {
  account_id   = data.aws_caller_identity.current.account_id
  ecr_registry = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  # Listas de subredes por capa (derivadas del mapa aws_subnet.this)
  public_subnet_ids = [for k, s in aws_subnet.this : s.id if startswith(k, "public")]
  app_subnet_ids    = [for k, s in aws_subnet.this : s.id if startswith(k, "app")]
  data_subnet_ids   = [for k, s in aws_subnet.this : s.id if startswith(k, "data")]

  # Definición central de los 4 microservicios backend.
  # port     = puerto en que escucha el contenedor Node.js
  # method   = método HTTP que enruta el ALB hacia este servicio
  # path     = patrón de ruta que enruta el ALB
  # priority = prioridad de la regla del listener (menor = evalúa antes)
  services = {
    "get-products" = {
      port     = 3001
      method   = "GET"
      path     = "/api/products*"
      priority = 10
    }
    "create-product" = {
      port     = 3002
      method   = "POST"
      path     = "/api/products"
      priority = 20
    }
    "update-product" = {
      port     = 3003
      method   = "PUT"
      path     = "/api/products/*"
      priority = 30
    }
    "delete-product" = {
      port     = 3004
      method   = "DELETE"
      path     = "/api/products/*"
      priority = 40
    }
  }
}
