# Frontend de Mini Netflix

El frontend es una página estática servida por Nginx. Desde la raíz del
repositorio se inicia junto con los servicios usando:

```sh
docker compose up --build
```

Luego se abre http://localhost:8080.

## Posters locales

Guarda cada póster como `images/posters/<id>.jpg`, donde `<id>` es el ID que
devuelve el catálogo para esa película. Por ejemplo, `images/posters/1.jpg`.
El frontend busca primero ese archivo local y, si no existe, intenta los campos
de imagen que entregue la API y finalmente muestra `images/poster-placeholder.svg`.

Al agregar o cambiar archivos, reconstruye el contenedor del frontend:

```sh
docker compose up --build -d frontend
```
