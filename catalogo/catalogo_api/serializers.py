from rest_framework import serializers


class PeliculaSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    titulo = serializers.CharField()
    genero = serializers.CharField()
    anio = serializers.IntegerField()