import os
import math
import requests

from fastapi import FastAPI, HTTPException


app = FastAPI(
    title="Mini Netflix - Recomendaciones",
    description="Microservicio de recomendaciones de películas",
    version="1.0.0",
)


CATALOGO_URL = os.getenv(
    "CATALOGO_URL",
    "http://catalogo:5000",
)

CALIFICACIONES_URL = os.getenv(
    "CALIFICACIONES_URL",
    "http://calificaciones:5000",
)


@app.get("/health")
def health():
    return {"status": "ok"}


def obtener_peliculas():
    try:
        respuesta = requests.get(
            f"{CATALOGO_URL}/peliculas",
            timeout=5,
        )
        respuesta.raise_for_status()
        return respuesta.json()

    except requests.RequestException:
        raise HTTPException(
            status_code=503,
            detail="No se pudo conectar con el catalogo",
        )


def obtener_promedios():
    try:
        respuesta = requests.get(
            f"{CALIFICACIONES_URL}/calificaciones/promedios",
            timeout=5,
        )
        respuesta.raise_for_status()
        return respuesta.json()

    except requests.RequestException:
        raise HTTPException(
            status_code=503,
            detail="No se pudo conectar con calificaciones",
        )



@app.get("/recomendaciones/carga")
def prueba_carga():
    resultado = 0.0

    for numero in range(1, 2_000_000):
        resultado += math.sqrt(numero)

    return {
        "status": "ok",
        "resultado": resultado,
    }

    
@app.get("/recomendaciones/{pelicula_id}")
def recomendar_peliculas(pelicula_id: int):
    peliculas = obtener_peliculas()
    promedios = obtener_promedios()

    pelicula_base = next(
        (
            pelicula
            for pelicula in peliculas
            if pelicula["id"] == pelicula_id
        ),
        None,
    )

    if pelicula_base is None:
        raise HTTPException(
            status_code=404,
            detail="Pelicula no encontrada",
        )

    promedios_por_id = {
        item["pelicula_id"]: item["promedio"]
        for item in promedios
    }

    recomendaciones = []

    for pelicula in peliculas:
        if pelicula["id"] == pelicula_id:
            continue

        if pelicula["genero"].lower() != pelicula_base["genero"].lower():
            continue

        recomendaciones.append(
            {
                **pelicula,
                "promedio": promedios_por_id.get(
                    pelicula["id"],
                    0.0,
                ),
            }
        )

    recomendaciones.sort(
        key=lambda pelicula: pelicula["promedio"],
        reverse=True,
    )

    return recomendaciones[:5]
