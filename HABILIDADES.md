# 📖 Guía de Habilidades de Cartas — MYL Engine

> **Documento vivo.** Se actualiza cada vez que se agregan nuevas opciones al sistema.
> Última actualización: 2026-03-21

---

## Cómo funciona el editor

Cada carta puede tener **una o más habilidades** configuradas desde la pantalla de detalle de carta (ícono 💡 en el AppBar, solo visible para admins).

Cada habilidad tiene estos bloques:

```
CUÁNDO → QUÉ HACE → A QUIÉN / FILTRO → COSTO → FASE → OPCIONAL
```

---

## 1. CUÁNDO SE ACTIVA (Trigger)

| Opción en editor | Cuándo dispara |
|---|---|
| Al entrar en juego | En el momento que la carta se juega desde la mano |
| Al jugar desde la mano | Idéntico al anterior (alias) |
| Al atacar | Cuando el jugador declara el ataque con esta carta |
| Al ser destruido | Cuando la carta muere en combate o por efecto |
| Al inicio del turno | Cada vez que empieza el turno del dueño |
| **Habilidad activada** | El jugador la activa manualmente tocando la carta |
| Cuando el oponente juega un aliado | Reactivo — el oponente juega un aliado |
| Cuando el oponente juega un talismán | Reactivo — el oponente juega un talismán |
| Cuando el oponente juega cualquier carta | Reactivo — cualquier carta del oponente |
| Cuando el oponente ataca | Reactivo — el oponente declara ataque |

> **Reactivos** disparan automáticamente y pueden tener costo (el jugador elige pagar o no).

---

## 2. QUÉ HACE (Tipo de efecto)

| Opción | Descripción |
|---|---|
| Robar cartas | Robas N cartas de tu mazo |
| Daño directo al castillo | Descarta N cartas del castillo del oponente (mill) |
| Destruir aliado (elige) | El jugador elige un aliado del pool de objetivos y lo destruye (cementerio) |
| Destruir todos con criterio | Destruye todos los aliados del pool que pasen el filtro |
| Subir propio poder | Aumenta el poder de esta carta en +N |
| Subir poder de todos mis aliados | Aumenta el poder de todos tus aliados en +N |
| Devolver aliado a la mano | El jugador elige un aliado y lo regresa a la mano |
| **Anular carta** | Solo para triggers reactivos. La carta del oponente no entra en juego, va directo al cementerio |
| **Buscar carta y ponerla en juego/mano** | Busca en mazo/cementerio/destierro una carta por tipo y la mueve a la zona elegida |
| **Desterrar aliado objetivo** | El jugador elige un aliado del pool y lo destierra (va a zona de destierro, NO al cementerio) |
| **Silenciar carta y copias** | El jugador elige una carta en juego. Esa carta Y todas sus copias pierden sus habilidades hasta la fase final del turno actual |

---

## 3. A QUIÉN AFECTA (Pool de objetivos)

Solo aplica para efectos que necesitan objetivo: `Destruir`, `Desterrar`, `Devolver`.

| Opción | Descripción |
|---|---|
| Cualquier aliado enemigo | Todos los aliados del oponente (defensa + ataque + soporte) |
| Aliados en defensa enemiga | Solo los que están en la línea de defensa |
| Aliados en ataque enemigo | Solo los atacantes declarados |
| Mis propios aliados | Tus propios aliados (para effectos de sacrificio) |
| Cualquier aliado en juego | Tuyo o del oponente |

---

## 4. FILTRO (Filtrar por)

Restringe qué cartas son **válidas como objetivo**. Si una carta no pasa el filtro, no aparece como opción.

| Stat | Operadores | Fuente del valor |
|---|---|---|
| Sin filtro | — | — |
| Coste | ≤ < = > ≥ | Valor fijo / Mis aliados en juego / Aliados enemigos / Mis oros |
| Poder | ≤ < = > ≥ | Valor fijo / Mis aliados en juego / Aliados enemigos / Mis oros |

**Ejemplo:** "destruir aliado de coste ≤ mis aliados en juego"
→ Filtrar por: `Coste` / Operador: `≤` / Fuente: `Cantidad de mis aliados en juego`

---

## 5. LIMITACIÓN (Condición para activar)

> ⚠️ **Diferencia clave con el Filtro:**
> - **Filtro** → restringe QUÉ cartas son objetivos válidos
> - **Limitación** → restringe SI el efecto se puede activar (basado en el estado del juego)

