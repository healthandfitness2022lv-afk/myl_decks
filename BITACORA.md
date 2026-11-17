# Bitácora diaria · MyL Mazos

Todos los cambios y arreglos del proyecto (app, motor del simulador, IA y
datos de cartas), un día por sección y lo más nuevo arriba. El detalle técnico
de las rondas de medición del simulador sigue en `simulator/CAMBIOS.md`.

Cómo se mide lo de la IA:
- **Lecciones:** una jugada tuya (o un error de la IA) se aplica solo si se
  confirma con 40 simulaciones (o 24 a 2 turnos), no con las 12 del análisis.
- **Lotes:** 200 partidas por cruce, reglas apagadas contra encendidas.
- **Tests:** `pytest` en `simulator/` (las 18 fallas que vienen de la otra
  sesión de trabajo no se cuentan) y `flutter test test/tablero_desafio_test.dart`.

---

## 2026-11-16

### Partidas de la noche (Defensor vs Dragón)

| Reporte | Qué pasó | Arreglo |
|---|---|---|
| fu7V T10: «no siempre tengo disponible Anillos de Badbury» | El Cinturón De Lady Ann del Dragón estaba en su Reserva («los Cementerios no pueden ser desterrados»). El motor estaba bien: cuando lo pagó para la Capa, Anillos volvió a salir. La app no decía por qué | Al tocar Anillos, dice «No se puede desterrar del Cementerio: Cinturón De Lady Ann (del rival) lo impide mientras esté en la Reserva». Test nuevo |
| fu7V T10: Conchobar barajado por la Capa no movió a nadie | Su texto dice zona `defensa` y el motor solo entendía `linea_defensa`: **nunca** encontraba objetivos, con o sin Capa. Lo mismo en 13 cartas más (`defensa`: Asaltar la Caravana, Aura Bendita, Bodicea, Brian Boru, Mafedet, Sir Robin de Lockesley, Suma; `ataque`: Asclepio, Carnero De Kush, Defensa Celestial, Lobo Fianna, Paris, Robar el Fuego Solar) | El motor entiende `defensa`/`ataque`/`apoyo` como las líneas. Regla de Héctor: la habilidad de entrada se resuelve aunque la barajen (solo se pierde si la cancelan: Siete contra Tebas, Desafiar a Arturo, Flidais) |
| Regla de Héctor: Haquika barajada en respuesta | Tomaba el control igual, aunque su control dura «mientras esté en juego» | Si ya salió del juego, no toma el control. Tests nuevos para Conchobar, Haquika y las zonas |
| Vwo2 T6: «me equivoqué al descartar la Bola de Fuego» | Error propio | Sin cambio |
| mgDm (Duda de la IA): error `cannot import remuestrear_ocultas` | El worker corre una versión vieja del código en memoria | Worker reiniciado a las 23:33 (se cortaron TJTK y Xa9P, que seguían en «esperando») |

**Publicado** (23:35): mesa fija del celular, aviso de la IA de 3 s y el motivo de Anillos de Badbury, en https://mylmazos.web.app.

### App: cartas grandes en el celular (todas las mesas del simulador)

Héctor: «no quiero tener que estarme acercando para ver qué carta es; debe ser
muy jugable y fácil». En el celular vertical las mesas se escalaban desde un
lienzo de 900 de ancho y las cartas quedaban de ~70 px.

- **Desafío IA y Dudas** (`tablero_desafio.dart`): lienzo propio de 480 de ancho
  (cartas de ~105 px en un teléfono de 390) que se desplaza en vertical y parte
  mostrando tu lado entero. Barra de acciones fija abajo (instrucción en 3 líneas,
  botones grandes); las opciones para elegir cartas quedan fijas arriba. Ficha
  compacta por jugador (Castillo, mano, Cementerio y Destierro tocables) y botón
  con todas las jugadas. El nombre de cada carta va escrito al pie.
- **Repetición de simulaciones y desafíos** (`tablero_screen.dart`): mismo
  lienzo de 480 con desplazamiento, nombre al pie, y tocar cualquier carta la
  muestra en grande (en todos los tamaños).
- Horizontal y pantallas anchas: sin cambios.
- Tests: `celular: cartas grandes con su nombre y la barra fija abajo`; ajustadas
  2 pruebas a la mesa del celular. `flutter test`: 109 pasan.
- Sin publicar todavía.

**Ajuste: una sola pantalla, sin scroll.** Héctor: «la pantalla fija, sin estar
escroleando, con los mensajes y respuestas al medio entre los dos campos».

- **Desafío/Dudas:** la mesa del celular ya no es un lienzo que se desplaza, sino
  columnas que llenan la pantalla. Las líneas vacías (Ataque casi siempre) quedan
  angostas, solo con su título, y las que tienen cartas se reparten el alto (mano
  con cartas de ~130 px en un teléfono normal fuera de combate). Al medio va la
  instrucción con sus botones (o, si no te toca, el turno y la última jugada;
  tocarla abre todas). Las cartas para elegir aparecen ahí mismo, entre los dos
  campos. La Reserva y lo Pagado del rival pasan a su ficha como fichas tocables.
- **Repetición:** el lienzo de 480 toma el alto de la pantalla; ficha de una fila
  por jugador (Oros como número, Cementerio y Destierro tocables), las líneas
  vacías se achican y la jugada queda al medio.
- Tests: `celular: una sola pantalla, cartas grandes y los botones al medio` y
  `celular: mesa llena en combate cabe sin desplazar` (360×640). `flutter test`:
  110 pasan. La repetición no tiene prueba automática (necesita Firestore).

**Aviso de la jugada de la IA más corto.** Héctor: «demora un montón en
desaparecer y entorpece el juego». El aviso de arriba (`desafio_ia_screen.dart`)
duraba 6 s cuando te tocaba elegir y todo el turno de la IA mientras jugaba,
tapando la mesa rival. Ahora dura 3 s en ambos casos (cada jugada nueva lo
reinicia) y se cierra al tocarlo; el aviso de habilidad fallida baja de 5 a 3 s.
La jugada sigue escrita al medio de la mesa y en el historial.

### Auditoría del entrenamiento: juez nuevo e IA buena `v1116`

Objetivo (Héctor): que la IA tome siempre la mejor decisión con lo que sabe en
la partida, gane o no.

**El corrector ya no ve la mano del rival** (`autopsia.reproducir`, `turnos.valorar`)
- Antes, al revisar una jugada, la partida se repetía con la mano real del rival
  en todas las muestras: una jugada buena quedaba como «error» si esa vez el
  rival tenía la respuesta. Ahora en cada muestra el rival recibe otra mano de
  las que podía tener. Rige en minería, cosecha del banco, precisión, dudas y
  el análisis de tus partidas.
- Señal de que importaba: en 40 partidas de prueba la minería ya no encontró
  ningún «error firme» (antes sí); con 80 aparece uno.

