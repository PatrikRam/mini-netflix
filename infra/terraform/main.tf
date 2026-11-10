data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  registry   = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"

  # 10.0.1.0/24, 10.0.2.0/24 privadas (nodos) | 10.0.101.0/24, 10.0.102.0/24 públicas (NAT, ELB)
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 101)]
}

# ---------------------------------------------------------------------------
# VPC: subredes públicas (NAT + LoadBalancers) y privadas (worker nodes)
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = var.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # Los nodos viven en subredes privadas y salen a Internet (ECR, Docker Hub,
  # endpoints de EKS) por el NAT Gateway.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = false

  # Etiquetas que el cloud-controller de Kubernetes usa para ubicar subredes:
  # Service type=LoadBalancer público -> subredes públicas; interno -> privadas.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
