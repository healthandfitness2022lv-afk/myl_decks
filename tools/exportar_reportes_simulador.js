// tools/exportar_reportes_simulador.js
//
// Junta los reportes que el dueño dejó en el tablero de una partida narrada
// ("Reportar" → habilidad mal ejecutada, jugada mejorable o regla mal
// aplicada), con el contexto necesario para reproducirlos:
//   - mazos, semilla y jugador de la simulación (narrar es determinista)
//   - las jugadas anteriores y la mesa en ese paso, con nombres de cartas
//   - las habilidades programadas de la carta reportada
//
// Uso (desde myl_decks/):  node tools/exportar_reportes_simulador.js
// Escribe simulator/cache/reportes_simulador.json y muestra un resumen.
// Lo usa el skill revisar-notas-simulador.

const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

initializeApp({
  credential: cert(
    require(path.join(__dirname, '..', 'secrets', 'firebase-admin.json')),
  ),
});

const CONTEXTO = 12; // jugadas previas que se incluyen

function mesaConNombres(paso, nombres) {
  const n = (id) => nombres[id] || id;
  return paso.j.map((j) => ({
    castillo: j.m,
    mano: j.h.map(n),
    cementerio: j.c,
    cementerioTope: j.ct ? n(j.ct) : null,
    destierro: j.d,
    reserva: j.r.map(n),
    orosTemporales: j.v || 0,
    pagado: j.p.map(n),
    apoyo: j.ap.map(n),
    defensa: j.def.map(([id, f, armas]) => ({ carta: n(id), fuerza: f, armas: armas.map(n) })),
    ataque: j.atk.map(([id, f, armas]) => ({ carta: n(id), fuerza: f, armas: armas.map(n) })),
  }));
}

async function main() {
  const db = getFirestore();
  const snap = await db.collection('simulations').get();
  const casos = [];
  const habilidadesPorId = {};
  for (const doc of snap.docs) {
    const s = doc.data();
    const reportes = Array.isArray(s.reportes) ? s.reportes : [];
    if (!reportes.length || !s.resultado) continue;
    const r = s.resultado;
    const nombres = r.cartas || {};
    const idPorNombre = Object.fromEntries(Object.entries(nombres).map(([id, nom]) => [nom, id]));
    const pasos = r.pasos || [];
    for (const rep of reportes) {
      const i = rep.paso;
      const paso = pasos[i];
      const cartaId = rep.carta ? idPorNombre[rep.carta] : null;
      if (cartaId && !(cartaId in habilidadesPorId)) {
        const c = await db.collection('cards').doc(cartaId).get();
        const d = c.data() || {};
        habilidadesPorId[cartaId] = {
          nombre: d.nombre,
          tipo: d.tipo,
          coste: d.coste,
          fuerza: d.fuerza ?? null,
          texto: d.habilidad || '',
          habilidades: d.habilidades || [],
        };
      }
      casos.push({
        simulacion: doc.id,
        mazoA: r.mazoA,
        mazoB: r.mazoB,
        deckA: s.deckA,
        deckB: s.deckB,
        seed: s.seed,
        jugador: s.jugador || 'heuristico',
        tipo: rep.tipo,
        carta: rep.carta || null,
        comentario: rep.comentario,
        paso: i,
        turno: rep.turno,
        fase: rep.fase,
        texto: rep.texto,
        anteriores: pasos.slice(Math.max(0, i - CONTEXTO), i).map((p) => p.x),
        siguientes: pasos.slice(i + 1, i + 4).map((p) => p.x),
        mesa: paso ? mesaConNombres(paso, nombres) : null,
        cartaProgramada: cartaId ? habilidadesPorId[cartaId] : null,
      });
    }
  }

  const dir = path.join(__dirname, '..', 'simulator', 'cache');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'reportes_simulador.json');
  fs.writeFileSync(file, JSON.stringify({ generado: new Date().toISOString(), casos }, null, 1));
  const porTipo = {};
  for (const c of casos) porTipo[c.tipo] = (porTipo[c.tipo] || 0) + 1;
  console.log(JSON.stringify({ file, reportes: casos.length, porTipo }, null, 2));
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
