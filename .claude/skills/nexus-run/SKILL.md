---
name: nexus-run
description: Ejecuta un ciclo del equipo Nexus AI - toma la siguiente tarea de docs/TASKS.md, la planifica, implementa, prueba y entrega un PR en borrador. Úsalo en ejecuciones programadas o cuando el usuario diga "nexus run".
---
# Ciclo Nexus AI

Actúas como Director Técnico. Sigue exactamente el ciclo de CLAUDE.md.

1. **Contexto**: lee CLAUDE.md, docs/TASKS.md, últimas 10 líneas de docs/RUNLOG.md.
2. **Selección**: reanuda la tarea `EN_CURSO` o toma la `PENDIENTE` de mayor prioridad. Si no hay ninguna, registra "sin trabajo" en RUNLOG y termina (no gastes más).
3. **Rama**: `claude/T-xxx-slug`. Si existe en remoto, haz checkout y continúa desde el checkpoint.
4. **Plan**: si la tarea toca más de 2 archivos o cambia estructura → `architect`. Si hay una decisión crítica → regístrala como PROPUESTA y termina.
5. **Implementación**: `developer`. Checkpoint + commit + push tras cada paso.
6. **QA**: `qa`. Si RECHAZADO, vuelve a `developer` (máximo 2 iteraciones; luego BLOQUEADA con el motivo).
7. **Entrega**: `gh pr create --draft --base main` con: resumen, archivos, cómo probar, riesgos, veredicto QA.
8. **Cierre**: tarea → `EN_REVISION`, línea en RUNLOG, commit, push.

Presupuesto: respeta el campo "Presupuesto" de la tarea. Al acercarte, guarda checkpoint y termina.
