# Reglas que usa el simulador (v1)

Resumen del **D.A.R. v1.0, Mitos y Leyendas Formato Primer Bloque (julio 2021)** (`tmp/pdfs/dar_primer_bloque.txt`), traducido a lo que el motor va a ejecutar. Cada regla indica la sección del D.A.R. de donde sale.

Marcas:
- ✅ sale del D.A.R.
- 👤 el D.A.R. no lo dice; lo confirmaste tú.
- ✂️ simplificación de la v1, que se completa más adelante.

---

## 1. Mazo y preparación

- ✅ **Mazo Castillo:** 50 cartas, incluido el Oro inicial (4.3.1). En myl_decks son 49 en el mazo más el Oro inicial.
- ✅ **Copias:** máximo 3 por nombre, salvo las Cartas Únicas, que van de a 1 (glosario 8).
- ✅ **Oro inicial:** cada jugador parte con un Oro **sin habilidad** en su Reserva de Oro (4.2.5, 4.3.2).
- 👤 **Mano inicial:** 8 cartas (confirmado por ti).
- 👤 **Mulligan:** se baraja la mano en el Mazo Castillo y se roba una carta menos: 8, luego 7, luego 6, y así. Se puede repetir.
  - Criterio del jugador heurístico: se queda con la mano si tiene **al menos 2 Oros** y **al menos una carta jugable en el turno 1**. Si no, hace mulligan. Un acelerador pagable en el turno 1 (Kawit, o Amyrteos con Ay) cuenta como un Oro.
- 👤 **Exceso de mano:** al final del turno, tras robar, si hay más de 8 cartas en la mano, las que sobran van al **Cementerio** (confirmado por ti). La narración dice cuáles.
- 👤 **Primer turno:** sin restricciones; el que empieza juega un turno normal.
- 👤 **Quién empieza:** cada jugador tira un dado (d6), se repite si empatan, y empieza quien gana. En el simulador se tira en cada partida y queda registrado para las estadísticas.

## 2. Zonas (4.3)

| Zona | Uso en el motor |
| --- | --- |
| Mazo Castillo | Robo desde arriba. El daño Bota cartas desde arriba al Cementerio. |
| Mano | Máximo 8 al final del turno. |
| Reserva de Oro | Oros disponibles para pagar. |
| Zona de Oro Pagado | Oros ya usados; vuelven en la Agrupación. |
| Línea de Defensa | Aliados que pueden bloquear. |
| Línea de Ataque | Aliados atacando; no pueden bloquear. |
| Línea de Apoyo | Tótems (y Armas que lo permitan). |
| Cementerio | Destruidas, descartadas, botadas y talismanes resueltos. |
| Zona de Destierro | Cartas desterradas. |

## 3. Tipos de carta (4.2)

- ✅ **Aliado:** tiene Fuerza y entra en la Línea de Defensa. Para atacar debe haber estado en juego desde el comienzo de la **última Fase de Agrupación** de su controlador, salvo que tenga "puede atacar el turno que entra".
- ✅ **Arma:** se carga en un Aliado que cumpla los requisitos. Por regla general, máximo una por Aliado. Si el portador sale del juego, el Arma va a la misma zona. Sin portador válido, el Arma no se puede jugar.
- ✅ **Talismán:** se resuelve y va al Cementerio. Si no tiene objetivos válidos, no se puede jugar.
- ✅ **Tótem:** entra en la Línea de Apoyo.
- ✅ **Oro:** solo uno por turno, al inicio de la Vigilia. Los Oros no tienen coste. Los **Oros virtuales** (habilidades que "generan") duran solo ese turno.

## 4. El turno (sección 5)

1. **Agrupación (5.1):**
   - ✅ Los Aliados de la Línea de Ataque vuelven a la Defensa y los Oros pagados vuelven a la Reserva.
   - ✂️ El reglamento permite no agrupar. El simulador **siempre agrupa**.
2. **Vigilia (5.2):**
   - ✅ Primero se puede jugar el Oro del turno: si no se juega ahí, no se puede jugar después.
   - ✅ Luego se juegan Aliados, Armas, Tótems y Talismanes, y se usan habilidades, en el orden que elija el jugador activo.
