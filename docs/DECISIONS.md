# DECISIONS — Registro de decisiones (ADR)

Estados: `PROPUESTA` (requiere aprobación humana) · `APROBADA` · `RECHAZADA` · `SUPERADA`.
Solo el humano cambia `PROPUESTA` → `APROBADA/RECHAZADA`.

## ADR-001 — Adopción de Nexus AI
- Estado: APROBADA
- Fecha: 2026-11-15
- Contexto: operar el repo con agentes autónomos con revisión humana obligatoria.
- Decisión: agentes trabajan en ramas `claude/*` y entregan PRs en borrador; `main` protegida.
- Consecuencias: ningún cambio llega a producción sin merge humano.

## ADR-002 — Regla estricta para `tournaments`
- Estado: PROPUESTA
- Fecha: 2026-11-17
- Contexto: el módulo de torneos nuevo usa `tournaments/{id}` con `players` y `matches`. La regla
  actual permite a cualquier usuario con sesión leer y escribir cualquier torneo y sus subcolecciones.
  La app restringe en pantalla (solo el organizador conduce el torneo, cada jugador carga su duelo),
  pero alguien con conocimientos podría editar resultados ajenos o leer listas ocultas.
- Decisión propuesta: (1) el documento del torneo lo edita solo `ownerUid`, salvo `playerUids` al
  inscribirse; (2) `players/{uid}` lo escribe su dueño mientras `status == 'inscripcion'` y el
  organizador siempre; el campo `cards` solo lo leen su dueño y el organizador hasta
  `status == 'finalizado'` (requiere mover la lista a un subdocumento); (3) `matches/{id}` lo crea el
  organizador y lo actualizan los dos jugadores del duelo o el organizador.
- Consecuencias: `firestore.rules` se comparte con NexusTCG; hay que desplegarla con cuidado y
  probarla en el emulador. Hasta entonces el torneo funciona con la regla abierta.

## ADR-003 — Borrar los datos de características de Firestore
- Estado: PROPUESTA
- Fecha: 2026-11-17
- Contexto: la app, el dashboard y el simulador ya no leen `cards.caracteristicasRaw`, `cards.tags`
  ni la colección `card_custom_features`. Quedan como datos sin uso.
- Decisión propuesta: respaldar y borrar esos campos y la colección.
- Consecuencias: irreversible sin el respaldo. Las habilidades conservan `featureName`, que el
  simulador usa para narrar la partida; eso no se toca.
