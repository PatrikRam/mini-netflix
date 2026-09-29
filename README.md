# Mini-Netflix: microservicios en Kubernetes (AWS)

Proyecto 1 de Cloud Computing.

## Servicios
| Servicio | Responsable | Puerto | Función |
|---|---|---|---|
| catalogo | Josué | 5001 | Mostrar, buscar y filtrar películas por género |
| recomendaciones | Evelyn | 5002 | Sugerir películas similares |
| rankings | Angela | 5003 | Top 10, mejor calificadas, rankings por género |
| calificaciones | Patrick | 5004 | Registrar puntuaciones y reseñas |
| frontend | por definir | 8080 | Página web |

## Reglas del equipo
- Cada quien trabaja solo en su carpeta.
- Los endpoints están en docs/contratos-api.md. No cambiarlos sin avisar.
- Todo servicio debe tener GET /health.
- Cada servicio corre en su propio contenedor Docker.

## Cómo probar un servicio en local
cd catalogo
docker build -t catalogo .
docker run -p 5001:5000 catalogo

## Cómo levantar todo
docker compose up --build