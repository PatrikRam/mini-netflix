from django.urls import path

from .views import health, pelicula_detalle, peliculas

urlpatterns = [
    path("health", health),
    path("peliculas", peliculas),
    path("peliculas/<int:pelicula_id>", pelicula_detalle),
]