**Juez de precisión** (`myl_sim/precision.py`)
- Prueba hasta 10 jugadas por decisión, 6 muestras a todas y hasta 24 a las
  finalistas, a 4 turnos. La mejor alternativa se elige con la mitad de las
  muestras y la pérdida se mide con la otra mitad (elegir y medir con las mismas
  inflaba los errores).
- `python -m myl_sim.precision nota <motores>`: puntos de probabilidad de ganar
  que se pierden por decisión, con IC95.

| Motor (20 partidas, ~150 decisiones) | Pierde por decisión | IC95 |
|---|---|---|
| aleatorio | 5,17 | 3,19 a 7,15 |
| nivel 1 | 2,43 | 1,30 a 3,56 |
| nivel 2 | 2,26 | 1,23 a 3,28 |
| nivel 3 | 2,47 | 1,36 a 3,58 |
| heurística | 1,86 | 0,62 a 3,11 |
| IA buena (la de ayer) | 1,54 | 0,59 a 2,49 |

- Ordena bien los extremos, pero con 150 decisiones no separa los niveles 1 a 3
  ni la heurística de la IA buena. Para una nota fina hacen falta unas 1.500
  decisiones por motor (falta correrlo).

**IA buena** (`busqueda_vigilia.py`, `busqueda_ataques.comparar_opciones`)
- Un solo criterio para apartarse de la regla: criba con 4 muestras y
  confirmación con al menos 8 pares nuevos (antes bastaban 4, las mismas con que
  se elegía la candidata). Test: con 8 opciones idénticas se aparta en menos de
  20 de 200 casos.
- Simula también los bloqueos y el descarte por exceso de mano al final del turno.
- Turno completo (`buscar_turno`): en cada jugada de la Vigilia compara la de la
  regla con las mejores alternativas y con pasar. Reemplaza a los 4 planes fijos.
- Valoración nueva (`valor_estado_v2.json`): suma letal a la vista, daño que
  pasa aunque bloqueen con todo, Oros disponibles y tipos de carta en mi mano.
- En el Desafío nivel 5 piensa hasta 5 s por búsqueda y confirma con hasta 24
  pares (`SEGUNDOS_NIVEL5`, `MUESTRAS_NIVEL5`). Rige al reiniciar el worker.

| Medición en la arena (por pares) | Resultado |
|---|---|
| Muestreo nuevo + bloqueos + descartes contra `v1115b`, 100 pares | 51,0% (IC95 46,0–56,0): sin diferencia clara |
| Turno completo contra los 4 planes, 80 pares | 58,8% (IC95 53,0–64,5), +61 Elo |
| Valoración nueva contra la fórmula fija, 80 pares | 55,6% (IC95 51,4–59,9), +39 Elo |
| Las dos juntas, otra semilla, 100 pares | 57,0% (IC95 52,0–62,0), +49 Elo |

- Quedan por defecto el turno completo y la valoración nueva. Versión congelada
  `v1116`. Tiempo: unos 90 s por partida entre dos IA buenas.
- No medido: cuánto aportan los bloqueos y los descartes por separado
  (`vigilia_sin_bloqueos`, `vigilia_sin_descartes`), ni la valoración nueva
  encima del turno completo.

**Banco de posiciones**
- `posiciones cosechar-juez`: errores de la IA buena que el juez confirma dos
  veces con barajadas distintas. Primera cosecha (40 partidas, 293 decisiones):
  8 sospechas, **6 posiciones**. Se cumplen con cualquier jugada que no sea la mala.
- `posiciones disputa`: 6 respuestas tuyas que la simulación contradice salieron
  del banco a `tests/posiciones_en_disputa/en_disputa.md`, para revisarlas
  juntos. Las dudas nuevas en ese caso van directo ahí.
- Puntaje hoy: IA buena 18 de 46 (heurística 8 de 46); 24 posiciones obsoletas
  por los cambios de reglas.
- Las dudas se generan por defecto con partidas de la IA buena y descartan
  posiciones que ya estaban perdidas.

**Proceso**
- `python -m myl_sim.filtro <nuevo> <referencia>`: arena, juez y banco en una corrida.
- Los 19 tests que fallaban quedaron como fallo esperado con su lista en
  `tests/conftest.py`: la suite está en verde (815 pasan) y una falla nueva se
  ve de inmediato. Falta confirmar cada regla con el juez y corregir o borrar.
- `python -m myl_sim.cobertura_cartas`: 229 de 348 cartas con habilidad de los
  mazos válidos tienen un test que las nombra (65,8%). Faltan 119; las más
  jugadas: Ogham, Árbol de Sangre, Manzana Sidhe, Bola de Energía, Cuna de
  Dragones. Lista en `simulator/cache/cobertura_cartas.md`.
- No se pudo: simular las habilidades opcionales, cancelar y responder. Se
  deciden a mitad de la resolución de una carta y el motor no permite retomar
  una copia desde ahí.

### Reportes de las partidas 1bXc y CfHJ

- Sir Erec quedó con fuerza 2 en el catálogo de Firestore (madrugada; el
  arreglo al cargar queda redundante).

**Desafío 1bXc (Sacer Tótem vs Caballero Armas)**
| Reporte | Causa | Arreglo |
|---|---|---|
| Ayu del Veneno no hizo botar ni pidió elegir Tótem | Estaba como «+0 de fuerza al Tótem» y la fuerza solo va a Aliados: nunca tenía objetivo | Acción «elegir» (opcional): eliges el Tótem y el rival bota su coste; la IA elige el más caro |
| Djedefhor no debería poder bloquear a Melisende | El motor ya lo prohibía, pero el desafío te ofrecía todos los defensores a cada atacante | Cada atacante trae solo sus bloqueadores posibles, y se valida la respuesta |
| Ayu se debe poder activar en la Guerra | Su texto no dice fase y quedó solo en la Vigilia | Se activa en cualquier fase (una vez por turno) |
| Saqqara cobra 3 (es 2) | El catálogo tiene coste 3 | `datos.COSTE_CORREGIDO` al cargar (falta corregirlo en el catálogo) |

**Desafío CfHJ (Desafiante Control vs Faerie Control)**
| Reporte | Causa | Arreglo |
|---|---|---|
| ¿Por qué no activa la Morgana? | La heurística solo pagaba un Aliado si valía menos de 4, sin mirar qué se destierra: Dama del Lago (6, ya usada) por Beleth (7) no pasaba | Para remover un Aliado rival, compara contra el valor del mejor objetivo |
| No robé por Bodb Derg | Guardia Gozosa: «pierde su habilidad y es destruido». Correcto | Sin cambio |
| Anand no preguntó robar o barajar (T15) | Las botadas fueron Anillos de Badbury (Tótem) y Capa de Invisibilidad: ni Oro ni Aliado. En T11 y T13 sí preguntó | Sin cambio |

- Tests: `tests/test_reportes_1bxc.py` (7). Suite: 793 pasan, mismas 19 fallas previas.
- Sin cambios en la app (ya usaba la lista de bloqueadores por atacante): no hace falta publicar.
- Worker reiniciado (03:51), sin desafíos en curso.

