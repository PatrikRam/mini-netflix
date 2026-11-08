variable "region" { default = "us-east-1" }
variable "project" { default = "mini-netflix" }
variable "cluster_name" { default = "mini-netflix-eks" }
variable "k8s_version" { type = string } # valor en terraform.tfvars
# AZs fijas: algunas zonas (p. ej. us-east-1e) no admiten el plano de control de EKS
variable "azs" { default = ["us-east-1a", "us-east-1b"] }
variable "services" {
  type    = list(string)
  default = ["catalogo", "calificaciones", "rankings", "recomendaciones", "frontend"]
}