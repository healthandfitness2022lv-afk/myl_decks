// tools/exportar_notas_simulador.js
//
// Junta lo que falta para simular bien las cartas:
//   - cartas con `notasSimulador` (la nota de la carta)
//   - habilidades (o efectos "luego") con acción "otra" (el motor aún no la ejecuta)
// junto con el texto de la carta y sus habilidades actuales.
//
// Uso (desde myl_decks/):  node tools/exportar_notas_simulador.js
// Escribe simulator/cache/notas_simulador.json y muestra un resumen.
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

async function main() {
  const db = getFirestore();
  const snap = await db.collection('cards').get();
  const pendientes = [];
  for (const doc of snap.docs) {
    const c = doc.data();
    const habilidades = Array.isArray(c.habilidades) ? c.habilidades : [];
    const sinMotor = habilidades
      .map((h, i) => ({
        indice: i,
        featureName: h.featureName,
        enLuego: (h.luego || []).some((e) => e.accion === 'otra'),
        accion: h.accion,
      }))
      .filter((h) => h.accion === 'otra' || h.enLuego);
    const notas = (c.notasSimulador || '').trim();
    if (!notas && !sinMotor.length) continue;
    pendientes.push({
      id: doc.id,
      nombre: c.nombre,
      tipo: c.tipo,
      coste: c.coste,
      fuerza: c.fuerza ?? null,
      raza: c.raza ?? null,
      edicion: c.edicion,
      texto: c.habilidad || '',
      notasSimulador: notas,
      habilidadesSinMotor: sinMotor,
      habilidades,
      habilidadesRevisadas: c.habilidadesRevisadas === true,
    });
  }
  pendientes.sort((a, b) => String(a.nombre).localeCompare(String(b.nombre)));

  const dir = path.join(__dirname, '..', 'simulator', 'cache');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'notas_simulador.json');
  fs.writeFileSync(
    file,
    JSON.stringify({ generado: new Date().toISOString(), pendientes }, null, 1),
  );
  console.log(JSON.stringify({
    file,
    cartasConPendientes: pendientes.length,
    conNotasDeCarta: pendientes.filter((p) => p.notasSimulador).length,
    conAccionSinMotor: pendientes.filter((p) => p.habilidadesSinMotor.length).length,
  }, null, 2));
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
