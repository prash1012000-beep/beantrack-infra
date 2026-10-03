variable "name" {
  type        = string
  description = "Project prefix, e.g. \"beantrack\"."
}

variable "service_name" {
  type        = string
  description = "This service's name, e.g. \"backend\". Combined with `name` for all resource names."
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type        = string
  description = "A single public subnet (networking module's public_subnet_ids[0]) - one instance, no need to spread across AZs."
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_listener_arn" {
  type = string
}

variable "listener_rule_priority" {
  type        = number
  description = "Must be unique across every service sharing this ALB listener."
}

variable "path_pattern" {
  type    = list(string)
  default = ["/*"]
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/actuator/health"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the existing ECR repository to grant this instance pull access to (reused from the ecs-fargate-service module's repo, not recreated here)."
}

variable "image" {
  type        = string
  description = "Placeholder image the instance starts with at boot, before the first real deploy. Same role as the Fargate module's `image` default - deploy.sh overwrites it on every real deploy."
  default     = "public.ecr.aws/docker/library/nginx:alpine"
}

variable "environment" {
  type        = list(object({ name = string, value = string }))
  description = "Plain (non-secret) container environment variables, written to /opt/<service>/app.env at boot."
  default     = []
}

variable "secrets" {
  type = list(object({
    env_name   = string
    secret_arn = string
    jq_filter  = string # "." for a plain-string secret, ".fieldName" for one field of a JSON secret
  }))
  description = "Resolved into /opt/<service>/secrets.env via `aws secretsmanager get-secret-value` + jq, at boot and on every deploy (so a rotated secret takes effect on the next deploy, not just a reboot)."
  default     = []
}
