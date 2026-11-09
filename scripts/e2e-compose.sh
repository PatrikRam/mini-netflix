
#!/usr/bin/env bash
set -euo pipefail

echo "=== Pruebas E2E - Mini Netflix ==="

python3 - <<'PY'
import json
import time
import urllib.request

CATALOGO = "http://localhost:5001"
CALIFICACIONES = "http://localhost:5004"
RANKINGS = "http://localhost:5003"


def consultar(url):
    for intento in range(30):
        try:
            with urllib.request.urlopen(url, timeout=5) as respuesta:
                return json.load(respuesta)
        except Exception:
            if intento == 29:
                raise
            time.sleep(2)


print("1. Consultando Catalogo...")
peliculas = consultar(f"{CATALOGO}/peliculas")
assert isinstance(peliculas, list)
assert len(peliculas) > 0
print(f"   OK: {len(peliculas)} peliculas")

print("2. Consultando Calificaciones...")
promedios = consultar(
    f"{CALIFICACIONES}/calificaciones/promedios"
)
assert isinstance(promedios, list)
assert len(promedios) > 0
print(f"   OK: {len(promedios)} promedios")

print("3. Consultando Rankings...")
ranking = consultar(f"{RANKINGS}/rankings/top10")
assert isinstance(ranking, list)
assert 0 < len(ranking) <= 10

valores = [p["promedio"] for p in ranking]
assert valores == sorted(valores, reverse=True)

print(f"   OK: {len(ranking)} peliculas ordenadas")

print("4. Verificando integracion real...")

ids_peliculas = {p["id"] for p in peliculas}
promedios_por_id = {
    p["pelicula_id"]: p["promedio"]
    for p in promedios
}

for pelicula in ranking:
    assert pelicula["id"] in ids_peliculas
    assert pelicula["id"] in promedios_por_id
    assert pelicula["promedio"] == promedios_por_id[pelicula["id"]]

print("   OK: Rankings utiliza datos de ambos servicios")

print("\n=== TODAS LAS PRUEBAS E2E APROBADAS ===")
PY
