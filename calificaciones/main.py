import os
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from database import crear_tabla, obtener_conexion

CATALOGO_URL = os.getenv("CATALOGO_URL", "")

app = FastAPI(title="Calificaciones - Mini Netflix")


@app.on_event("startup")
def iniciar_base_datos():
    crear_tabla()


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
        respuesta = httpx.get(
            f"{CATALOGO_URL}/peliculas/{pelicula_id}",
            timeout=3,
        )
    except httpx.RequestError:
        raise HTTPException(
            status_code=503,
            detail="Catalogo no disponible",
        )

    if respuesta.status_code == 404:
        raise HTTPException(
            status_code=404,
            detail="No se encontro la pelicula",
        )

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/calificaciones", status_code=201)
def crear_calificacion(datos: NuevaCalificacion):
    verificar_pelicula(datos.pelicula_id)
    conexion = obtener_conexion()
    try:
        with conexion.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO calificaciones (pelicula_id, puntaje, resena)
                VALUES (%s, %s, %s)
                RETURNING pelicula_id, puntaje, resena;
                """,
                (
                    datos.pelicula_id,
                    datos.puntaje,
                    datos.reseña,
                ),
            )

            nueva = cursor.fetchone()
        conexion.commit()

    finally:
        conexion.close()

    return {
        "pelicula_id": nueva["pelicula_id"],
        "puntaje": nueva["puntaje"],
        "reseña": nueva["resena"],
    }


# IMPORTANTE: esta ruta va antes que /calificaciones/{pelicula_id}
@app.get("/calificaciones/promedios")
def promedios():
    conexion = obtener_conexion()

    try:
        with conexion.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    pelicula_id,
                    ROUND(AVG(puntaje)::numeric, 2) AS promedio
                FROM calificaciones
                GROUP BY pelicula_id
                ORDER BY pelicula_id;
                """
            )

            resultados = cursor.fetchall()

    finally:
        conexion.close()

    return [
        {
            "pelicula_id": fila["pelicula_id"],
            "promedio": float(fila["promedio"]),
        }
        for fila in resultados
    ]


@app.get("/calificaciones/{pelicula_id}")
def calificaciones_de_pelicula(pelicula_id: int):
    conexion = obtener_conexion()
    try:
        with conexion.cursor() as cursor:
            cursor.execute(
                """
                SELECT puntaje, resena
                FROM calificaciones
                WHERE pelicula_id = %s
                ORDER BY id;
                """,
                (pelicula_id,),
            )
            calificaciones = cursor.fetchall()

    finally:
        conexion.close()

    if calificaciones:
        promedio = round(
            sum(c["puntaje"] for c in calificaciones)
            / len(calificaciones),
            2,
        )
    else:
        promedio = 0.0

    return {
        "pelicula_id": pelicula_id,
        "promedio": promedio,
        "total": len(calificaciones),
        "reseñas": [
            {
                "puntaje": c["puntaje"],
                "reseña": c["resena"],
            }
            for c in calificaciones
        ],
    }