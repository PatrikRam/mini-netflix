// Todas las llamadas van a /api/<servicio>/... y nginx las reenvía (ver nginx.conf)
const API = { cat: '/api/catalogo', cal: '/api/calificaciones', rank: '/api/rankings', rec: '/api/recomendaciones' };
const $ = s => document.querySelector(s);
let tab = 'catalogo', promedios = {};

function h(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  kids.flat().forEach(c => e.append(c));
  return e;
}
async function get(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(r.status);
  return r.json();
}
// El campo de imagen del catálogo puede llamarse distinto: se prueban varios nombres
const poster = p => p.imagen || p.imagen_url || p.poster_url || p.poster || p.url_imagen || p.image || '';
const meta = p => [p.genero, p.anio].filter(Boolean).join(' · ');

function card(p) {
  const img = poster(p), prom = p.promedio ?? promedios[p.id];
  return h('article', { class: 'card', onclick: () => abrir(p) },
    img ? h('img', { src: img, alt: p.titulo, loading: 'lazy', onerror: e => e.target.remove() }) : '',
    h('div', { class: 'info' }, h('strong', {}, p.titulo), h('span', {}, meta(p)),
      prom != null ? h('span', { class: 'star' }, `★ ${Number(prom).toFixed(1)}`) : ''));
}

async function cargar() {
  const g = $('#genero').value, q = $('#q').value.trim().toLowerCase();
  $('#msg').textContent = 'Cargando...';
  try {
    let lista;
    if (tab === 'top') {
      lista = await get(g ? `${API.rank}/rankings/genero/${encodeURIComponent(g)}` : `${API.rank}/rankings/top10`);
      lista = lista.slice(0, 10);
    } else {
      const ps = new URLSearchParams();
      if (g) ps.set('genero', g);
      if (q) ps.set('buscar', q);
      lista = await get(`${API.cat}/peliculas${ps.toString() ? '?' + ps : ''}`);
    }
    // filtro extra en el navegador por si el servicio ignora algún parámetro
    lista = lista.filter(p => (!g || (p.genero || '').toLowerCase() === g) && (!q || p.titulo.toLowerCase().includes(q)));
    $('#grid').replaceChildren(...lista.map(card));
    $('#msg').textContent = lista.length ? '' : 'Sin resultados.';
  } catch (e) {
    $('#grid').replaceChildren();
    $('#msg').textContent = 'No se pudo conectar con el servicio.';
  }
}

async function cargarPromedios() {
  try { (await get(`${API.cal}/calificaciones/promedios`)).forEach(x => promedios[x.pelicula_id] = x.promedio); } catch (e) {}
}

function abrir(p) {
  const m = $('#modal'), cont = h('div');
  m.replaceChildren(h('button', { class: 'x', onclick: () => m.close() }, '✕'),
    h('h2', {}, p.titulo), h('p', { class: 'meta' }, meta(p)),
    p.descripcion ? h('p', {}, p.descripcion) : '', cont);
  m.showModal();
  detalle(p, cont);
}

async function detalle(p, cont) {
  let d = { promedio: 0, total: 0 };
  try { d = await get(`${API.cal}/calificaciones/${p.id}`); } catch (e) {}
  const rs = (d['reseñas'] || d.resenas || []).filter(r => r['reseña'] || r.resena);
  const form = h('form', { onsubmit: async e => {
    e.preventDefault();
    const f = e.target;
    try {
      const r = await fetch(`${API.cal}/calificaciones`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pelicula_id: p.id, puntaje: +f.puntaje.value, 'reseña': f.resena.value.trim() || null }) });
      if (!r.ok) throw new Error(r.status);
      await cargarPromedios();
      detalle(p, cont);
      cargar();
    } catch (err) { alert('No se pudo guardar la calificación.'); }
  } },
    h('select', { name: 'puntaje' }, [5, 4, 3, 2, 1].map(n => h('option', { value: n }, '★'.repeat(n)))),
    h('textarea', { name: 'resena', rows: 3, placeholder: 'Escribe tu reseña (opcional)' }),
    h('button', { class: 'ok' }, 'Calificar'));
  const sim = h('div', { class: 'chips' });
  cont.replaceChildren(
    h('p', { class: 'star' }, d.total ? `★ ${Number(d.promedio).toFixed(1)} (${d.total} calificaciones)` : 'Aún sin calificaciones'),
    form, h('h3', {}, 'Reseñas'),
    ...(rs.length ? rs.map(r => h('blockquote', {}, `★${r.puntaje} — ${r['reseña'] || r.resena}`)) : [h('p', { class: 'meta' }, 'Sin reseñas todavía.')]),
    h('h3', {}, 'Similares'), sim);
  try {
    let r = await get(`${API.rec}/recomendaciones/${p.id}`);
    r = Array.isArray(r) ? r : (r.recomendaciones || r.recomendadas || []);
    r.forEach(x => sim.append(h('span', { class: 'chip', onclick: () => abrir(x) }, x.titulo)));
    if (!r.length) sim.textContent = 'Sin recomendaciones.';
  } catch (e) { sim.textContent = 'Recomendaciones no disponibles aún.'; }
}

async function init() {
  try {
    const todas = await get(`${API.cat}/peliculas`);
    [...new Set(todas.map(p => p.genero).filter(Boolean))].sort()
      .forEach(x => $('#genero').append(h('option', { value: x.toLowerCase() }, x)));
  } catch (e) {}
  await cargarPromedios();
  cargar();
}
document.querySelectorAll('nav button').forEach(b => b.onclick = () => {
  tab = b.dataset.tab;
  document.querySelectorAll('nav button').forEach(x => x.classList.toggle('on', x === b));
  cargar();
});
let t;
$('#q').oninput = () => { clearTimeout(t); t = setTimeout(cargar, 300); };
$('#genero').onchange = cargar;
init();
