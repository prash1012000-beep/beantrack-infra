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

variable "github_repos" {
  type        = list(string)
  description = "Service repos allowed to assume the deploy role. Add a new entry when onboarding a new service."
  default     = ["beantrack-backend"]
}
