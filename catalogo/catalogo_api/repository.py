from .models import Pelicula


class PeliculaRepository:
    """Único punto de acceso a la tabla Pelicula. Si cambia la fuente de
    datos (otra DB, una API externa), solo se toca esta clase."""

    def listar(self, genero=None, buscar=None):
        qs = Pelicula.objects.all()
        if genero:
            qs = qs.filter(genero__iexact=genero)   # __iexact = insensible a mayúsculas
        if buscar:
            qs = qs.filter(titulo__icontains=buscar)  # __icontains = LIKE insensible
        return qs

    def obtener_por_id(self, pelicula_id):
        return Pelicula.objects.filter(id=pelicula_id).first()  # None si no existe