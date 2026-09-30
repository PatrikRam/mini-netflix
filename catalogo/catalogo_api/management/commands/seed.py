import json
from django.core.management.base import BaseCommand
from catalogo_api.models import Pelicula


class Command(BaseCommand):
    help = "Carga docs/peliculas.json en la base de datos, sin duplicar."

    def handle(self, *args, **kwargs):
        with open("docs/peliculas.json", encoding="utf-8") as f:
            peliculas = json.load(f)

        creadas = 0
        for p in peliculas:
            _, fue_creada = Pelicula.objects.get_or_create(
                titulo=p["titulo"], anio=p["anio"], defaults={"genero": p["genero"]}
            )
            if fue_creada:
                creadas += 1

        self.stdout.write(self.style.SUCCESS(f"{creadas} películas nuevas cargadas."))