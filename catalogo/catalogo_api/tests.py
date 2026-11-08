from unittest.mock import patch

from django.test import TestCase
from rest_framework.test import APIClient

from .models import Pelicula
from .services import ServicioNoDisponibleError


class CatalogoApiTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        # Datos propios de la prueba: no dependen de docs/peliculas.json
        Pelicula.objects.create(titulo="Matrix", genero="accion", anio=1999)
        Pelicula.objects.create(titulo="Coco", genero="animacion", anio=2017)

    def setUp(self):
        self.client = APIClient()

    def test_health(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {"status": "ok"})

    def test_lista_completa(self):
        r = self.client.get("/peliculas")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.json()), 2)

    def test_filtro_genero_insensible_a_mayusculas(self):
        r = self.client.get("/peliculas?genero=ACCION")
        self.assertEqual([p["titulo"] for p in r.json()], ["Matrix"])

    def test_busqueda_por_titulo_parcial(self):
        r = self.client.get("/peliculas?buscar=matr")
        self.assertEqual([p["titulo"] for p in r.json()], ["Matrix"])

    def test_resultado_vacio_es_lista_vacia(self):
        r = self.client.get("/peliculas?genero=inexistente")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), [])

    def test_detalle_existente(self):
        pid = Pelicula.objects.get(titulo="Coco").id
        r = self.client.get(f"/peliculas/{pid}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(set(r.json()), {"id", "titulo", "genero", "anio"})  # formato del contrato

    def test_detalle_inexistente_404(self):
        self.assertEqual(self.client.get("/peliculas/999999").status_code, 404)

    def test_base_de_datos_caida_devuelve_503(self):
        with patch("catalogo_api.views.service.listar_peliculas",
                   side_effect=ServicioNoDisponibleError()):
            self.assertEqual(self.client.get("/peliculas").status_code, 503)