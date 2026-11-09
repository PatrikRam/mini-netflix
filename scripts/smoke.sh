
#!/usr/bin/env bash
set -euo pipefail

# Direcciones configurables para Docker local o Kubernetes.
CATALOGO_URL="${CATALOGO_URL:-http://localhost:5001}"
CALIFICACIONES_URL="${CALIFICACIONES_URL:-http://localhost:5004}"
RANKINGS_URL="${RANKINGS_URL:-http://localhost:5003}"
RECOMENDACIONES_URL="${RECOMENDACIONES_URL:-http://localhost:5002}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:8080}"

verificar() {
    local nombre="$1"
    local url="$2"

    echo "Verificando $nombre: $url"

    if curl --fail --silent --show-error \
        --connect-timeout 5 --max-time 15 \
        --output /dev/null "$url"; then
        echo "OK: $nombre"
    else
        echo "ERROR: $nombre no responde correctamente"
        return 1
    fi
}

echo "=================================="
echo "Smoke Tests - Mini Netflix"
echo "=================================="

verificar "Catalogo" "$CATALOGO_URL/peliculas"
verificar "Calificaciones" "$CALIFICACIONES_URL/calificaciones/promedios"
verificar "Rankings Health" "$RANKINGS_URL/health"
verificar "Rankings Top 10" "$RANKINGS_URL/rankings/top10"

verificar "Recomendaciones Health" "$RECOMENDACIONES_URL/health"
verificar "Recomendaciones API" "$RECOMENDACIONES_URL/recomendaciones/1"

verificar "Frontend" "$FRONTEND_URL/"

echo "=================================="
echo "TODOS LOS SMOKE TESTS APROBADOS"
echo "=================================="
