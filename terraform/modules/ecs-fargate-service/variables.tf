variable "name" {
  type        = string
  description = "Project prefix, e.g. \"beantrack\"."
}

variable "service_name" {
  type        = string
  description = "This service's name, e.g. \"backend\". Combined with `name` for all resource names."
}

variable "cluster_id" {
  type        = string
  description = "ECS cluster ARN/ID from the ecs-cluster module."
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the service's tasks run in - the networking module's public subnets by default (see that module's cost-vs-security note)."
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
  type        = list(string)
  description = "ALB listener rule path pattern routed to this service, e.g. [\"/*\"] for a single-service setup or [\"/api/backend/*\"] once multiple services share the ALB."
  default     = ["/*"]
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/actuator/health"
}

variable "cpu" {
  type        = number
  description = "Fargate task vCPU units (256 = 0.25 vCPU)."
  default     = 256
}

variable "memory" {
  type        = number
  description = "Fargate task memory in MiB."
  default     = 512
}

variable "desired_count" {
  type        = number
  description = "Initial task count. Ignored on later applies once autoscaling has adjusted it - see the ecs_service lifecycle block."
  default     = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 3
}

variable "cpu_target_percent" {
  type        = number
  description = "Target-tracking autoscaling goal for average CPU utilization."
  default     = 60
}

variable "image" {
  type        = string
  description = "Placeholder image for the very first `terraform apply`, before CI has ever pushed a real one. The deploy workflow registers a new task definition revision pointing at the real ECR image on every deploy - Terraform never manages the running image after this."
  default     = "public.ecr.aws/docker/library/nginx:alpine"
}

variable "environment" {
  type        = list(object({ name = string, value = string }))
  description = "Plain (non-secret) container environment variables."
  default     = []
}

variable "secrets" {
  type        = list(object({ name = string, valueFrom = string }))
  description = "Container environment variables sourced from Secrets Manager/SSM at task launch. `valueFrom` is the secret ARN (optionally with a :jsonKey:: suffix for one field of a JSON secret)."
  default     = []
}

variable "task_role_policy_json" {
  type        = string
  description = "Optional inline IAM policy (JSON) granting the application code's own AWS permissions (e.g. S3 access), attached to the task role. Leave null if the app doesn't call AWS APIs directly."
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}
