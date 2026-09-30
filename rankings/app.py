import os
import requests

from fastapi import FastAPI, HTTPException

app = FastAPI(
    title="Mini Netflix - Rankings",
    description="Microservicio de rankings de películas",
    version="1.0.0"
)

# Direcciones de los otros microservicios
CATALOGO_URL = os.getenv(
    "CATALOGO_URL",
    "http://catalogo:5000"
)

CALIFICACIONES_URL = os.getenv(
    "CALIFICACIONES_URL",
    "http://calificaciones:5000"
)


@app.get("/health")
def health():
    return {"status": "ok"}


def obtener_peliculas():
    """Consulta las películas del microservicio de catálogo."""

    try:
        respuesta = requests.get(
            f"{CATALOGO_URL}/peliculas",
            timeout=5
        )

        respuesta.raise_for_status()
        return respuesta.json()

    except requests.RequestException:
        raise HTTPException(
            status_code=503,
            detail="No se pudo conectar con el catálogo"
        )


def obtener_promedios():
    """Consulta los promedios del microservicio de calificaciones."""

    try:
        respuesta = requests.get(
            f"{CALIFICACIONES_URL}/calificaciones/promedios",
            timeout=5
        )

        respuesta.raise_for_status()
        return respuesta.json()

    except requests.RequestException:
        raise HTTPException(
            status_code=503,
            detail="No se pudo conectar con calificaciones"
        )


def construir_ranking():
    """Relaciona las películas con sus promedios y las ordena."""

    peliculas = obtener_peliculas()
    promedios = obtener_promedios()

    promedios_por_id = {
        calificacion["pelicula_id"]: calificacion["promedio"]
        for calificacion in promedios
    }

    ranking = []

    for pelicula in peliculas:
        pelicula_id = pelicula["id"]

        if pelicula_id in promedios_por_id:
            pelicula_con_promedio = {
                **pelicula,
                "promedio": promedios_por_id[pelicula_id]
            }

            ranking.append(pelicula_con_promedio)

    ranking.sort(
        key=lambda pelicula: pelicula["promedio"],
        reverse=True
    )

    return ranking


@app.get("/rankings/top10")
def obtener_top10():
    ranking = construir_ranking()
    return ranking[:10]


@app.get("/rankings/genero/{genero}")
def obtener_ranking_genero(genero: str):
    ranking = construir_ranking()

    return [
        pelicula
        for pelicula in ranking
        if pelicula["genero"].lower() == genero.lower()
    ]