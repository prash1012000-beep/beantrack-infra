variable "name" {
  type        = string
  description = "Prefix for all resource names, e.g. \"beantrack\"."
}

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the service repos allowed to assume the deploy role."
}

variable "github_repos" {
  type        = list(string)
  description = "Repo names (without the org prefix) allowed to assume the deploy role, e.g. [\"beantrack-backend\"]. Add a new entry here when onboarding a new service repo."
}
