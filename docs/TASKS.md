# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Solo el humano mueve tareas a `HECHA` (al hacer merge).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | HECHO | Completar ARCHITECTURE.md inspeccionando el código real | claude/T-001-architecture | QA APROBADO; docs + valoración inicial | — | $67.250.000 |
| T-002 | P2 | PENDIENTE | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | — | — | — | por estimar |
| T-003 | P2 | EN_REVISION | Análisis comercial (sales): cliente objetivo, propuesta de valor, precios y 3 mejoras prioritarias | claude/T-003-analisis-comercial | QA APROBADO (solo docs; sin Flutter SDK en el entorno). SALES.md + T-004..T-006 + ADR-002 (PROPUESTA) | https://github.com/healthandfitness2022lv-afk/myl_decks/pull/9 | $600.000 |
| T-004 | P1 | PENDIENTE | Planes y cuotas por plan (entitlements) para simulador/IA | — | Propuesta T-003; requiere aprobación de ADR-002 (precios) y del cambio de esquema | — | por estimar |
| T-005 | P1 | PENDIENTE | Dashboard de liga compartible con marca de tienda | — | Propuesta T-003 | — | por estimar |
| T-006 | P2 | PENDIENTE | Informe público "Meta de la semana" compartible | — | Propuesta T-003 | — | por estimar |

## Detalle de tareas

### T-001 — Completar ARCHITECTURE.md
- Objetivo: describir stack, módulos, flujo de datos, cómo testear. Rellenar "Comandos del proyecto" en CLAUDE.md.
- Criterio de aceptación: documentos reflejan el código; **docs/VALORACION.md con la valoración inicial de todos los módulos existentes** (horas × $25.000 CLP/h y referencia de mercado); PR en borrador abierto.
- Presupuesto: 40 turnos.

### T-002 — Diagnóstico de calidad
- Objetivo: ejecutar análisis estático y tests del stack; por cada problema relevante crear una tarea nueva (P1/P2). No corregir aún.
- Criterio de aceptación: informe en el PR con salida real de los comandos.
- Presupuesto: 30 turnos.

### T-003 — Análisis comercial
- Responsable: subagente `sales` (requiere T-001 hecha para conocer la app).
- Objetivo: crear docs/SALES.md (segmento, propuesta de valor, competidores con precios, planes sugeridos) y sección "Visión comercial" en ROADMAP.md; proponer 3 mejoras como tareas nuevas.
- Criterio de aceptación: PR con docs/SALES.md y tareas nuevas en TASKS.md.
- Presupuesto: 30 turnos.

### T-004 — Planes y cuotas por plan (entitlements)
- Origen: `docs/SALES.md` §6, mejora 1. Impacto: sin plan/cuota no se puede cobrar ni proteger el worker que corre en el PC del dueño.
- Objetivo: modelo de plan por usuario (gratis/pro/liga/tienda), límites diarios de simulaciones y Desafío IA, y pantalla de upgrade (sin cobro real en esta tarea).
- Restricción: el cambio de esquema de `users/{uid}` (compartido con NexusTCG) y de `firestore.rules` es decisión crítica; si se necesita, registrar PROPUESTA y marcar `BLOQUEADA (aprobación)`. Depende de aprobar ADR-002.
- Criterio de aceptación: lógica de dominio pura en `lib/domain/` con tests (límites, reseteo diario, planes); UI de cuota restante en el Simulador; `flutter analyze` y `flutter test` en verde; PR en borrador.
- Presupuesto: 40 turnos.

### T-005 — Dashboard de liga compartible con marca de tienda
- Origen: `docs/SALES.md` §6, mejora 2. Impacto: la tienda/organizador es el comprador de mayor ticket y la liga es su caso de uso.
- Objetivo: enlace público por liga con nombre/logo de la tienda, tabla de posiciones y rondas, y exportación de resultados como imagen para RRSS; basado en `dashboard/index.html` y `screens/leagues/*`.
- Restricción: solo lectura de colecciones ya públicas; cualquier cambio a reglas es PROPUESTA. No desplegar.
- Criterio de aceptación: dashboard muestra marca configurable (campo opcional en la liga, retrocompatible); JS valida con el mismo chequeo de `deploy.ps1`; tests Flutter para la lógica nueva; PR en borrador con capturas.
- Presupuesto: 35 turnos.

### T-006 — Informe público "Meta de la semana"
- Origen: `docs/SALES.md` §6, mejora 3. Impacto: adquisición gratuita; contenido compartible en Discord/RRSS que lleva jugadores a la app.
- Objetivo: generar desde la matriz del meta existente (`meta_stats_screen`, `matriz_meta.py`) un resumen (mazos top, winrate con IC, cambios por Ban List) exportable como póster PNG y enlace de solo lectura.
- Restricción: no ejecutar el worker ni leer datos reales; trabajar sobre datos ya publicados en Firestore o fixtures de test.
- Criterio de aceptación: póster generado con datos de prueba, reutilizando el flujo de pósters existente (`deck_poster_share_service`); tests unitarios del armado del resumen; PR en borrador.
- Presupuesto: 25 turnos.
