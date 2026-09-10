# =====================================================================
#  KMS — llave de cifrado para RDS y para el secreto de credenciales
# =====================================================================
# La contraseña de RDS la gestiona y rota AWS automáticamente en
# Secrets Manager (manage_master_user_password en rds.tf), cifrada con
# esta llave. Las tareas Fargate la leen por referencia, nunca en texto plano.

resource "aws_kms_key" "main" {
  description             = "FreshBox EP1 - cifrado RDS y Secrets Manager"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = { Name = "${var.name_prefix}-kms" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}
