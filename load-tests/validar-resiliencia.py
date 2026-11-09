
import json
import sys
from pathlib import Path

RUTA = Path("load-tests/resultados/resiliencia")
JSON = RUTA / "resiliencia-final.json"
LOG = RUTA / "resiliencia-final.log"


def fallar(mensaje):
    print(f"PRUEBA RECHAZADA: {mensaje}")
    sys.exit(1)


if not JSON.exists() or not LOG.exists():
    fallar("Faltan archivos de resultados.")

with JSON.open(encoding="utf-8") as archivo:
    datos = json.load(archivo)

logs = LOG.read_text(encoding="utf-8", errors="replace")

checks = datos.get("root_group", {}).get("checks", {})

# 1. Comprobar los cuatro servicios independientes.
servicios = [
    "catalogo",
    "rankings",
    "calificaciones",
    "frontend",
]

for servicio in servicios:
    nombre = f"{servicio} responde 200"
    resultado = checks.get(nombre)

    if not resultado:
        fallar(f"No hay resultados para {servicio}.")

    exitos = resultado.get("passes", 0)
    fallos = resultado.get("fails", 0)

    if exitos == 0 or fallos != 0:
        fallar(
            f"{servicio}: {exitos} exitos, {fallos} fallos."
        )

    print(f"CORRECTO: {servicio}: {exitos} respuestas HTTP 200.")

# 2. Comprobar que recomendaciones fallo.
recomendaciones = checks.get("recomendaciones responde 200")

if not recomendaciones:
    fallar("No hay resultados de recomendaciones.")

if recomendaciones.get("fails", 0) == 0:
    fallar("No se detecto la interrupcion de recomendaciones.")

if recomendaciones.get("passes", 0) == 0:
    fallar("Recomendaciones nunca respondio HTTP 200.")

# 3. Comprobar el orden de los eventos.
posicion_fallo = logs.find("[FALLO DETECTADO]")

if posicion_fallo == -1:
    fallar("No se registro el fallo.")

posicion_recuperacion = logs.find(
    "[SERVICIO RECUPERADO]",
    posicion_fallo
)

if posicion_recuperacion == -1:
    fallar("No se registro recuperacion despues del fallo.")

# 4. Verificar que k6 registro un tiempo de recuperacion.
metrica = datos.get("metrics", {}).get("tiempo_recuperacion_ms")

if not metrica or metrica.get("avg", 0) <= 0:
    fallar("No existe una medicion valida de recuperacion.")

tiempo_ms = metrica["avg"]

print("CORRECTO: Recomendaciones fallo y se recupero.")
print(f"Tiempo de recuperacion observado: {tiempo_ms:.0f} ms")
print("PRUEBA DE RESILIENCIA APROBADA")
