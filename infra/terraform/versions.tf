terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80" # >= 5.80: access entries, thumbprint opcional en OIDC
    }
  }
}

# Las credenciales NUNCA van aquí: Terraform usa la cadena estándar del AWS CLI
# (perfil en ~/.aws, AWS_PROFILE o SSO). Ver scripts/refresh-aws-secrets.sh.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = "persona-1-infra"
    }
  }
}
