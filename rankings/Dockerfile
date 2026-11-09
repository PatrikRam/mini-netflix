
# Etapa 1: preparar las dependencias
FROM python:3.11-slim AS builder

WORKDIR /app

RUN python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt


# Etapa 2: imagen final de Rankings
FROM python:3.11-slim

WORKDIR /app

# Copiar las dependencias de la primera etapa
COPY --from=builder /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

# Crear usuario sin privilegios de root
RUN useradd --create-home --uid 10001 appuser

# Copiar el código del microservicio
COPY --chown=appuser:appuser app.py .

# Ejecutar como usuario no root
USER appuser

EXPOSE 5000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"]
