# ---------------------------------------------------------------------------
# Generales
# ---------------------------------------------------------------------------
variable "region" {
  description = "Región AWS. us-east-1 está bloqueada por SCP en esta cuenta."
  type        = string
  default     = "us-east-2"
}

variable "azs" {
  description = "Dos AZs de Ohio (EKS exige subredes en al menos 2 AZs)."
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "project" {
  type    = string
  default = "mini-netflix"
}

variable "cluster_name" {
  type    = string
  default = "mini-netflix-eks"
}

variable "k8s_version" {
  description = <<-EOT
    Versión de Kubernetes. Usa SIEMPRE una en STANDARD_SUPPORT (las de
    EXTENDED_SUPPORT cobran $0.60/h en vez de $0.10/h). Consultar con:
    aws eks describe-cluster-versions --region us-east-2 --default-only
  EOT
  type        = string
  default     = "1.37"
}

variable "services" {
  description = "Un repositorio ECR por microservicio (mini-netflix/<servicio>)."
  type        = list(string)
  default     = ["catalogo", "calificaciones", "rankings", "recomendaciones", "frontend"]
}

variable "kubernetes_namespace" {
  description = "Namespace donde despliegan GitHub Actions y el equipo."
  type        = string
  default     = "mini-netflix"
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = 1 NAT Gateway compartido (~$32/mes + datos). Recomendado para la demo.
    false = 1 NAT Gateway por AZ (alta disponibilidad, ~el doble de costo).
  EOT
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Nodos
# ---------------------------------------------------------------------------
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# ---------------------------------------------------------------------------
# GitHub Actions (OIDC, sin access keys)
# ---------------------------------------------------------------------------
variable "github_repository" {
  description = "Repositorio en formato owner/repo autorizado a asumir el rol de CI/CD."
  type        = string
  default     = "PatrikRam/mini-netflix"
}

variable "github_oidc_repo_prefixes" {
  description = <<-EOT
    Formas exactas en que GitHub identifica al repositorio en el claim 'sub'.
    Con "immutable subject" activo, GitHub usa owner@<id>/repo@<id>. Consultar con:
    gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  type        = list(string)
  default     = ["PatrikRam/mini-netflix", "PatrikRam@104391546/mini-netflix@1396175104"]
}

variable "github_oidc_subjects" {
  description = <<-EOT
    Sufijos del claim 'sub' permitidos (después de repo:<owner>/<repo>:).
    - ref:refs/heads/main   -> ejecuciones sobre la rama main
    - environment:<nombre>  -> si el job declara 'environment:'
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "create_github_oidc_provider" {
  description = "false si la cuenta ya tiene el provider token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Equipo (acceso humano al clúster y a ECR)
# ---------------------------------------------------------------------------
variable "team_member_arns" {
  description = <<-EOT
    ARNs de los usuarios/roles IAM de los compañeros que podrán asumir el rol
    del equipo (ej. arn:aws:iam::<cuenta>:user/persona2). Se define en
    terraform.tfvars (no versionado).
  EOT
  type        = list(string)
  default     = []
}

variable "team_cluster_admin" {
  description = "true = el rol del equipo es admin de TODO el clúster; false = admin solo del namespace."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Presupuesto
# ---------------------------------------------------------------------------
variable "budget_limit_usd" {
  description = "Límite mensual en USD para la alerta de AWS Budgets."
  type        = number
  default     = 50
}

variable "budget_alert_emails" {
  description = "Correos que reciben las alertas (vacío = no se crea el budget). Va en terraform.tfvars."
  type        = list(string)
  default     = []
}
