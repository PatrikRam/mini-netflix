#!/usr/bin/env bash
# =============================================================================
# refresh-aws-secrets.sh — Acceso seguro a AWS/EKS para Mini-Netflix (us-east-2)
#
# Principio: NINGUNA credencial de larga duración sale de tu máquina ni entra
# al repositorio. GitHub Actions usa OIDC (rol temporal) y kubectl usa tokens
# EKS de 15 minutos que se regeneran solos (aws eks get-token).
#
# Uso:
#   scripts/refresh-aws-secrets.sh check          # identidad, región, acceso al clúster
#   scripts/refresh-aws-secrets.sh kubeconfig     # (re)genera el contexto de kubectl
#   scripts/refresh-aws-secrets.sh token          # muestra expiración del token EKS actual
#   scripts/refresh-aws-secrets.sh github [owner/repo]   # publica variables NO secretas en GitHub
#   scripts/refresh-aws-secrets.sh purge-legacy [owner/repo]  # borra secrets viejos (keys/kubeconfig)
#   scripts/refresh-aws-secrets.sh rotate-keys    # rota TU access key IAM local (solo usuarios IAM)
#   scripts/refresh-aws-secrets.sh all [owner/repo]       # check + kubeconfig + github
#
# Variables de entorno opcionales:
#   AWS_PROFILE    perfil del AWS CLI (por defecto: el perfil default)
#   AWS_REGION     por defecto us-east-2
#   CLUSTER_NAME   por defecto: terraform output, o mini-netflix-eks
#   ROLE_ARN       rol a asumir para kubectl (compañeros: rol mini-netflix-team)
#   GITHUB_REPO    por defecto PatrikRam/mini-netflix
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/terraform"

export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
GITHUB_REPO="${GITHUB_REPO:-PatrikRam/mini-netflix}"
NAMESPACE="${NAMESPACE:-mini-netflix}"

log()  { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Falta '$1' en el PATH"; }

# Lee un output de Terraform si existe el state local (solo Persona 1 lo tiene)
tf_out() {
  [ -d "$TF_DIR/.terraform" ] || return 1
  command -v terraform >/dev/null 2>&1 || return 1
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null
}

CLUSTER_NAME="${CLUSTER_NAME:-$(tf_out cluster_name || echo mini-netflix-eks)}"

# -----------------------------------------------------------------------------
cmd_check() {
  need aws
  log "Región: $AWS_REGION | Perfil: ${AWS_PROFILE:-default} | Clúster: $CLUSTER_NAME"

  local arn
  if ! arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
    warn "No hay sesión AWS válida."
    if aws configure get sso_start_url >/dev/null 2>&1 || aws configure get sso_session >/dev/null 2>&1; then
      die "Tu perfil usa SSO: ejecuta  aws sso login${AWS_PROFILE:+ --profile $AWS_PROFILE}"
    fi
    die "Configura tu perfil:  aws configure${AWS_PROFILE:+ --profile $AWS_PROFILE}"
  fi
  ok "Identidad AWS: $arn"

  if [ -n "${ROLE_ARN:-}" ]; then
    aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "check-$(whoami)" \
      --query 'AssumedRoleUser.Arn' --output text >/dev/null \
      || die "No puedes asumir $ROLE_ARN (¿tu usuario está en team_member_arns?)"
    ok "Puedes asumir $ROLE_ARN"
  fi

  local status
  status=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.status --output text 2>/dev/null) \
    || { warn "No se pudo describir el clúster (¿no existe aún o sin permisos?)"; return 0; }
  ok "Clúster $CLUSTER_NAME: $status"

  if command -v kubectl >/dev/null 2>&1 && kubectl config current-context >/dev/null 2>&1; then
    if kubectl get nodes >/dev/null 2>&1; then
      ok "kubectl conectado. Nodos:"
      kubectl get nodes -o wide
    else
      warn "kubectl no conecta: ejecuta  $0 kubeconfig"
    fi
  fi
}

