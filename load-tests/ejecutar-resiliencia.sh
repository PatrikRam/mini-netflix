
#!/usr/bin/env bash
set -euo pipefail

RESULTADOS="load-tests/resultados/resiliencia"

mkdir -p "$RESULTADOS"

rm -f "$RESULTADOS/resiliencia-final.json" \
      "$RESULTADOS/resiliencia-final.log" \
      "$RESULTADOS/resiliencia-eventos.log"

registrar_evento() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" |
        tee -a "$RESULTADOS/resiliencia-eventos.log"
}

limpiar() {
    docker compose start recomendaciones >/dev/null 2>&1 || true
}

trap limpiar EXIT

registrar_evento "INICIO DE PRUEBA"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --network host \
    -v "$PWD:/app" \
    -w /app \
    -e CATALOGO_URL=http://localhost:5001 \
    -e RECOMENDACIONES_URL=http://localhost:5002 \
    -e RANKINGS_URL=http://localhost:5003 \
    -e CALIFICACIONES_URL=http://localhost:5004 \
    -e FRONTEND_URL=http://localhost:8080 \
    grafana/k6:2.3.0 run \
    --summary-export="$RESULTADOS/resiliencia-final.json" \
    load-tests/resiliencia.js \
    > "$RESULTADOS/resiliencia-final.log" 2>&1 &

K6_PID=$!

registrar_evento "K6 INICIADO"

sleep 20

registrar_evento "DETENIENDO RECOMENDACIONES"
docker compose stop recomendaciones

registrar_evento "RECOMENDACIONES DETENIDO"

sleep 20

registrar_evento "INICIANDO RECOMENDACIONES"
docker compose start recomendaciones

registrar_evento "COMANDO DE INICIO COMPLETADO"

wait "$K6_PID"

registrar_evento "PRUEBA FINALIZADA"
