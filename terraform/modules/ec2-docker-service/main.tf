locals {
  full_name = "${var.name}-${var.service_name}"
}

data "aws_region" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- IAM: one instance role covers both jobs an ECS task split across two
# roles (execution vs. task) - there's no separate "agent" pulling the
# image here, the instance does everything itself. ---

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.full_name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${local.full_name}-ecr-pull"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

data "aws_iam_policy_document" "secrets_read" {
  count = length(var.secrets) > 0 ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = distinct([for s in var.secrets : s.secret_arn])
  }
}

resource "aws_iam_role_policy" "secrets_read" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "${local.full_name}-secrets-read"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.secrets_read[0].json
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.full_name}-instance"
  role = aws_iam_role.instance.name
}

# --- Networking (same posture as the Fargate module: public subnet,
# security group locked to the ALB only) ---

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

resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.service.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    service_name          = var.service_name
    region                = data.aws_region.current.name
    container_port        = var.container_port
    initial_image         = var.image
    secrets_manifest_json = jsonencode(var.secrets)
    environment_env_lines = join("\n", [for e in var.environment : "${e.name}=${e.value}"])
  })

  tags = { Name = local.full_name }

  # Changing user_data on an existing instance doesn't re-run it (cloud-init
  # only runs on first boot) - deploys go through deploy.sh via SSM, not
  # through re-applying Terraform, so this is intentional, not a gap.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_lb_target_group" "this" {
  # Suffixed, not local.full_name bare - the Fargate module used that exact
  # name, and its target group is still alive in AWS (state rm doesn't
  # destroy), so the bare name collides. Both can coexist under their own
  # names; only one has a listener rule pointed at it at a time.
  name        = "${local.full_name}-ec2"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "this" {
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_instance.this.id
  port             = var.container_port
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

output "instance_id" {
  value = aws_instance.this.id
}

output "security_group_id" {
  value = aws_security_group.service.id
}

output "instance_role_arn" {
  value = aws_iam_role.instance.arn
}
