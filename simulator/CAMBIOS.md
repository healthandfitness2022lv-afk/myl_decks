# Bitácora del simulador

Cada ronda de reportes: qué se corrigió, qué cambió en la carta (si aplica) y
cómo quedó medido. Lo más nuevo arriba.

Cómo se mide:
- **Tests:** `.venv/Scripts/python -m pytest` en `simulator/`.
- **Lote:** 1000 partidas Faraón Djoser vs Sacerdote (semillas 0–999) con los
  mazos del reporte. Se anota cómo terminan: combate, botar o autodaño
  (un jugador se deja sin castillo a sí mismo).

---

## 2026-11-18 · Lote de 38 cartas (Helénica y Espada Sagrada) y reportes del tablero

- 38 cartas programadas y guardadas con `python -m myl_sim.lote_20261117 --aplicar`
  (el módulo guarda la programación y las notas de cada una; sin `--aplicar`
  solo valida contra el vocabulario del editor).
- Motor: disparador `propia_juega`, `coste_disparadora`, `armas_propias`,
  `incluyeFuente` en `aliados_arquetipo`, `distintoNombre` + `oponenteEligeMano`
  en buscar, copia `permanente`, `entra_atacando`, `valorPorCada`
  `carta_afectada` / `destierro_propio`, `encarecer` con `protege`,
  `disparoArquetipo`, filtro en `destruirPropias`, `incluyeEstaCarta` en
  `destruirAliados`, `privado` en mirarTope y `copias_maximas` (Draco Águila).
- Correcciones: el Oro del turno dispara `propia_entra` (interruptor
  `ORO_JUGADO_DISPARA_ENTRADA`), destinos `ataque`/`defensa` sin prefijo,
  arquetipos de 3 letras o menos como palabra completa («Sir»), y la IA ya no
  deja en fuerza 0 a sus propios Aliados.
- Reportes SkkvVn: el motor dice qué Restricción dejó un efecto sin objetivos
  (`quien_prohibe`), y la mano inicial dice quién empieza.
- **Resultado:** 55 tests nuevos (`test_lote_20261117.py`, `test_reportes_1118.py`).
  600 partidas completas con las cartas nuevas (6 mazos de prueba, IA
  heurística): 0 errores, las 38 se jugaron; 4 terminaron por autodaño.
- Sin medir: los ajustes de IA de este lote no pasaron por `myl_sim.filtro`.
- Segundo lote (`lote_20261118.py`, 11 tests): 11 cartas antiguas que no hacían
  nada (acción `grupoElegir` con `opciones`, `fondoMazo`, `subirCementerio`,
  `al_descartar_por_habilidad`, Absalon) reescritas con el vocabulario del
  motor. Motor: un Talismán que una habilidad ya colocó en una zona (Absalon lo
  baraja) no se manda después al Cementerio. IA: entre dos cambios de fuerza
  (Ascenso Draco) elige el que mueve más fuerza.
- Mercenario: `copias_maximas` = 6 para las cartas «Puedes tener más de 3…».

## 2026-11-15 · Ampliación del motor para cartas pendientes

- Nuevas formas de pagar y resolver efectos: desterrar Oro de la Reserva,
  recordar la fuerza del Aliado pagado como coste, robar hasta un límite y
  calcular valores a partir de Tótems propios.
- Los descartes de la mano ahora disparan el evento `al_descartarse` y quedan
  contados durante el turno. Se agregaron condiciones de Cementerio, mesa y
  descarte para las habilidades que dependen de ellas.
- Se incorporaron efectos opcionales al final de una fase y la restricción que
  salta la Agrupación, junto con objetivos para el bloqueador del portador.
- Armas: inmunidad del portador, requisito de raza y una Arma adicional sobre
  un Aliado ya equipado.
- Nuevas acciones de selección y movimiento: `barajarTipos`, `mirarManoAzar`
  y `botarOroAMano`. Las habilidades recién cargadas tienen 32 pruebas enfocadas.
- El catálogo pasó a mostrar 883/883 cartas revisadas mientras se trabajaba en
  esta tanda. Varias fueron marcadas por otra ejecución; queda pendiente auditar
  que cada configuración coincida con el texto y tenga soporte real en el motor.
- Pruebas: 32/32 casos enfocados aprobados. Suite completa: 728 aprobados,
  1 omitido y 19 fallidos en pruebas de IA/reportes, aún por investigar.

## 2026-11-12 · Evaluador de cartas y trabajos de meta desde la app

- **`evaluador.py`:** `python -m myl_sim.evaluador <id_carta>`. Para cada mazo
  de la raza de la carta prueba meterle 1, 2 y 3 copias (lo que permita la Ban
  List) con el optimizador (la carta nueva como único "side"). Una copia entra
  solo si mejora con IC95 > 0. Informe en `cache/meta/evaluaciones/`.
- **`meta matriz --app`:** la matriz con todos los mazos completos de la app
  (todos los jugadores + notables), en vez de los del caché.
