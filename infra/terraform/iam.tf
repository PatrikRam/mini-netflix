# ===========================================================================
# GitHub Actions -> AWS sin access keys (OIDC)
#
# El workflow pide un JWT a GitHub (permissions: id-token: write), AWS STS lo
# valida contra este provider y entrega credenciales temporales (1 h) del rol
# github_actions. No hay secretos AWS de larga duración en GitHub.
# ===========================================================================

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS ya valida GitHub con su propia CA; se dejan las huellas públicas por compatibilidad.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )

  ecr_repository_arns = [for r in aws_ecr_repository.svc : r.arn]
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.project}-github-actions"
  description          = "Rol asumido por GitHub Actions (${var.github_repository}) via OIDC"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.github_oidc_provider_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Solo este repositorio y solo las ramas/entornos permitidos
        StringLike = {
          "token.actions.githubusercontent.com:sub" = flatten([
            for p in var.github_oidc_repo_prefixes : [
              for s in var.github_oidc_subjects : "repo:${p}:${s}"
            ]
          ])
        }
      }
    }]
  })
}

# Permisos mínimos: login + push/pull a los repos del proyecto y describir el clúster
data "aws_iam_policy_document" "ecr_push_and_eks_describe" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # esta acción no admite restricción por recurso
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = local.ecr_repository_arns
  }

  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }

  statement {
    sid       = "EksList"
    actions   = ["eks:ListClusters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "ecr-push-eks-describe"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push_and_eks_describe.json
}

# ---------------------------------------------------------------------------
# Permisos de GitHub Actions DENTRO del clúster (Access Entries, reemplaza aws-auth)
#   - Edit en el namespace del proyecto: set image, rollout, apply, port-forward
#   - View en todo el clúster: 'kubectl get namespace', nodos, etc.
# ---------------------------------------------------------------------------
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_edit_ns" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.kubernetes_namespace]
  }
}

resource "aws_eks_access_policy_association" "github_actions_view_cluster" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}

# ===========================================================================
# Rol del equipo (Personas 2, 3 y 4)
#
# Cada compañero usa SU PROPIO usuario IAM (o SSO) y asume este rol; nadie
# comparte claves. Se crea solo si team_member_arns no está vacío.
# ===========================================================================

resource "aws_iam_role" "team" {
  count                = length(var.team_member_arns) > 0 ? 1 : 0
  name                 = "${var.project}-team"
  description          = "Rol del equipo para operar EKS/ECR de ${var.project}"
  max_session_duration = 14400 # 4 h por sesión de trabajo

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { AWS = var.team_member_arns }
    }]
  })
}

resource "aws_iam_role_policy" "team" {
  count  = length(aws_iam_role.team)
  name   = "ecr-push-eks-describe"
  role   = aws_iam_role.team[0].id
  policy = data.aws_iam_policy_document.ecr_push_and_eks_describe.json
}

# Lectura de métricas y logs (Container Insights, dashboards) para la fase de monitorización
resource "aws_iam_role_policy_attachment" "team_cloudwatch_ro" {
  count      = length(aws_iam_role.team)
  role       = aws_iam_role.team[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_eks_access_entry" "team" {
  count         = length(aws_iam_role.team)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.team[0].arn
  type          = "STANDARD"
}

# Admin del namespace del proyecto (o de todo el clúster si team_cluster_admin = true)
resource "aws_eks_access_policy_association" "team_admin" {
  count         = length(aws_iam_role.team)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.team[0].principal_arn
  policy_arn = (
    var.team_cluster_admin
    ? "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    : "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
  )

  access_scope {
    type       = var.team_cluster_admin ? "cluster" : "namespace"
    namespaces = var.team_cluster_admin ? null : [var.kubernetes_namespace]
  }
}

resource "aws_eks_access_policy_association" "team_view_cluster" {
  count         = var.team_cluster_admin ? 0 : length(aws_iam_role.team)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.team[0].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
