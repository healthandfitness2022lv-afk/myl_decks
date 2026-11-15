# Simulador de partidas MyL (v1)

Enfrenta dos mazos de myl_decks N veces y calcula:
- el winrate, con su intervalo de confianza;
- la ventaja de empezar;
- el impacto de cada carta;
- la duración de las partidas y la causa de cada victoria.

Las reglas que aplica están en [REGLAS.md](REGLAS.md).

## Preparación (una vez)

Desde `myl_decks/simulator/`:

```
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
```

La credencial es `myl_decks/secrets/firebase-admin.json`, que está fuera de git.

## Uso

| Qué | Comando |
| --- | --- |
| Ver tus mazos (con su id) | `.venv/Scripts/python -m myl_sim.cli mazos` |
| Simular N partidas | `.venv/Scripts/python -m myl_sim.cli simular <idA> <idB> -n 1000` |
| Ver una partida narrada | `.venv/Scripts/python -m myl_sim.cli partida <idA> <idB>` |
| Atender la pantalla Simulador de la app | `.venv/Scripts/python -m myl_sim.worker` |
| Tests | `.venv/Scripts/python -m pytest` |
| Generar episodios locales de autojuego | `.venv/Scripts/python -m myl_sim.cli recolectar <idA> <idB> -n 1000` |
| Entrenar primera política con los episodios | `.venv/Scripts/python -m myl_sim.aprendizaje entrenar cache/entrenamiento/djoser_vs_sacerdote_train_v1.jsonl cache/entrenamiento/modelos/djoser_v1.json` |
| Evaluarla contra la heurística | `.venv/Scripts/python -m myl_sim.aprendizaje evaluar cache/entrenamiento/modelos/djoser_v1.json --pares 40 --salida cache/entrenamiento/modelos/djoser_v1_evaluacion.json` |
| Probar jugadas alternativas de Djoser | `.venv/Scripts/python -m myl_sim.exploracion recolectar <idDjoser> <idRival> cache/entrenamiento/djoser_exploracion_v1.jsonl --pares 1000` |
| Aprender preferencias de esas pruebas | `.venv/Scripts/python -m myl_sim.exploracion aprender cache/entrenamiento/djoser_exploracion_v1.jsonl cache/entrenamiento/modelos/djoser_alternativas_v1.json` |
| Comparar con semillas nuevas | `.venv/Scripts/python -m myl_sim.exploracion evaluar cache/entrenamiento/modelos/djoser_alternativas_v1.json --pares 100 --salida cache/entrenamiento/modelos/djoser_alternativas_v1_evaluacion.json` |
| Comprobar otro rival | `.venv/Scripts/python -m myl_sim.exploracion evaluar cache/entrenamiento/modelos/djoser_alternativas_v1.json --rival <idRival> --pares 200 --seed 380001 --salida cache/entrenamiento/modelos/djoser_otro_rival.json` |
| Probar búsqueda de bloqueos | `.venv/Scripts/python -m myl_sim.busqueda_bloqueos <idDjoser> <idRival> --pares 100 --muestras 4 --max-candidatos 8 --sin-limite-tiempo --salida cache/entrenamiento/busqueda_bloqueos.json` |
| Recuperar jugadas de una exploración anterior | `.venv/Scripts/python -m myl_sim.informe_entrenamiento cache/entrenamiento/djoser_sacerdote_actual_v3.jsonl` |
| Auditar errores en lote (todos los cruces) | `.venv/Scripts/python -m myl_sim.auditoria lote <idA> <idB> <idC> -n 100 --cache` (o `--formato racial`) |
| Simular con ataques por búsqueda (más lento, +8 pts) | `.venv/Scripts/python -m myl_sim.cli simular <idA> <idB> -n 200 --jugador busqueda_ataques` |
| Repetir una partida que marcó el auditor | `.venv/Scripts/python -m myl_sim.auditoria repetir <idA> <idB> --seed <s> --inicial <0/1> --cache` |
| Matriz del meta (todos contra todos, ranking ponderado) | `.venv/Scripts/python -m myl_sim.meta matriz ["<meta>"] -n 40` |
| Guardar un meta con pesos por Ban List | `.venv/Scripts/python -m myl_sim.meta crear "BL 2026-11" <id1> <id2> ... --peso <id1>=3` |
| Optimizar un mazo contra el meta | `.venv/Scripts/python -m myl_sim.optimizador <id> [--meta "BL 2026-11"] --rondas 2` |
| Probar las cartas del side deck en el mazo | `.venv/Scripts/python -m myl_sim.optimizador <id> --side` |