**Desafío LyCy (Sombra Agro vs Faraón guerrero)**
| Reporte | Causa | Arreglo |
|---|---|---|
| El rival no debería ver lo que miro con Látigo y Bastón | `_dice_mostrar` (ronda 5VXY) hacía pública cualquier carta cuyo texto dijera «mostrar», aunque fuera otra habilidad («muestra un Guerrero de tu Mano») | Solo es público si el texto muestra cartas del Mazo («mostrar las 3 primeras cartas de tu Mazo»). Látigo y Bastón, Marmita Druida y Cuerno de la Bestia vuelven a ser privadas; Estrella de Belén, Tom Thumb, Cáliz Maldito y Castillo de Bran siguen públicas |
- Tests: 9 casos nuevos. Suite: 802 pasan, mismas 19 fallas previas.

**Qué se baraja a la vista** (regla del usuario: «todo lo que se baraje desde el
Cementerio se muestra; la Roseta no, porque barajas algo de tu mano»)
- Desde el Cementerio: se nombra cada carta (ya pasaba; «una carta de cada tipo»
  daba solo la cantidad y ahora nombra las cartas).
- Desde la mano (Piedra Roseta y cualquier «baraja una carta de tu mano»):
  solo lo ve quien baraja; el rival ve «(oculto)». Antes salía el nombre.
- El resto de un «mira» privado que vuelve al Mazo sigue sin nombrarse; lo que
  va al Cementerio sí. Estrella de Belén y Tom Thumb siguen mostrando las 3.
- Tests: 2 nuevos y `test_piedra_roseta` ajustado. Suite: 804 pasan, mismas 19 fallas.

## 2026-11-15

### Auditoría de la IA: arena con Elo, nivel 5 y mazos válidos

**Arena y Elo** (`simulator/myl_sim/arena.py`, `tests/test_arena.py`)
- Motores enfrentados por pares (mismos mazos, semilla e inicial, motores
  intercambiados) y ranking Elo acumulado en `cache/arena/`.
- IA de hoy congelada como `v1115` (ancla = 1500). Cada cambio de IA se mide
  contra la versión congelada anterior.
- Cada partida con búsqueda guarda dónde se aparta de la heurística
  (`arena desviaciones`) y en cuántas decisiones coincide (`arena precision`).

| Motor | Elo | ± |
|---|---|---|
| busqueda_vigilia (IA buena) | 1598 | 39 |
| experto (nivel 5 anterior: heurística + bloqueos) | 1505 | 55 |
| heuristico (nivel 4) | 1500 | 36 |
| nivel 3 | 1365 | 41 |
| nivel 2 | 1236 | 40 |
| nivel 1 | 1034 | 45 |
| aleatorio | 738 | 66 |

**Mediciones** (40 pares por cruce)
| Pregunta | Resultado |
|---|---|
| Nivel 5 anterior contra nivel 4 | 50,0% (IC95 45,0–55,0): no era más fuerte |
| IA buena contra heurística | 65,0% (IC95 57,8–72,2) |
| IA buena con valoración aprendida contra IA buena | 47,5% (40,5–54,5): no sirve, sigue apagada |
| IA buena con doble de muestras contra IA buena | 52,5% (43,3–61,8): sin diferencia, 2,4 veces más lenta |
| Heurística juzgada por la búsqueda | coincide en 93,3% de 5.239 decisiones; lo más débil: qué Oro bajar (89,9%) y plan de Vigilia (91,5%) |

Estas mediciones se hicieron antes del filtro de mazos válidos (sorteaban
entre 43 mazos, algunos fuera de la Ban List).

**Desafío IA**
- El nivel 5 «Experto» ahora juega con la IA buena (`BuscadorVigilia`). En dos
  partidas de prueba con mazos reales pensó 2,6 s como máximo por decisión y la
  grabación reprodujo la partida idéntica. Worker reiniciado (sin desafíos activos).

**Solo mazos válidos** (pedido de Héctor)
- Todos los simuladores exigen 49 cartas y Ban List del formato
  (`datos.problemas_mazo`, `exigir_validos`, `solo_validos`): worker (Simulador
  y Desafío), arena, matriz del meta, optimizador, evaluador, minería y consola.
- En la app los mazos inválidos no aparecen en Simulador, Desafío IA ni
  Laboratorio (`soloMazosValidos` en `estado_mazos.dart`). Falta publicar la app.
- De 65 mazos raciales del caché, 23 quedan fuera.

**Otros**
- `meta.huella_motor` ahora incluye la búsqueda de Vigilia, la de bloqueos y la
  valoración (una matriz con la IA buena podía reutilizar resultados viejos).
- `myl_sim/precision.py`: % de acierto por partida (todas las decisiones de
  ambos lados). Funciona, pero con la heurística como juez es demasiado blando
  (87% a una partida al azar): no está conectado al Desafío hasta calibrarlo.

**Sinergias: la IA entiende las cadenas de su mazo** (`jugadores._valor_cadena`, `myl_sim/sinergias.py`)
- Una carta vale también lo que arrastra gratis al entrar, calculado desde las
  habilidades y lo que hay en el Mazo y el Cementerio (Taliesin → Dama del Lago →
  Escudo Tryamour → Dame Tryamour → Morgana: 4 Oros pagados, 19 en cartas). Una
  entrada que hoy no trae nada resta (Dame Tryamour sin Morgana en el
  Cementerio: se trae a Merlín). Sin reglas por carta.
- En la IA buena, qué carta propia traer o buscar ahora se simula: la regla
  propone 4 candidatas y la simulación decide (`buscar_objetivos_propios`).
- `python -m myl_sim.sinergias <mazo> [--validar]`: cadenas, llaves, eslabones
  topados por la Ban List y sugerencias del catálogo probadas contra el meta.
- `optimizador --catalogo`: prueba todas las cartas legales del catálogo.

| Mazo (heurística, 400–600 partidas por piloto) | v1115 | Ahora | Diferencia (IC95) |
|---|---|---|---|
| Auditore Faire | 24,0% | 38,2% | +14,2 (+9,4 a +19,1) |
| Faerie Control | 30,7% | 42,7% | +12,0 (+8,0 a +16,0) |
| Titán Minotauro | 47,8% | 55,0% | +7,2 (+3,5 a +11,0) |
| Sacer Tótem | 42,2% | 47,0% | +4,8 (+0,8 a +8,7) |
| Druida, Caballero Armas, Dragón, Titanes, Sombra Control | | | sin diferencia clara |

En los 31 mazos a la vez: 50,7% contra v1115 (IC95 49,4–51,9), sin diferencia clara.

