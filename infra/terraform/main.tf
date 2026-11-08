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

  # Etiqueta que Kubernetes usa para ubicar subredes al crear balanceadores
  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.k8s_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true # para que kubectl y GitHub Actions lleguen al clúster

  # ---- Adaptaciones a Learner Lab (no podemos crear roles/OIDC) ----
  create_iam_role                  = false
  iam_role_arn                     = data.aws_iam_role.lab.arn # rol del plano de control
  enable_irsa                      = false
  create_kms_key                   = false
  cluster_encryption_config        = {}
  attach_cluster_encryption_policy = false
  create_cloudwatch_log_group      = false
  cluster_enabled_log_types        = []

  # Quien ejecuta terraform (tu rol del lab) queda como administrador del clúster.
  # Como GitHub Actions usará ese mismo rol, también podrá desplegar.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    vpc-cni                         = { most_recent = true, before_compute = true }
    coredns                         = { most_recent = true }
    kube-proxy                      = { most_recent = true }
    amazon-cloudwatch-observability = { most_recent = true } # Container Insights (Fase 9)
  }

  eks_managed_node_groups = {
    default = {
      instance_types  = ["t3.medium"]
      min_size        = 2
      max_size        = 3
      desired_size    = 2
      create_iam_role = false
      iam_role_arn    = data.aws_iam_role.lab.arn # rol de los nodos
    }
  }
}