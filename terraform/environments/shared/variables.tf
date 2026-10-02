variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type        = string
  description = "Prefix for every resource name across the shared infra."
  default     = "beantrack"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the service repos."
}

variable "github_owner_id" {
  type        = string
  description = "Numeric GitHub id of github_org - see ecs-cluster module's variables.tf for why this is required."
}

variable "github_repos" {
  type = list(object({
    name = string
    id   = string
  }))
  description = "Service repos (name + numeric GitHub repository id) allowed to assume the deploy role. Add a new entry when onboarding a new service."
}