| Stat | Cuándo bloquea la activación |
|---|---|
| Sin condición | Siempre se puede activar |
| Coste (de la carta trigger) | Solo reactivos. Ej: "solo si el aliado tiene coste ≤ 3" |
| Poder (de la carta trigger) | Solo reactivos. Ej: "solo si el aliado tiene poder > 2" |

> ⚠️ **Actualmente la limitación está en el config pero NO evaluada por el engine.** Está pendiente de implementar.

---

## 6. COSTO DE ACTIVACIÓN

Lo que el jugador paga para que el efecto se resuelva.

| Opción | Descripción |
|---|---|
| Ninguno (gratuito) | No cuesta nada |
| Destruir esta carta | Esta carta va al cementerio |
| **Desterrar esta carta** | Esta carta va al destierro (no al cementerio) |
| Destruir uno de tus talismanes | El jugador elige qué talismán sacrificar |
| Destruir uno de tus aliados | El jugador elige qué aliado sacrificar |
| Pagar oros | Se pagan N oros de tu reserva |
| Descartar una carta de la mano | El jugador elige qué carta descartar |
| **Desterrar cartas del tope de tu mazo** | Se destierran automáticamente las N primeras del tope |

> Los costos con asterisco (**negrita**) son los más complejos. `exileSelf` es único: la carta que paga el costo NO va al cementerio.

---

## 7. FASE DE ACTIVACIÓN

Solo relevante para `Habilidad activada`.

| Opción | Cuándo puede usarse |
|---|---|
| Cualquier momento | Sin restricción |
| Solo en mi fase de vigilia | Solo durante tu vigilia |
| En cualquier momento de mi turno | Cualquier fase de tu turno |
| En respuesta (turno del oponente) | Solo durante el turno del oponente |

---

## 8. OPCIONAL

Si está activado ✅, el efecto **no se dispara automáticamente**. En cambio:
- La carta entra en juego normalmente
- Parpadea en **naranja** con el badge `¡ACTIVAR!`
- El jugador la toca y decide si activarla o no
- Al final del turno, si no se activó, se pierde la oportunidad

---

## 9. BÚSQUEDA (solo para "Buscar carta")

| Campo | Opciones |
|---|---|
| Buscar desde | Mi mazo / Mi cementerio / Mi destierro / Mazo oponente / Cementerio oponente / Destierro oponente |
| Tipo a buscar | Cualquier carta / Oro / Aliado / Talismán / Tótem |
| Poner en | Reserva (en juego) / Mano / Campo de batalla |
| Cuántas | N (número) |

---

## 📋 Configuraciones de ejemplo

### "Cuando entra en juego, robas 1 carta"
| Campo | Valor |
|---|---|
| Cuándo | Al entrar en juego |
| Qué hace | Robar cartas |
| Cantidad | 1 |

---

### "Cuando el oponente juega un aliado, puedes anularlo destruyendo un talismán tuyo"
| Campo | Valor |
|---|---|
| Cuándo | Cuando el oponente juega un aliado |
| Qué hace | Anular carta |
| Costo | Destruir uno de tus talismanes |

---

### "Al entrar, puedes desterrar 3 cartas del tope de tu mazo para desterrar un aliado enemigo de coste ≤ 3"
| Campo | Valor |
|---|---|
| Cuándo | Al entrar en juego |
| Opcional | ✅ |
| Qué hace | Desterrar aliado objetivo |
| Objetivos | Cualquier aliado enemigo |
| Filtrar por | Coste ≤ 3 (valor fijo) |
| Costo | Desterrar cartas del tope de tu mazo |
| Cartas a desterrar | 3 |

---

### "Habilidad activada en vigilia: destiérrate para buscar un oro en tu mazo y ponerlo en la reserva"
| Campo | Valor |
|---|---|
| Cuándo | Habilidad activada |
| Fase | Solo en mi fase de vigilia |
| Qué hace | Buscar carta y ponerla en juego/mano |
| Buscar desde | Mi mazo/castillo |
| Tipo a buscar | Oro |
| Poner en | Reserva (en juego) |
| Cuántas | 1 |
| Costo | Desterrar esta carta |

---

### "Al inicio de tu turno, +1 poder a todos tus aliados"
| Campo | Valor |
|---|---|
| Cuándo | Al inicio del turno |
| Qué hace | Subir poder de todos mis aliados |
| Cantidad | 1 |

---

