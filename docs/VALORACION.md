# VALORACIÓN — Valor de mercado y costo de desarrollo

> Mantenida por los agentes de Nexus AI. Se actualiza con cada módulo o mejora entregada (PR).
> Método: horas reales estimadas que tomaría desarrollar el módulo desde cero × tarifa base **$25.000 CLP/hora** (ver comercial/SERVICIOS.md en el repo nexus-ai). Incluye diseño, desarrollo, pruebas y documentación; no incluye hosting ni licencias.

## Valor de mercado (lo que se puede cobrar)
> Estimación comercial: cuánto pagaría un cliente por resolver su problema, según precios de alternativas en el mercado chileno (nov 2026). Las horas de abajo son solo el costo interno de desarrollo.

- **Qué resuelve:** Laboratorio del meta de Mitos y Leyendas: simular partidas y probar mazos.
- **Competencia y precios de referencia:** Nicho sin competidor directo conocido para MyL; en otros TCG las herramientas son freemium con planes premium de pocos dólares al mes.
- **Precio a un cliente:** Premium $2.000–$5.000/mes por jugador; licencia a tiendas u organizadores de torneos $20.000–$50.000/mes
- **Venta exclusiva a un cliente:** $2.000.000 – $5.000.000 (venta a una tienda/editorial de MyL)
- **Valor hoy como producto (sin clientes):** $3.000.000 – $8.000.000
- **Actualización T-003:** precios propuestos de planes (Pro $2.990/mes, Liga $14.990/mes, Tienda $150.000 + $39.900/mes) caen dentro del rango anterior y están ancladas en Deckbox/MTGGoldfish/YGOPRODeck (US$5-6/mes); el valor de mercado no cambia hasta validar con jugadores y resolver la consulta de propiedad intelectual. Detalle en `docs/SALES.md`.
- **Nota:** Valor alto por ser único en su nicho, pero depende del tamaño de la comunidad que pague; validar con 20–30 jugadores antes de invertir más.
- Fuentes: apps.shopify.com/bsale · guiadesoftware.com/blog/mejor-software-gestion-inventario-pymes-latam · capterra.es (GymMaster, Fitco, Boxmagic) · zenoti.com/es/thecheckin/best-fitness-gym-software-2026 · ecosistemastartup.com (easycancha) · 2x3.cl/p/precios-desarrollo-aplicacion-movil


## Resumen
- **Costo de desarrollo estimado (horas × tarifa): $67.850.000 CLP**
- Horas acumuladas: 2.714 h
- Última actualización: 2026-11-17 (T-003, análisis comercial)
- Referencia de mercado (funcional, sin precio de desarrollo comparable verificado):
  - Moxfield — constructor de mazos y colección para Magic: The Gathering, de uso gratuito: https://www.moxfield.com/ (equivale a los módulos de catálogo, mazos y colección; no tiene simulador).
  - Forge — motor de reglas e IA open source para Magic: The Gathering: https://github.com/Card-Forge/forge (referencia del alcance de un motor de reglas con IA; proyecto comunitario de muchos años).
  - Cotización pública de desarrollo a medida comparable en Chile: **pendiente de verificación** (no se citó ninguna URL sin certeza).

## Módulos
Criterio: estimación conservadora de un desarrollador senior con el dominio ya conocido, a partir del tamaño y complejidad real del código (≈115.000 líneas entre Dart, Python, JS y tests; ≈43 líneas/h promedio, más alto que la productividad típica, para no inflar el valor).

