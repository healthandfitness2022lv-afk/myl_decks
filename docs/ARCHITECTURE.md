# ARCHITECTURE

> Mantenido por el subagente `architect`. Debe reflejar el código real, no intenciones.
> Última revisión: 2026-11-15 (T-001), por inspección directa del repositorio.

Producto: **MyL Mazos** (https://mylmazos.web.app/) — app para jugadores de Mitos y Leyendas (formato Primer Bloque):
catálogo de cartas, mazos, colección/inventario, Ban List, teams y ligas, comunidad, y un **laboratorio del meta**
(simulador de partidas, Desafío contra IA y entrenamiento de la IA). Incluye un dashboard web público de ligas
(https://mylmazos.web.app/dashboard/).

Tamaño aproximado (líneas, 2026-11-15): `lib/` ~70.600 (119 archivos Dart) · `simulator/myl_sim` ~22.000 Python
· `simulator/tests` ~12.000 · `test/` ~2.400 (19 suites) · `dashboard/index.html` ~5.750 · `firestore.rules` ~620.

## Stack

**App cliente (Flutter)**
- Flutter / Dart SDK `^3.7.0`. Objetivo principal: **web** (Firebase Hosting); también Android (`android/`) y configuración para Windows en `firebase.json`.
- Navegación: `go_router` (`lib/router.dart`, URLs limpias con `usePathUrlStrategy`). Estado global: `provider` (`ChangeNotifierProvider<CurrentUser>`); el resto es `StatefulWidget` + `StreamBuilder` sobre Firestore. **No usa Riverpod.**
- Firebase: `firebase_core`, `firebase_auth` (email/contraseña), `cloud_firestore` (persistencia offline con caché ilimitada, ver `lib/main.dart`), `firebase_storage` (solo foto de perfil).
- UI/medios: `fl_chart` (estadísticas), `google_fonts`, `material_symbols_icons`, `cached_network_image`, `video_player`, `flutter_colorpicker`, `image` (compresión), `image_picker`, `file_picker`, `excel` (importar resultados de liga), `share_plus`, `path_provider`, `web` (descarga PNG en web), `http`, `uuid`, `shared_preferences`, `intl`, `collection`.
- Dependencias declaradas en `pubspec.yaml` **sin import detectado en `lib/`**: `cloud_functions`, `google_sign_in`, `pdf`, `printing` (candidatas a limpieza; no eliminar sin aprobación).
- Lints: `flutter_lints` (`analysis_options.yaml`). Iconos: `flutter_launcher_icons`.

**Simulador / IA (Python, se ejecuta en el PC del dueño)**
- Python 3 + `firebase-admin` (Firestore vía Admin SDK), `pytest`, `openai` (lectura de texto de cartas desde imagen), `pillow` (`simulator/requirements.txt`).
- Paquete `simulator/myl_sim` con CLI (`python -m myl_sim.cli`) y un **worker** de larga duración que atiende colas en Firestore.

**Dashboard web de ligas**
- `dashboard/index.html`: HTML + JavaScript vanilla con Firebase JS SDK (CDN `gstatic.com/firebasejs`), solo lectura de `teams`, `leagues`, `rounds`, `players`, `cards`. Se copia dentro del build web en el deploy.

**Infraestructura**
- Firebase (proyecto `mylmazos`): Hosting (target `mylmazos`, `build/web-mylmazos`), Firestore (`firestore.rules`, `firestore.indexes.json`), Auth, Storage.
- El proyecto Firebase y el documento `users/{uid}` se **comparten con la app NexusTCG/marketplace** (repo separado `app_marketplace`); por eso `firestore.rules` también contiene reglas de `orders`, `cart_items`, `listings`, `reviews`, etc.
- No hay Cloud Functions en este repo (no existe `functions/`). El `package.json` raíz declara `firebase-admin`, `firebase-functions` y `nodemailer`, pero no hay código que los use aquí (residuo o código que vive en otro repo).
- `tools/`: scripts de mantenimiento con `firebase-admin` (Node y Python) que **escriben en datos reales**.
- CI: `.github/workflows/nexus-qa.yml` solo lanza la revisión del agente QA sobre PRs `claude/*`; **no ejecuta `flutter test` ni `pytest`**.

## Módulos principales

### App Flutter (`lib/`)
| Módulo | Rutas | Responsabilidad |
|---|---|---|
| Arranque y navegación | `lib/main.dart`, `lib/router.dart`, `lib/auth_gate.dart`, `lib/theme/app_theme.dart` | Inicializa Firebase y Firestore offline, instala `ErrorLogService`, escucha `users/{uid}` para poblar `CurrentUser` (rol `basico`/`administrador`), migra inventario al iniciar sesión. Rutas: `/`, `/login`, `/inventario`, `/catalogo`, `/meta`, `/mazos`, `/mazos/nuevo`, `/wishlist`, `/amigos`, `/comunidades/:id`, `/teams`, `/teams/:id`, `/perfil`, `/mazo/:uid/:id` (todas salvo `/` y `/login` con `_AuthGuard`). El resto de pantallas se abre con `Navigator.push`. |
| Autenticación y perfil | `screens/login_screen.dart`, `screens/profile_screen.dart`, `screens/nexus_home_screen.dart`, `models/app_user.dart`, `models/current_user.dart`, `screens/admin_users_screen.dart` | Login/registro email+contraseña, landing pública, perfil con foto en Storage, administración de roles. |
| Modelos | `lib/models/*` | `CardMyl`, `CardVariant`, `CardHabilidad` (~2.100 líneas: esquema de habilidades para el simulador), `Deck` (v1 y v2 unificado), `Inventory`, `BanListEntry`, `Team`, `Community`, `ChatMessage`. |
| Dominio (lógica pura, testeable) | `lib/domain/*` | `validation/deck_validator.dart` (reglas de construcción), `deck_statistics.dart`, `deck_coverage.dart`, `deck_stock_groups.dart`, `inventory_planner.dart` (asignación de copias entre mazos), `collection_reconciliation.dart`, `inventory_keys.dart`, `social_permissions.dart`, `perfil_habilidades.dart`. |
| Servicios / repositorios | `lib/services/*` | Acceso a Firestore por agregado: `card_service`, `deck_service`, `deck_v2_migration_service`, `inventory_service` (~2.250 líneas), `wishlist_service`, `ban_list_service`, `team_service`, `community_repository`, `chat_repository`, `notable_deck_service`, `feature_catalog_service`, `card_ai_job_service`, `error_log_service`; integraciones: `cloudinary_service`, `drive_service`, `deck_poster_share_service`. |
| Catálogo de cartas | `screens/cards_catalog_screen.dart`, `card_details_screen.dart`, `new_card_screen.dart`, `add_cards_screen.dart`, `submissions_screen.dart`, `feature_grouping_screen.dart`, `lib/data/pb_data.dart` | Catálogo de Primer Bloque (ediciones, razas), alta/edición de cartas y variantes, propuestas de usuarios (`card_submissions`), características personalizadas. |
| Imágenes de cartas | `screens/admin_bulk_assign_screen.dart`, `widgets/drive_image_picker.dart`, `widgets/card_image*.dart`, `widgets/network_image.dart`, `utils/card_image_resolver.dart` | Asignación masiva de imágenes desde Google Drive, subida a Cloudinary, resolución de URL por variante. |
| Mazos | `screens/create_deck_screen.dart`, `my_decks_screen.dart`, `deck_details_screen.dart` + `deck_details/` (stats, diálogos, export de póster), `deck_by_id_screen.dart`, `compare_decks_screen.dart`, `deck_diff_dialog.dart`, `notable_decks_screen.dart` | Constructor de mazos, validación, estadísticas, comparación y diff, mazos notables, póster PNG compartible. |
| Colección / inventario | `screens/card_inventory_screen.dart`, `wishlist_screen.dart`, `all_missing_cards_screen.dart`, `overall_completeness.dart`, `widgets/fill_decks_dialog.dart`, `transfer_plan_checklist.dart`, `deck_reconciliation_dialog.dart`, `per_copy_variant_dialog.dart` | Stock por variante, armado de mazos desde la colección, faltantes, wishlist, planes de traspaso. |
| Ban List | `screens/ban_list_screen.dart`, `screens/ban_list/ban_list_poster_export.dart`, `services/ban_list_service.dart` | Ban List general/libre/completa y póster exportable. |
| Social | `screens/friends_screen.dart`, `communities_screen.dart` | Amigos y solicitudes, comunidades con posts, respuestas y videos, chat. |
| Teams y ligas | `screens/teams_screen.dart`, `team_members_screen.dart`, `screens/leagues/*` (~7.300 líneas) | Teams, ligas, fechas/rondas, emparejamientos, importación de resultados desde Excel, Ban List por ronda, constructor de mazos de liga, historial. |
| Editor de habilidades | `screens/habilidades/*` (`habilidad_editor`, `luego_editor`, `card_habilidades_section`, `glosario_screen`), `models/card_habilidad.dart`, `HABILIDADES.md` | Programación declarativa de habilidades de cada carta (trigger → efecto → objetivo → costo → fase) que consume el motor Python. |
| Laboratorio / simulador (UI) | `screens/simulador/*`, `screens/meta_stats_screen.dart` | `simulador_screen` (pide simulaciones N partidas), `tablero_screen` (partida narrada), `desafio_ia_screen` + `tablero_desafio` (jugar contra la IA), `jugadas_ia`, `laboratorio_ml_screen` (trabajos de entrenamiento), `estado_mazos`, `cartas_por_completar` (cartas sin programar). |
| Utilidades y widgets | `lib/utils/*`, `lib/widgets/*` | Normalización de texto, constantes, descarga PNG (web/stub), skeletons, vistas de estado asíncrono. |

### Simulador e IA (`simulator/myl_sim/`)
| Grupo | Archivos | Responsabilidad |
|---|---|---|
| Motor de reglas | `modelo.py`, `motor.py`, `habilidades.py` (~3.500), `simulacion.py`, `datos.py`, `REGLAS.md` | Estado de partida, turno/oro/combate/zonas, ejecución de cada habilidad del catálogo, N partidas con IC del winrate, carga de cartas/mazos desde Firestore con caché en `simulator/cache/`. |
| Jugadores / IA | `jugadores.py` (~7.100), `busqueda_ataques.py`, `busqueda_bloqueos.py`, `busqueda_vigilia.py`, `creencias.py`, `valor.py`, `evaluador.py`, `posiciones.py`, `politica_meta.py` | Jugadores aleatorio, niveles 1–5 y heurístico; búsquedas por simulación; modelo de mano oculta; valoración de estado. |
| Aprendizaje y medición | `aprendizaje.py`, `aprendizaje_humano.py`, `exploracion.py`, `entrenamiento.py`, `informe_entrenamiento.py`, `arena.py` (Elo Bradley-Terry), `auditoria.py`, `autopsia.py`, `precision.py`, `mineria.py` | Episodios de autojuego, políticas aprendidas con criterios de aprobación estadística, arena de motores, auditor de bugs de regla y jugadas sospechosas. |
| Meta y optimización | `meta.py`, `matriz_meta.py`, `optimizador.py` | Matriz todos contra todos ponderada por Ban List; optimización de mazos (screening + successive halving). |
| Integración con la app | `worker.py`, `desafio.py`, `trabajos.py`, `reportes_desafio.py`, `ia_cartas.py`, `codigos_cartas.py`, `cola_agente.py`, `cli.py` | Worker que atiende colas Firestore; sesión de Desafío humano-vs-IA mediada por documento; lectura de cartas con OpenAI. |

### Otros
- `dashboard/index.html` — dashboard público de ligas (clasificación, impacto del dado, duelos pendientes; ver `DASHBOARD_FUNCIONES.txt`).
- `tools/` — `exportar_notas_simulador.js`, `exportar_reportes_simulador.js` (alimentan el skill `.claude/skills/revisar-notas-simulador`), `unificar_catalogo.py`, `reetiquetar_cartas.py` (migraciones de datos de cartas), `generar_resumen_2026_11_14.py`.
- `deploy.ps1` — build web + copia del dashboard + `firebase deploy` (hosting y opcionalmente reglas/índices). **Uso exclusivo del humano.**
- Documentación de dominio: `HABILIDADES.md`, `BITACORA.md` (cambios diarios), `simulator/README.md`, `simulator/REGLAS.md`, `simulator/CAMBIOS.md`.

## Flujo de datos

1. **Auth**: Firebase Auth (email/contraseña) → `main.dart` escucha `users/{uid}` y llena `CurrentUser` (rol). Reglas usan `role == 'administrador'` / `marketplaceRole == 'admin'` y una lista fija de correos para el "super admin" de catálogo.
2. **Lectura/escritura directa a Firestore desde el cliente** (no hay backend propio). Colecciones principales:
   - Catálogo: `cards/{id}` + `cards/{id}/variants`, `card_custom_features`, `card_submissions`, `ban_list`, `ban_list_libre`, `ban_list_full`, `notable_decks`, `config`.
   - Por usuario: `users/{uid}` con subcolecciones `decks` (+ `match_logs`), `inventory`, `wishlist`, `transfer_plans`, `friends`, `teams`, `favorites`, `notifications`… (más las del marketplace compartido: `bundles`, `manual_sales`, `marketplace_folders/listings`, `cart_items`, `reviews`).
   - Social y competitivo: `friend_requests`, `communities/{id}/posts|replies|members|videos`, `chats/{id}/messages`, `teams/{id}/members|players`, `leagues/{id}/players|rounds`, `tournaments`, `matches`.
   - Telemetría: `app_errors` (errores no manejados en release).
3. **Migraciones en cliente**: `deck_v2_migration_service` y `InventoryService.migrateFromDecksIfNeeded` convierten datos al iniciar sesión (marca `users/{uid}.deckMigrationV2`); las reglas validan `schemaVersion == 2` una vez completada.
4. **Colas app ↔ worker Python** (Firestore como bus; el worker corre en el PC del dueño con credencial Admin fuera de git):
   - `simulations/{id}` (`status: pending → running → done|error`, `progreso`, `resultado`) — Simulador.
   - `ai_challenges/{id}` (+ `grabacion/registro`, `repeticion/{chunk}`) — Desafío IA: el worker publica opciones legales y la app escribe la decisión del humano; también autopsias pedidas.
   - `ml_jobs/{id}` — trabajos de meta/entrenamiento del Laboratorio ML.
   - `card_ai_jobs/{id}` — lectura del texto de la carta desde su imagen oficial con OpenAI (solo cuenta dueña, `CardAiJobService.puedeUsar`).
   - `ia_lecciones/{id}` — lecciones extraídas de partidas humanas.
   - `simulator_status/worker` — latido cada 30 s; la app muestra si el worker está vivo.
   - Toma de trabajos con transacción (`status == pending`) para tolerar más de un worker.
5. **Imágenes**: cartas → Google Drive (listado vía Drive API v3 con API key) y Cloudinary (subida unsigned con preset, compresión a ≤500 KB en cliente); avatar → Firebase Storage. Pósters de mazo/Ban List se renderizan a PNG en cliente y se comparten/descargan.
6. **Dashboard**: lee `teams`/`leagues`/`rounds` con el SDK JS directamente.
7. **Datos locales del simulador**: `simulator/cache/` (episodios, modelos, arena, auditorías) — no se suben a Firebase.

## Integraciones externas
| Servicio | Dónde | Uso | Notas / riesgos |
|---|---|---|---|
| Firebase Auth / Firestore / Storage / Hosting | toda la app, `firebase.json`, `deploy.ps1` | Backend completo | Proyecto compartido con NexusTCG; un deploy de `firestore.rules` desde aquí afecta también al marketplace. `storage.rules` no está en el repo. |
| Cloudinary | `lib/services/cloudinary_service.dart` | Subida de imágenes y videos (presets unsigned) | Presets unsigned permiten subir a cualquiera que conozca el cloud name; plan/costo fuera del repo. |
| Google Drive API v3 | `lib/services/drive_service.dart`, `widgets/drive_image_picker.dart` | Explorar carpetas de imágenes de cartas y wallpapers | **API key embebida en el código cliente**: debe estar restringida por referrer y a Drive API (verificar en consola; no citar la clave). |
| OpenAI API | `simulator/myl_sim/ia_cartas.py`, `codigos_cartas.py` | Leer texto/códigos de cartas desde imagen | Modelo configurable por `OPENAI_MODEL`; clave en variable de entorno o `secrets/` (fuera de git). Costo variable por uso. |
| Firebase Admin SDK (Python/Node) | `simulator/`, `tools/` | Worker y scripts de mantenimiento | Credencial en `secrets/` fuera de git; los scripts de `tools/` modifican datos reales. |
| Firebase JS SDK (CDN) | `dashboard/index.html` | Dashboard de ligas | Versión fijada por URL de CDN. |
| GitHub Actions + Claude Code Action | `.github/workflows/nexus-qa.yml` | Revisión QA automática de PRs `claude/*` | No corre tests. |

## Cómo se prueba

**Flutter** (desde la raíz): `flutter pub get` · `flutter analyze` · `flutter test`. 19 suites en `test/`, todas unitarias o de widget, sin Firebase real:
- Dominio: `deck_validator_test`, `deck_coverage_test`, `deck_stock_groups_test`, `inventory_planner_test`, `collection_reconciliation_test`, `social_permissions_test`, `perfil_habilidades_test`.
- Modelos: `deck_v2_model_test`, `inventory_marketplace_test`, `ban_list_snapshot_test`, `round_ban_list_format_test`, `card_habilidad_test`, `card_habilidad_campos_extra_test`, `card_habilidad_campos_nuevos_test`, `card_habilidad_guerrero_dragon_titan_test`.
- Widgets / simulador UI: `per_copy_variant_dialog_test`, `deck_reconciliation_dialog_test`, `tablero_desafio_test`, `mazo_valido_simulador_test`.

**Simulador Python** (desde `simulator/`): `python -m venv .venv` · `pip install -r requirements.txt` · `python -m pytest`. 35 test_*.py + conftest en `simulator/tests/` (motor, habilidades por tandas de cartas, reportes de partidas reproducidos, arena, auditoría, worker, entrenamiento, meta). Al menos 12 suites usan `cargar_mazo`/`db()`/`CACHE` y dependen de `simulator/cache/` local o de credenciales Firestore; no son reproducibles en CI sin esos datos. Según `BITACORA.md` (2026-11-15) la suite completa dio 728 aprobadas, 1 omitida y 19 fallidas pendientes de análisis.

**Dashboard**: `deploy.ps1` valida que el JavaScript del dashboard parsee (`node -e "new Function(...)"`); no hay tests de comportamiento.

**Brechas conocidas**: no hay tests de servicios Firestore (sin `fake_cloud_firestore`), ni de reglas (`firestore.rules` sin emulador), ni de integración; la CI no ejecuta tests. Estas brechas son insumo para T-002.
