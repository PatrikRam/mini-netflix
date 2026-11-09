#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Valores ficticios: no se utilizan credenciales reales.
export ECR_REGISTRY="example.invalid"
export IMAGE_TAG="test"
export CALIFICACIONES_DB_PASSWORD="solo-validacion"

command -v envsubst >/dev/null || {
  echo "ERROR: falta envsubst"
  exit 1
}

python -c "import yaml" || {
  echo "ERROR: falta PyYAML"
  exit 1
}

for archivo in k8s/eks/*.yaml; do
  echo "Validando: $archivo"

  temporal=$(mktemp)
  trap 'rm -f "$temporal"' EXIT

  envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${CALIFICACIONES_DB_PASSWORD}' \
    < "$archivo" > "$temporal"

  if grep -Fq '${' "$temporal"; then
    echo "ERROR: variables sin sustituir en $archivo"
    exit 1
  fi

  python - "$temporal" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as archivo:
    documentos = list(yaml.safe_load_all(archivo))

if not documentos:
    raise SystemExit("ERROR: manifiesto vacío")

for recurso in documentos:
    if not isinstance(recurso, dict):
        raise SystemExit("ERROR: recurso YAML inválido")
    if not recurso.get("apiVersion") or not recurso.get("kind"):
        raise SystemExit("ERROR: faltan apiVersion o kind")
    if not isinstance(recurso.get("metadata"), dict):
        raise SystemExit("ERROR: falta metadata")
    if not recurso["metadata"].get("name"):
        raise SystemExit("ERROR: falta metadata.name")

print(f"  OK: {len(documentos)} recurso(s)")
PY

  rm -f "$temporal"
  trap - EXIT
done

echo "Validación estructural completada correctamente."
