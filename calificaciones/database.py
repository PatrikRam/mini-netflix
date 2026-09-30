import os

import psycopg2
from psycopg2.extras import RealDictCursor


DB_HOST = os.getenv("POSTGRES_HOST", "db")
DB_NAME = os.getenv("POSTGRES_DB", "calificaciones")
DB_USER = os.getenv("POSTGRES_USER", "calificaciones")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "calificaciones")


def obtener_conexion():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        cursor_factory=RealDictCursor,
    )


def crear_tabla():
    conexion = obtener_conexion()

    try:
        with conexion.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS calificaciones (
                    id SERIAL PRIMARY KEY,
                    pelicula_id INTEGER NOT NULL,
                    puntaje INTEGER NOT NULL CHECK (puntaje BETWEEN 1 AND 5),
                    resena TEXT,
                    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
            )

        conexion.commit()

    finally:
        conexion.close()