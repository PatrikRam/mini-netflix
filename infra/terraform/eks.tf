# Clúster EKS con recursos nativos. El módulo de la comunidad consulta iam:GetRole
# sobre tu rol "voclabs" (denegado en Learner Lab); aquí no hay esa consulta.

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = data.aws_iam_role.lab.arn # LabRole como rol del plano de control

  vpc_config {
    subnet_ids             = module.vpc.public_subnets
    endpoint_public_access = true # para que kubectl y GitHub Actions lleguen al clúster
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # EKS da administrador al principal que crea el clúster (tu rol del lab).
    # GitHub Actions usa las credenciales de ese mismo rol, así que también podrá desplegar.
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# Red y proxy de los nodos: se instalan ANTES de crear los nodos
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = data.aws_iam_role.lab.arn # LabRole también para los nodos
  subnet_ids      = module.vpc.public_subnets
  instance_types  = ["t3.medium"]

  scaling_config {
    min_size     = 2
    max_size     = 3
    desired_size = 2
  }

  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
}

# DNS interno: necesita que ya existan nodos donde correr
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}

# Container Insights (CloudWatch). Es el más probable de fallar en Learner Lab:
# si da error, comenta este recurso y usa el plan B de la Fase 9.
resource "aws_eks_addon" "cloudwatch" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}