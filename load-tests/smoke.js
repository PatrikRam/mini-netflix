
import http from 'k6/http';
import { check } from 'k6';

// URLs parametrizables
const CATALOGO_URL =
  __ENV.CATALOGO_URL || 'http://host.docker.internal:5001';

const RECOMENDACIONES_URL =
  __ENV.RECOMENDACIONES_URL || 'http://host.docker.internal:5002';

const RANKINGS_URL =
  __ENV.RANKINGS_URL || 'http://host.docker.internal:5003';

const CALIFICACIONES_URL =
  __ENV.CALIFICACIONES_URL || 'http://host.docker.internal:5004';

const FRONTEND_URL =
  __ENV.FRONTEND_URL || 'http://host.docker.internal:8080';

// Configuración de la prueba Smoke
export const options = {
  vus: 1,
  iterations: 2,

  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
    checks: ['rate==1'],
  },
};

export default function () {
  const endpoints = [
    {
      nombre: 'catalogo',
      url: `${CATALOGO_URL}/peliculas`,
    },
    {
      nombre: 'recomendaciones',
      url: `${RECOMENDACIONES_URL}/recomendaciones/1`,
    },
    {
      nombre: 'rankings',
      url: `${RANKINGS_URL}/rankings/top10`,
    },
    {
      nombre: 'calificaciones',
      url: `${CALIFICACIONES_URL}/calificaciones/1`,
    },
    {
      nombre: 'frontend',
      url: `${FRONTEND_URL}/`,
    },
  ];

  for (const endpoint of endpoints) {
    const respuesta = http.get(endpoint.url, {
      tags: { servicio: endpoint.nombre },
    });

    check(respuesta, {
      [`${endpoint.nombre} responde 200`]: (r) =>
        r.status === 200,
    });
  }
}