**Letales que la IA dejaba pasar** (auditoría de 2.790 partidas: 0 errores de regla)
| Caso | Causa | Arreglo |
|---|---|---|
| Melisende no cerraba (Caballero Armas) | El letal contaba bloqueadores que no podían bloquearla | Bloqueable solo si algún bloqueador libre puede frenarlo |
| Dos Werin no cerraban (Sacer Premier) | El −1 de Toro Apis se restaba a todos los atacantes | Una rebaja por cada Oro que la da |
| Con 1 carta de castillo no atacaba | Miedo al cancelador aunque no atacar perdía igual | Con castillo 1 el letal se ataca siempre |
- Los otros 6 casos eran correctos: el rival tenía Flechas de Lava y Oros. El
  auditor ya no los marca como error grave (`no_ataca_letal_por_riesgo`).

**Faerie Control y Sombra Control**
- Faerie Control: ninguna de 4 sugerencias del catálogo mejoró con confianza
  (la lista ya lleva sus piezas en el máximo de la Ban List).
- Sombra Control (6,2%): 3 Oillipheist por 2 Sonriente + Bocan, 3 Caoranach o
  2 Tumulario + Bocan suben a ~10% (+3,3 a +3,8 pts, IC95 sobre cero). No sacar Irgoll.

**Cómo aprende: banco de posiciones y dudas**
- `posiciones cosechar`: juega heurística contra heurística con mazos válidos,
  busca los errores del perdedor, los reconfirma con 40 muestras y fija solo los
  firmes (≥20 pts). Primera cosecha (400 partidas): **32 posiciones**, 25 de ellas
  «no atacó y debía atacar».
- `posiciones puntaje --jugador X`: nota de exactitud por motor. Heurística 0 de 32
  (el banco son sus errores), **IA buena 24 de 32 (75%)**.
- `myl_sim/dudas.py`: la IA juega sola y deja en cola las posiciones donde duda
  (partida abierta, decisión que importa, simulación que no separa las mejores).
  `dudas ver` muestra la pregunta sin porcentajes; `dudas responder <id> <letra>`
  fija la respuesta de Héctor en el banco y la contrasta con una simulación larga.
  8 dudas en `cache/dudas/pendientes.md`.
- **Dudas en el tablero:** botón «Dudas de la IA» en Desafío IA. Crea un desafío
  `modo: "duda"`; el worker reproduce la partida hasta la decisión, publica la mesa
  con Héctor en el asiento del que dudaba y espera su jugada en el mismo tablero.
  Al responder: compara su jugada con la de la IA (30 muestras), la fija en el
  banco y muestra el resultado con «Siguiente duda». Probado contra Firestore
  (el worker la toma en 2 s). Publicado en mylmazos.web.app.
- **Turno completo** (pedido de Héctor, `myl_sim/turnos.py`): en una duda se juega
  todo lo que queda del turno; el rival responde con la heurística. La IA juega
  ese mismo turno desde la misma posición y orden de mazo, y se comparan las dos
  mesas resultantes simulando 3 turnos con las mismas barajadas. En el banco queda
  el turno entero (`turnoDebe`), no una jugada. Motivo: con una sola jugada, un
  mismo turno en otro orden (Demoledor de Amón antes de activar Akhet) salía como
  desacuerdo. Las 13 respuestas previas quedaron como jugadas sueltas.
- Cada corrección de la búsqueda guarda su certeza (muestras y z): de 228, solo
  62 (27%) son firmes. Las reglas nuevas salen solo de las firmes.

**Mediciones con mazos válidos (versión `v1115b`)**
| Medición | Resultado |
|---|---|
| IA buena contra heurística, 80 pares | 65,6% (IC95 59,4–71,8), +112 Elo |
| Heurística juzgada por la búsqueda | coincide en 94,4% de 5.050 decisiones |
| IA buena, segundos por partida | 77 (antes 50): costo de simular qué carta propia traer, sin medir aún si rinde |

**Pasividad de la heurística** (auditoría + juez + banco apuntan a lo mismo)
- «No atacó con el rival sin bloqueadores» (362 casos): 69% por la regla «en
  peligro, me quedo a bloquear», 23% por «último defensor». El juez (16 muestras)
  dice que atacar era mejor con diferencia firme en ~10% de esos casos.
- Probado y **no adoptado**: quitar la regla de peligro (banco 9/32, arena 50,6%,
  IC95 49,7–51,5) y dejarla solo si bloqueando sobrevivo (banco 1/32, arena 50,0%).
  Ninguna mejora el global; la heurística quedó igual que `v1115b`.
- Conclusión: estas carreras de daño no se resuelven con otra regla; la IA buena
  las ve simulando (19 de 25).

**Correcciones de Héctor (dudas) convertidas en criterio**
Revisadas 18 respuestas: 7 coinciden con la IA, 6 empate, 3 la simulación prefiere
a la IA (ignoradas), 2 la apoyan. Ninguna de las 2 la jugaba la heurística ni la IA buena.
| Duda | Héctor | IA | Criterio nuevo (jugadores.py) |
|---|---|---|---|
| Sombra Control, te atacan | Irgoll bloquea a Pixie (20% vs 4%) | no bloquear | `_dana_al_morir`: bloquea con gusto quien al salir le quita algo al rival (Irgoll, Slaine, Tuthu…) |
| Defensor T7, mesa rival vacía | Guerreras + Conchobar y ataca (75% vs 66%) | Fergus + Guerreras | `_pega_ya`: un Aliado que ataca al entrar y no tiene quién lo bloquee no se guarda por su habilidad |
- La heurística ahora resuelve esas dos posiciones (banco 9 de 50).
- Arena contra v1115b, 600 pares: 49,8% (IC95 49,6–50,1), neutro. Defensor +1,3
  (IC95 −0,5 a +3,1), Druida +0,7 (+0,0 a +1,3). Se adoptan: corrigen jugadas
  validadas sin empeorar nada medible. Suite: mismos 19 fallos previos, 760 pasan.
- Rige en el Desafío al reiniciar el worker.

**Reportes desde la simulación Sombra Agro vs Caballero Plaga (yI09) en adelante**
(sim. yI09, sim. eTOU Desafiante Control vs Desafiante Plaga, duda 1GfZ, desafío 2PE6, duda gYcs)

