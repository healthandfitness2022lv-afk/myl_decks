# Informe de correcciones del simulador

Registro de lo que se corrigió a partir de los reportes que Héctor deja en el tablero (botón del bicho).
Lo actualiza el agente horario «Corregir reportes del simulador (cada hora)». Lo más nuevo va arriba.

Cómo funciona: el worker copia cada 10 minutos los reportes de Firestore a `simulator/cache/reportes/`.
El agente revisa los nuevos (`python -m myl_sim.buzon_reportes pendientes`), reproduce la mesa, corrige el motor
con un test y deja aquí una fila por reporte. Si cambió el código, hay que reiniciar el worker.

Borrado: el worker borra de Firestore los reportes ya atendidos (menos las dudas). La copia local en
`simulator/cache/reportes/` los conserva todos, con su estado en `atendidos.json`.

## 20/11/2026 00:30 (dudas resueltas con Héctor)

| Reporte | Qué pedía | Qué se hizo | Archivo y test |
|---|---|---|---|
| g3hq T10 | Ver los oros generados (Herrero, Saladino, Dragones, Imhotep, Jano…) | Se ven como fichas «Oro temporal» en la Reserva de ambos tableros; también cuentan los de Saladino | `oro_temporal.dart`, `tablero_screen.dart`, `tablero_desafio.dart`, `motor.py`; `oros_temporales_test.dart` |
| g3hq T11 | Destrucciones en masa en una sola lista | «Destruidos en combate: A, B, C» y después lo que dispara cada uno | `motor.py`, `test_destrucciones_en_masa_en_una_sola_lista` |
| g3hq T11 | Mercaderes en un solo paso | Ya se agrupaba en la Fase Final | — |
| VWmE | El cuadro de la jugada debe crecer si el texto no cabe | Crece hasta más de la mitad de la pantalla, achica la letra en jugadas largas y muestra la barra | `tablero_screen.dart`, `oros_temporales_test.dart` |
| qZJp T12 | Erec con fuerza 3 | No era error: la fuerza estaba mal escrita en la base de datos | — |

Queda una duda: Haquika tomó el control de sí misma (oXy1); si vuelve a pasar, reportarla.

## 20/11/2026 00:30 (revisión de todos los reportes antiguos)

Se revisaron los 632 reportes: 516 corregidos (2 hoy y el resto ya estaban arreglados), 106 sugerencias de juego,
4 que no eran error y 6 dudas.

**Corregidos hoy**

| Reporte | Carta | Qué pasaba | Qué se hizo | Archivo y test |
|---|---|---|---|---|
| NJO9 T13 | Resplandor de Heka | Dejaba al Aliado sin habilidad por toda la partida | Ahora es solo hasta la Fase Final | `datos.py`, `test_resplandor_de_heka_*` |
| A3SB T14 | Orfeo | Te mostraba el mazo rival para elegir | Primero nombras a ciegas y después busca; puede fallar | `desafio.py` |

**Ya estaban corregidos** (se comprobó con un test en `test_reportes_20261120.py`): Guerrero Escorpión no se cuenta
a sí mismo (lLnW, ffAu), Djedefhor no se baraja a sí mismo (oXy1), Crom Dubh desterrado no dispara (5Lcf),
Epicuro no se sube a sí mismo (qZJp), Focea deja al Aliado en el tope (g3hq), Teseo solo destruye Aliados rivales
(g3hq), no se juega un segundo Killgharrah (lLnW), Cleopatra no nombra Faraón (9Phx), Demoledor sin habilidad no
ataca al entrar (oHee), Melisende pone al Caballero en el tope (tJU3, RVPb) y Neferite I ofrece al Kobold (pyCo).
Los otros 499 reportes eran de partidas ya revisadas en sesiones anteriores.

**No eran error**: Oillipheist pegaba 4 por el +2 permanente de Clochafarmore (tI7B); Galatine costó 2 por el
descuento de Yvain (tJU3); Crom Cruach sin objetivo de coste 2 (5Lcf, aclarado por Héctor).

**Dudas (no se borran)**: oros generados como temporales en la reserva (g3hq); agrupar destrucciones en masa y los
pasos de Mercaderes en la narración (g3hq); agrandar el cuadro cuando el texto no cabe (VWmE); Haquika tomó el
control de sí misma (oXy1, no reproducible); Erec con fuerza 3 (qZJp, no reproducible). Las cuatro primeras son
cambios de la app, no del motor.

**Sugerencias de juego (106)**: son de partidas del 9 al 12/11. Desde entonces la IA cambió mucho (búsqueda y
utilidad), así que no se tocaron una por una. Los temas que más se repiten: no descartar cartas clave (Lady Calvaur,
Idmon, oros), no barajar cartas útiles con Cathach o Cuna de Dragones, usar el Resplandor de Heka o la Guardia
Gozosa en el momento justo, no atacar a morir y bajar oro todos los turnos.

## 19/11/2026 22:57 (primera ejecución del agente)

- Se activó el buzón: 630 reportes copiados (46 desafíos y 94 simulaciones). Ninguno nuevo desde el último arreglo.

## 19/11/2026 00:15 (arreglo manual, antes del agente)

| Reporte | Carta | Qué pasaba | Qué se hizo | Archivo y test |
|---|---|---|---|---|
| IQVB T2 | Sir Agravain | Robaba 2 estando solo, aunque pide «otro Aliado Caballero» | Al jugarla, la propia carta ya no cuenta para su condición | `habilidades.py`, `test_sir_agravain_solo_no_roba` |
| dmwP T11 y P3Cy T18 | Magia Amatista | Dejaba robar sin destruir una copia en juego | El robo solo va si destruyó (nueva relación `si_anterior`, «si lo haces») | `datos.py`, `habilidades.py`, `test_magia_amatista_*` |
| dmwP T1 | Marmita Druida | Robaba sin mostrar un Druida de la mano | Ahora muestra un Druida y luego roba | `datos.py`, `test_marmita_druida_muestra_un_druida_para_robar` |
| dmwP T3 | Tadg | La carta tomada quedaba oculta aunque solo puede ser Oro o Aliado Druida | Se muestra la carta para probar que cumple | `habilidades.py`, `test_tadg_muestra_la_carta_que_toma` |
| gYcs T7 | Damarchus | No se podía activar en la Guerra de Talismanes | Se habilitó su activación en esa fase | `test_damarchus_se_activa_en_la_guerra_de_talismanes` |
