#!/usr/bin/env bash
set -euo pipefail

# CD de Mini-Netflix: actualizar Deployments existentes.
# Compatible con EKS o K3s mediante kubeconfig.
# No crea ni elimina bases de datos, Jobs o volúmenes.

NAMESPACE="${NAMESPACE:-mini-netflix}"
: "${ECR_REGISTRY:?Falta ECR_REGISTRY}"
: "${IMAGE_TAG:?Falta IMAGE_TAG}"

SERVICIOS=(catalogo calificaciones rankings recomendaciones frontend)

echo "Verificando acceso al namespace: $NAMESPACE"
kubectl get namespace "$NAMESPACE" >/dev/null

echo "Comprobando que existen los Deployments..."
for servicio in "${SERVICIOS[@]}"; do
  kubectl -n "$NAMESPACE" get deployment "$servicio" >/dev/null
done

echo "Actualizando imágenes..."
for servicio in "${SERVICIOS[@]}"; do
  imagen="${ECR_REGISTRY}/mini-netflix/${servicio}:${IMAGE_TAG}"

  kubectl -n "$NAMESPACE" set image \
    "deployment/${servicio}" \
    "${servicio}=${imagen}"

  echo "Actualizado: $servicio"
done

echo "Verificando los rollouts..."
for servicio in "${SERVICIOS[@]}"; do
  kubectl -n "$NAMESPACE" rollout status \
    "deployment/${servicio}" \
    --timeout=180s
done

echo "Despliegue verificado correctamente."
