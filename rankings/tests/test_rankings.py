"""Pruebas aisladas de la API Rankings, sin depender de otros servicios."""
from unittest.mock import patch

import pytest
import requests
from fastapi.testclient import TestClient

from app import app

client = TestClient(app)

PELICULAS = [
    {"id": 1, "titulo": "Pelicula A", "genero": "Accion"},
    {"id": 2, "titulo": "Pelicula B", "genero": "Drama"},
    {"id": 3, "titulo": "Pelicula C", "genero": "ACCION"},
    {"id": 4, "titulo": "Sin calificaciones", "genero": "Drama"},
]
PROMEDIOS = [
    {"pelicula_id": 1, "promedio": 3.5},
    {"pelicula_id": 2, "promedio": 4.8},
    {"pelicula_id": 3, "promedio": 4.2},
]


@pytest.fixture
def servicios_simulados():
    with (
        patch("app.obtener_peliculas", return_value=PELICULAS),
        patch("app.obtener_promedios", return_value=PROMEDIOS),
    ):
        yield


def test_health():
    respuesta = client.get("/health")
    assert respuesta.status_code == 200
    assert respuesta.json() == {"status": "ok"}


def test_top10_ordenado_y_sin_peliculas_sin_calificaciones(servicios_simulados):
    respuesta = client.get("/rankings/top10")
    assert respuesta.status_code == 200
    datos = respuesta.json()
    assert [p["id"] for p in datos] == [2, 3, 1]
    assert [p["promedio"] for p in datos] == [4.8, 4.2, 3.5]


def test_genero_no_distingue_mayusculas(servicios_simulados):
    respuesta = client.get("/rankings/genero/accion")
    assert respuesta.status_code == 200
    assert [p["id"] for p in respuesta.json()] == [3, 1]


def test_genero_inexistente_retorna_lista_vacia(servicios_simulados):
    respuesta = client.get("/rankings/genero/Comedia")
    assert respuesta.status_code == 200
    assert respuesta.json() == []


def test_top10_limita_a_diez():
    peliculas = [{"id": i, "titulo": str(i), "genero": "Drama"} for i in range(1, 13)]
    promedios = [{"pelicula_id": i, "promedio": float(i)} for i in range(1, 13)]
    with (
        patch("app.obtener_peliculas", return_value=peliculas),
        patch("app.obtener_promedios", return_value=promedios),
    ):
        respuesta = client.get("/rankings/top10")
    assert respuesta.status_code == 200
    assert len(respuesta.json()) == 10
    assert respuesta.json()[0]["id"] == 12


@pytest.mark.parametrize(
    ("url", "mensaje"),
    [
        ("/rankings/top10", "No se pudo conectar con el catálogo"),
        ("/rankings/genero/Drama", "No se pudo conectar con el catálogo"),
    ],
)
def test_catalogo_no_disponible_responde_503(url, mensaje):
    with patch("app.requests.get", side_effect=requests.ConnectionError("sin red")):
        respuesta = client.get(url)
    assert respuesta.status_code == 503
    assert respuesta.json()["detail"] == mensaje


def test_calificaciones_no_disponible_responde_503():
    respuesta_catalogo = requests.Response()
    respuesta_catalogo.status_code = 200
    respuesta_catalogo._content = b'[{"id":1,"titulo":"Pelicula A","genero":"Accion"}]'
    with patch("app.requests.get", side_effect=[respuesta_catalogo, requests.Timeout("timeout")]):
        respuesta = client.get("/rankings/top10")
    assert respuesta.status_code == 503
    assert respuesta.json()["detail"] == "No se pudo conectar con calificaciones"


def test_sin_promedios_devuelve_lista_vacia():
    with (
        patch("app.obtener_peliculas", return_value=PELICULAS),
        patch("app.obtener_promedios", return_value=[]),
    ):
        respuesta = client.get("/rankings/top10")
    assert respuesta.status_code == 200
    assert respuesta.json() == []
