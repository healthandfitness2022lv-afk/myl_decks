# DECISIONS — Registro de decisiones (ADR)

Estados: `PROPUESTA` (requiere aprobación humana) · `APROBADA` · `RECHAZADA` · `SUPERADA`.
Solo el humano cambia `PROPUESTA` → `APROBADA/RECHAZADA`.

## ADR-001 — Adopción de Nexus AI
- Estado: APROBADA
- Fecha: 2026-11-15
- Contexto: operar el repo con agentes autónomos con revisión humana obligatoria.
- Decisión: agentes trabajan en ramas `claude/*` y entregan PRs en borrador; `main` protegida.
- Consecuencias: ningún cambio llega a producción sin merge humano.
