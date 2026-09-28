provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "../../modules/networking"

  name = var.name
  azs  = var.azs
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name         = var.name
  github_org   = var.github_org
  github_repos = var.github_repos
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "isolated_subnet_ids" {
  value = module.networking.isolated_subnet_ids
}

output "alb_security_group_id" {
  value = module.networking.alb_security_group_id
}

output "alb_dns_name" {
  value = module.networking.alb_dns_name
}

output "alb_listener_arn" {
  value = module.networking.alb_listener_arn
}

output "cluster_id" {
  value = module.ecs_cluster.cluster_id
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "github_deploy_role_arn" {
  value = module.ecs_cluster.github_deploy_role_arn
}