- **`trabajos.py` + `worker.py`:** la colección `ml_jobs` acepta los tipos
  `meta_matriz`, `optimizar` y `evaluar_carta` (además de `matriz`). Corren la
  CLI en otro proceso, muestran la última línea de avance en `parcial` y dejan
  un resumen en `resultado` (ranking, cambios aceptados o veredicto) y el
  informe completo en `cache/meta/ml_jobs/`.

## 2026-11-12 · Side deck como banco de pruebas y Ban List real

- `datos.py` lee `sideboardCards` del mazo (campo `Mazo.side`, también en el
  caché) y la Ban List del formato (`ban_list`, `ban_list_libre`,
  `ban_list_full` → `cache/ban_list_<formato>.json`).
- `optimizador --side`: prueba cambiar cartas del mazo por las del side deck
  (todas las combinaciones del mismo tipo, hasta 60), respetando las copias
  máximas de la Ban List. Sin side deck, usa el pool de la raza.

## 2026-11-12 · Matriz del meta v2 y optimizador

- **`meta.py`:** todos contra todos con pesos de frecuencia por meta/Ban List
  (`cache/meta/meta_<nombre>.json`; sin pesos, iguales). Cada cruce se guarda
  por huella de mazos + motor + jugador en `cache/meta/cruces/`: si nada cambió
  no se re-simula y si se piden más partidas solo se juegan las que faltan.
  Semillas por huella y salida alternada. `score_meta` = winrate esperado
  contra el meta con IC95. 25 raciales × 40 partidas: 12.000 partidas en 2 min.
- **`optimizador.py`:** cambios 1 por 1 del mismo tipo desde el pool de la raza
  (copias máximas según los mazos del caché, ≤ 3) → screening pareado →
  successive halving → confirmación con semillas nuevas; solo acepta si el
  IC95 es > 0. Sacerdote: mejor cambio −Takelot +Oseye, +1,5 pts [−0,2, +3,2],
  no aceptado todavía.

## 2026-11-12 · Flechas de Lava, Killgharrah errante y búsqueda más fiable

- **Flechas de Lava (Killgharrah, Artabano):** la IA atacaba con castillo 7 y
  un Aliado de fuerza 6; Flechas cancelaba, botaba 6 y el robo final la dejaba
  sin castillo. Ahora, si el rival puede tenerla (`creencias`) y pagarla, no
  ataca cuando el bote la deja en ≤1. Con letal solo arriesga si la
  probabilidad es baja (< 35 %).
- **Salir de rango:** a rango de Flechas, la Vigilia prioriza barajar al Mazo
  Castillo (Cathach) y castiga robar por gusto (Vínculo del Aullido).
- **Killgharrah:** "Sólo puedes tener un Kilgharrah en juego" funciona como
  Errante: no se ofrece la segunda copia mientras la primera esté en juego.
- **Búsqueda de ataques:** solo se aparta de la heurística con ventaja
  pareada significativa (media > 2 errores estándar) y suma muestras (hasta
  16) cuando las opciones están parejas. El caso de la Kawit (72 % con 4
  muestras, 56 % contra 60 % con 40) era ruido. Desvíos: ~380 → 151 por
  tanda; winrate igual (+2,2 pts, ns).
- **Auditor:** el ataque perdido muestra los porcentajes de la búsqueda;
  perder por el robo obligatorio con el castillo ya agotado en turnos
  anteriores ya no se marca como autodaño (Lady Calvaur).

## 2026-11-12 · Ataques por simulación con mano rival estimada

- `myl_sim/creencias.py`: modelo de la mano oculta del rival. Pondera las
  listas conocidas del meta (`p.meta_listas`) según lo que el rival ya mostró
  (mesa, Cementerio, Destierro, reveladas), descuenta lo visto y da la
  probabilidad de que tenga una carta (hipergeométrica) o muestrea manos
  plausibles. Sin listas del meta usa la lista real (como antes).
- `myl_sim/busqueda_ataques.py`: jugador `busqueda_ataques`. En cada
  declaración de ataque prueba hasta 8 alternativas (la de la heurística, no
  atacar, todos, subconjuntos) y juega 4 continuaciones de 4 turnos con el
  motor real y la mano rival muestreada. Se aparta de la heurística solo con
  +4 pts de ventaja estimada.
- Auditor: un Aliado que muere atacando no cuenta como pérdida si tiene
  habilidad al salir/ser destruido, es errante, o fue un ataque masivo que
  hizo daño. `lote --procesos N` usa varios núcleos (mismo resultado).
- **Resultado** (8 mazos racial, 336 pares por medición, mismas semillas,
  asientos alternados): búsqueda vs heurística **+8,0 pts** de winrate
  (IC95 +3,6 a +12,5); validación con semillas nuevas **+8,0 pts** (IC95
  +4,0 a +12,0). Pasan los 611 tests.

## 2026-11-12 · Auditoría automática y dos errores letales de la IA

