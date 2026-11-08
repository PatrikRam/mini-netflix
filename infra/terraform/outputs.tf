output "ecr_registry" { value = local.registry }
output "kubeconfig_command" { value = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}" }