| Congelar la IA de hoy como versión | `.venv/Scripts/python -m myl_sim.arena congelar <etiqueta>` |
| Medir un motor contra otro (pares con motores intercambiados) | `.venv/Scripts/python -m myl_sim.arena jugar heuristico heuristico@<etiqueta> --pares 200` |
| Ranking Elo de los motores | `.venv/Scripts/python -m myl_sim.arena ranking` |
| Dónde la búsqueda corrige a la heurística | `.venv/Scripts/python -m myl_sim.arena desviaciones` |

En Windows conviene poner antes `set PYTHONIOENCODING=utf-8` para que los acentos se vean bien en la consola.

## Primeros datos de aprendizaje

`recolectar` guarda en `cache/entrenamiento/episodios.jsonl` una observaciÃ³n
legal por cada jugada de la heurÃ­stica: mesa visible, mano propia, conteos
ocultos del rival, acciones legales, elecciÃ³n y recompensa final. No sube
partidas ni modelos a Firebase. El archivo incluye las huellas de ambas listas:
si cambias cartas o habilidades, se genera otra huella y no se mezclan datos
sin saberlo.

El primer modelo aprende a elegir entre las jugadas legales de Djoser (lado A)
tomadas por la heurística. Separa
partidas completas para validar el acierto y conserva la huella exacta de ambos
mazos. La evaluación enfrenta Djoser con el modelo y con la heurística contra
Sacerdote, en ambos asientos y con semillas nuevas. Ataques, bloqueos y otras
respuestas todavía usan la heurística. Entrenar por imitación no demuestra una
mejora en victorias: el modelo queda local y fuera del Desafío IA hasta superar
una evaluación independiente.
El informe guarda `aptoParaDesafio=false` hasta tener al menos 100 partidas
válidas de evaluación y un límite inferior positivo para la mejora de winrate.

La exploración modifica solo algunas jugadas de Vigilia entre alternativas
legales que la heurística considera útiles. Cada partida se compara con otra
de control con la misma semilla; se alternan los asientos. El resultado enseña
preferencias por carta, que se comprueban con semillas distintas antes de
considerar su uso en el Desafío IA.
`mejoraEnEsteCruce` solo evalúa Djoser contra el rival indicado. El informe
mantiene `aptoParaDesafio=false` como indicador de que aún no hay una política
general para todo el meta. El registro local
`cache/entrenamiento/modelos/djoser_registro_v2.json` permite usar una política
aprendida únicamente en cruces concretos aprobados, si las huellas de ambos
mazos coinciden. Para aprobar un cruce exige dos evaluaciones independientes,
con al menos 400 partidas válidas cada una y ventaja positiva en el límite
inferior de ambas estimaciones. En cualquier otro caso el Desafío IA usa la
heurística.
El informe de otro rival registra su huella y cuántas copias tienen habilidades
sin programar; esos cruces sirven para detectar regresiones, pero no para
afirmar que el modelo entiende todo el meta mientras faltan reglas.

La exploración de alternativas, el entrenamiento de modelos y sus evaluaciones
generan un archivo `*_jugadas.md` con un identificador de ejecución. Si una
evaluación no indica `--salida`, sus archivos se crean en
`cache/entrenamiento/ejecuciones`. El detalle JSON o JSONL conserva la
mesa visible, opciones, semilla y resultado cuando esos datos fueron registrados.
Para atribuir cambios de cartas, el resumen distingue las partidas con una sola
variación de aquellas con varias; ambas pueden divergir después de la jugada.
Los datos anteriores que no guardaron la mesa no permiten reconstruirla con certeza.

La búsqueda experimental de bloqueos copia la partida en la declaración,
prueba asignaciones legales y continúa cada copia hasta terminar con las
heurísticas actuales. Muestrea la mano oculta rival y los órdenes de robo;
conserva las cartas reveladas y asume que se conocen ambas listas de mazo. El
motor aún no conserva memoria completa de cartas conocidas en el tope o fondo,
por lo que las simulaciones no incorporan esa información. El presupuesto de
opciones y muestras limita el tiempo; los porcentajes por decisión son
estimaciones con esa cantidad de simulaciones. Se puede activar por partida con
el interruptor experimental del Desafío IA; al terminar se guardan las opciones
comparadas y sus resultados en la revisión de decisiones.
En las evaluaciones locales se prueban además ocho escenarios independientes
para comparar cada elección distinta de la referencia; `--muestras-validacion`
ajusta ese presupuesto. El Desafío usa las muestras de la búsqueda para mantener
una respuesta ágil y las señala como estimaciones preliminares.

