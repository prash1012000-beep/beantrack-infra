variable "name" {
  type        = string
  description = "Prefix for all resource names, e.g. \"beantrack\"."
}

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the service repos allowed to assume the deploy role."
}

variable "github_owner_id" {
  type        = string
  description = <<-EOT
    Numeric GitHub id of github_org. GitHub's OIDC tokens embed this
    alongside the owner name in the sub claim
    (repo:<org>@<owner_id>/<repo>@<repo_id>:...) so renaming/recreating an
    account can't inherit old trust - the trust policy must match the ID
    form exactly, or AssumeRoleWithWebIdentity fails with a generic
    "not authorized" that gives no hint why. Find it via
    `curl https://api.github.com/users/<org>` (.id field), or read
    `repository_owner_id` straight off a real token (see the debug step
    pattern in beantrack-infra's build-and-push.yml history).
  EOT
}

variable "github_repos" {
  type = list(object({
    name = string
    id   = string
  }))
  description = <<-EOT
    Repos (name + numeric GitHub repository id, same reasoning as
    github_owner_id) allowed to assume the deploy role. Find a repo's id
    via `curl https://api.github.com/repos/<org>/<repo>` (.id field), or
    the `repository_id` claim on a real token. Add a new entry when
    onboarding a new service repo.
  EOT
}
