from flask import Flask, jsonify, request

app = Flask(__name__)

PELICULAS = [
    {"id": 1, "titulo": "Matrix", "genero": "accion", "anio": 1999},
    {"id": 2, "titulo": "Toy Story", "genero": "animacion", "anio": 1995},
    {"id": 3, "titulo": "El Padrino", "genero": "drama", "anio": 1972},
]

@app.route("/health")
def health():
    return jsonify(status="ok")

@app.route("/peliculas")
def listar():
    genero = request.args.get("genero")
    if genero:
        return jsonify([p for p in PELICULAS if p["genero"] == genero])
    return jsonify(PELICULAS)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)