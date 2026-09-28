  # beantrack-infra

Reusable AWS deployment template: Terraform modules for ECS Fargate + a
shared ALB, and GitHub Actions reusable workflows to build/push/deploy a
container image. One service (`beantrack-backend`) uses it today; the goal
is that onboarding the *next* service is copying a thin per-service layer,
not re-deriving any of this.

## Architecture

- **Compute:** ECS on Fargate, one shared cluster for every service.
- **Networking:** one VPC, one ALB shared by all services (host/path-based
  routing per service), no NAT Gateway — Fargate tasks run in public
  subnets with a security group locked to the ALB only. See
  `terraform/modules/networking/main.tf` for the cost-vs-security tradeoff
  and how to upgrade to private subnets later.
- **Registry:** one ECR repo per service (created by `ecs-fargate-service`).
- **State:** S3 + DynamoDB, bootstrapped once by `terraform/bootstrap`.
- **CI/CD auth:** GitHub OIDC → a scoped IAM role, no long-lived AWS keys
  in any repo secret.
- **Ownership split:** Terraform manages the ECS *service*, ALB, IAM, etc.
  CI manages the running *image* — it registers a new task definition
  revision and updates the service on every deploy. Terraform is told to
  ignore that (see `ecs-fargate-service`'s `lifecycle` block) so a routine
  `terraform apply` never rolls a deploy back.

## One-time account setup

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="aws_region=us-east-1"
# note the state_bucket output
```

Fill that bucket name into `terraform/environments/shared/backend.tf`
(`bucket = "..."`), then:

```bash
cd terraform/environments/shared
cp terraform.tfvars.example terraform.tfvars   # fill in github_org, etc.
terraform init
terraform apply
```

Note the outputs — `github_deploy_role_arn`, `cluster_name`,
`alb_dns_name` — you'll need them for every service repo's workflow and
Terraform.

## Onboarding a new service

1. In `terraform/environments/shared/terraform.tfvars`, add the new repo
   name to `github_repos` and `terraform apply` (grants that repo's Actions
   runs permission to assume the deploy role).
2. In the service repo: a `Dockerfile`, a `terraform/` directory that
   instantiates the `ecs-fargate-service` module (see
   `beantrack-backend/terraform/` for the reference instance — RDS, secrets,
   and the module call live there, not here, since they're per-service),
   and a `.github/workflows/ci-cd.yml` that calls this repo's two reusable
   workflows. Copy `beantrack-backend`'s versions of all three as the
   starting point.
3. Give the new service a distinct `listener_rule_priority` and
   `path_pattern` in its `ecs-fargate-service` module call — every service
   shares one ALB listener, so these can't collide.

## Reusable workflows

- `.github/workflows/build-and-push.yml` — builds the Dockerfile at a given
  context, pushes to the service's ECR repo tagged with the git SHA.
- `.github/workflows/deploy.yml` — renders that image into the current ECS
  task definition, registers a new revision, updates the service, waits for
  it to stabilize.

Call them with `uses: <org>/beantrack-infra/.github/workflows/build-and-push.yml@main`
(and pin to a tag once this repo has a release, rather than tracking `main`
forever).

ECR repos here are tag-**immutable** — re-running a workflow for the exact
same commit SHA will fail to re-push that tag. This is deliberate (prevents
silently swapping out a deployed image); re-run means re-trigger with a new
commit, not force-push the same tag.

## What's deliberately out of scope for v1

- HTTPS on the ALB (needs an ACM cert + a real domain — add an
  `aws_lb_listener` on 443 once you have one; the security group already
  allows 443 inbound).
- Multi-region / multi-account.
- A staging vs. production *environment* split at the Terraform level —
  right now this template stands up one environment. Duplicate
  `environments/shared` and `<service>/terraform` per environment (e.g.
  `environments/staging`, `environments/prod`) when you actually need two;
  don't build it before you do.
