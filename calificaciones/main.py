import os
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

# Si esta variable esta vacia, no se valida la pelicula contra el catalogo.
# En Kubernetes se define como http://catalogo:5001
CATALOGO_URL = os.getenv("CATALOGO_URL", "")

app = FastAPI(title="Calificaciones - Mini Netflix")

CALIFICACIONES = []  # lista en memoria: {"pelicula_id", "puntaje", "reseña"}


@app.exception_handler(StarletteHTTPException)
async def manejar_http(request: Request, exc: StarletteHTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


@app.exception_handler(RequestValidationError)
async def manejar_validacion(request: Request, exc: RequestValidationError):
    return JSONResponse(status_code=400, content={"error": "Datos invalidos"})


class NuevaCalificacion(BaseModel):
    pelicula_id: int
    puntaje: int = Field(ge=1, le=5)
    reseña: Optional[str] = None


def verificar_pelicula(pelicula_id: int):
    if not CATALOGO_URL:
        return
    try:
        r = httpx.get(f"{CATALOGO_URL}/peliculas/{pelicula_id}", timeout=3)
    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="Catalogo no disponible")
    if r.status_code == 404:
        raise HTTPException(status_code=404, detail="No se encontro la pelicula")


def calcular_promedio(puntajes):
    return round(sum(puntajes) / len(puntajes), 2) if puntajes else 0.0


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/calificaciones", status_code=201)
def crear_calificacion(datos: NuevaCalificacion):
    verificar_pelicula(datos.pelicula_id)
    nueva = {
        "pelicula_id": datos.pelicula_id,
        "puntaje": datos.puntaje,
        "reseña": datos.reseña,
    }
    CALIFICACIONES.append(nueva)
    return nueva


# IMPORTANTE: esta ruta va antes que /calificaciones/{pelicula_id}
@app.get("/calificaciones/promedios")
def promedios():
    ids = sorted({c["pelicula_id"] for c in CALIFICACIONES})
    return [
        {
            "pelicula_id": i,
            "promedio": calcular_promedio(
                [c["puntaje"] for c in CALIFICACIONES if c["pelicula_id"] == i]
            ),
        }
        for i in ids
    ]


@app.get("/calificaciones/{pelicula_id}")
def calificaciones_de_pelicula(pelicula_id: int):
    propias = [c for c in CALIFICACIONES if c["pelicula_id"] == pelicula_id]
    return {
        "pelicula_id": pelicula_id,
        "promedio": calcular_promedio([c["puntaje"] for c in propias]),
        "total": len(propias),
        "reseñas": [
            {"puntaje": c["puntaje"], "reseña": c["reseña"]} for c in propias
        ],
    }
