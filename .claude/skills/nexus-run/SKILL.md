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
7. **Entrega**: abre el PR en borrador con la API REST (GraphQL no está disponible en sesiones en la nube, así que `gh pr create` falla):
   `gh api repos/OWNER/REPO/pulls -f title="T-xxx: ..." -f head="claude/T-xxx-slug" -f base="RAMA_POR_DEFECTO" -F draft=true -f body="$(cat /tmp/pr.md)"`
   El cuerpo incluye: resumen, archivos, cómo probar, riesgos y veredicto QA. Si la API falla, deja la rama publicada y reporta el enlace `https://github.com/OWNER/REPO/compare/RAMA_POR_DEFECTO...claude/T-xxx-slug`.
8. **Valoración**: actualiza `docs/VALORACION.md` en la misma rama: agrega una fila por el módulo o mejora entregada (horas estimadas desde cero × $25.000 CLP/h, enlace al PR), recalcula el valor total y las horas acumuladas, y escribe el valor en la columna "Valor (CLP)" de la tarea en TASKS.md. Si el archivo no existe o su valor total es $0, primero haz la **valoración inicial**: una fila por cada módulo que ya existe en el código (marcada "inicial" en la columna PR), con sus horas y valor, y recién después suma la mejora de esta ejecución.
9. **Cierre**: tarea → `EN_REVISION`, línea en RUNLOG, commit, push.

Presupuesto: respeta el campo "Presupuesto" de la tarea. Al acercarte, guarda checkpoint y termina.
