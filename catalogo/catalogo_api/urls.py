from django.urls import path
from .views import health, peliculas, pelicula_detalle

urlpatterns = [
    path("health", health),
    path("peliculas", peliculas),
    path("peliculas/<int:pelicula_id>", pelicula_detalle),
]