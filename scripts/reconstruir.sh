#!/usr/bin/env bash
# =============================================================================
# Reconstruye TODO el entorno desde cero (tras scripts/destruir.sh). ~25 min.
#   1. terraform apply           (VPC, EKS, ECR, IAM/OIDC, dashboard)
#   2. bootstrap-k8s.sh          (kubeconfig, nodos Ready, namespace, metrics-server)
#   3. Variables de GitHub       (INFRA_ACTIVA=true -> reactiva el CD automático)
#   4. build + push a ECR        (los repos se recrean vacíos)
#   5. deploy-inicial.sh         (todos los microservicios + HPA)
#
# Uso: scripts/reconstruir.sh             (pide confirmación antes del apply)
#      DESDE=4 scripts/reconstruir.sh     (reanuda desde un paso si algo falló)
#      SKIP_GITHUB=1 scripts/reconstruir.sh
# Log completo: evidencias/reconstruir-<fecha>.log
# =============================================================================
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export AWS_REGION="${AWS_REGION:-us-east-2}"
TF="terraform -chdir=infra/terraform"
DESDE="${DESDE:-1}"

mkdir -p evidencias
LOG="evidencias/reconstruir-$(date +%Y%m%d-%H%M).log"
exec > >(tee -a "$LOG") 2>&1

PASO=0
trap 'echo; echo "✖ FALLÓ el paso $PASO/5 (línea $LINENO). Revisa el log: $LOG"; echo "  Para reanudar sin repetir lo anterior:  DESDE=$PASO scripts/reconstruir.sh"' ERR

paso() { PASO=$1; echo; echo "==> $1/5 $2"; }
hacer() { [ "$DESDE" -le "$1" ]; }

if hacer 1; then
  paso 1 "Terraform"
  $TF init -input=false >/dev/null
  $TF plan -input=false -out=tfplan
  read -r -p "¿Aplicar este plan? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { echo "Cancelado"; exit 1; }
  $TF apply -input=false tfplan
  rm -f infra/terraform/tfplan
fi

if hacer 2; then
  paso 2 "Bootstrap del clúster"
  scripts/bootstrap-k8s.sh
fi

if hacer 3 && [ -z "${SKIP_GITHUB:-}" ] && command -v gh >/dev/null; then
  paso 3 "Variables de GitHub Actions"
  scripts/refresh-aws-secrets.sh github || echo "AVISO: no se pudieron actualizar las variables (¿gh auth login?)"
fi

REG=$($TF output -raw ecr_registry)
export IMAGE_TAG="${IMAGE_TAG:-manual-$(git rev-parse --short HEAD)}"

if hacer 4; then
  paso 4 "Build + push de imágenes a ECR (tag $IMAGE_TAG)"
  aws ecr get-login-password | docker login -u AWS --password-stdin "$REG" >/dev/null
  for s in catalogo calificaciones rankings recomendaciones frontend; do
    if aws ecr describe-images --repository-name "mini-netflix/$s" --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
      echo "ya existe: $s:$IMAGE_TAG"; continue
    fi
    docker build -q -t "$REG/mini-netflix/$s:$IMAGE_TAG" "./$s" >/dev/null
    docker push -q "$REG/mini-netflix/$s:$IMAGE_TAG" >/dev/null
    echo "publicado: $s:$IMAGE_TAG"
  done
fi

if hacer 5; then
  paso 5 "Despliegue de la aplicación"
  ECR_REGISTRY="$REG" scripts/deploy-inicial.sh
fi

trap - ERR
echo
echo "✔ Reconstrucción completa. Log: $LOG"
$TF output cloudwatch_dashboard_url
