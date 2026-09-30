FROM nginx:alpine
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    CATALOGO_URL=http://catalogo:5000 \
    CALIFICACIONES_URL=http://calificaciones:5000 \
    RANKINGS_URL=http://rankings:5000 \
    RECOMENDACIONES_URL=http://recomendaciones:5000
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY index.html app.js styles.css /usr/share/nginx/html/