| Reporte | Causa | Arreglo |
|---|---|---|
| yI09 T3 Desafiar a Arturo se baraja a sí mismo | Un Talismán se elegía a sí mismo desde el Cementerio | Un Talismán no se elige como objetivo de sus propios efectos |
| eTOU T14 Caturix solo baraja Aine | «Oros y/o Aliados Desafiante»: la raza también filtraba a los Oros | `coincide` respeta `filtroSoloAliados` |
| Duda 1GfZ Piedra Roseta con 2 Sacerdotes | Solo se activaba desde la Reserva | Corrección de carta: también pagada (no exige Reserva ni pagarla) |
| Desafío 2PE6 Amkh previene una destrucción | `prevenir` no saltaba el modo `barajar_mazo` | Amkh solo previene barajar o mandar al Mazo |
| eTOU T17 Salmón del Saber a un Bodb Derg que no atacaba | La IA no miraba quién hacía daño | Al atacante que más daño hace al castillo |
| eTOU T8 Magia Amatista destierra Nuada | No buscaba la copia del Aliado en juego | Prefiere el nombre con copia rival en mesa (la destruye y roba) |
| yI09 T9 Oillipheist destierra Sir Dinadan | Valoraba las cartas rivales como si fueran mías | Valor para el rival: roba/busca y defensa pesan (Espada Larga) |
| yI09 T9 Martillo Pesado destruye a Saladino | El objetivo «cualquiera» no se simulaba | La IA buena simula las cartas rivales como objetivo |
| eTOU T17 segunda Tutatis en vez de Martillo | — | La heurística de hoy ya juega Martillo en Caturix (test) |
| yI09 T7 recibe 10 de daño | La suma es correcta (3 + 4 + 3) | Sin cambio |
| eTOU T17 Bodb Derg no roba al morir | La habilidad funciona; la IA no roba si el rival ya tiene letal en mesa | Sin cambio (decisión discutible) |
| Duda gYcs Damarchus en la Guerra | Cleopatra VII le quitó la habilidad | La mesa avisa «SIN HABILIDAD · Cleopatra VII» y une con flechas bloqueador → atacante (falta publicar) |

- Tests: `tests/test_reportes_1116.py` (9). Suite: mismos 19 fallos previos.
- Arena contra v1115b, 600 pares: 50,1% (IC95 49,3–50,9), neutro.
- Elección de carta por simulación (nivel 5): 45,8% y 138 s por partida → apagada en el código.
- Worker sin reiniciar (a pedido): todo esto rige al reiniciar.

**Tablero (pedido de Héctor)**
- Un Aliado sin habilidad se ve en blanco y negro, con el aviso «SIN HABILIDAD · quién se la quitó».
- «YA USADA ESTE TURNO» en las habilidades de una vez por turno (Damarchus).
- Flecha de color de cada bloqueador a su atacante (los que eliges y los ya declarados).
- Cartas más grandes: las líneas de combate y la mano crecen (horizontal +15%, vertical +29%);
  la mano rival (solo dorsos) y el divisor se achican.
- Tests: 20 del tablero (uno nuevo en 4 tamaños de pantalla). Worker reiniciado y app publicada.

**Reportes de desafíos 5VXY, nOC1 y 15cB**
| Reporte | Causa | Arreglo |
|---|---|---|
| 5VXY T17/T26 Mut y la prevención de Ra no se podían cancelar con Desafiar a Arturo | La app no tenía la ventana de cancelar habilidades: solo la IA podía usarla | `HumanoRemoto.cancelar_habilidad` («¿Cancelar la habilidad de Mut? (roba 1)»); la prevención de un Aliado (Ra) también se puede cancelar |
| 5VXY T13 Bola de Fuego contra Apophis no hizo botar 3 | Apophis reaccionaba después de resolver la carta (ya estaba destruido) | Las reacciones a «el oponente juega una carta» van antes de resolverla; Apophis no cuenta Oros |
| 5VXY T4 Estrella de Belén no mostraba las 3 cartas | Solo era pública con la marca `muestra` en los datos | Si el texto dice «mostrar/muestra», las cartas se ven (y el rival las ve) aunque no haya Oro que tomar |
| 5VXY T4 Gaspar y Pixie: dos «activar» iguales | El título no decía qué hacía cada habilidad | «activar Gaspar · baraja 2 Aliado Dragón del Cementerio» (todas las activaciones) |
| 5VXY T18 Vouivre se ofrecía a sí misma | «Baraja un Aliado que controles para…» incluía a la propia carta | El que se paga es otro |
| 15cB Escudo Celestial barajaba 1 | Cantidad fija 1 | Tantas como el daño hecho (si hay menos en el Cementerio, se barajan todas solas) |
| nOC1 Galatine no mandó a Lady Calvaur al fondo | Correcto: solo Aliados de coste 4 o menos (Lady cuesta 7) | Sin cambio |
- Tests: `tests/test_reportes_5vxy.py` (9). Suite: 781 pasan, mismas 19 fallas previas.
- Worker reiniciado (01:20).

**Desafío BwBe (Sombra Agro vs Caballero Armas): Clochafarmore pagada**
- Regla general (`datos._oro_activable_pagado`): un Oro que se activa
  desterrándose, destruyéndose o subiéndose a la mano también se usa pagado,
  salvo que su texto diga «Reserva» o que el costo sea pagarlo a él mismo.
  Pasan a activarse pagados: Clochafarmore, La Llama de Brigit, Arcas del
  Imperio, Antorcha Olímpica, Letanía (y Piedra Roseta). Siguen solo desde la
  Reserva: Joya Amatista, Rito de Atón, Vino de la Eternidad, Linaje Celta,
  Riton, Deidades Egipcias, Milano Negro. Las Aves (se convierten en Aliado) no
  se tocaron.
- Tests: 5 nuevos. Suite: mismas 19 fallas; 15 posiciones del banco quedaron
  obsoletas (las partidas grabadas cambian con las jugadas nuevas). Worker reiniciado.

**Desafío gXXd (Sombra Agro vs Caballero Armas)**
| Reporte | Causa | Arreglo |
|---|---|---|
| Sir Erec sale con fuerza 3 (es 2) | El catálogo tiene fuerza 3 | `datos.FUERZA_CORREGIDA` al cargar (falta corregirlo en el catálogo de la app) |
| ¿Por qué no puedo activar la Llama de Brigit? | Tu Carmix: «los Oros en juego no pueden ser desterrados» (también los tuyos). Correcto | El aviso dice «No se puede desterrar: Carmix (tuyo)…» en vez de «no puedes pagar el coste» |
| En la Guerra, sin nada que hacer, que pase sola | Los avisos de cartas de tu mano abrían la ventana | Fuera de tu Vigilia, si solo puedes pasar, pasa sola |
- Tests: 3 nuevos. Suite sin fallas nuevas. Worker reiniciado.

**Pendiente**
- Responder las dudas de `cache/dudas/pendientes.md`.
- Publicar la app (filtro de mazos y texto del nivel 5).
- IA buena con simulación de cartas propias, en Faerie Control (90 partidas por
  piloto): 31,1% → 40,0% contra v1115 (+8,9 pts, IC95 −1,2 a +19,0: no concluyente).
  Falta medir si la simulación aporta sobre la regla sola (`vigilia_regla`); se cortó.
- IA de hoy congelada como `v1115b`: la próxima medición va contra esa versión.
- Optimizar Sombra Control con el catálogo (detenido en la ronda 1 a pedido).
- 19 tests que ya fallaban (reglas rígidas de Dragón y control): verificar cada
  regla por simulación antes de volver a forzarla.
- Juez de precisión con la búsqueda, calibrado contra los niveles.
- Reglas para la heurística desde las desviaciones (Oros y plan de Vigilia).
- La búsqueda de bloqueos elige el máximo sin margen ni significancia.
- El optimizador solo prueba cartas que ya están en mazos de la raza.