- Nuevo `myl_sim/auditoria.py`: corre todos los cruces con un motor
  instrumentado, revisa invariantes de reglas en cada decisión y agrupa
  jugadas sospechosas por patrón, mazo y carta (ver README).
- **No atacar con letal** (`elegir_atacantes`): si la IA se creía "en
  peligro" (o era un mazo lento) dejaba a los Aliados bloqueando aunque el
  ataque ganaba la partida en ese turno. Ahora se calcula el letal entre
  todos los atacantes (el rival bloquea a los más fuertes) antes de esos
  filtros. Se mantiene no atacar ante Flechas de Lava revelada y pagable.
- **Bloquear el ataque que mata** (`elegir_bloqueos`): "apurado" cuenta lo
  que el atacante bota al atacar o al dañar y un margen por los Oros libres
  del rival (subidas en la Guerra de Talismanes). El Codex Arturicus cuenta
  también desde los Oros pagados.
- **Resultado:** 25 mazos racial, 300 cruces, 6000 partidas, mismas semillas:
  no ataca con letal **114 → 3** partidas; bloqueos perdidos 815 → 808 (no
  bloquea de más); posible autodaño 390 → 324; 0 bugs de regla. 1 test
  nuevo de la IA y 8 del auditor; pasan los 608.

## 2026-11-10 · Programación de Faraón guerrero, Dragón y Titán Minotauro

- Las 67 cartas sin programar de los tres mazos quedaron programadas (12 + 33 + 22).
- Funciones nuevas del motor y del editor (con test):
  - Condición **Aliados del arquetipo declarados atacantes** (Guerrero Escorpión).
  - **Botar** entrega las cartas botadas a los "luego", filtrables por tipo (Ramsés IX: Oro o Aliado).
  - **Elige una opción** (`grupoElegir`) en habilidades y en "luego" (Luz de Prometeo, Cuerno de la Bestia, Bereber).
  - Objetivo **declarado atacante o bloqueador** (Toque de Pérsival).
  - Oros generados con **coste mínimo** (Dragones) y disparador con coste mínimo (Monte Killgharrah).
  - Mirar las de arriba y **barajar el resto** (Estrella de Belén).
  - **Carta vetada** mientras la carta esté en juego (Titán Gorila).
  - Restricción **bloqueo obligatorio** (Laberinto de Creta).
  - Prevenir con efectos "luego" (Soteira) y coste "según los Aliados de un arquetipo" (Minotauro Colosal).
- La IA no juega ni ataca con cartas que botan también su castillo (Kamose, Guerrero Medjay, Ramsés IX) si la dejan al borde de perder.
- Hechizo de Niebla solo cancela el ataque de un Aliado oponente; cancelar un bloqueo con ese Talismán aún no se simula.
- **Resultado:** 17 tests nuevos; pasan 406 de 407. `test_akhet_saca_al_portador_con_su_arma` falla
  por la elección de objetivo de la IA y no depende de esto. Autodaño 7 → 1 de 1200 partidas entre los tres mazos.

## 2026-11-10 · Partida iQeBPG4J25pk9PMelFel (Sacerdote vs Héroe, 11 reportes)

- **Constantino** reprogramado: +2 a tus Aliados solo si **todos** son Héroe
  (antes, en manos del Sacerdote, seguía dando +2).
- **La Odisea**: a la mano lo que más vale conservar; una remoción (Focea)
  suma según los Aliados del mazo rival (Haquika).
- **Perseo** (y toda remoción que sacrifica a su Aliado): solo contra algo
  que valga más que él.
- **Sacar al ladrón** (Haquika) vale también lo que me devuelve; **destruir lo
  mío robado** queda al final (Ganimedes ya no mata a Constantino).
- **Indestructible débil** (Haquika 2) no ataca contra un bloqueador que no
  muere: se queda defendiendo. Ramsés (bota al ser bloqueado) sí ataca.
- **Robar al jugarse** (Nacimiento de Pegaso) cuenta en el puntaje de los
  Talismanes, más con la mano corta.
- **Figuras Negras/Adiós a Oros**: no a Escarabeo (Cementerio); sí a Amkh
  (prevención) si tengo una remoción lista, y antes de usarla.
- **Focea**: con la mano corta (≤ 3) se destruye en la Guerra para robar 2.
- En la repetición: Odisea guarda la Focea, Focea saca a Haquika y vuelve
  Perseo, el Demoledor ataca y quita la habilidad a Constantino; gana Héroe.
- **Resultado:** 6 tests nuevos; pasan los 363. 600 partidas por cruce, 0
  autodaño: Druida vs Héroe **75 % → 58 %** para el Druida (el Héroe usa mejor
  sus cartas); Sacerdote 76 % vs Héroe; Faraón 51 % vs Sacerdote.

## 2026-11-10 · Tanda B + lote 3: Druida y Héroe completos