# -----------------------------------------------------------------------------
cmd_kubeconfig() {
  need aws; need kubectl
  local args=(eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" --alias "$CLUSTER_NAME")
  [ -n "${ROLE_ARN:-}" ] && args+=(--role-arn "$ROLE_ARN")
  [ -n "${AWS_PROFILE:-}" ] && args+=(--profile "$AWS_PROFILE")

  aws "${args[@]}"
  kubectl config set-context --current --namespace "$NAMESPACE" >/dev/null
  chmod 600 "${KUBECONFIG:-$HOME/.kube/config}" 2>/dev/null || true
  ok "Contexto '$CLUSTER_NAME' listo (namespace por defecto: $NAMESPACE)."
  log "El kubeconfig NO guarda tokens: cada kubectl llama a 'aws eks get-token' (válido 15 min)."
  # Solo el usuario: 'kubectl auth whoami' completo muestra el Access Key ID
  kubectl auth whoami -o jsonpath='{.status.userInfo.username}{"\n"}' 2>/dev/null || true
}

# -----------------------------------------------------------------------------
cmd_token() {
  need aws
  local args=(eks get-token --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION")
  [ -n "${ROLE_ARN:-}" ] && args+=(--role-arn "$ROLE_ARN")
  local exp
  exp=$(aws "${args[@]}" --query status.expirationTimestamp --output text)
  ok "Token EKS nuevo generado; expira: $exp (se renueva automáticamente)"
}

# -----------------------------------------------------------------------------
cmd_github() {
  need gh
  local repo="${1:-$GITHUB_REPO}"
  gh auth status >/dev/null 2>&1 || die "Ejecuta primero: gh auth login"

  local role_arn registry
  role_arn="$(tf_out github_actions_role_arn || true)"
  registry="$(tf_out ecr_registry || true)"
  [ -n "$role_arn" ] || die "No hay output github_actions_role_arn. ¿Ejecutaste terraform apply?"

  # Estos valores NO son secretos (un ARN no da acceso por sí solo: la confianza
  # está limitada por OIDC al repo $repo). Se guardan como Variables de Actions.
  gh variable set AWS_ROLE_ARN     --repo "$repo" --body "$role_arn"
  gh variable set AWS_REGION       --repo "$repo" --body "$AWS_REGION"
  gh variable set EKS_CLUSTER_NAME --repo "$repo" --body "$CLUSTER_NAME"
  gh variable set ECR_REGISTRY     --repo "$repo" --body "$registry"
  ok "Variables actualizadas en $repo: AWS_ROLE_ARN, AWS_REGION, EKS_CLUSTER_NAME, ECR_REGISTRY"
  log "Ningún access key fue enviado a GitHub."
}

# -----------------------------------------------------------------------------
cmd_purge_legacy() {
  need gh
  local repo="${1:-$GITHUB_REPO}"
  local legacy=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN KUBECONFIG_B64)
  log "Se eliminarán de $repo los secrets: ${legacy[*]}"
  read -r -p "¿Confirmas? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "Cancelado"; return 0; }
  for s in "${legacy[@]}"; do
    if gh secret delete "$s" --repo "$repo" 2>/dev/null; then ok "eliminado: $s"; else log "no existía: $s"; fi
  done
}

# -----------------------------------------------------------------------------
# Rota la access key del usuario IAM local: crea una nueva, la guarda en el
# perfil, verifica que funciona y recién entonces desactiva y borra la vieja.
cmd_rotate_keys() {
  need aws
  local profile="${AWS_PROFILE:-default}"
  local arn user old_key new_json new_id new_secret
  arn=$(aws sts get-caller-identity --query Arn --output text)
  [[ "$arn" == *":user/"* ]] || die "Solo aplica a usuarios IAM (tu identidad es $arn)"
  user="${arn##*/}"
  old_key=$(aws configure get aws_access_key_id --profile "$profile")

  [ "$(aws iam list-access-keys --user-name "$user" --query 'length(AccessKeyMetadata)' --output text)" -lt 2 ] \
    || die "El usuario ya tiene 2 keys; borra la que no uses en la consola IAM."

  read -r -p "Rotar la access key de '$user' (perfil $profile)? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "Cancelado"; return 0; }

  new_json=$(aws iam create-access-key --user-name "$user" --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  new_id=$(cut -f1 <<<"$new_json"); new_secret=$(cut -f2 <<<"$new_json")
  aws configure set aws_access_key_id "$new_id" --profile "$profile"
  aws configure set aws_secret_access_key "$new_secret" --profile "$profile"
  unset new_json new_secret

  log "Esperando propagación de la nueva key..."
  for _ in $(seq 1 12); do
    aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1 && break
    sleep 5
  done
  aws sts get-caller-identity --profile "$profile" >/dev/null || die "La nueva key no funciona; la vieja sigue activa."

  aws iam update-access-key --user-name "$user" --access-key-id "$old_key" --status Inactive
  aws iam delete-access-key --user-name "$user" --access-key-id "$old_key"
  ok "Key rotada para $user (nueva: ${new_id:0:4}****************)"
}

# -----------------------------------------------------------------------------
case "${1:-}" in
  check)        cmd_check ;;
  kubeconfig)   cmd_kubeconfig ;;
  token)        cmd_token ;;
  github)       shift; cmd_github "${1:-}" ;;
  purge-legacy) shift; cmd_purge_legacy "${1:-}" ;;
  rotate-keys)  cmd_rotate_keys ;;
  all)          shift; cmd_check; cmd_kubeconfig; cmd_github "${1:-}" ;;
  *) sed -n '2,27p' "$0"; exit 1 ;;
esac
