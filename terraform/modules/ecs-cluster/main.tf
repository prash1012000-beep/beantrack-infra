# Shared ECS cluster + the GitHub Actions OIDC trust, applied once. Every
# service (ecs-fargate-service module) runs inside this one cluster.

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# GitHub's OIDC provider - lets Actions runs assume an AWS role via a
# short-lived federated token instead of long-lived access keys stored as
# repo secrets. One provider per AWS account, shared across every repo.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint is stable and documented; AWS also validates
  # the token signature independently, so this is a defense-in-depth check.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to specific repos, any branch/ref - a per-repo deploy
    # workflow further gates *which* ref can reach production via GitHub
    # Environments' manual-approval rule, so this doesn't need to be
    # branch-scoped too.
    #
    # Matches GitHub's extended-subject-claim format
    # (repo:<org>@<owner_id>/<repo>@<repo_id>:ref:...), confirmed from a
    # real token - plain repo:<org>/<repo>:* does NOT match this and fails
    # AssumeRoleWithWebIdentity with a generic "not authorized" error.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for repo in var.github_repos :
        "repo:${var.github_org}@${var.github_owner_id}/${repo.name}@${repo.id}:*"
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Scoped to exactly what a deploy needs: push to this account's ECR repos,
# register/update ECS task definitions, and update this cluster's services.
# Deliberately does NOT include ecs:DeleteService, iam:*, or anything that
# could touch resources outside this template's blast radius.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:*:*:repository/${var.name}-*"]
  }

  # Kept active (not just left in state) even while EC2 is the deploy
  # target - costs nothing to leave granted, and switching back to the
  # ecs-fargate-service module later needs these again.
  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"] # ECS task-def/service actions don't support resource-level scoping this granularly
  }

  # EC2/SSM deploy path: send the deploy.sh command to the instance and
  # poll for its result. SSM doesn't support resource-level scoping for
  # SendCommand's target instances via a condition that's practical here,
  # so this is account-wide for the two read-style describe calls and the
  # document itself; the actual command text (which script, which image)
  # is controlled entirely by the calling workflow, not by this policy.
  statement {
    sid    = "SSMDeploy"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/${var.name}-*-task*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.name}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