### Programación de cartas y motor

- Se incorporaron habilidades de cartas pendientes en el catálogo y se amplió el
  motor para pagar costes con Oros de la Reserva, resolver descartes como eventos,
  aplicar efectos al final de una fase, limitar la Agrupación y manejar nuevas
  formas de buscar, barajar y botar cartas.
- Se añadieron reglas específicas para Armas: protección del portador, requisitos
  de raza y equipar una Arma adicional. Hay pruebas enfocadas para estos casos.
- Al consultar de nuevo el catálogo, las cartas restantes aparecían marcadas por
  otra ejecución: **883 de 883 revisadas**. Esa marca indica carga de datos; no
  equivale por sí sola a una auditoría completa de exactitud de cada habilidad.
- Verificación de esta tanda: 32 pruebas enfocadas aprobadas. La suite completa
  terminó con 728 aprobadas, 1 omitida y 19 fallidas, concentradas en pruebas
  previas de decisiones de la IA y reportes; esas fallas siguen pendientes de
  análisis.

### Reglas y datos de cartas

| Carta / caso | Problema | Arreglo |
|---|---|---|
| Escudo Celestial | **Error grave:** barajaba cartas «en juego o del Cementerio» (te ofrecía tus propias cartas en mesa) | Solo del Cementerio; si tienes N o menos, se barajan todas sin preguntar |
| Ptah | — | Si el Cementerio tiene 6 o menos, se barajan todas sin preguntar |
| Baal-Zaphon | Quien lo activaba elegía por los dos jugadores | Cada jugador elige las 3 de su Cementerio (3 o menos: automático) |
| Tom Thumb | Lo que tomaba salía «(oculto)» | Su texto dice «muestra»: las 3 cartas son públicas |
| Magia Amatista (reporte) | — | Correcto: sin copia en juego no destruye ni roba |
| Broche de Tara (uX2m) | Pagando tú a mano, el rival no botaba | Pagar a mano también lo dispara |
| Fase Final (z7to) | El robo de Guerrero Escorpión iba antes que Látigo y Bastón (miraba otra carta) | Primero las habilidades; los robos al final |
| Orfeo (g9FE) | Pedía nombrar al jugarlo y otra vez al activarlo | Nombra solo al activarse; ves el mazo rival (una carta por nombre) y eliges la que destierras |
| Orfeo «no me deja activar» (g9FE) | — | Se activa en tu Vigilia o en la Guerra de Talismanes del rival; en Batalla (declarar atacantes) no hay ventana |
| Oros de la IA (g9FE) | — | Correcto: no robó Oros en T2–T6 y gastó los 2 que tenía en Nephre-Ka |
| Idmon / Afrodita al fallar (g9FE) | Solo en el registro, pasaba desapercibido | Aviso rojo sobre la mesa por 5 s («✗ Idmon falla: sale Coliseo…») |
| Nacimiento de Pegaso «no se podía jugar» (lj65) | Correcto: tu Marco Antonio dice «No se pueden jugar Talismanes» | Al tocar una carta bloqueada, la app dice quién lo impide («Marco Antonio (tuyo) lo impide») |

### Auditoría de las reglas de IA de ayer

- **Guardar un bloqueador** (kZYc): la auditoría de uX2m T5 y z7to T8 mostró
  que se aplicaba de más (dejaba a Fergus en casa contra 5 de daño; guardaba un
  Beleth de 3 contra atacantes de 3). Ahora solo si el contraataque es ≥20% del
  castillo y el que se queda es **más fuerte** que el mejor atacante rival.
  uX2m: atacar con los dos cierra en 4,5 turnos vs 5,4; z7to: 28% vs 0%.

### App

- **Imágenes en toda la app (web):** las pantallas de mazos, catálogo, crear
  mazo, ligas, lista de deseos, Ban List e inventario también dejaban cartas en
  negro (el mismo cuelgue de `cached_network_image` en la web). Nuevo
  componente común `MylNetworkImage` (`lib/widgets/network_image.dart`): en el
  teléfono sigue con caché en disco; en la web usa el cargador del navegador,
  con 6 s de plazo, proxy de respaldo y reintentos (1 s, 2 s, 4 s…). Reemplaza
  los 22 usos directos y el de `MylCardImage`.

### IA (verificado con 40 simulaciones)

| Partida | Lección | Antes → después |
|---|---|---|
| P3Cy T6 | Anillos de Badbury baraja la carta del rival, no la propia (la IA habría barajado tu Anand en vez de Tom Thumb) | 70% → 93% |
| P3Cy T1 (IA) | Con el rival sin mesa, en los primeros turnos se juega el motor de robo (Bruja Anís) en vez de guardar Oros para responder | 45% → 82% |
| z7to T8 | Un Talismán de coste 0 que busca una carta (Aton) siempre vale: carta gratis, también en la Guerra del rival | gana en 1 turno vs 3,2 |
| tmi4 T9 | Cuando me atacan (castillo ≤20), un Oro que achica a un atacante (Diente de la Bestia: −2 y sin habilidad) se usa en la Guerra | 25% → 57% |
| lj65 T8 | En peligro (castillo ≤12 y el rival con más Aliados), Perseo vale el removal que trae (por cada copia en mano), por sobre un buff como Constantino | 3% → 33% |

**¿La IA habría salvado mjiR (tu remontada)?** Con tu mazo Héroe jugando
ella el resto (40 partidas por punto): desde T1 gana 68%, T3 82%, T5 80%, T7
75%, T9 (castillo 3 contra 15) 100%. La mesa en T9 ya era ganadora. Ojo: en
estas simulaciones el rival juega con la heurística normal, sin la búsqueda
de bloqueos del nivel Experto.

Sin aplicar (no se confirmó o la diferencia fue chica): uX2m T1 Broche vs
Torc Fiana (30% vs 17%; ese Broche además no funcionaba), z7to T8 IA Cerveza
Verde vs Joya Amatista (25% vs 0%, posición ya perdida).

Sin aplicar: P3Cy T10 (descartar Red de Plata o Bola de Energía: con la
tuya se gana 1,3 turnos antes, pero no hay una regla clara aún).

### Tests

- Sin fallas nuevas por estos cambios. Una falla nueva en
  `test_mesa_tranquila_juega_el_motor_antes_que_el_golpe_que_me_bota` viene de
  la copia guardada del mazo Desafiante Control, que se actualizó al jugar P3Cy
  con el mazo modificado (falla igual con todas las lecciones apagadas).

---

## 2026-11-14

### Reglas del motor (cartas que no funcionaban como dicen)

