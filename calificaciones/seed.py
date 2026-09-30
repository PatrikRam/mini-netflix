import random

from database import crear_tabla, obtener_conexion

TOTAL_PELICULAS = 30
TOTAL_CALIFICACIONES = 100


def generar_calificaciones():
    crear_tabla()
    conexion = obtener_conexion()
    
    try:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) AS total FROM calificaciones;")
            total_actual = cursor.fetchone()["total"]

            if total_actual > 0:
                print(
                    f"La base ya contiene {total_actual} calificaciones. "
                    "No se generaron nuevas."
                )
                return

            for _ in range(TOTAL_CALIFICACIONES):
                pelicula_id = random.randint(1, TOTAL_PELICULAS)

                # Distribución ligeramente favorable para que
                # los promedios no queden todos demasiado bajos.
                puntaje = random.choices(
                    population=[1, 2, 3, 4, 5],
                    weights=[5, 10, 20, 35, 30],
                    k=1,
                )[0]

                cursor.execute(
                    """
                    INSERT INTO calificaciones (
                        pelicula_id,
                        puntaje,
                        resena
                    )
                    VALUES (%s, %s, %s);
                    """,
                    (
                        pelicula_id,
                        puntaje,
                        None,
                    ),
                )

        conexion.commit()
        print(f"{TOTAL_CALIFICACIONES} calificaciones generadas.")

    finally:
        conexion.close()


if __name__ == "__main__":
    generar_calificaciones()