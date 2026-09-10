# =====================================================================
#  SEED — tarea Fargate de un solo uso para poblar la BD con init.sql
# =====================================================================
#  La RDS es privada (buena práctica). Para cargar el esquema + datos se
#  ejecuta esta tarea EFÍMERA de mysql DENTRO de la VPC: usa SG-APP (que
#  ya tiene permiso 3306 → RDS) y corre en subred pública con IP pública
#  solo para poder descargar la imagen mysql de Docker Hub.
#  El contenido de init.sql viaja como variable de entorno (file()).
# =====================================================================

resource "aws_cloudwatch_log_group" "seed" {
  name              = "/ecs/${var.name_prefix}/seed"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "seed" {
  family                   = "${var.name_prefix}-seed"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "seed"
      image     = "mysql:8.0"
      essential = true

      command = ["sh", "-c", "printf '%s' \"$INIT_SQL\" | mysql -h \"$DB_HOST\" -u \"$DB_USER\""]

      environment = [
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_USER", value = "admin" },
        { name = "INIT_SQL", value = file("${path.module}/../../app/init.sql") }
      ]

      # La contraseña se inyecta desde Secrets Manager como MYSQL_PWD
      secrets = [
        { name = "MYSQL_PWD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.seed.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