Funciones nuevas (simulador + editor + tests):
- **Mirar las de arriba y repartir** (acción nueva): mira N del Mazo, toma
  las que cumplan el filtro (a la mano o jugarlas sin pagar) y el resto va
  arriba, al fondo, al Cementerio o "elige arriba o abajo"; o reparte una a
  cada zona en orden (La Odisea). Filtro nuevo: **raza/arquetipo solo para
  Aliados** ("un Oro o un Aliado Druida").
- **Cambiar raza** (Alejandro Magno: el robado "se considera Héroe").
- **Convertir en Aliado** (Ave de Hera: el Oro es un Aliado 3/3 hasta la
  Fase Final y luego vuelve a la Reserva).
- Editor: "Agrupar" acepta "solo esta carta" (Gaitas) y "Elegir" tiene sus
  preguntas.

- Lote 3: Tadg, La Odisea, Nacimiento de Pegaso, Idmon, Alejandro Magno, Ave
  de Hera. Tu nota en Alejandro quedó resuelta.
- **Resultado:** **Druida 33/33 y Héroe 29/29 programadas.** 6 tests de motor
  y 1 de Flutter nuevos; pasan los 357. En 300 partidas: Idmon se activó 525
  veces (jugó un Héroe en 275), Alejandro robó en 287 de 314 entradas.
  Lote Druida vs Héroe (1000): Druida 754 · Héroe 246.

## 2026-11-10 · Tanda A de funciones nuevas + lote 2 (Druida / Héroe)

Funciones nuevas (simulador + editor de la app + tests):
- **Arquetipo** en objetivo y condiciones ("Aliado Druida": va en el nombre).
- **Excepto esta carta y sus copias** ("tus demás Aliados", "que no sea Amergin").
- Selección **"la de mayor fuerza"** (Fergus).
- Comparación **"coste ≤ tus Aliados de una raza"** (Ganimedes).
- Condiciones: **todos tus Aliados de una raza**, **2+ de una misma raza**,
  **menos Aliados que el oponente**, **cartas de un arquetipo en la mano**.
- **Por cada Aliado de un arquetipo** (Druida Maldito).
- Costos: **barajar esta carta**, **mover a la Línea de Ataque**, **pagar el
  coste del objetivo** (Ceangal).
- **Límite compartido** entre habilidades (Cathbadh: +1 o −1).
- Acción **Elegir (referencia)** (Amergin: bota tanto como la fuerza del Druida).
- "Luego": **si no se cumplió** y **si la afectada es de raza/arquetipo**.
- Duración **"durante tu próximo turno"** (Berserk).
- Restricción **"no se puede declarar ataque"** (Pwyll); restricciones de
  desterrar limitadas a un tipo (Carmix: solo Oros).
- Disparador **"cuando declaras tu ataque"** + **"por cada atacante"** (Coliseo).
- **Nombrar al activar**, cada vez (Orfeo). **Agrupar solo este Oro** (Gaitas).
- Continuas que otorgan propiedades a otras cartas (Julio César: imbloqueables).
- **Berserk duplica la fuerza total** con todas las bonificaciones (también
  las continuas): Tadg + Carro Celta + 2 Clochafarmore + 2 Berserk = 48.

- Lote 2: 25 cartas programadas. Trono Dorado: tu nota ("se baraja") quedó
  resuelta con el costo nuevo.
- **Resultado:** Druida 32/33 y Héroe 24/29. Faltan Tadg, Alejandro Magno, Ave
  de Hera, Idmon, La Odisea y Nacimiento de Pegaso (mirar y repartir, cambiar
  raza, Oro que se vuelve Aliado). 17 tests nuevos de motor + 1 de Flutter;
  pasan los 351. Lote Druida vs Héroe (1000) sin errores: Druida 779 ·
  Héroe 221 (Amergin bota cada turno tanto como la fuerza de un Druida).

## 2026-11-10 · Lote 1 de Druida y Héroe (programadas por el agente)

- 29 cartas programadas con el vocabulario actual. Druida: Druida de Man,
  Red de Plata, Bola de Energía, Anillos de Badbury, Ulster, Salmón del
  Saber, Ogham, Clochafarmore, Manzana Sidhe, Joya Amatista, Piel de Lobo,
  Conla, Magia Amatista, Sidhes del Bosque, Figol el Druida. Héroe:
  Leonidas, Rey Minos, Teseo de Atenas, Aceite de Oliva, Figuras Negras,
  Titanes, Focea, Espartaco, Caja de Pandora, Epicuro de Samos, Hilo de
  Ariadna, Héroes, Atenas, Doce Pruebas.
- Verificado en el motor una por una: Ulster (+2 a Defensores), Leonidas
  (roba en la Fase Final), Figol (bloquea y cancela todo el ataque), Piel de
  Lobo (roba y descarta al entrar un Defensor).
- Regla #13 (no sacrificar Oros) ajustada: si el Oro se sacrifica para jugar
  desde el Cementerio, quitar habilidades, dar una propiedad, modificar
  fuerza o anular, lo decide el efecto. Para poner un Oro en juego, solo si
  trae un Oro con habilidad. Antes Clochafarmore y Joya Amatista nunca se
  usaban.
