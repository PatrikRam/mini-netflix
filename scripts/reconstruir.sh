#!/usr/bin/env bash
# =============================================================================
# Reconstruye TODO el entorno desde cero (tras scripts/destruir.sh). ~25 min.
#   1. terraform apply           (VPC, EKS, ECR, IAM/OIDC, dashboard)
#   2. bootstrap-k8s.sh          (kubeconfig, nodos Ready, namespace, metrics-server)
#   3. Variables de GitHub       (mismos nombres de rol -> normalmente no cambian)
#   4. build + push a ECR        (los repos se recrean vacíos)
#   5. deploy-inicial.sh         (todos los microservicios + HPA)
#
# Uso: scripts/reconstruir.sh            (pide confirmación antes del apply)
#      SKIP_GITHUB=1 scripts/reconstruir.sh
# =============================================================================
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export AWS_REGION="${AWS_REGION:-us-east-2}"
TF="terraform -chdir=infra/terraform"

echo "==> 1/5 Terraform"
$TF init -input=false >/dev/null
$TF plan -input=false -out=tfplan
read -r -p "¿Aplicar este plan? [y/N] " ans
[[ "$ans" =~ ^[yY]$ ]] || { echo "Cancelado"; exit 1; }
$TF apply -input=false tfplan
rm -f infra/terraform/tfplan

echo "==> 2/5 Bootstrap del clúster"
scripts/bootstrap-k8s.sh

if [ -z "${SKIP_GITHUB:-}" ] && command -v gh >/dev/null; then
  echo "==> 3/5 Variables de GitHub Actions"
  scripts/refresh-aws-secrets.sh github || echo "AVISO: no se pudieron actualizar las variables (¿gh auth login?)"
fi

echo "==> 4/5 Build + push de imágenes a ECR"
REG=$($TF output -raw ecr_registry)
export IMAGE_TAG="${IMAGE_TAG:-manual-$(git rev-parse --short HEAD)}"
aws ecr get-login-password | docker login -u AWS --password-stdin "$REG" >/dev/null
for s in catalogo calificaciones rankings recomendaciones frontend; do
  if aws ecr describe-images --repository-name "mini-netflix/$s" --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
    echo "ya existe: $s:$IMAGE_TAG"; continue
  fi
  docker build -q -t "$REG/mini-netflix/$s:$IMAGE_TAG" "./$s" >/dev/null
  docker push -q "$REG/mini-netflix/$s:$IMAGE_TAG" >/dev/null
  echo "publicado: $s:$IMAGE_TAG"
done

echo "==> 5/5 Despliegue de la aplicación"
ECR_REGISTRY="$REG" scripts/deploy-inicial.sh

echo
$TF output cloudwatch_dashboard_url
