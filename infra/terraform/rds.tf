# =====================================================================
#  RDS MySQL — Multi-AZ, cifrado, credenciales gestionadas
#  Reemplaza al EC2+MySQL del diseño base (más seguro y sin operación).
# =====================================================================

# Grupo de subredes: RDS vive en las 2 subredes privadas DATA
resource "aws_db_subnet_group" "data" {
  name       = "${var.name_prefix}-db-subnet"
  subnet_ids = local.data_subnet_ids
  tags       = { Name = "${var.name_prefix}-db-subnet" }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name_prefix}-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  db_name  = "freshbox"
  username = "admin"

  # AWS crea y rota la contraseña en Secrets Manager (cifrada con KMS)
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.key_id

  # Alta disponibilidad: réplica en la otra AZ con failover automático
  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.data.name
  vpc_security_group_ids = [aws_security_group.data.id]

  # Respaldos automáticos (requisito del caso: contingencia)
  backup_retention_period = 7

  # Solo público de forma temporal para cargar init.sql (default: privado)
  publicly_accessible = var.enable_db_public_seeding

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = { Name = "${var.name_prefix}-mysql" }
}
