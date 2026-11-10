#!/usr/bin/env bash
# =============================================================================
# Fase 5 (Persona 1): preparar el clúster recién creado por Terraform.
#   1. kubeconfig  2. esperar 2 nodos Ready  3. namespace  4. metrics-server
# Uso: scripts/bootstrap-k8s.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export AWS_REGION="${AWS_REGION:-us-east-2}"
CLUSTER_NAME="${CLUSTER_NAME:-mini-netflix-eks}"
NAMESPACE="${NAMESPACE:-mini-netflix}"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-v0.8.0}"

echo "==> 1/4 kubeconfig"
"$ROOT_DIR/scripts/refresh-aws-secrets.sh" kubeconfig

echo "==> 2/4 Esperando nodos Ready (hasta 10 min)"
until [ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l)" -ge 2 ]; do sleep 10; done
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl get nodes -o wide

echo "==> 3/4 Namespace $NAMESPACE"
kubectl apply -f "$ROOT_DIR/k8s/eks/namespace.yaml"

echo "==> 4/4 metrics-server $METRICS_SERVER_VERSION (requerido por el HPA)"
# Se descarga de GitHub: se reintenta por si hay un fallo de red pasajero
for intento in 1 2 3 4 5; do
  kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" && break
  [ "$intento" -eq 5 ] && { echo "ERROR: no se pudo instalar metrics-server"; exit 1; }
  echo "Reintentando metrics-server ($intento/5)..."; sleep 10
done
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

echo "Esperando a que la Metrics API responda..."
for _ in $(seq 1 18); do
  kubectl top nodes 2>/dev/null && break
  sleep 10
done

kubectl get namespace "$NAMESPACE"
kubectl get apiservice v1beta1.metrics.k8s.io
echo "Clúster listo para desplegar."
