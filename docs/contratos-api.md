# Contratos de API

Cada película se identifica con un `id` numérico (ver datos de ejemplo abajo).
Todas las respuestas son JSON. Todos los servicios exponen `GET /health` → {"status":"ok"}

## Catálogo (Josué), puerto 5001
- GET /peliculas                     → lista de películas
- GET /peliculas?genero=accion       → filtrar por género
- GET /peliculas?buscar=matrix       → buscar por título
- GET /peliculas/{id}                → detalle de una película

## Calificaciones (Patrick), puerto 5004
- POST /calificaciones               → body: {"pelicula_id":1,"puntaje":4,"reseña":"Muy buena"}
- GET  /calificaciones/{pelicula_id} → lista de reseñas + promedio
- GET  /calificaciones/promedios     → promedio de todas: [{"pelicula_id":1,"promedio":4.5}, ...]

## Rankings (Angela), puerto 5003
- GET /rankings/top10                → 10 mejor calificadas
- GET /rankings/genero/{genero}      → ranking dentro de un género
(usa /calificaciones/promedios y /peliculas)

## Recomendaciones (Evelyn), puerto 5002
- GET /recomendaciones/{pelicula_id} → películas similares por género y calificación
- GET /recomendaciones/carga         → cálculo pesado a propósito (para la prueba de escalabilidad)
(usa /peliculas y /calificaciones/promedios)

## Formato de película
{"id":1,"titulo":"Matrix","genero":"accion","anio":1999}