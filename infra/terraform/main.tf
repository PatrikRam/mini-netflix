data "aws_caller_identity" "current" {}

# LabRole YA existe: solo la leemos. Es el único rol que Learner Lab nos deja usar.
data "aws_iam_role" "lab" { name = "LabRole" }

locals {
  registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"
  azs  = var.azs

  public_subnets          = ["10.0.101.0/24", "10.0.102.0/24"]
  map_public_ip_on_launch = true # los nodos salen a internet por su IP pública (sin NAT)
  enable_dns_hostnames    = true

  # Etiquetas que Kubernetes usa para ubicar subredes al crear balanceadores
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}