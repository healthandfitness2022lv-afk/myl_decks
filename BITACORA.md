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

## 2026-11-15

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