## Arena y Elo de la IA

Las simulaciones ponen la misma IA en los dos asientos: miden mazos. La arena
(`myl_sim/arena.py`) mide la IA. Cada **par** son dos partidas con los mismos
mazos, semilla y jugador inicial, intercambiando los motores, así la suerte y
el mazo se cancelan. Los resultados se acumulan en `cache/arena/partidas.jsonl`
y el ranking (`cache/arena/ranking.md`) es un ajuste Bradley-Terry en escala
Elo con el ancla en 1500.

- Motores: `aleatorio`, `nivel1`–`nivel3`, `heuristico` (nivel 4), `experto`
  (nivel 5 del Desafío), `busqueda_ataques`, `busqueda_completa`,
  `busqueda_vigilia`, `vigilia_valor` (con la valoración aprendida) y
  `vigilia_x2` (doble de muestras).
- `congelar <etiqueta>` copia los archivos de IA a `cache/arena/versiones/`;
  `heuristico@<etiqueta>` juega con esa copia sobre las reglas actuales.
- Un motor sin congelar entra al ranking con la huella de sus archivos
  (`heuristico#3fa2c1`). Al cambiar la IA aparece como motor nuevo.
- Rutina para un cambio de IA: `jugar heuristico heuristico@<última versión>
  --pares 200`. Si el IC95 queda sobre 50 %, el cambio sirve; se congela una
  versión nueva cuando hay una mejora confirmada.
- Los buscadores anotan cada decisión en que se apartan de la heurística
  (`cache/arena/desviaciones.jsonl`). `desviaciones` las agrupa: los patrones
  que más se repiten son reglas candidatas para la heurística.

## Auditoría automática

`auditoria lote` corre todos los cruces entre los mazos indicados con un motor
instrumentado y deja `cache/auditoria/auditoria_<fecha>.md` (informe) y `.json`
(detalle). Busca dos cosas:

- **Bugs de regla** (siempre se arreglan): carta en dos zonas, carta perdida,
  zona o controlador incoherente, Oros virtuales negativos, mano sobre 8 al
  cerrar el turno, jugada no ofrecida como legal, excepción del motor,
  partida sin fin.
- **Jugadas sospechosas**, agrupadas por patrón, mazo y carta y ordenadas por
  gravedad y frecuencia: no atacar con daño letal, no bloquear el ataque que
  mata, posible autodaño, no jugar Oro pudiendo, Oro temporal sin gastar,
  ataque que pierde el Aliado sin ganar nada, bloqueo caro con castillo
  holgado, remoción sobre un objetivo claramente menor, Aliados jugables
  guardados con Oro sobrante, no atacar con la mesa rival vacía.

Cada grupo trae un ejemplo con su comando `repetir`, que narra exactamente esa
partida y marca con `⚠ AUDITOR` el momento del hallazgo. La revisión humana se
reduce a confirmar o descartar el top del informe; lo confirmado se reporta
como siempre y se convierte en test.

## Cómo se usan las cartas

- **Carta marcada como programada:** el simulador usa sus habilidades. Las habilidades se marcan en la app, en el detalle de la carta, sección "Habilidades para el simulador".
- **Carta sin marcar o con notas pendientes:** se juega sin habilidad, solo con su coste y su fuerza, y el informe lo advierte.
- **Notas:** lo que el editor no permite expresar se anota en la carta. El skill `/revisar-notas-simulador` las revisa y mejora el editor y el motor.

## Piezas

- `myl_sim/modelo.py`: estado de la partida.
- `myl_sim/motor.py`: turno, oro, combate, zonas y fin del juego.
- `myl_sim/habilidades.py`: ejecuta cada acción del catálogo.
- `myl_sim/jugadores.py`: los jugadores aleatorio y heurístico. MCTS y la IA entrenada van a usar la misma interfaz.
- `myl_sim/simulacion.py`: corre las N partidas y arma el informe.
- `myl_sim/datos.py`: carga cartas y mazos desde Firestore, con caché en `cache/`.
- `myl_sim/worker.py`: procesa `simulations/{id}` creadas desde la app.
- `myl_sim/auditoria.py`: auditor automático de reglas y jugadas sospechosas.
- `myl_sim/creencias.py`: modelo de la mano oculta del rival.
- `myl_sim/busqueda_ataques.py`: jugador que decide los ataques simulando.
- `myl_sim/meta.py`: matriz del meta v2 (pesos, caché por huellas, score_meta).
- `myl_sim/optimizador.py`: cambios de cartas con screening, successive halving y confirmación.