3. **Batalla Mitológica (5.3, opcional):**
   - **Declaración de Ataque:** ✅ se eligen los atacantes y pasan a la Línea de Ataque.
   - **Declaración de Bloqueo:** ✅ el defensor asigna un bloqueador por atacante, si quiere. Solo bloquean Aliados que estén en la Línea de Defensa. Los Imbloqueables no se pueden bloquear.
   - **Guerra de Talismanes:**
     - ✅ Empieza el defensor y se alternan de a una acción (Talismanes o habilidades) hasta que ambos pasan seguido.
     - ✂️ En la v1, cada jugador pasa o juega una acción por vez, sin "ceder prioridad" explícitamente.
   - **Asignación de Daño (5.3.4):** ✅
     - **Atacante con más Fuerza que su bloqueador:** la diferencia es daño al Castillo y el bloqueador muere.
     - **Empate de Fuerza:** no hay daño y mueren ambos.
     - **Bloqueador con más Fuerza:** no hay daño y muere el atacante.
     - **Atacante sin bloqueo:** toda su Fuerza es daño.
     - **Daño:** por cada punto, el defensor Bota la primera carta de su Mazo Castillo al Cementerio.
     - **Indestructible:** no muere en combate.
     - **Bloqueador que sale del juego antes del daño:** el atacante hace todo su daño.
4. **Fase Final (5.4):**
   - ✅ Terminan los efectos "hasta la Fase Final", primero los del jugador activo y luego los del inactivo.
   - ✅ Se disparan los efectos "en la Fase Final".
5. **Fin del turno (5.5):**
   - ✅ El jugador activo **roba 1 carta**. Si tiene más de 8, descarta hasta quedar con 8.
   - ✅ El robo es al **final** del turno, no al inicio.

## 5. Jugar una carta (4.5.3)

✅ El orden es:
1. Se declara la carta.
2. Se cumplen sus requisitos.
3. Se paga el Coste (los Oros pasan a la Zona de Oro Pagado).
4. Se disparan sus habilidades "al jugar".
5. El oponente puede responder con **una** acción (anular, etc.).
6. Si no es anulada, entra en juego o se resuelve.
7. Sus efectos se cumplen "en la medida de lo posible".

✂️ **Ventanas de respuesta, v1:** solo se implementan las **anulaciones** (un jugador anula la carta que el otro acaba de jugar). La redirección, la prevención y las cadenas de "en respuesta" vienen en la v2.

## 6. Habilidades (4.6)

- ✅ **Tipos:** Continuas, Disparadas y Activadas, con prioridad en ese orden (4.6.6).
- ✅ **Duración:** hasta la Fase Final, hasta la Vigilia, permanente o por el resto del juego (4.6.10).
- ✅ **Una sola copia en juego** (4.13): si se controlan 2, una se va al Cementerio.
- ✅ **Regla de Oro** (4.14): el texto de la carta manda sobre el reglamento. En el simulador eso significa que la habilidad programada de la carta puede saltarse cualquier regla de arriba.

## 7. Fin del juego

- ✅ **Derrota:** un jugador que debe robar o botar sin cartas en su Mazo Castillo pierde (4.3.1).
- ✅ **Empate:** si ambos quedan sin cartas a la vez por un mismo efecto, es empate (ejemplo 27).
- 👤 **Las partidas siempre terminan** (confirmado por ti); no existe empate por tiempo.
  - Como protección, el motor corta a los 200 turnos. Esa partida **no se cuenta** en el winrate: se reporta aparte como "partida anómala" para revisar, porque indica un error del motor o de una carta programada.

## 8. Verbos del glosario que el motor ejecuta (sección 6)

| Verbo | Qué hace en el motor |
| --- | --- |
| Robar | Del tope del Mazo Castillo a la Mano, de a una. |
| Botar | Del tope del Mazo Castillo al Cementerio. Es daño directo. |
| Descartar | De la Mano al Cementerio. |
| Destruir | De una zona en juego al Cementerio. Sale del juego. |
| Desterrar | A la Zona de Destierro. |
| Subir | De una zona en juego a la Mano. |
| Barajar | Mezclar el Mazo Castillo. Es obligatorio tras buscar en él. |
| Buscar | En el Mazo, el Cementerio o el Destierro. Puede fallar a propósito. |
| Anular | La carta jugada va directo al Cementerio sin efecto. |
| Generar | Oros virtuales que duran solo este turno. |
| Modificar fuerza | Aumentar, disminuir, duplicar o establecer, con un mínimo de 0. |
| Imbloqueable / Indestructible / Indesterrable | Propiedades que el motor respeta. |
| Mirar / Mostrar / Considerar / Mover | v2. |
| Cancelar / Redirigir / Prevenir | v2. |