- "Druida" no es raza: es un **arquetipo** (parte del nombre, como Goblin,
  Minotauro, Guerrero). Averix pasa a la lista de funciones faltantes.
- **Resultado:** Druida 15/33 y Héroe 16/29 programadas. Lote Druida vs Héroe
  (1000): sin errores; Druida 532 · Héroe 468. Pasan los 333 tests.

## 2026-11-10 · Flujo definitivo: leer en la app, programar desde el chat

- En **cartas por completar**: "Leer habilidades con IA (N)" lee el texto de
  todas las que no lo tienen; cada carta muestra su texto en la lista.
- Cada carta con texto tiene **"Programar"**: la deja en la cola del agente
  (`cards/{id}.solicitudAgente.estado = "pendiente"`). Se avanza una por una,
  cuando el dueño quiere; nada es automático.
- El agente (Claude, desde el chat) lista la cola con
  `python -m myl_sim.cola_agente`, programa cada carta y crea lo que falte en
  el editor o el motor; `cola_agente.aplicar()` guarda respaldo, la marca
  programada y cierra la solicitud. Programar no gasta API de OpenAI.
- Se quitó la revisión con propuestas de OpenAI (pantalla aparte).
- **Resultado:** 1 test nuevo; pasan los 330.

## 2026-11-10 · Cartas con "." como texto (Constantino)

- 79 cartas tienen solo "." en el campo oficial `habilidad` (Constantino,
  Biblioteca Eterna, Jeroglíficos, Grandes Faraones…). Se tomaba como "ya
  tiene texto": no se leía la imagen y la IA programaba sobre ".".
- Ahora un texto con menos de 8 letras cuenta como vacío (worker, simulador
  y pantalla de revisión). El texto leído por la IA tiene prioridad sobre el
  oficial. Si el texto cambia, la propuesta vieja se descarta y se pide otra.
- Las propuestas se normalizan: listas de un elemento en campos de un solo
  valor (`raza: ["Héroe"]` → `"Héroe"`).
- Constantino (Helénica): el recorte también sirve en esa edición. Primera
  función faltante anotada: condición "si todos tus Aliados son de raza X".
- **Resultado:** 2 tests nuevos; pasan los 329.

## 2026-11-10 · Leer y programar con IA desde "cartas por completar"

- Ya no es una opción aparte: al elegir los dos mazos, en **cartas por
  completar** aparece **"Leer y programar con IA (N)"**.
- Lee el texto de todas (recorte del cuadro, ~470 tokens por carta) y abre
  una revisión **carta por carta**. La propuesta de cada carta se pide recién
  al llegar a ella (~5.200 tokens de entrada + ~300 de salida: vocabulario
  compacto del editor de ~3.200 tokens en vez del archivo completo).
- Por carta: **Aceptar**, **Aceptar y editar** (abre el editor; la marcas tú),
  **responder las dudas de la IA** (vuelve a programar con tus respuestas) o
  **Saltar**. Lo anterior queda en `habilidadesAntesIA`.
- Lo que el editor/motor no soporta queda en `propuestaIA.funcionesFaltantes`
  y en `cards/{id}.funcionesFaltantesIA` para que el agente lo implemente.
- Prueba real: Cleopatra VII salió con "no se puede nombrar Faraón".
- **Resultado:** pasan los 326 tests.

## 2026-11-10 · Leer habilidades con IA (OpenAI, al menor costo)

- Nueva pantalla: Simulador → **Leer habilidades con IA**. Eliges cartas y
  se crea `card_ai_jobs/{id}`; el worker la procesa.
- Por carta (`myl_sim/ia_cartas.py`): se recorta **solo el cuadro de
  habilidad** (franja 72–96 % del alto, ≤ 768 px, JPEG: ~53 KB en vez de
  1,2 MB) y OpenAI (gpt-5.5 por defecto: gpt-5.4-mini leyó mal Ramsés II 2 de 3 veces; gpt-5.5 acertó 3 de 3, ~470 tokens por carta) **solo transcribe** el texto.
  Si la carta ya tiene texto (`habilidad` o `habilidadTextoIA`), no se llama
  a la API.
- El texto queda en `habilidadTextoIA` (aparte de las notas; el simulador lo
  usa como texto de la carta). No se toca la programación: la habilidad se
  programa después desde el chat.
- Probado el recorte con Cleopatra VII, Papiros de Lahun, Ramsés II (6
  líneas) y Flechas de Lava: el cuadro sale completo y legible.
- **Resultado:** 4 tests nuevos; pasan los 321. Falta: clave de OpenAI,
  deploy de reglas y app, reinicio del worker.

## 2026-11-10 · Botar alimenta a Neferite

- Antes de botar (Jinetes de Fuego, Mercado Egipcio…), la máquina calcula si
  el rival tiene una remoción pagada con su Cementerio según el coste del
  objetivo (Neferite I) y qué Aliado mío pasaría a quedar a su alcance
  (Haquika, Demoledor). Si pierde más de lo que gana, no bota, salvo que el
  botar gane la partida.
