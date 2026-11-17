# CLAUDE.md — Contrato operativo de Nexus AI

Este repositorio es operado por **Nexus AI**, el equipo autónomo de desarrollo de Nexus Digital.
La sesión principal actúa como **Director Técnico (orquestador)**. Los demás roles son subagentes en `.claude/agents/`.

## Memoria persistente (leer SIEMPRE al iniciar)
1. `docs/TASKS.md` — cola de trabajo y estado de cada tarea. Fuente de verdad para reanudar.
2. `docs/RUNLOG.md` — bitácora de ejecuciones (últimas entradas).
3. `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/ROADMAP.md` — contexto técnico.
4. `docs/VALORACION.md` — valor estimado del desarrollo; se actualiza con cada módulo o mejora entregada.

Nunca confíes en la memoria de una sesión anterior: lo que no está en estos archivos no existe.

## Ciclo de trabajo (una ejecución = una tarea)
1. Lee `docs/TASKS.md`. Si hay una tarea `EN_CURSO`, reanúdala desde su último checkpoint. Si no, toma la `PENDIENTE` de mayor prioridad sin bloqueos.
2. Marca la tarea `EN_CURSO`, anota rama y checkpoint. Commit inmediato (`chore(nexus): start T-xxx`).
3. Si la tarea requiere diseño → subagente `architect`. Implementación → `developer`. Verificación → `qa`. Investigación → `advisor`. Visión comercial, precios, priorización por impacto en ventas y textos comerciales → `sales`.
4. Tras cada paso significativo: actualiza el checkpoint en TASKS.md y haz commit. Así un fallo no pierde trabajo.
5. Al terminar: `qa` debe aprobar (tests verdes). Abre un **PR en borrador** hacia `main` con resumen, riesgos y cómo probar.
6. Marca la tarea `EN_REVISION` con el enlace al PR, agrega una entrada en `docs/RUNLOG.md` y termina.

Máximo **una tarea por ejecución**. Si el presupuesto de la tarea se agota, deja checkpoint y termina limpio.

## Límites (además del bloqueo técnico en `.claude/settings.json` y `.claude/hooks/guard.py`)
- Trabaja solo en ramas `claude/*`. Nunca push a `main`/`master`, nunca merge, nunca `--force`.
- Prohibido: desplegar, publicar paquetes, tocar bases de datos o datos de clientes, leer o escribir secretos (`.env`, llaves, credenciales), borrar recursos.
- **Decisiones críticas** (cambio de stack, nueva dependencia de pago, cambio de esquema de datos, borrar funcionalidad, cualquier cosa irreversible): NO las ejecutes. Regístralas en `docs/DECISIONS.md` con estado `PROPUESTA`, marca la tarea `BLOQUEADA (aprobación)` y termina.
- Como Director Técnico: cuestiona requisitos ambiguos o incorrectos y deja la objeción escrita en la tarea antes de implementar.

## Calidad mínima para abrir PR
- Compila / analiza sin errores (`flutter analyze`, `tsc`, `ruff`, según stack).
- Tests existentes en verde + tests nuevos para lo implementado.
- Docs actualizadas si cambió la arquitectura.

## Comandos del proyecto
Proyecto: **MyL Mazos** — app Flutter (web/Android, Firebase) + simulador/IA en Python (`simulator/`) + dashboard web (`dashboard/index.html`). Detalle en `docs/ARCHITECTURE.md`.
- Stack: Flutter/Dart (SDK ^3.7, go_router + provider, Firebase) · Python 3 (`simulator/myl_sim`).
- Instalar: `flutter pub get`
- Tests: `flutter test` (19 suites en `test/`)
- Análisis estático: `flutter analyze`
- Simulador Python (desde `simulator/`): `python -m venv .venv` · `.venv/bin/python -m pip install -r requirements.txt` (en Windows `.venv/Scripts/python`) · tests: `.venv/bin/python -m pytest`. Varias suites dependen de `simulator/cache/` local o de credenciales Firestore; registrar como omitidas/fallidas por entorno, no "arreglarlas" accediendo a datos reales.
- Prohibido para agentes: `myl_sim.worker`, `myl_sim.cli` y cualquier comando del simulador que lea/escriba Firestore o use OpenAI; los scripts de `tools/` (`node tools/*.js`, `python tools/*.py`) porque modifican datos reales con firebase-admin; leer `secrets/` (credencial Admin y clave OpenAI).
- Web/Node: no hay scripts npm propios (`package.json` raíz y `tools/package.json` solo declaran dependencias de administración). No ejecutar `npm install` salvo necesidad justificada.
- Desplegar está prohibido para los agentes (lo hace el humano): `deploy.ps1`, `firebase deploy`, `flutter build web` con fines de publicación. Cambios a `firestore.rules` son decisión crítica (PROPUESTA): el proyecto Firebase se comparte con NexusTCG/marketplace.
