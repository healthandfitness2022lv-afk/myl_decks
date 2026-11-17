# DECISIONS — Registro de decisiones (ADR)

Estados: `PROPUESTA` (requiere aprobación humana) · `APROBADA` · `RECHAZADA` · `SUPERADA`.
Solo el humano cambia `PROPUESTA` → `APROBADA/RECHAZADA`.

## ADR-001 — Adopción de Nexus AI
- Estado: APROBADA
- Fecha: 2026-11-15
- Contexto: operar el repo con agentes autónomos con revisión humana obligatoria.
- Decisión: agentes trabajan en ramas `claude/*` y entregan PRs en borrador; `main` protegida.
- Consecuencias: ningún cambio llega a producción sin merge humano.

## ADR-002 — Modelo de negocio y precios de MyL Mazos
- Estado: PROPUESTA
- Fecha: 2026-11-17
- Contexto: T-003 (`docs/SALES.md`). Hoy la app es gratuita; hay simulador/IA diferenciador y ligas utilizables por tiendas.
- Decisión propuesta: modelo freemium con planes Gratis $0 · Pro Jugador $2.990/mes ($29.900/año) · Liga/Team $14.990/mes · Tienda $150.000 de instalación + $39.900/mes (+IVA). Precios CLP con IVA para personas.
- Condiciones previas: validar disposición a pagar con 20-30 jugadores y 3-5 tiendas; consultar propiedad intelectual del juego con su titular; cotizar medio de pago local (comisiones no verificadas).
- Consecuencias: requiere T-004 (cuotas por plan, posible cambio de esquema de `users` compartido con NexusTCG: decisión crítica adicional). No comunicar precios a clientes hasta aprobar.
