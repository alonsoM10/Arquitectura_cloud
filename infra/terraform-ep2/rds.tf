# =====================================================================
#  EP2 — AMAZON RDS MySQL Multi-AZ (capa 3, privada de datos)
#
#  Se mantiene el servicio gestionado ya adoptado en EP1, ajustando la
#  clase de instancia a la que exige la pauta EP2 (db.t4g.small).
# =====================================================================

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

  db_name  = var.db_name
  username = var.db_username

  # AWS genera y rota la contraseña en Secrets Manager (cifrada con KMS).
  # Nunca hay credenciales en texto plano en el repositorio.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.key_id

  # ALTA DISPONIBILIDAD: réplica síncrona en la otra AZ con failover
  # automático. Es el mecanismo central de HA de la capa de datos.
  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.data.name
  vpc_security_group_ids = [aws_security_group.data.id]

  # Snapshots automáticos diarios
  backup_retention_period = var.db_backup_retention

  # La base nunca se expone a Internet: vive en subredes privadas DATA
  publicly_accessible = false

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = { Name = "${var.name_prefix}-mysql" }
}
