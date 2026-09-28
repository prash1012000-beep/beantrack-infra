locals {
  full_name = "${var.name}-${var.service_name}"
}

resource "aws_ecr_repository" "this" {
  name                 = local.full_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Untagged images pile up from every build that never got deployed (e.g. a
# superseded PR push) - expire them so the repo doesn't grow unbounded.
# Tagged (deployed) images are kept forever.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.full_name}"
  retention_in_days = var.log_retention_days
}

# --- IAM: two roles, two different jobs ---
# Execution role: the ECS agent uses this to pull the image and resolve
# `secrets` into env vars before the container even starts.
# Task role: the *application code* uses this for its own AWS API calls.
# Keeping them separate means a compromised app process can't use the
# execution role's image-pull/secrets-read permissions for anything else.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.full_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    # `valueFrom` may carry a `:jsonKey::` suffix (ECS resolves one field of
    # a JSON secret) - IAM's Resource element needs the bare secret ARN
    # (7 colon-separated parts), so trim back down to that.
    resources = [for s in var.secrets : join(":", slice(split(":", s.valueFrom), 0, 7))]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "${local.full_name}-secrets-read"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${local.full_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task_extra" {
  count  = var.task_role_policy_json != null ? 1 : 0
  name   = "${local.full_name}-app-permissions"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

resource "aws_security_group" "service" {
  name_prefix = "${local.full_name}-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From the shared ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_lb_target_group" "this" {
  name        = local.full_name
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.path_pattern
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.service_name
    image     = var.image
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    environment = var.environment
    secrets     = var.secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.service_name
      }
    }
  }])
}

data "aws_region" "current" {}

resource "aws_ecs_service" "this" {
  name            = local.full_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # The deploy workflow (not Terraform) registers new task definition
  # revisions and updates the service on every deploy - without these,
  # the next `terraform apply` would silently roll the service back to
  # this module's placeholder image. Autoscaling owns desired_count the
  # same way.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener_rule.this]
}

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${split("/", var.cluster_id)[length(split("/", var.cluster_id)) - 1]}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.full_name}-cpu-target-tracking"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.this.name
}

output "task_definition_family" {
  value = aws_ecs_task_definition.this.family
}

output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "security_group_id" {
  value = aws_security_group.service.id
}
