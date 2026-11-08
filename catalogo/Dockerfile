# Etapa 1 "builder": instala dependencias en una carpeta aparte
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Etapa 2: imagen final, solo con lo necesario para ejecutar (más liviana)
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

# UID numérico: Kubernetes puede comprobar "runAsNonRoot" con un USER numérico
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser . .
USER 10001
EXPOSE 5000

# gunicorn reemplaza a runserver (el servidor de desarrollo, no apto para producción)
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-"]