
import http from 'k6/http';
import { check, sleep } from 'k6';

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

const PICO_VUS = Number(__ENV.PICO_VUS || 20);

// Configuración de la prueba de pico
export const options = {
  stages: [
    { duration: '30s', target: 5 },
    { duration: '5s', target: PICO_VUS },
    { duration: '20s', target: PICO_VUS },
    { duration: '5s', target: 5 },
    { duration: '30s', target: 5 },
    { duration: '5s', target: 0 },
  ],

  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
    checks: ['rate>0.99'],
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

  sleep(1);
}
