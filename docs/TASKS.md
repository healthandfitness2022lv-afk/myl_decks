# TASKS — Cola de trabajo

Estados: `PENDIENTE` → `EN_CURSO` → `EN_REVISION` → `HECHA` · también `BLOQUEADA (motivo)`.
Prioridad: P0 (urgente) · P1 · P2. Solo el humano mueve tareas a `HECHA` (al hacer merge).

| ID | Prioridad | Estado | Título | Rama | Checkpoint / Notas | PR | Valor (CLP) |
|----|-----------|--------|--------|------|--------------------|----|-------------|
| T-001 | P1 | HECHO | Completar ARCHITECTURE.md inspeccionando el código real | claude/T-001-architecture | QA APROBADO; docs + valoración inicial | — | $67.250.000 |
| T-002 | P2 | BLOQUEADA (entorno: sin SDK Flutter en sesión nube) | Diagnóstico de calidad: análisis estático y tests, registrar fallos como tareas | claude/T-002-diagnostico-calidad | Parte Python hecha (ver docs/DIAGNOSTICO.md). Falta `flutter analyze` y `flutter test`: el proxy de la sesión bloquea storage.googleapis.com (403), no se puede descargar el SDK. Ejecutar esa parte en un entorno con Flutter o allowlistear el dominio. | — | $250.000 |
| T-004 | P2 | PENDIENTE | Test `test_trabajos_comandos_y_evaluador` depende de credenciales Firestore: aislarlo (mock de `cargar_carta`/skip sin credencial) | — | Hallazgo de T-002. Único fallo de pytest (1 failed, 571 passed, 244 skipped, 39 xfailed). No acceder a datos reales. | — | por estimar |
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
