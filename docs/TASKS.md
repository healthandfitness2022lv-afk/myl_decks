# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Solo el humano mueve tareas a `HECHA` (al hacer merge).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | PENDIENTE | Completar ARCHITECTURE.md inspeccionando el código real | — | — | — | por estimar |
| T-002 | P2 | BLOQUEADA (entorno: sin Flutter/Dart SDK) | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | claude/T-002-diagnostico | Clone de Flutter OK, pero la descarga del Dart SDK (storage.googleapis.com) devuelve 403 del proxy de la sesión en la nube. No se pudo ejecutar `flutter analyze`/`flutter test`. Reintentar cuando el entorno permita el dominio, o ejecutarlo en local. | — | $0 |
| T-003 | P2 | PENDIENTE | Análisis comercial (sales): cliente objetivo, propuesta de valor, precios y 3 mejoras prioritarias | — | — | — | por estimar |
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
