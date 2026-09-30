from django.db import models


class Pelicula(models.Model):
    titulo = models.CharField(max_length=200)
    genero = models.CharField(max_length=100)
    anio = models.IntegerField()

    class Meta:
        # Equivale al UNIQUE(titulo, anio) — evita duplicados al recargar el dataset
        constraints = [
            models.UniqueConstraint(fields=["titulo", "anio"], name="titulo_anio_unico")
        ]