| Carta / caso | Problema | Arreglo |
|---|---|---|
| Morir de Pie (y todo Talismán de anulación) | Se ofrecía sin 2 Aliados de una misma raza; también a la IA | Se exige la condición al anular, cancelar y responder |
| Bereber, Sir Erec, Dario III, Anand | "¿Usar habilidad?" sin decir cuál; se aplicaba la primera | Eliges por nombre («+1 a esta carta · +2 a otro Guerrero · No usar») |
| Nacimiento de Pegaso | No preguntaba si dejar arriba o mandar al fondo | Te pregunta antes de robar 2 |
| Afrodita | Siempre nombraba Aliado, sin preguntar | Nombras el tipo (Aliado/Arma/Tótem) antes de mirar; la IA nombra el que más tiene |
| Afrodita / Idmon al fallar | No se notaba | «✗ Afrodita falla: sale X, no es Aliado» |
| Sir Bedivere | Ofrecía cualquier carta de la partida | Solo Aliados de la raza del rival, con campo de texto que filtra |
| Mano rival (Bedivere, Destrozar la Mente, Neferhetepes, Cultistas) | No se veía, o quedaba descubierta | Se ve completa solo en ese momento (franja + Confirmar), acierte o no |
| Renpet, Estrella de Belén y otros «mira las primeras» | Te mostraba lo que tomaba la IA | Lo que mira el rival te sale «(oculto)»; lo que se *muestra* (Estrella) es público |
| Olímpicos | No veías la carta que mirabas | La ves en el registro y queda boca arriba sobre tu castillo |
| Ptah | Elegía la IA | Eliges tú las 6 cartas de su Cementerio |
| Prevención (Ptolomeo II, etc.) | No decía qué te iba a afectar | «Helios va a ser afectada por «Subir a la mano» de Jeroglíficos. ¿Prevenirlo?» |
| Milano Negro | No nombraba raza | Nombras la raza antes de convertirlo |
| Escudo Miliciano (desde el Cementerio) | Solo en Declaración de Ataque | También en Declaración de Bloqueo |
| Corona Faraónica y efectos con un solo objetivo | Preguntaba lo obvio | Se toma solo |
| Pago de Oros | Si se elegía un Oro que el motor no aceptaba, la jugada se cortaba sin aviso | Se completa con un Oro válido (resguardo) |
| Amon (reporte) | — | Correcto: se activó en la Vigilia de la IA (T18) |
| Saladino (reporte) | — | Correcto: genera 2 Oros solo, sin activarlo |
| Ptolomeo II / Djoser (reporte) | — | Correcto: Djoser seguía en juego con fuerza 9 |

### App (tablero del Desafío IA)

- **Franja central:** muestra todas las opciones a la vez (cuadrícula legible
  con desplazamiento vertical); si hay opciones fuera de la mesa, también las
  de la mesa (antes tapaba la mesa rival y no se podía elegir a Kobold o Erec).
- **Armas portadas:** se pueden tocar para elegirlas (destruirlas, desterrarlas).
- **Atacar:** solo arrastrando; tocar un Aliado ya no lo manda al ataque.
- **Avisos:** «Tu turno · T#» por 3 s; la jugada de la IA queda 6 s en pantalla
  aunque ya te toque decidir (antes no se veía cuando te anulaba una carta).
- **Oros:** contador en Reserva y Pagado («RESERVA · 8»); los virtuales con su
  uso («+ 4 virtuales (2 libres, 2 solo Aliado Dragón coste 4+)»), para
  Saladino, Herrero, Ogham, Dragones y todas las que generan Oros; al pagar
  (jugada o «Paga N Oros») la franja muestra todos tus Oros para elegir.
- **Registro privado:** el registro distingue lo que solo ve un jugador.

### Análisis de las partidas (aprendizaje)

- **Revisión de la IA:** antes miraba 3 decisiones y solo si perdía (casi
  siempre «no se encontró un error claro»). Ahora revisa 6 decisiones con
  alternativas reales, gane o pierda, y marca también errores chicos (a 2
  turnos), salvo que el resultado final los contradiga.
- **Desempate por rapidez:** si tu jugada y la de la IA ganan las dos, gana la
  que cierra antes la partida («con la tuya en 2,0 turnos y con la de la IA en
  2,5»); si las dos pierden, la que resiste más.
- **Reproducción:** las partidas en que elegías «No usar» (Saladino, Dario,
  Anand, Ptah) no se podían reanalizar («se separó de lo grabado»). Arreglado
  también para las ya grabadas; ZTSY quedó analizada.
- **Narración de simulaciones:** salían marcas `⟪…⟫` del registro privado; ya no.

### IA: lecciones aplicadas (verificadas)

| Partida | Lección | Tu jugada vs la de la IA |
|---|---|---|
| qx6H T3 | Removal sin blanco (Anillos de Badbury) se guarda | 55% vs 47% |
| qx6H T15 | Anand es un motor: Aplastar Fomor en el turno propio | 50% vs 17% |
| kZYc T7 | Buscar la respuesta (Rito de Atón → Neferite) antes que robar | 100% vs 20% |
| FeCs T8 | Furia contra mesa vacía (Teseo), menos si el rival tiene Oros para responder | 78% vs 57% |
| tInn T5 | Djoser con Arma en mano, si el rival es agro | 100% vs 78% |
| FeCs T6 | No jugar Ganimedes sin blanco | 66% vs 20% |
| ezWO T8 (IA) | No bajar la 2.ª País Sin Luz si lleva a descartar | 95% vs 57% |
| kZYc T6 (IA) | Guardar un bloqueador si el rival devuelve más atacantes | 82% vs 38% |
| 4NtK T3 | No sacar un Aliado que premia al salir (Renpet); Eter queda como cuerpo | 55% vs 17% |
| 5R9h T5 (IA) | Carnwennan al bloqueador que muere y premia al salir (Draig Ifanc) | 75% vs 42% |
| ZTSY T9 | Bola de Fuego en mi turno si saca al único bloqueador | 94% vs 79% (a 2 turnos) |
| cuZm T3 | No bajar un Oro de removal sin blanco (Ceangal) ni Aine contra mesa vacía | 92% vs 58% |
| Tu comentario | Killgharrah salva primero lo valioso si hay Escarabeo y no hay Cinturón | — |
| Tu comentario | Bedivere solo apuesta si se conoce un Aliado en la mano rival | — |
| Sim. yI09 T4 | Yvain busca el Arma: Rey Arturo en mano sin Oros no la reemplaza | — |
| Sim. yI09 T7 | Tótem antes que el Aliado al que habilita Furia (Tótem → Gronw Pebyr) | — |

No aplicadas (no se confirmaron con más simulaciones): Lanza de Osiris,
Focea (HIM0), Estrella de Belén (5R9h), Hipnos (4NtK).

**Lote de cierre del día** (200 partidas por cruce, lecciones apagadas → encendidas):

| Cruce | Antes | Ahora |
|---|---|---|
| Héroe vs Sacer Totem | 63,5% | 65,5% |
| Faraón guerrero vs Caballero Armas | 50,0% | 49,5% |
| Caballero Armas vs Olímpico | 67,5% | 63,5% |
| Faraón Djoser vs Sombra Agro | 26,5% | 31,0% |
| Sombra Agro vs Caballero Plaga | 50,0% | 46,0% |
| Faraón Djoser vs Desafiante Control | 58,5% | 56,0% |

