from django.db.utils import OperationalError
from .repository import PeliculaRepository


class PeliculaService:
    def __init__(self):
        self.repository = PeliculaRepository()

    def listar_peliculas(self, genero=None, buscar=None):
        try:
            return list(self.repository.listar(genero=genero, buscar=buscar).values())
        except OperationalError:
            # La DB caída se traduce aquí en una señal clara,
            # no en un error genérico de Django hacia el cliente.
            raise ServicioNoDisponibleError()

    def obtener_pelicula(self, pelicula_id):
        try:
            pelicula = self.repository.obtener_por_id(pelicula_id)
        except OperationalError:
            raise ServicioNoDisponibleError()
        if pelicula is None:
            raise PeliculaNoEncontradaError()
        return {"id": pelicula.id, "titulo": pelicula.titulo, "genero": pelicula.genero, "anio": pelicula.anio}


class ServicioNoDisponibleError(Exception):
    pass


class PeliculaNoEncontradaError(Exception):
    pass