### "Al atacar, hace 2 de daño directo al castillo enemigo"
| Campo | Valor |
|---|---|
| Cuándo | Al atacar |
| Qué hace | Daño directo al castillo |
| Cantidad | 2 |

---

### "Talismán: silencia una carta y todas sus copias hasta la fase final"
| Campo | Valor |
|---|---|
| Cuándo | Al jugar desde la mano |
| Qué hace | Silenciar carta y copias hasta fase final |
| Objetivos | Cualquier aliado en juego |

> Los talismanes se juegan y van directo al cementerio, el efecto se dispara en ese momento. Pueden jugarse en vigilia o en guerra de talismanes.

---

### "Al morir, destruye un aliado enemigo de poder ≥ 3"
| Campo | Valor |
|---|---|
| Cuándo | Al ser destruido |
| Qué hace | Destruir aliado (elige) |
| Objetivos | Cualquier aliado enemigo |
| Filtrar por | Poder ≥ 3 (valor fijo) |

---

---

## ⚔️ Sistema de Armas

Las armas son un tipo especial de carta que se **equipa a un aliado** en vez de entrar al campo directamente.

### Reglas
- Máximo **1 arma por aliado** por defecto (`maxWeapons = 1`)
- Una vez equipada, **queda fija** — no se puede mover a otro aliado
- El arma **sigue al portador** a donde vaya (cementerio, destierro, mano, mazo)
- Algunos aliados pueden portar más (configurado como habilidad del aliado)

### Tipos de efectos de armas

| Tipo | Trigger en editor | Cuándo dispara |
|---|---|---|
| **Al equiparse** | `Al equiparse (onEquip)` | Una sola vez cuando se equipa |
| **Continuo** | `Continuo (mientras equipada)` | Siempre activo mientras esté en el aliado |
| **Del portador ataca** | `Cuando el portador ataca` | Cada vez que el aliado portador ataca |
| **Del portador hace daño** | `Cuando el portador hace daño` | Cuando el portador derrota bloqueadores o pasa sin bloqueo |

### Efectos exclusivos de armas

| Efecto | Descripción |
|---|---|
| `Dar poder al portador` | +N poder permanente al aliado (continuo) |
| `Portador imbloqueable` | El aliado no puede ser bloqueado (continuo) |
| + todos los demás | draw, mill, destroyTarget, searchAndPlay, etc. |

### A quién se equipa (configurado en el arma)

| Opción | Descripción |
|---|---|
| Un aliado propio | Solo puedes equiparla a tus propios aliados |
| Un aliado enemigo | Solo puedes equiparla a los aliados del oponente |
| Cualquier aliado | Eliges cualquier aliado en juego |

### Ejemplos de configuración

**"El portador gana +2 poder"**
| Campo | Valor |
|---|---|
| Cuándo | Continuo |
| Qué hace | Dar poder al portador |
| Cantidad | 2 |
| A quién equipar | Un aliado propio |

**"Al equiparse, el oponente bota 2 cartas"**
| Campo | Valor |
|---|---|
| Cuándo | Al equiparse |
| Qué hace | Daño directo al castillo |
| Cantidad | 2 |
| A quién equipar | Un aliado propio |

**"Si el portador ataca, el oponente bota 1"**
| Campo | Valor |
|---|---|
| Cuándo | Cuando el portador ataca |
| Qué hace | Daño directo al castillo |
| Cantidad | 1 |
| A quién equipar | Un aliado propio |

**"El portador es imbloqueable"**
| Campo | Valor |
|---|---|
| Cuándo | Continuo |
| Qué hace | Portador imbloqueable |
| A quién equipar | Un aliado propio |

---

## 🚧 Pendiente de implementar

| Feature | Estado |
|---|---|
| Limitación evaluada por el engine | ❌ Pendiente |
| Habilidades continuas (mientras esté en juego) | ❌ Pendiente |
| Trigger: al bloquear | ❌ Pendiente |
| Trigger: al ser bloqueado | ❌ Pendiente |
| Efecto: intercambiar cartas entre zonas | ❌ Pendiente |
| Efecto: copiar efecto de otro aliado | ❌ Pendiente |
| Múltiples efectos encadenados en una habilidad | ❌ Pendiente |
| Costo: sacrificar un aliado específico (por tipo/nombre) | ❌ Pendiente |
| Aliado con maxWeapons > 1 configurable desde el editor | ❌ Pendiente |
| Mostrar armas equipadas al tocar el aliado (detalle) | ❌ Pendiente |
