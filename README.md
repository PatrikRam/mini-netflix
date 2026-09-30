# Mini Netflix

Proyecto de Cloud Computing basado en una arquitectura de microservicios para una plataforma simplificada de streaming de películas.

El sistema está compuesto por servicios independientes para catálogo, calificaciones, rankings y recomendaciones, además de una interfaz web. Los servicios se ejecutan mediante Docker y Docker Compose y cuentan con manifiestos para su despliegue en Kubernetes.

## Arquitectura

El sistema se divide en los siguientes microservicios:

| Servicio | Puerto local | Función |
|---|---:|---|
| Catálogo | 5001 | Consulta, búsqueda y filtrado de películas |
| Recomendaciones | 5002 | Recomienda películas similares |
| Rankings | 5003 | Genera Top 10 y rankings por género |
| Calificaciones | 5004 | Registra puntuaciones y reseñas |
| Frontend | 8080 | Interfaz web del sistema |

Catálogo y Calificaciones utilizan PostgreSQL para almacenar información de forma persistente.

Rankings y Recomendaciones no mantienen una base de datos propia. Estos servicios consultan la información disponible en Catálogo y Calificaciones.

### Comunicación entre servicios

```text
                         ┌──────────────┐
                         │   Frontend   │
                         └──────┬───────┘
                                │
              ┌─────────────────┼──────────────────┐
              │                 │                  │
              ▼                 ▼                  ▼
        ┌──────────┐      ┌───────────────┐   ┌─────────────────┐
        │ Catálogo │      │ Calificaciones│   │     Rankings    │
        └────┬─────┘      └───────┬───────┘   └────────┬────────┘
             │                    │                     │
             ▼                    ▼                     │
       PostgreSQL           PostgreSQL                  │
              ▲                 ▲                       │
              │                 │                       │
              └────────┬────────┴───────────────────────┘
                       │
                ┌──────▼──────────┐
                │ Recomendaciones │
                └─────────────────┘
```

Rankings utiliza:

```text
Catálogo + Calificaciones → Ranking de películas
```

Recomendaciones utiliza:

```text
Catálogo + Calificaciones → Películas similares
```

## Tecnologías

- Python
- FastAPI
- Django REST Framework
- PostgreSQL
- Nginx
- Docker
- Docker Compose
- Kubernetes
- HTML
- CSS
- JavaScript

## Estructura del proyecto

```text
mini-netflix/
│
├── catalogo/
│   └── Microservicio de catálogo
│
├── calificaciones/
│   └── Microservicio de puntuaciones y reseñas
│
├── rankings/
│   └── Microservicio de rankings
│
├── recomendaciones/
│   └── Microservicio de recomendaciones
│
├── frontend/
│   └── Interfaz web y configuración de Nginx
│
├── k8s/
│   └── Manifiestos de Kubernetes
│
├── docs/
│   └── Contratos de API y documentación
│
├── docker-compose.yml
└── README.md
```

# Microservicios

## 1. Catálogo

Gestiona la información de las películas disponibles en el sistema.

### Endpoints

```http
GET /health
GET /peliculas
GET /peliculas?genero=accion
GET /peliculas?buscar=matrix
GET /peliculas/{id}
```

Ejemplo:

```text
http://localhost:5001/peliculas
```

Catálogo utiliza PostgreSQL para persistir la información de las películas.

---

## 2. Calificaciones

Permite registrar puntuaciones y reseñas para las películas.

### Endpoints

```http
GET  /health
POST /calificaciones
GET  /calificaciones/{pelicula_id}
GET  /calificaciones/promedios
```

Ejemplo de una calificación:

```json
{
  "pelicula_id": 1,
  "puntaje": 5,
  "reseña": "Muy buena"
}
```

Los puntajes deben encontrarse entre 1 y 5.

El servicio utiliza PostgreSQL para persistir las calificaciones.

También existe un proceso de carga inicial de datos mediante:

```bash
python seed.py
```

El seed genera calificaciones iniciales para facilitar las pruebas del sistema y evita generar nuevos datos si la base ya contiene registros.

---

## 3. Rankings

Genera rankings a partir de la información proporcionada por Catálogo y Calificaciones.

El servicio consulta:

```http
GET /peliculas
GET /calificaciones/promedios
```

Luego relaciona ambas respuestas mediante el identificador de la película y ordena los resultados por promedio.

### Endpoints

```http
GET /health
GET /rankings/top10
GET /rankings/genero/{genero}
```

Ejemplos:

```text
http://localhost:5003/rankings/top10
http://localhost:5003/rankings/genero/accion
```

Rankings no utiliza una base de datos propia.

---

## 4. Recomendaciones

Genera recomendaciones de películas similares.

Para una película determinada, el servicio:

1. Obtiene la película desde Catálogo.
2. Identifica su género.
3. Busca otras películas del mismo género.
4. Excluye la película original.
5. Consulta sus promedios en Calificaciones.
6. Ordena las alternativas por calificación.
7. Devuelve hasta cinco recomendaciones.

### Endpoints

```http
GET /health
GET /recomendaciones/{pelicula_id}
GET /recomendaciones/carga
```

Ejemplo:

```text
http://localhost:5002/recomendaciones/1
```

El endpoint `/recomendaciones/carga` realiza una operación de mayor consumo de CPU y se utiliza para las pruebas de carga y escalabilidad.

Recomendaciones tampoco utiliza una base de datos propia.

---

## 5. Frontend

La interfaz web permite interactuar con los diferentes microservicios.

Incluye:

- listado de películas;
- búsqueda por título;
- filtrado por género;
- Top 10;
- visualización de promedios;
- registro de calificaciones;
- registro de reseñas;
- visualización de películas similares.

El frontend utiliza Nginx como servidor web y proxy para comunicarse con las APIs.

Acceso:

```text
http://localhost:8080
```

# Ejecución con Docker Compose

## Requisitos

- Docker
- Docker Compose

Desde la raíz del proyecto:

```bash
docker compose up -d --build
```

Comprobar los contenedores:

```bash
docker compose ps
```

## Preparar Catálogo

Cuando se utiliza una base de datos nueva, ejecutar:

```bash
docker compose exec catalogo python manage.py migrate
docker compose exec catalogo python manage.py seed
```

## Preparar Calificaciones

Si la base de datos de Calificaciones todavía no contiene los datos iniciales:

```bash
docker compose exec calificaciones python seed.py
```

## Probar los servicios

Catálogo:

```text
http://localhost:5001/peliculas
```

Calificaciones:

```text
http://localhost:5004/calificaciones/promedios
```

Rankings:

```text
http://localhost:5003/rankings/top10
```

Recomendaciones:

```text
http://localhost:5002/recomendaciones/1
```

Frontend:

```text
http://localhost:8080
```

## Detener el proyecto

```bash
docker compose down
```

Los datos almacenados en los volúmenes de PostgreSQL se mantienen.

Para eliminar también los volúmenes:

```bash
docker compose down -v
```

> Este último comando elimina los datos persistidos de las bases de datos.

# Persistencia

El proyecto utiliza volúmenes de Docker para conservar los datos de PostgreSQL.

```text
catalogo_data
calificaciones_data
```

Esto permite eliminar y recrear los contenedores sin perder las películas y calificaciones almacenadas.

# Kubernetes

Los manifiestos se encuentran en:

```text
k8s/
```

El proyecto utiliza principalmente:

- Deployments
- Services
- PersistentVolumeClaims
- readiness probes
- liveness probes

Rankings y Recomendaciones están configurados con múltiples réplicas para permitir la distribución de solicitudes.

## Construir imágenes

Desde la raíz:

```bash
docker build -t mini-netflix/catalogo:1.0 ./catalogo
docker build -t mini-netflix/calificaciones:1.0 ./calificaciones
docker build -t mini-netflix/rankings:1.0 ./rankings
docker build -t mini-netflix/recomendaciones:1.0 ./recomendaciones
```

## Desplegar

Bases de datos:

```bash
kubectl apply -f k8s/catalogo-db.yaml
kubectl apply -f k8s/calificaciones-db.yaml
```

Microservicios:

```bash
kubectl apply -f k8s/catalogo.yaml
kubectl apply -f k8s/calificaciones.yaml
kubectl apply -f k8s/rankings.yaml
kubectl apply -f k8s/recomendaciones.yaml
```

Comprobar recursos:

```bash
kubectl get pods
kubectl get services
```

## Preparar las bases de datos en Kubernetes

Catálogo:

```bash
kubectl exec deployment/catalogo -- python manage.py migrate
kubectl exec deployment/catalogo -- python manage.py seed
```

Calificaciones:

```bash
kubectl exec deployment/calificaciones -- python seed.py
```

# Probar Rankings en Kubernetes

```bash
kubectl port-forward service/rankings 5003:5000
```

Después:

```text
http://localhost:5003/health
http://localhost:5003/rankings/top10
http://localhost:5003/rankings/genero/accion
```

# Probar Recomendaciones en Kubernetes

```bash
kubectl port-forward service/recomendaciones 5002:5000
```

Después:

```text
http://localhost:5002/health
http://localhost:5002/recomendaciones/1
http://localhost:5002/recomendaciones/carga
```

# Escalabilidad y tolerancia a fallos

Los microservicios desplegados en Kubernetes utilizan Deployments para administrar sus instancias.

Por ejemplo, Rankings y Recomendaciones pueden mantener varias réplicas:

```text
Deployment
   │
   ├── Pod 1
   └── Pod 2
```

Los Services proporcionan un punto estable de comunicación y distribuyen las solicitudes entre las réplicas disponibles.

Los endpoints `/health` son utilizados por las probes de Kubernetes:

- `readinessProbe`: determina si un contenedor está listo para recibir solicitudes.
- `livenessProbe`: permite detectar un contenedor que dejó de responder.

Esto permite realizar pruebas de:

- escalabilidad;
- tolerancia a fallos;
- recuperación de pods;
- carga y estrés.

El endpoint `/recomendaciones/carga` fue creado específicamente para generar carga computacional durante estas pruebas.

# Contratos de API

Los contratos entre los microservicios se encuentran en:

```text
docs/contratos-api.md
```

Los servicios se comunican utilizando HTTP y respuestas en formato JSON.

Todos los microservicios exponen:

```http
GET /health
```

para comprobar su disponibilidad.

# Flujo general

```text
Código
  ↓
Dockerfile
  ↓
Imagen Docker
  ↓
Docker Compose
  ↓
Integración entre microservicios
  ↓
Persistencia con PostgreSQL
  ↓
Manifiestos Kubernetes
  ↓
Deployments + Services
  ↓
Pods y réplicas
  ↓
Pruebas de escalabilidad y tolerancia a fallos
```

# Equipo

| Microservicio | Responsable |
|---|---|
| Catálogo | Josué |
| Recomendaciones | Evelyn |
| Rankings | Angela |
| Calificaciones | Patrick |

# Curso

Proyecto desarrollado para el curso de **Cloud Computing**.