- Test de T20 corregido: Ay es Guardián (no ataca). El alcance del rival ya
  solo contaba Aliados que pueden atacar.
- **Resultado:** 1 test nuevo; pasan los 317. Lote: destierros de Neferite
  **822 → 805** (efecto chico: su Cementerio suele llenarse solo con combates
  y cartas usadas). Faraón 525 · Sacerdote 475. 0 autodaño.

## 2026-11-10 · Kawit con "puedes" (carta corregida por ti)

- Buscar y "luego robar" de Kawit son opcionales. Jugar Kawit ya no cuenta
  como adelgazar el castillo; al resolver, rechaza buscar/robar si el
  castillo quedaría a tiro de lo que el rival puede quitar (Papiros + fuerza).
- El freno de "robo suicida" ahora cubre también buscar en el propio mazo.
- **Resultado:** 1 test nuevo; pasan los 316. Lote con tus mazos actuales:
  Kawit buscó 871 veces y rechazó 185 (todas con el castillo a tiro, al
  final de la partida). 0 autodaño. Faraón 524 · Sacerdote 476.

## 2026-11-10 · Partida LLQmSkOIAM4wb7v84iVG (súper reporte, 9 puntos)

| Reporte | Causa | Arreglo |
| --- | --- | --- |
| T5 Resplandor a Neferite | Neferite contaba como "motor" aunque no tenía Cementerio para pagar su destierro. | Resplandor solo contra un motor que pueda pagar. Anularla con Gran Guardián sí vale (Escarabeo la destierra después). |
| T5 Ay destierra a Neferite | Sin habilidad (Resplandor), Neferite parecía un Aliado común. | Las piezas del candado se reconocen por la carta impresa y nunca pagan costos (Ay). |
| T8 Jinetes en vez de Escarabeo al Escudo | Para Escarabeo, una carta del Cementerio rival valía la mitad de su coste. | Lo que el rival juega desde el Cementerio (Escudo Miliciano, Qer-Her) y sus piezas clave valen mucho más como objetivo. |
| T12 Demoledor obliga a Djoser con Lanza de Osiris | **Motor:** no excluía a quien no puede bloquear. | Corregido. |
| T11 Jentakus busca Ptolomeo III | Ptolomeo II solo sumaba si el rival me superaba en mesa. | Bono de candado al buscar (como al jugar). |
| T15 Werin bloquea a Cleopatra | Los atacantes se revisaban solo por fuerza. | Primero se bloquea al que gana algo al hacer daño (Escudo Celestial). La narración ahora dice "bloquea a X con Y". |
| T16 Resplandor a Quemar los Templos | **Motor:** la respuesta no miraba el tipo; un Talismán nunca está en juego. | Corregido (también en la decisión de anular). |
| T20 Cierre (2 reportes) | La máquina no hacía la cuenta de castillos. | No adelgazar el castillo (Kawit) si queda a tiro de Papiros + fuerza rival. Riton Aqueménida al fondo (+1) cuando el castillo peligra. Candado del Tocador: Papiros para dejar al rival donde botarme lo mata. El remate rival no se suicida contra mi Tocador. |

- **Resultado:** 9 tests nuevos; pasan los 315. Lote (1000): Riton al fondo
  341 veces, Tocador devolviendo lo botado 105, Gran Guardián a Neferite 43
  y Escarabeo desterrándola después 27. Ay pagando con Neferite 0.
  Resplandor a un Talismán 0. 0 autodaño. Faraón 516 · Sacerdote 484.

## 2026-11-10 · Exceso de mano

- Confirmado: al final del turno, las cartas sobre 8 van al **Cementerio**
  (anotado en REGLAS.md). Ahora la narración dice cuáles: "descarta por
  exceso de mano: …".
- Un Oro solo se descarta con **más de 3 Oros en la mano** (antes: con 3, o
  con 5 en juego). Un Oro con habilidad útil igual vale más que un Escudo Miliciano.
- **Resultado:** 1 test nuevo; pasan los 306. En 1000 partidas hubo 760
  descartes por exceso. Solo en 6 se fue un Oro teniendo 3 o menos (todo lo
  demás valía menos). En una muestra anterior de 300 partidas, en cambio,
  los Oros sumaban ~48 de 251 descartes. 0 autodaño.

## 2026-11-10 · Partida zDGKX582b8mRYGZXQ2pF

- **Reporte:** mulligan con 1 Oro + Amyrteos + Ay.
- **Arreglo:** un acelerador pagable en el turno 1 con el Oro inicial cuenta
  como un Oro más (Kawit busca uno; Amyrteos con Ay en mano pone uno al
  desterrarse y además Ay roba 2).
- **Resultado:** 1 test nuevo; pasan los 305. Lote: mulligans del Faraón
  **255 → 206** y del Sacerdote **409 → 268**. Victorias: Faraón 498 → 483 ·
  Sacerdote 502 → 517. 0 autodaño.

