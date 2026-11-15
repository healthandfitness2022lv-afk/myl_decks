---
name: revisar-notas-simulador
description: Revisa las notas que el dueño dejó en las cartas de MyL sobre lo que el simulador de partidas aún no sabe hacer, y mejora el editor de habilidades y el motor Python para cubrirlas. Úsalo cuando el usuario pida revisar las notas del simulador, las cartas pendientes, o mejorar el simulador a partir de sus notas.
---

# Revisar notas del simulador

El dueño (hecturnicolas@gmail.com) programa a mano las habilidades de cada carta en myl_decks. Cuando el editor no le alcanza para expresar una carta, deja una nota. Este skill convierte esas notas en mejoras.

## Piezas del sistema

- **Formato de habilidad (el contrato):** `lib/models/card_habilidad.dart`. La app guarda `cards/{id}.habilidades[]` (cada una puede traer efectos encadenados en `luego[]`), más `habilidadesRevisadas` y `notasSimulador`. Hay **una sola nota por carta** (`notasSimulador`); las habilidades no tienen notas propias. El motor Python lee exactamente esos mapas.
- **Editor:** `lib/screens/habilidades/habilidad_editor.dart`, `luego_editor.dart` (efectos "Luego…", con referencia a las cartas afectadas o a sus copias), `card_habilidades_section.dart` y `glosario_screen.dart`.
- **Motor:**
  - `simulator/myl_sim/habilidades.py`: un ejecutor por cada `accion`, además de filtros, condiciones y costos.
  - `simulator/myl_sim/motor.py`: turno, combate y zonas.
- **Reglas:** `simulator/REGLAS.md`, resumen validado del D.A.R. El texto completo está en `tmp/pdfs/dar_primer_bloque.txt`.
- **Tests:** `test/card_habilidad_test.dart` (Dart) y `simulator/tests/` (pytest).

## Pasos

1. **Exportar lo pendiente.** Desde `myl_decks/`, corre `node tools/exportar_notas_simulador.js`. Esto escribe `simulator/cache/notas_simulador.json` con dos tipos de caso:
   - cartas con `notasSimulador`;
   - habilidades o efectos `luego` con `accion: "otra"`.

   Si no hay pendientes, dilo y termina.

2. **Agrupar las notas por tipo de carencia**, no carta por carta. Por ejemplo:
   - una condición nueva (como "si el oponente tiene más Aliados");
   - un disparador nuevo;
   - un parámetro nuevo de objetivo;
   - una acción nueva del motor;
   - una regla del D.A.R. que falta en `REGLAS.md`.

   Para cada grupo, lista las cartas afectadas con su texto.

3. **Proponer antes de cambiar.** Muestra al usuario los grupos y la mejora propuesta para cada uno: qué campo u opción nueva va en el formato, cómo se ve en el editor y qué hace el motor. Si una nota es ambigua o contradice el D.A.R., pregunta. El usuario conoce el juego mejor que el reglamento resumido.

4. **Implementar cada mejora aprobada en las tres capas a la vez:**
   - **Formato y editor:** el modelo Dart (`fromMap`, `toMap`, `copyWith` y `resumen`) y el editor. Los valores nuevos deben tener id estable y etiqueta en español.
   - **Motor:** soporte en `habilidades.py` o `motor.py`. Un valor desconocido nunca debe romper una partida: si llega algo que el motor no entiende, se ignora y se cuenta como "sin motor".
   - **Tests:** un test Dart de ida y vuelta para el campo nuevo, y un test pytest con un escenario fijo que pruebe el efecto. Si tomaste una carta de las notas, úsala como ejemplo en el test.

5. **Verificar:**
   - `flutter analyze` sin errores nuevos y `flutter test`;
   - en `simulator/`, `.venv/Scripts/python -m pytest`.

6. **No editar las cartas en Firestore.** Las habilidades de cada carta las ajusta el dueño en la app, ya con las opciones nuevas, y él borra la nota cuando la carta queda bien. Al terminar, entrégale la lista de cartas que ya puede reprogramar y con qué opción nueva.

## Reportes de partidas narradas

Además de las notas de las cartas, el dueño reporta errores mientras mira una partida narrada en el tablero (botón **Reportar**). Cada reporte queda en `simulations/{id}.reportes[]` con el paso, el tipo, la carta (opcional) y qué debió pasar. Si el usuario pide revisar los reportes, o si hay reportes al revisar las notas:

1. Desde `myl_decks/`, corre `node tools/exportar_reportes_simulador.js`. Esto escribe `simulator/cache/reportes_simulador.json`, con cada reporte, las jugadas previas, la mesa en ese paso, la semilla y las habilidades programadas de la carta.
2. **Reproducir:** `narrar(mazo_a, mazo_b, seed=..., jugador=...)` es determinista. Carga los mazos igual que el worker (`myl_sim.worker`) y revisa `partida.pasos[paso]`.
3. **Clasificar según la causa:**
   - **Habilidad mal ejecutada.** Si la carta está mal programada (campo equivocado en el editor), dile al dueño cómo cargarla bien. No la edites. Si el motor no respeta lo que la carta dice, arréglalo en `habilidades.py` o `motor.py`.
   - **Regla mal aplicada:** compárala con `REGLAS.md` y el D.A.R., y arregla `motor.py`.
   - **Jugada mejorable:** ajusta la heurística en `simulator/myl_sim/jugadores.py` de forma general, nunca para una carta puntual, salvo que la carta lo exija.
4. En cada caso, agrega un test pytest con el escenario reportado.
5. Reinicia el worker y dile al dueño que use **"Repetir esta partida (misma semilla)"** para comprobarlo. Él marca el reporte como resuelto en la app. Si cambia la heurística o el motor, la partida puede tomar otro camino desde ese punto; eso es esperado.

## Reglas

- **Compatibilidad:** los campos nuevos son opcionales y tienen valor por defecto, así las habilidades ya guardadas siguen funcionando.
- **Prioridad:** si una carta contradice el reglamento, manda la carta (Regla de Oro, D.A.R. 4.14). Va en su habilidad, no como regla general del motor.
- **Reglas compartidas:** si un cambio necesita reglas de Firestore, edita `firestore.rules` en myl_decks **y** en app_marketplace. Los dos archivos deben quedar idénticos porque despliegan al mismo proyecto.
