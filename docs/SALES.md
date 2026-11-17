# SALES — Análisis comercial de MyL Mazos

> Subagente `sales`, T-003. Fecha: 2026-11-17. Precios en USD/EUR verificados vía web (fuente en cada fila).
> Todo precio en CLP de esta página es una **PROPUESTA** (ver `docs/DECISIONS.md`, ADR-002). No es promesa a clientes.
> Conversión USD/EUR a CLP: **no verificada**; se usa un supuesto de ~$950 CLP/USD y ~$1.050 CLP/EUR solo como orden de magnitud. Revisar con tipo de cambio del día.

## 1. Qué es hoy (resumen)
MyL Mazos (https://mylmazos.web.app/): catálogo, constructor de mazos, colección/inventario, Ban List, teams y ligas con dashboard público, comunidad, y **laboratorio del meta** (simulador N partidas, Desafío contra IA, optimizador de mazos). Detalle técnico en `docs/ARCHITECTURE.md`. Valor de reposición: $67.250.000 CLP (`docs/VALORACION.md`).

## 2. Segmento / cliente objetivo
Quien paga y quien decide:

| Segmento | Dolor | Quién paga | Quién decide | Prioridad |
|---|---|---|---|---|
| Jugador competitivo de Primer Bloque | No sabe qué mazo rinde en el meta; armar mazos con colección real es manual; Ban List cambia | El mismo jugador | El mismo (compra por impulso, ticket bajo) | Alta (volumen, boca a boca) |
| Capitán de team / organizador de liga | Armar rondas, resultados en Excel, tabla de posiciones, Ban List por ronda | Organizador o team | Organizador | Alta (puente a tiendas) |
| Tienda de cartas / productor de torneos | Torneos y ligas sin herramienta, fidelizar jugadores | La tienda (factura) | Dueño o encargado de eventos | Media-alta (ticket mayor) |
| Marca / editorial del juego | Herramienta digital oficial | Empresa | Gerencia | Baja, oportunista (ver riesgos) |

Evidencia de mercado: el juego es chileno y vive un renacimiento por la reedición de Primer Bloque; un torneo en junio 2024 en la tienda El Reino de los Duelos anunció premio de $1.000.000 CLP al primer lugar y ~350 competidores esperados de todo el país (https://www.biobiochile.cl/noticias/sociedad/curiosidades/2024/06/14/anuncian-torneo-de-mitos-y-leyendas-con-un-premio-mayor-a-un-millon-de-pesos.shtml). Tamaño real de la comunidad que paga: **no verificado**; validar con 20-30 jugadores (ya indicado en `docs/VALORACION.md`).

## 3. Propuesta de valor (una frase)
"Arma tu mazo con las cartas que ya tienes, pruébalo contra el meta con miles de partidas simuladas y organiza tu liga en un solo lugar, para Mitos y Leyendas Primer Bloque."

Diferenciador: el simulador con IA y la matriz del meta no existen en las alternativas encontradas para MyL (ver sección 4).

## 4. Competidores y precios (verificados)
No encontré una herramienta equivalente para Mitos y Leyendas con simulador + constructor + ligas (búsqueda web 2026-11-17: solo resultaron material oficial de myl.cl, tiendas y un juego en Steam). Eso **no prueba** que no exista (puede haber grupos de Discord/Facebook o hojas de cálculo); validar con jugadores.

### 4.1 Directos (mismo juego)
| Alternativa | Qué ofrece | Precio | Fuente |
|---|---|---|---|
| Myths & Legends Online (Steam, dev. Salo) | Versión digital para jugar; acceso anticipado desde 2019-08-09; 58% de 610 reseñas positivas ("Mixed"); última actualización de desarrolladores hace ~4 años según la página | Gratis (free to play) | https://store.steampowered.com/app/1005340/Myths_and_Legends__Card_Game?l=greek |
| Mitos y Leyendas Digital (Klu, Unity) | Anunciado en 2018 como versión digital; estado actual **no verificado** | No verificado | https://www.levelup.com/noticias/conoce-como-se-desarrolla-mitos-y-leyendas-digital-y-ve-avances-exclusivos-del-juego/ |
| Material oficial (manuales, FAQ, oráculos, mazos preconstruidos en PDF) | Reglas y listas; no es herramienta interactiva | Gratis | https://blog.myl.cl/ (ej. https://blog.myl.cl/wp-content/uploads/2026/03/Oraculo-Toolkit-PB-2026.pdf) |

Lectura: lo digital existente es para jugar, no para analizar meta ni gestionar colección/ligas. MyL Mazos es complementario, no sustituto.

### 4.2 Referentes de otros TCG (ancla de precio del plan Pro)
| Producto | Juego | Precio verificado | Qué cobra | Fuente |
|---|---|---|---|---|
| Deckbox Premium | Multi-TCG (inventario, mazos) | US$5,99/mes o US$3,99/mes facturado anual (US$47,88/año) | Mazos desde inventario real, historial, sin anuncios | https://deckbox.org/premium |
| MTGGoldfish Premium | Magic | US$5,99/mes o US$4,99/mes facturado anual (US$59,88/año) | Buscador de mazos según colección, alertas de precio, sin anuncios | https://www.mtggoldfish.com/premium |
| YGOPRODeck Premium | Yu-Gi-Oh! | EUR 4,99/mes (+ impuestos); precio anual no listado | Deck Brew según colección, sin anuncios, extras de perfil | https://ygoprodeck.com/premium/ |
| TCG Collector Premium | Pokemon | Precio **no verificado** (la página no lo muestra); free limita variantes por carta a 2 y wishlist a 300 | Límites ampliados y exportación | https://www.tcgcollector.com/premium |

No verificados (no se pudo obtener la página de precios): **Moxfield** y **Archidekt** (mencionados como referencia funcional en `docs/VALORACION.md`; su precio premium no se cita).

Lectura: el mercado cobra ~US$4-6/mes (~$3.800-5.700 CLP con el supuesto de tipo de cambio) por funciones de colección/mazos, siempre con plan gratis. Ninguno incluye simulación con IA, lo que respalda un plan Pro sobre ese ancla, pero el poder adquisitivo del jugador chileno y el tamaño de la comunidad sugieren entrar por debajo.

## 5. Planes sugeridos (CLP, PROPUESTA)
Precios con IVA (19%) incluido para personas; a tiendas/empresas se emite factura con IVA aparte. Cobro sugerido con medios locales (Flow, Mercado Pago o similar; **comisiones no verificadas**, cotizar antes de decidir).

| Plan | Para quién | Incluye | Precio sugerido |
|---|---|---|---|
| Gratis | Todo jugador | Catálogo, constructor y validador de mazos, colección básica, Ban List, comunidad | $0 |
| Pro Jugador | Competitivo | Todo lo gratis + simulador N partidas con IC, matriz del meta, optimizador, Desafío vs IA, póster sin marca | $2.990/mes o $29.900/año (2 meses gratis) |
| Liga / Team | Capitán u organizador | Pro para el equipo (hasta 10), ligas, rondas, importación Excel, Ban List por ronda, dashboard público | $14.990/mes (IVA aparte si factura) |
| Tienda / Organizador | Tienda o productora de torneos | Ligas ilimitadas, dashboard con marca de la tienda, soporte, onboarding | Instalación $150.000 + $39.900/mes (+IVA) |
| Venta exclusiva (opcional) | Editorial / marca | Licencia o venta del producto | $2.000.000-$5.000.000 (rango de `docs/VALORACION.md`, no validado) |

Coherencia con `docs/VALORACION.md`: Premium $2.000-5.000/mes por jugador y licencia a tiendas $20.000-50.000/mes; los planes caen dentro del rango.

Supuestos de unidad económica (a validar): el simulador y el worker corren en el PC del dueño (`docs/ARCHITECTURE.md`); no escala a muchos pagantes simultáneos sin cuotas ni infraestructura propia. Costos Firestore/OpenAI por usuario: **no estimados**.

## 6. Tres mejoras prioritarias por impacto comercial
| # | Mejora | Tarea | Por qué vende |
|---|---|---|---|
| 1 | Planes y cuotas (entitlements) con límites de simulaciones | T-004 (P1) | Sin esto no se puede cobrar ni proteger el PC-worker |
| 2 | Dashboard de liga compartible con marca de tienda | T-005 (P1) | Entrada B2B: la tienda es el comprador de mayor ticket |
| 3 | Informe público "Meta de la semana" compartible | T-006 (P2) | Adquisición gratuita: contenido que los jugadores comparten |

## 7. Riesgos comerciales
- **Propiedad intelectual:** nombres, ilustraciones y textos de cartas pertenecen al titular del juego; vender suscripciones sobre ese contenido puede requerir permiso/licencia. Titular y política de uso de terceros: **no verificados**. Consultar antes de cobrar (puede ser también una oportunidad de alianza).
- **Escala del simulador:** depende del PC del dueño; fuera de línea = servicio caído.
- **Comunidad pequeña:** conversión típica freemium es baja; con pocos cientos de jugadores activos el ingreso del plan Pro será modesto. Validar antes de invertir.
- **Calidad:** 19 tests Python fallidos y CI sin tests (ver `docs/VALORACION.md`) afectan la promesa de "simulación confiable".
- **Datos compartidos:** el proyecto Firebase se comparte con NexusTCG; cambios de esquema/reglas son decisión crítica.

## 8. Textos listos para usar

**Titular landing:** Arma, prueba y gana: el laboratorio del meta de Mitos y Leyendas Primer Bloque.

**Subtítulo:** Simula miles de partidas con tus mazos, usa las cartas que realmente tienes y organiza tu liga. Gratis para empezar.

**Mensaje para jugadores (RRSS/Discord):**
"¿Tu mazo aguanta el meta? En MyL Mazos lo simulas contra los demás mazos, ves tu winrate con margen de error y optimizas la lista. Prueba gratis: https://mylmazos.web.app/"

**Mensaje para tiendas (WhatsApp/correo):**
"Hola, soy [nombre] de Nexus Digital. Creamos MyL Mazos, la plataforma de ligas y mazos de Primer Bloque. Podemos llevar la liga de tu tienda con tabla de posiciones pública, Ban List por ronda y resultados desde Excel, con tu marca. ¿Te muestro una demo de 15 minutos?"

**Cierre de objeciones:**
- "Ya uso Excel": importamos tu Excel; la tabla y el dashboard se arman solos.
- "Es caro": el plan Pro cuesta menos que una carta suelta [validar con precios de singles antes de usar la frase].
- "¿Es oficial?": no; es una herramienta independiente de la comunidad [ajustar según resultado de la consulta de IP].

## 9. Próximos pasos
1. Entrevistar a 20-30 jugadores y 3-5 tiendas (disposición a pagar, precio, qué usan hoy).
2. Resolver consulta de IP con el titular del juego.
3. Aprobar o ajustar ADR-002 (precios) antes de comunicar cualquier valor.
4. Ejecutar T-004 a T-006 según prioridad.
