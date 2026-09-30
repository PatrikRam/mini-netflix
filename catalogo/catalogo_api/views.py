from rest_framework.decorators import api_view
from rest_framework.response import Response
from .services import PeliculaService, ServicioNoDisponibleError, PeliculaNoEncontradaError
from .serializers import PeliculaSerializer

service = PeliculaService()


@api_view(["GET"])
def health(request):
    # No pasa por el service: no depende de la DB, igual que en la versión Flask.
    return Response({"status": "ok"})


@api_view(["GET"])
def peliculas(request):
    genero = request.query_params.get("genero")
    buscar = request.query_params.get("buscar")
    try:
        resultado = service.listar_peliculas(genero=genero, buscar=buscar)
    except ServicioNoDisponibleError:
        return Response({"error": "base de datos no disponible"}, status=503)
    return Response(PeliculaSerializer(resultado, many=True).data)


@api_view(["GET"])
def pelicula_detalle(request, pelicula_id):
    try:
        pelicula = service.obtener_pelicula(pelicula_id)
    except ServicioNoDisponibleError:
        return Response({"error": "base de datos no disponible"}, status=503)
    except PeliculaNoEncontradaError:
        return Response({"error": "no encontrada"}, status=404)
    return Response(PeliculaSerializer(pelicula).data)