## 2026-11-10 · Partida aomi9eavAWzvvK312kcH

| Reporte | Causa | Arreglo |
| --- | --- | --- |
| T5 Bennu en vez de Werin | El puntaje base es coste × 2: Bennu (3) le ganaba a Werin (2) aunque no había Aliado en el Cementerio para traer. | Bennu sin Aliado válido en el Cementerio resta su coste; con Haquika en el Cementerio vuelve a convenir. |
| T6 Amyrteos pone Papiros de Lahun | Al poner un Oro solo contaba lo que bota. | Perdiendo la mesa (el rival tiene más fuerza), primero un Oro defensivo: Jeroglíficos, Toro Apis. En la repetición pone Toro Apis. |
| T7 Neferite no desterró a Ay | Resplandor de Heka le quitó la habilidad a Neferite al entrar (en el motor, para siempre). | Sin cambio: confirmado que con Resplandor encima no puede desterrar ese turno. |
| T10 Corona en vez de Biblioteca | Solo prefería la Biblioteca con 3 cartas o menos en mano. Además contaba el Relámpago Arcano como gasto del turno. | Las cartas de respuesta no cuentan como gasto. Con 6+ Oros y de sobra, baja la Biblioteca y la cambia por 2 cartas. También se sacrifica para buscar un Arma si los Aliados no tienen y quedan en el mazo, salvo que ya haya una jugable desde el Cementerio (Escudo Miliciano). |

- Autodaño reapareció (3 de 2000): el atajo de "jugada letal" usaba Grandes
  Faraones con 1 y 1 cartas. Ahora mira el castillo propio.
- **Resultado:** 4 tests nuevos; pasan los 303. Lotes: 0 autodaño.
  Mazos del desafío: Sacerdote 730 · Faraón 270. Mazos de esta partida:
  Faraón 498 · Sacerdote 502. Biblioteca sacrificada 944 → 973 veces en 1000 partidas.

## 2026-11-10 · Combo Adiós Belleza + remoción contra Werin

- Quitarle la habilidad a un Aliado rival sirve si tengo a mano con qué
  sacarlo: su Inmunidad bloqueaba la remoción (Neferite, Nephre-Ka), o al
  salir del juego hace algo (Werin busca Talismán; también con Akhet).
- Adiós Belleza se juega **antes** que la remoción que habilita.
- La habilidad Errante (solo una copia en juego) ya no justifica gastar Adiós Belleza.
- **Resultado:** 2 tests nuevos; pasan los 298. En el lote, Adiós Belleza a
  Werin **23 → 40** veces y a Rito de Aton **51 → 0** (solo tenía Errante + una
  activación). 0 autodaño (Sacerdote 735 · Faraón 265; corregido: antes decía al revés).

## 2026-11-10 · Desafío 92LI2l565sS3IYM95QYT (tú contra la IA)

| Reporte | Causa | Arreglo |
| --- | --- | --- |
| T7 Adiós Belleza innecesario | Se daba por útil por la Inmunidad de Werin, y el objetivo se elegía con otro criterio (terminó en Neferite). | La Inmunidad no cuenta. El objetivo sale de la misma lista que decide jugarla. |
| T7 Ramsés descarta Papiros de Lahun | Con 5 Oros en juego, todo Oro en mano valía 0 para descartar, aunque tuviera habilidad. | Un Oro con habilidad (Papiros bota 3) conserva su valor; se descarta el Escudo Miliciano. |
| T13 No pagó el Nudo de Isis ni usó Adiós Belleza en Jeroglíficos | El Nudo estaba cargado como "la usa tu oponente". Además, la regla #99 descartaba siempre los Oros que se activan fuera de combate. | Nueva opción "Cualquier jugador" en *¿Quién puede usarla?*. Pagar mi propio Nudo cuando me impide barajar (Escudo Celestial). Adiós Belleza a Jeroglíficos en la Vigilia si voy a atacar. |

- **Carta que debes corregir:** Nudo De Isis → *¿Quién puede usarla?* →
  **Cualquier jugador** (requiere la app actualizada).
- **Resultado:** 4 tests nuevos; pasan los 295. Lote: 0 autodaño
  (Sacerdote 733 · Faraón 267; corregido: antes decía al revés).

## 2026-11-10 · Partida 3fvzLbFvoQ2bGIC4qSCe

- **Reporte:** el Faraón se suicidó robando con Biblioteca Eterna (4 cartas en el castillo).
- **Arreglo:** no se roba de lo propio si el castillo queda en ≤ 2 o al
  alcance del ataque rival. Grandes Faraones y el remate ya no botan el castillo propio. Nudo de Isis no paga "botar 3" si eso deja el castillo en 0.
- **Resultado:** autodaño en el lote **10 → 0** de 1000. 3 tests nuevos; pasan los 291.

## 2026-11-10 · Partida hvRcpW8SuKs0zarNsjcP

