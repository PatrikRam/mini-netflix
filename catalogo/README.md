# Microservicio Catálogo

## Requisitos
- Docker + Docker Compose
- kubectl + Minikube (para probar en Kubernetes)

## Correr localmente (Docker Compose)
Desde la raíz del repo:

    docker compose up -d --build
    docker compose exec catalogo python manage.py migrate
    docker compose exec catalogo python manage.py seed
    curl http://localhost:5001/peliculas

> Si el build falla con un error de Buildx/moby-buildkit, usa:
> `DOCKER_BUILDKIT=0 docker compose up -d --build`

## Correr en Kubernetes (Minikube)
Desde la raíz del repo:

    minikube start
    eval $(minikube docker-env)
    docker build -t catalogo:latest ./catalogo

    kubectl create configmap peliculas-dataset --from-file=docs/peliculas.json
    kubectl apply -f k8s/catalogo-db.yaml
    kubectl apply -f k8s/catalogo.yaml

    kubectl exec -it deploy/catalogo -- python manage.py migrate
    kubectl exec -it deploy/catalogo -- python manage.py seed

    kubectl port-forward svc/catalogo 5001:5000
    curl http://localhost:5001/peliculas

> Al terminar de construir imágenes para Kubernetes, vuelve a tu Docker
> normal con `eval $(minikube docker-env -u)` antes de usar `docker compose`.
>
> Si `kubectl port-forward` se corta con "lost connection to pod" tras un
> `rollout restart` o `delete pod`, es normal — solo vuelve a correrlo.

## Endpoints (contrato — ver docs/contratos-api.md)
| Método | Ruta | Descripción |
|---|---|---|
| GET | /health | Estado del servicio (no depende de la DB) |
| GET | /peliculas | Lista completa |
| GET | /peliculas?genero=X | Filtra por género |
| GET | /peliculas?buscar=X | Busca por título (parcial, insensible a mayúsculas) |
| GET | /peliculas/{id} | Detalle de una película |

## Actualizar el dataset
Si editas `docs/peliculas.json`:

    # Local (Compose): no necesitas rebuild, el volumen es en vivo
    docker compose exec catalogo python manage.py seed

    # Kubernetes: actualiza el ConfigMap y reinicia
    kubectl create configmap peliculas-dataset --from-file=docs/peliculas.json --dry-run=client -o yaml | kubectl apply -f -
    kubectl rollout restart deployment/catalogo
    kubectl exec -it deploy/catalogo -- python manage.py seed

## Arquitectura interna
- `models.py`: define el modelo `Pelicula`
- `repository.py`: único punto de acceso a la base de datos
- `services.py`: lógica de negocio, traduce errores de DB a excepciones propias
- `views.py`: capa HTTP, traduce excepciones a códigos de estado
- `serializers.py`: formato de salida JSON
- `management/commands/seed.py`: carga idempotente del dataset
