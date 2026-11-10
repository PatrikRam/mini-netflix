// Prueba de carga para disparar el HPA de catalogo (y rankings vía frontend).
//
// Uso:
//   BASE_URL=http://<elb-del-frontend> k6 run pruebas/k6/carga-catalogo.js
//   k6 run -e BASE_URL=http://<elb> -e VUS=80 -e DURACION=4m pruebas/k6/carga-catalogo.js
//
// En otra terminal, observar el escalado:
//   kubectl -n mini-netflix get hpa -w
//   kubectl -n mini-netflix get pods -l app=catalogo -w
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const VUS = parseInt(__ENV.VUS || '60', 10);
const DURACION = __ENV.DURACION || '4m';

export const options = {
  stages: [
    { duration: '30s', target: VUS },    // rampa de subida
    { duration: DURACION, target: VUS }, // carga sostenida: el HPA escala aquí
    { duration: '30s', target: 0 },      // bajada
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],      // < 5 % de errores
    http_req_duration: ['p(95)<3000'],   // p95 < 3 s
  },
};

const generos = ['accion', 'drama', 'comedia', 'ciencia ficcion', 'terror'];

export default function () {
  // 70 % catálogo (servicio con HPA al 50 %), 30 % rankings (HPA al 60 %)
  let res;
  if (Math.random() < 0.7) {
    const r = Math.random();
    if (r < 0.5) res = http.get(`${BASE_URL}/api/catalogo/peliculas`);
    else if (r < 0.8) res = http.get(`${BASE_URL}/api/catalogo/peliculas?genero=${generos[Math.floor(Math.random() * generos.length)]}`);
    else res = http.get(`${BASE_URL}/api/catalogo/peliculas/${1 + Math.floor(Math.random() * 30)}`);
  } else {
    res = http.get(`${BASE_URL}/api/rankings/rankings/top10`);
  }
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.1);
}
