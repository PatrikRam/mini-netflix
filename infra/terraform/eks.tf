# ===========================================================================
# 1. ROLES IAM DEL CLÚSTER Y DE LOS NODOS
# ===========================================================================

# Rol del plano de control de EKS
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# Rol de los worker nodes (EC2). Sin estas políticas los nodos no se registran
# en el clúster (NotReady) ni pueden hacer pull de ECR (ImagePullBackOff).
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Registro del kubelet contra el control plane
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

# IPs de pods (VPC CNI)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

# Pull de imágenes desde ECR
resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Envío de métricas/logs del add-on amazon-cloudwatch-observability (Container Insights)
resource "aws_iam_role_policy_attachment" "eks_cloudwatch_agent_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_node_role.name
}

# Acceso por SSM Session Manager a los nodos (depuración sin SSH ni llaves)
resource "aws_iam_role_policy_attachment" "eks_ssm_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_role.name
}

# ===========================================================================
# 2. CLÚSTER EKS
# ===========================================================================

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    # El control plane coloca sus ENIs en las privadas; las públicas quedan
    # disponibles para LoadBalancers.
    subnet_ids              = concat(module.vpc.private_subnets, module.vpc.public_subnets)
    endpoint_public_access  = true # kubectl del equipo y GitHub Actions
    endpoint_private_access = true # los nodos hablan con el API server dentro de la VPC
  }

  access_config {
    # Solo Access Entries (API): ya no se usa el ConfigMap aws-auth.
    # Los managed node groups reciben su access entry automáticamente.
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # quien ejecuta apply (Persona 1) = admin
  }

  # Evita caer en Extended Support (6x más caro) si la versión envejece.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# Add-ons de red: se instalan ANTES que los nodos
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ===========================================================================
# 3. MANAGED NODE GROUP (2 nodos Ready en subredes privadas)
# ===========================================================================

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = module.vpc.private_subnets

  ami_type       = "AL2023_x86_64_STANDARD" # AL2 ya no existe para K8s >= 1.33
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types
  disk_size      = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    project = var.project
  }

  # Las políticas deben existir antes de que arranquen los nodos y deben
  # seguir existiendo hasta que se destruyan (si no, el destroy se cuelga).
  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# DNS interno: necesita nodos donde correr
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.default]
}

# Container Insights (CloudWatch) para la fase de monitorización
resource "aws_eks_addon" "cloudwatch" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.default,
    aws_iam_role_policy_attachment.eks_cloudwatch_agent_policy,
  ]
}
