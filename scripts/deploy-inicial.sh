#!/usr/bin/env bash
# =============================================================================
# Despliegue COMPLETO de Mini-Netflix en EKS (primera vez o tras reconstruir).
# Después de esto, el CD (deploy-k8s.sh desde GitHub Actions) solo actualiza
# las imágenes de los Deployments que ya existen.
#
# Uso:
#   IMAGE_TAG=<tag-en-ECR> scripts/deploy-inicial.sh
#
# Es idempotente: si los Secrets ya existen en el clúster, se REUTILIZAN
# (cambiar la contraseña rompería las bases de datos ya inicializadas).
# Las contraseñas se generan al azar y solo viven en el clúster, nunca en Git.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export AWS_REGION="${AWS_REGION:-us-east-2}"
NAMESPACE="${NAMESPACE:-mini-netflix}"
: "${IMAGE_TAG:?Define IMAGE_TAG (ej. IMAGE_TAG=manual-abc1234 o el SHA publicado por CI)}"

if [ -z "${ECR_REGISTRY:-}" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
fi
export ECR_REGISTRY IMAGE_TAG

k() { kubectl -n "$NAMESPACE" "$@"; }
render() { envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${CALIFICACIONES_DB_PASSWORD}' < "$1"; }
secret_val() { k get secret "$1" -o jsonpath="{.data.$2}" 2>/dev/null | base64 -d 2>/dev/null || true; }

echo "==> Verificando que las 5 imágenes existen en ECR con tag $IMAGE_TAG"
for s in catalogo calificaciones rankings recomendaciones frontend; do
  aws ecr describe-images --repository-name "mini-netflix/$s" --image-ids imageTag="$IMAGE_TAG" >/dev/null \
    || { echo "ERROR: falta mini-netflix/$s:$IMAGE_TAG en ECR"; exit 1; }
done

echo "==> Namespace"
kubectl apply -f k8s/eks/namespace.yaml

echo "==> Secrets (se reutilizan si ya existen)"
if ! k get secret catalogo-secrets >/dev/null 2>&1; then
  k create secret generic catalogo-secrets \
    --from-literal=db-password="$(openssl rand -hex 16)" \
    --from-literal=django-secret-key="$(openssl rand -hex 32)"
fi
CALIFICACIONES_DB_PASSWORD="$(secret_val calificaciones-secrets db-password)"
export CALIFICACIONES_DB_PASSWORD="${CALIFICACIONES_DB_PASSWORD:-$(openssl rand -hex 16)}"

echo "==> Dataset de películas (ConfigMap)"
k create configmap peliculas-dataset --from-file=docs/peliculas.json \
  --dry-run=client -o yaml | kubectl apply -n "$NAMESPACE" -f -

echo "==> Bases de datos"
render k8s/eks/catalogo-db.yaml | k apply -f -
k rollout status deployment/catalogo-db --timeout=180s

echo "==> Catálogo + migración/seed + HPA"
render k8s/eks/catalogo.yaml | k apply -f -
k delete job catalogo-migrate --ignore-not-found
render k8s/eks/catalogo-migrate-job.yaml | k apply -f -
render k8s/eks/catalogo-hpa.yaml | k apply -f -

echo "==> Calificaciones (+ su DB y seed), Rankings (+ HPA), Recomendaciones, Frontend"
k delete job calificaciones-seed --ignore-not-found
for f in calificaciones rankings recomendaciones frontend; do
  render "k8s/eks/$f.yaml" | k apply -f -
done

echo "==> Esperando Jobs de datos"
k wait --for=condition=complete job/catalogo-migrate --timeout=300s
k wait --for=condition=complete job/calificaciones-seed --timeout=300s

echo "==> Esperando rollouts"
for d in catalogo calificaciones rankings recomendaciones frontend; do
  k rollout status "deployment/$d" --timeout=300s
done

echo "==> Esperando URL pública del frontend (LoadBalancer)"
for _ in $(seq 1 30); do
  LB=$(k get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

k get pods,svc,hpa
echo
echo "Frontend: http://${LB:-<pendiente>}   (el DNS del ELB puede tardar 1-3 min en responder)"
