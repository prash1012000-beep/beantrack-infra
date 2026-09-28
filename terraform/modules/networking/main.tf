# Shared networking, applied once for the whole account/template.
#
# Cost-vs-security tradeoff made here deliberately: there is NO NAT Gateway
# (the single biggest recurring cost in a small ECS setup, ~$32/mo +
# per-GB data processing). Fargate tasks run in the *public* subnets with a
# public IP, but a security group only open to the ALB - not one big open
# private network, just no NAT hop. RDS lives in dedicated "isolated"
# subnets with no route to the internet at all (it never needs one).
#
# To upgrade to a private-subnet-for-compute setup later: add NAT Gateway(s)
# in the public subnets, private subnets with a route through them, move the
# ECS service's `subnets` to the private ones, and drop `assign_public_ip`
# in ecs-fargate-service.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# Public subnets: ALB + ECS Fargate tasks (public IP, locked down by SG).
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${var.azs[count.index]}" }
}

# Isolated subnets: RDS only. No route to the internet at all.
resource "aws_subnet" "isolated" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + length(var.azs))
  availability_zone = var.azs[count.index]

  tags = { Name = "${var.name}-isolated-${var.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Isolated subnets get the VPC's implicit default route table (no explicit
# association needed) - it has no internet route, which is the point.

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.name}-alb-sg" }
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# Every service gets its own target group (created in ecs-fargate-service)
# and a host/path-based listener rule off this one shared listener - that's
# how multiple services share one ALB instead of each paying for their own.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "No service configured for this path."
      status_code  = "404"
    }
  }
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "isolated_subnet_ids" {
  value = aws_subnet.isolated[*].id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_listener_arn" {
  value = aws_lb_listener.http.arn
}
