
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

// =====================================================
// 1. CONFIGURACIÓN DE ENDPOINTS
// =====================================================

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

// =====================================================
// 2. MÉTRICAS PERSONALIZADAS
// =====================================================

// Tiempo entre la detección de una interrupción
// y la primera respuesta exitosa posterior.
const tiempoRecuperacion = new Trend(
  'tiempo_recuperacion_ms',
  true
);

// =====================================================
// 3. CONFIGURACIÓN DE K6
// =====================================================

export const options = {
  vus: 1,
  duration: '90s',

  thresholds: {
    // Servicios que deben permanecer disponibles.
    'checks{servicio:catalogo}': ['rate==1'],
    'checks{servicio:rankings}': ['rate==1'],
    'checks{servicio:calificaciones}': ['rate==1'],
    'checks{servicio:frontend}': ['rate==1'],
  },
};

// =====================================================
// 4. ESTADO DE LA PRUEBA
// =====================================================

// Un único VU mantiene este estado entre iteraciones.
let inicioFallo = null;

// =====================================================
// 5. EJECUCIÓN PRINCIPAL
// =====================================================

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

    // ================================================
    // 6. REALIZAR SOLICITUD HTTP
    // ================================================

    const respuesta = http.get(endpoint.url, {
      timeout: '2s',

      tags: {
        servicio: endpoint.nombre,
      },

      // Solo HTTP 200 se considera exitoso.
      // Los fallos intencionales de recomendaciones
      // se analizan por separado mediante checks.
      responseCallback: http.expectedStatuses(200),
    });

    const disponible = respuesta.status === 200;

    // ================================================
    // 7. VERIFICAR DISPONIBILIDAD
    // ================================================

    check(
      respuesta,
      {
        [`${endpoint.nombre} responde 200`]: (r) =>
          r.status === 200,
      },
      {
        servicio: endpoint.nombre,
      }
    );

    // ================================================
    // 8. MONITOREAR FALLO DE RECOMENDACIONES
    // ================================================

    if (endpoint.nombre === 'recomendaciones') {

      const ahora = Date.now();
      const fecha = new Date(ahora).toISOString();

      // Detectar primera respuesta fallida.
      if (!disponible && inicioFallo === null) {

        inicioFallo = ahora;

        console.log(
          `[FALLO DETECTADO] ${fecha} ` +
          `- HTTP ${respuesta.status} ` +
          `- Error: ${respuesta.error || 'sin detalle'}`
        );
      }

      // Detectar recuperación.
      if (disponible && inicioFallo !== null) {

        const duracion = ahora - inicioFallo;

        tiempoRecuperacion.add(duracion);

        console.log(
          `[SERVICIO RECUPERADO] ${fecha} - HTTP 200`
        );

        console.log(
          `[TIEMPO DE RECUPERACION OBSERVADO] ` +
          `${duracion} ms (${(duracion / 1000).toFixed(3)} s)`
        );

        inicioFallo = null;
      }
    }

    // ================================================
    // 9. MONITOREAR LOS OTROS MICROSERVICIOS
    // ================================================

    if (
      endpoint.nombre !== 'recomendaciones' &&
      !disponible
    ) {

      console.error(
        `[FALLO INESPERADO] ` +
        `Servicio: ${endpoint.nombre} ` +
        `- HTTP ${respuesta.status} ` +
        `- Fecha: ${new Date().toISOString()} ` +
        `- Error: ${respuesta.error || 'sin detalle'}`
      );
    }
  }

  // Esperar antes de la siguiente iteración.
  sleep(1);
}