| Módulo / mejora | Descripción breve | Horas | Valor (CLP) | Fecha | PR |
|---|---|---|---|---|---|
| Base de la app y autenticación | `main.dart`, `router.dart` (go_router, rutas protegidas), login/registro, landing, perfil con Storage, roles, tema, registro de errores, widgets y utilidades comunes (~2.500 líneas) | 60 | $1.500.000 | 2026-11-15 | inicial |
| Catálogo de cartas | Catálogo Primer Bloque, detalle/alta/edición de cartas y variantes, propuestas de usuarios, características personalizadas (~8.700 líneas) | 180 | $4.500.000 | 2026-11-15 | inicial |
| Gestión de imágenes | Asignación masiva desde Google Drive, picker de Drive, subida y compresión a Cloudinary, resolución de imagen por variante (~3.800 líneas) | 90 | $2.250.000 | 2026-11-15 | inicial |
| Mazos | Constructor, validador, estadísticas, cobertura, comparación y diff, mazos notables, migración a esquema v2 (~20.000 líneas) | 320 | $8.000.000 | 2026-11-15 | inicial |
| Colección e inventario | Stock por variante, planificador de copias entre mazos, conciliación, faltantes, completitud, wishlist, planes de traspaso (~9.500 líneas) | 220 | $5.500.000 | 2026-11-15 | inicial |
| Ban List y pósters | Ban List general/libre/completa, exportación de pósters PNG de Ban List y mazos, compartir/descargar (~4.000 líneas) | 90 | $2.250.000 | 2026-11-15 | inicial |
| Social | Amigos y solicitudes, comunidades con posts/respuestas/videos, chat, permisos sociales (~2.300 líneas) | 70 | $1.750.000 | 2026-11-15 | inicial |
| Teams y ligas | Teams, miembros, ligas, rondas, emparejamientos, importación Excel, Ban List por ronda, mazos de liga, historial (~7.900 líneas) | 180 | $4.500.000 | 2026-11-15 | inicial |
| Dashboard web de ligas | `dashboard/index.html` en JS vanilla + Firebase JS SDK: clasificación, impacto del dado, duelos pendientes (~5.750 líneas) | 120 | $3.000.000 | 2026-11-15 | inicial |
| Editor de habilidades | Modelo declarativo `CardHabilidad`, editor de habilidades y efectos "luego", glosario, perfil de habilidades, guía `HABILIDADES.md` (~5.300 líneas) | 150 | $3.750.000 | 2026-11-15 | inicial |
| Laboratorio / simulador (UI Flutter) | Pantallas de simulación, tablero narrado, Desafío contra la IA, jugadas IA, laboratorio ML, estado de mazos, cartas por completar, estadísticas del meta (~7.800 líneas) | 200 | $5.000.000 | 2026-11-15 | inicial |
| Motor de reglas del simulador (Python) | Modelo de partida, turnos/oro/combate/zonas, ejecución del catálogo de habilidades (883 cartas cargadas), simulación N partidas con IC, carga desde Firestore (~5.800 líneas) | 300 | $7.500.000 | 2026-11-15 | inicial |
| IA de juego | Jugadores por niveles y heurístico, búsquedas por simulación (ataques, bloqueos, vigilia), modelo de mano oculta, valoración de estado (~9.000 líneas) | 280 | $7.000.000 | 2026-11-15 | inicial |
| Aprendizaje, arena, auditoría y meta | Autojuego y políticas aprendidas con criterios estadísticos, arena Elo, auditor de reglas, autopsias, matriz del meta y optimizador de mazos (~5.000 líneas) | 180 | $4.500.000 | 2026-11-15 | inicial |
| Worker e integración app-IA | Worker con colas Firestore (simulaciones, desafíos, trabajos ML, lectura de cartas con OpenAI), sesión humano-vs-IA mediada por documento, latido (~2.900 líneas) | 100 | $2.500.000 | 2026-11-15 | inicial |
| Infraestructura y herramientas | `firestore.rules` (~620 líneas) e índices, `deploy.ps1`, scripts de mantenimiento en `tools/` | 50 | $1.250.000 | 2026-11-15 | inicial |
| Suites de pruebas de regresión | 19 suites Flutter (~2.400 líneas) y 36 archivos pytest (~12.000 líneas, casos reportados reproducidos); solo la parte que excede lo incluido en cada módulo | 100 | $2.500.000 | 2026-11-15 | inicial |
| Análisis comercial y planes | `docs/SALES.md`: segmentos, competidores con precios verificados, planes en CLP (PROPUESTA ADR-002), 3 mejoras priorizadas | 24 | $600.000 | 2026-11-17 | T-003 (borrador) |

## Notas
- Valor de venta sugerido como producto (instalación + mensualidad): por definir tras la valoración inicial (T-003, subagente `sales`).
- La valoración mide costo de reposición del código, no valor de mercado del producto ni de sus datos (catálogo de cartas, habilidades programadas, partidas registradas), que no se incluyen.
- Las horas son conservadoras: el simulador con IA y el editor de habilidades son las piezas de mayor complejidad y podrían justificar más horas; no se infló la estimación.
- Reservas que pueden restar valor en una auditoría: 19 tests Python fallidos según `BITACORA.md`, CI sin ejecución de tests, dependencias declaradas sin uso, API key de Drive embebida en el cliente (ver `docs/ARCHITECTURE.md`).
