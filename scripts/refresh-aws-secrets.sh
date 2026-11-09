#!/usr/bin/env bash
# Copia las credenciales del lab (~/.aws/credentials) a GitHub Secrets sin mostrarlas.
set -euo pipefail
REPO="${1:?uso: $0 usuario/repositorio}"
for k in aws_access_key_id aws_secret_access_key aws_session_token; do
  name=$(echo "$k" | tr '[:lower:]' '[:upper:]')
  aws configure get "$k" | tr -d '\n' | gh secret set "$name" --repo "$REPO"
  echo "actualizado: $name"
done