- Kawit busca Piedra Roseta (robo repetible) antes que Rito de Aton.
- Nuh le pone el Arma al Aliado que ataca ese turno.
- Resplandor de Heka responde a Aliados con motor activado gratis (Nuh).
- Con la mesa vacía y el castillo sano, se juega un Aliado aunque haya Flechas/Resplandor que reservar.
- Flechas de Lava cancela antes de los efectos de Declaración de Ataque (el Mandoble no bota).
- **Resultado:** 5 tests nuevos; pasan los 288. Lote sin errores.

## 2026-11-09 · Partida tFD3S15MFMIy6RUvr16z

- Cleopatra VII: se puede nombrar una raza que no está en la partida. La máquina descuenta sus propios Aliados al elegir.
- Nacer de la Muerte no trae a Cleopatra si no tiene raza útil que nombrar (trae Ramsés II).
- **Carta que debes corregir:** Cleopatra VII → *No se pueden nombrar* → **Faraón**.
- **Resultado:** 3 tests nuevos; pasan los 276. Lote sin errores.

## 2026-11-13 · Auditoría de cartas y Oros + búsqueda de qué Oro bajar
- `datos._corregir`: correcciones de texto vs habilidades al cargar (sin tocar Firestore). Rito de Aton, Toro Apis, Qadesh, Amkh, Soteira, Grandes Faraones, Corona Faraónica, Quemar los Templos, Djedefhor, Resplandor de Heka, Herrero, Milano Negro, Joya Amatista, Busto Imperial, Nacer de la Muerte. Programadas aquí (sin habilidades en Firestore): Wep Renpet, Antorcha Olímpica, Mochuelo, Glas Gaibhenenn, Águila Imperial, Vino de la Eternidad. Apagar: `CORRECCIONES_ACTIVAS = False`.
- Motor: Carmix impide pagar costos de desterrar Oros; Amkh (prevenir barajar/mandar al Mazo); Soteira solo en combate; Herrero se destruye al perder la habilidad; Águila Imperial solo desde la Reserva; Milano Negro toma la raza de tus Aliados.
- IA: Tebas no se baja si frena más mis ataques (`_VETO_ATAQUE_SIMETRICO`). "Oro de entrada inútil" (`_ORO_ETB_INUTIL`) neutro, apagado.
- IA buena: `BuscadorVigilia._elegir_oro` (`buscar_oro=True`): simula cada Oro distinto de la mano. 1.056 partidas pareadas, 12 razas: +2,7 ±2,2 pts.
- Tests: tests/test_auditoria_cartas.py (17).

## 2026-11-13 — Dragón: uso de Oros (jugadores.py)
- `_USAR_GENERADOS`: tras activar Dragones, los 2 Oros generados se usan en el Dragón más caro que pagan (antes bajaba un Draco Cometa y se perdían).
- `_CODEX_MINIMO`: el Codex no se gasta en 1-2 de daño.
- `_VINCULO_FRENA`: el Vínculo no se paga si impide bajar el Aliado de coste 3+ de ese turno (mano de 4+).
- Medido (IA buena, 3 Dragones × 11 rivales × 5, pareado): 70,3% → 78,2% (+7,9 ±6,2).

## 2026-11-13 (tarde) — IA buena: activar Oros por simulación (busqueda_vigilia.py)
- `buscar_activar_oro` (encendido): en la Vigilia, simula activar cada habilidad de mis Oros (máx. 3) frente a la jugada elegida. Genérico, todas las razas.
- Medido en 12 razas × 11 × 4 × 2 tandas (1.056 pareadas): +2,4 ±2,1.
- `horizonte_oro` (None = 4): 8 turnos fue neutro (+0,8). jugadores.py: `_VINCULO_MANO_MIN` (4).
- Reglas Dragón en 12 razas: +0,4 ±2,3 (neutras, encendidas).

## 2026-11-14 — Gestión de mano (jugadores.py), apagada
- `_GESTION_MANO` (False) + `Heuristico._guardar_para_la_mano`: en mi Vigilia no bajo un Aliado/Tótem/Arma que me deje con menos de `_MANO_MIN` cartas si tengo ≥ `_MANO_MESA_MIN` Aliados y no menos que el rival, no estoy en peligro, el rival no está por caer y la jugada no es excelente (`_MANO_UMBRAL`) ni roba.
- IA rápida, 4 mazos de Héctor × 11 rivales, pareado (2.640 por variante): conservar 2 → +0,2 ±0,3; 3 → +0,2 ±0,5; 3 con mesa ≥1 → +0,2 ±0,6; 2 con mesa ≥1 → +0,2 ±0,4; 4 → +0,0 ±0,7.
- IA buena (busqueda_vigilia), conservar 3, 88 pareadas: −2,3 ±4,5. Neutra: queda apagada.
- La IA casi nunca queda con ≤1 carta (Druida 6% de los turnos, Desafiante 3,6%, Dragón 1%, Sacerdote 0,6%).
