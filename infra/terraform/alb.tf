# =====================================================================
#  ALB — Application Load Balancer (capa pública)
#  Enruta por MÉTODO HTTP + ruta hacia cada microservicio.
# =====================================================================

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = "${var.name_prefix}-alb" }
}

# Un Target Group por microservicio (targets = IPs de tareas Fargate)
resource "aws_lb_target_group" "svc" {
  for_each = local.services

  name        = "${var.name_prefix}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

# Listener HTTP:80. Por defecto sirve el frontend (todo lo que no sea /api).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# Reglas: cada método HTTP va a su microservicio
resource "aws_lb_listener_rule" "svc" {
  for_each = local.services

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }

  condition {
    http_request_method {
      values = [each.value.method]
    }
  }
}
