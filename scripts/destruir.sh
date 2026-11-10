#!/usr/bin/env bash
# =============================================================================
# Fase 11: destrucción limpia de TODO (para el video/demostración).
#   1. Borra el namespace -> elimina los LoadBalancers que creó Kubernetes
#      (no están en el state de Terraform y bloquearían el borrado de la VPC)
#   2. terraform plan -destroy + apply
#   3. Limpia log groups de Container Insights y verifica que no queda nada
# Uso: scripts/destruir.sh
# =============================================================================
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export AWS_REGION="${AWS_REGION:-us-east-2}"
CLUSTER=mini-netflix-eks
TF="terraform -chdir=infra/terraform"

echo "==> Estado actual"
$TF output 2>/dev/null | grep -E 'cluster_name|ecr_registry|vpc_id' || true
kubectl get svc -A 2>/dev/null | grep LoadBalancer || true

read -r -p "Se DESTRUIRÁ toda la infraestructura (imágenes ECR incluidas). ¿Continuar? [y/N] " ans
[[ "$ans" =~ ^[yY]$ ]] || { echo "Cancelado"; exit 1; }

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh variable set INFRA_ACTIVA --repo "${GITHUB_REPO:-PatrikRam/mini-netflix}" --body false \
    && echo "GitHub Actions: build/deploy automáticos desactivados (INFRA_ACTIVA=false)"
fi

echo "==> 1/3 Liberando recursos creados por Kubernetes"
if kubectl get namespace mini-netflix >/dev/null 2>&1; then
  kubectl delete namespace mini-netflix --wait=true --timeout=300s
fi
for _ in $(seq 1 18); do
  n=$(aws elb describe-load-balancers --query 'length(LoadBalancerDescriptions[?VPCId==`'"$($TF output -raw vpc_id)"'`])' --output text 2>/dev/null || echo 0)
  [ "$n" = "0" ] && break
  echo "Esperando que AWS borre $n LoadBalancer(s)..."; sleep 10
done

echo "==> 2/3 Terraform destroy"
$TF plan -destroy -input=false -out=destroy.tfplan
$TF apply -input=false destroy.tfplan
rm -f infra/terraform/destroy.tfplan

echo "==> 3/3 Limpieza y verificación"
for lg in $(aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/$CLUSTER" --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$lg" && echo "log group borrado: $lg"
done
echo "State:        $($TF state list | wc -l) recursos"
echo "Clústeres:    $(aws eks list-clusters --query 'clusters' --output text)"
echo "NAT activos:  $(aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'length(NatGateways)' --output text)"
echo "ELB clásicos: $(aws elb describe-load-balancers --query 'length(LoadBalancerDescriptions)' --output text)"
echo "EC2 activas:  $(aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=$CLUSTER Name=instance-state-name,Values=running,pending --query 'length(Reservations)' --output text)"
echo "EIPs libres:  $(aws ec2 describe-addresses --query 'length(Addresses[?AssociationId==null])' --output text)"
echo "Destrucción completada."
