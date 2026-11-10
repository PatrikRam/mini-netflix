output "region" {
  value = var.region
}

output "account_id" {
  value = local.account_id
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Subredes de los worker nodes"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Subredes de NAT Gateway y LoadBalancers"
  value       = module.vpc.public_subnets
}

output "nat_gateway_public_ips" {
  value = module.vpc.nat_public_ips
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "node_group_status" {
  value = aws_eks_node_group.default.status
}

output "ecr_registry" {
  value = local.registry
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "github_actions_role_arn" {
  description = "Valor del secret/variable AWS_ROLE_ARN en GitHub"
  value       = aws_iam_role.github_actions.arn
}

output "team_role_arn" {
  description = "Rol que asumen los compañeros (null si team_member_arns está vacío)"
  value       = try(aws_iam_role.team[0].arn, null)
}

output "node_role_arn" {
  value = aws_iam_role.eks_node_role.arn
}

output "kubeconfig_command" {
  description = "Para Persona 1 (creador del clúster)"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name} --alias ${var.cluster_name}"
}

output "kubeconfig_command_team" {
  description = "Para los compañeros (asumen el rol del equipo)"
  value = try(
    "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name} --alias ${var.cluster_name} --role-arn ${aws_iam_role.team[0].arn}",
    null
  )
}
