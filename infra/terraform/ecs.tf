# =====================================================================
#  ECS FARGATE — 4 servicios en contenedores, sin servidores que operar
#  Reemplaza al EC2+Docker+ASG del diseño base.
# =====================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

# Un grupo de logs por microservicio
resource "aws_cloudwatch_log_group" "svc" {
  for_each          = local.services
  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = 7
}

# --- Task Definitions (1 por microservicio) ---
resource "aws_ecs_task_definition" "svc" {
  for_each = local.services

  family                   = "${var.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  # En Learner Lab se reutiliza LabRole (no se pueden crear roles)
  execution_role_arn = data.aws_iam_role.lab.arn
  task_role_arn      = data.aws_iam_role.lab.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${local.ecr_registry}/${var.name_prefix}-${each.key}:latest"
      essential = true

      portMappings = [{ containerPort = each.value.port }]

      # Datos no sensibles como variables de entorno
      environment = [
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_NAME", value = "freshbox" },
        { name = "DB_PORT", value = "3306" },
        { name = "PORT", value = tostring(each.value.port) }
      ]

      # Credenciales inyectadas desde Secrets Manager (nunca en texto plano)
      secrets = [
        { name = "DB_USER", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:username::" },
        { name = "DB_PASS", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.svc[each.key].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# --- Services (mantienen 2 tareas por microservicio, repartidas Multi-AZ) ---
resource "aws_ecs_service" "svc" {
  for_each = local.services

  name            = "${var.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.svc[each.key].arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false # salida por VPC Endpoints, no por Internet
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  # Evita fallo si la imagen aún no está en ECR en el primer apply
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

# --- Auto Scaling por servicio (mín 2, máx 4, objetivo CPU 70%) ---
resource "aws_appautoscaling_target" "svc" {
  for_each = local.services

  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.svc[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.services

  name               = "${each.key}-cpu70"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70
  }
}