Todo dentro del ruido (±7 puntos con 200 partidas). Ojo: Caballero Armas vs
Olímpico bajó ~3,5 puntos en las 3 mediciones del día; revisar con un lote
mayor si se repite. Tests: sin fallas nuevas.

### Ronda de la noche (vg1J, JD4r, w8nI y simulación yI09)

| Caso | Problema | Arreglo |
|---|---|---|
| «Tus jugadas vs. la IA» | Mostraba jugadas iguales (dos copias de Tótem de la Serpiente) y muchas «parejo» | Solo jugadas distintas y con algo que aprender (tuya mejor o la de la IA mejor); las parejas solo se cuentan |
| Caldero de Corff / Gaitas | Los Oros **pagados** no disparaban su efecto de inicio de fase (Gaitas nunca se ofrecía; un Caldero pagado no desterraba) | Los Oros pagados también disparan (salvo los que dicen «si está en tu Reserva») |
| Fuego Pascual | No se podía jugar: el objetivo apuntaba a una zona que el motor no reconocía | Corregido el dato de la carta (Aliado de tu Línea de Defensa) |
| Mut | No se activaba con un Cementerio vacío y la IA elegía qué desterrar | Robas 1 siempre; cada jugador destierra 1 de su Cementerio (eliges la tuya); luego, si tienes más destierro, eliges barajar o robar |
| Castillo en 0 | Dos Oillipheist dejaron al rival sin castillo y la partida siguió | Sin castillo se pierde ya, no solo al robar o botar |
| Fases sin nada que hacer | Había que pasarlas a mano | Pasan solas si no hay nada que jugar, activar ni explicar |
| Gaitas (IA) | La IA la pagaba al azar | La paga primero: vuelve a la Reserva en su Fase Final (pago gratis) |
| Imágenes de cartas | A veces quedaba solo el nombre (y tras el primer arreglo, miniaturas en negro: la precarga compartía la imagen con el tablero) | El servidor manda las URLs de los dos mazos; la app las precarga en la caché del navegador («Cargando cartas 32/45»); en la web cada carta usa el cargador estándar (caché del navegador): si una descarga se cuelga 6 s o falla, prueba la otra dirección y reintenta hasta 5 rondas; mientras carga muestra el nombre, nunca negro |
| Tamaño de las cartas | Se veían chicas | Títulos de zona más chicos y menos margen: las cartas de la mesa crecen ~15% |
| Cartas en el tablero (web) | Poca respuesta visual | Crecen y se elevan al pasar el cursor |
| Narración de simulaciones | Marcas `⟪…⟫` del registro privado | Limpias |
| Reanálisis de partidas viejas | Tras cambios de reglas se separaban | Interruptores para reanalizar con las reglas de cuando se jugó (vg1J y w8nI reanalizadas) |

**IA (verificado con 40 simulaciones):**
- vg1J T5 (IA): Ataque Fulminante no se juega sin dos Aliados rivales del mismo coste/fuerza (17% → Eter 88%).
- Sim. yI09: Yvain busca el Arma; Tótem antes que el Aliado al que habilita Furia.
- Sin aplicar: vg1J T4 Gronw Pebyr en vez de Orcos (93% vs 35%, confirmado pero
  la causa depende de cómo responde el rival; pendiente de entender), vg1J T3
  Panteón (90% vs 62%; la IA sobrevalora Eter contra Crom Dubh), JD4r T11 Ra
  (no se confirmó: 100% vs 97%).

### Primera parte del día (partidas PzofIK y 4n5oe, rediseño del tablero)

**Rediseño de la jugabilidad del Desafío IA**
- Se corrigieron las «alucinaciones» (aparecían arriba habilidades y acciones
  que no ocurrieron): las partidas imaginarias de la búsqueda de la IA ya no
  publican en la mesa.
- Atacar arrastrando un Aliado a la Línea de Ataque y luego tocando a los demás.
- Sin la ventana grande de «¿Terminar turno?»; la mesa dice qué hacer y la
  barra de abajo confirma (ej. la Manzana: tocas la carta a descartar y Confirmar).
- Pago de Oros dentro de la mesa, con los Oros preseleccionados.
- Ver las Armas portadas sobre el Aliado y ampliar cualquier carta (doble clic
  o mantener apretada).
- Imágenes en la web por el CDN de Google (lh3), con respaldo (weserv) y caché.
- La IA juega más pausado (×1,8 en jugadas importantes) y deja ventana para
  anular (ej. Morir de Pie contra Desafiar a Arturo).
- Reportar en vivo (botón 🐞) en el momento exacto, con turno, fase y posición.

**Reglas**
| Carta | Arreglo |
|---|---|
| Las tres Olas | Cancela el ataque rival (declaración de ataque del oponente) |
| Sidhes del Bosque | Elige la carta clave del mazo rival según la posición |
| Rhiannon | Mira 3 una sola vez; tú ves las 3 y eliges el modo |
| Magia Amatista | Destruye una sola copia (elegida) |
| Salmón del Saber | Solo en la Asignación de Daño, no en la Guerra de Talismanes |
| Desafiar a Arturo / Resplandor de Heka | El Talismán jugado en respuesta se puede anular |
| Anand | Eliges robar, barajar o no usar |
| Talismanes (Bola de Energía) | Se juegan soltándolos en cualquier zona |
| Franja de selección | Todas las cartas a la vista (Constantino, Cementerio) |

**IA**
- Reparto de los objetivos de removal según la situación (Desafiante Control).
- Barajar una carta rival en juego cuenta como removal (Anillos de Badbury, 4n5oe T7).
- Aprendizaje de tus jugadas: cada partida compara tus decisiones con las de la
  IA y deja lecciones (con comparación a 2 turnos cuando el final no distingue).
- Lecciones PzofIK (Rhiannon, Ceangal) aplicadas.

**Mediciones**
- Desafiante Control (heurística nueva, 200 partidas por cruce): 22→29,5%
  vs Caballero Armas, 26→42,5% vs Eterno Agro, 26,5→33,5% vs Faraón guerrero,
  23→36% vs Héroe.
- Mazo DC nuevo contra el anterior: 36,1% vs 35,9% (igual).
- Sombra Control con las lecciones de qx6H: sin cambio (7–17% según el rival).

### Infraestructura

- `android/gradle.properties`: Gradle de 8 GB a 4 GB (el build se caía sin
  memoria; ELEGOO SatelLite tenía 13,7 GB tomados).

### Pendiente

- Elegir el orden cuando se activan varias habilidades a la vez (4NtK).
- Más animación en el tablero para seguir el flujo de jugadas (4NtK).
- Desempate por rapidez también en la revisión de la IA (hoy solo en tus jugadas).
- Entender Gronw vs Orcos (vg1J T4) y Panteón vs Eter (vg1J T3) antes de hacerlos regla.
