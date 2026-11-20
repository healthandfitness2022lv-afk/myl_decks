"""Búsqueda por simulación para la Vigilia (con "pasar" como opción).

Una vez por Vigilia, en la primera decisión después del Oro, compara planes
para el resto de la fase jugando continuaciones con el motor real (misma
técnica que `busqueda_ataques`: mano rival estimada con `creencias`,
muestras pareadas, horizonte corto y valoración del estado):

- ``heuristica``: lo que haría la heurística.
- ``pasar``: no bajar nada más (solo el Oro si todavía no se jugó). Ej.: con
  Apophis rival en mesa, guardar las cartas y esperar la respuesta.
- ``una``: jugar solo lo que la heurística quiere ahora y pasar.
- ``todo``: la heurística, pero si quiere pasar con Oro y cartas pagables,
  baja la mejor que se pueda pagar.

Se desvía de la heurística solo con ventaja clara (margen + diferencia
pareada significativa). Los ataques también se buscan (hereda de
`BuscadorAtaques`).
"""

from __future__ import annotations

import random
import time

from .busqueda_ataques import BuscadorAtaques, _copia, valor_estado
from .jugadores import JUGADORES, Heuristico
from .modelo import Tipo
from .motor import FinPartida, Partida

PLANES = ("heuristica", "pasar", "una", "todo")
_FASES_RESPUESTA = {"cualquiera", "guerra_talismanes", "declaracion_ataque", "declaracion_bloqueo",
                    "asignacion_dano"}


def reserva_respuestas(p, yo) -> int:
    """Oros para la mejor respuesta que tengo en la mano: un Talismán que se
    juega fuera de mi Vigilia (Guerra de Talismanes, cancelar un ataque,
    anular o responder a lo que juega el rival)."""
    costes = []
    for c in p.j(yo).mano:
        if c.tipo != Tipo.TALISMAN:
            continue
        habs = [h for h in c.habilidades if h.get("cuando") in ("al_jugar", None)]
        fases = {h.get("fase", "cualquiera") for h in habs}
        respuesta = any(h.get("cuando") in ("oponente_juega", "habilidad_oponente") for h in c.habilidades)
        if respuesta or fases & _FASES_RESPUESTA:
            costes.append(p.coste_de(yo, c))
    costes = [x for x in costes if x <= p.j(yo).oro_disponible]
    return max(costes, default=0)


def _es_vigilia_propia(p, yo) -> bool:
    return p.e.fase == "vigilia" and p.e.activo == yo


def _jugables(jugadas):
    return [x for x in jugadas if x.tipo in ("jugar", "activar")
            and not (x.tipo == "jugar" and x.carta is not None and x.carta.tipo == Tipo.ORO)]


def _pasar(jugadas):
    return next((x for x in jugadas if x.tipo == "pasar"), None)


def aplicar_plan(jug: Heuristico, p, yo, jugadas, plan: str, estado: dict):
    """Jugada del plan `plan` en esta decisión de mi Vigilia."""
    base = Heuristico.elegir_jugada(jug, p, yo, jugadas)
    if plan == "heuristica":
        return base
    if base.tipo == "oro":
        return base  # el Oro va igual en todos los planes
    pasar = _pasar(jugadas) or base
    if plan == "pasar":
        return pasar
    if plan == "reservar":
        if "reserva" not in estado:
            estado["reserva"] = reserva_respuestas(p, yo)
        reserva = estado["reserva"]
        oro = p.j(yo).oro_disponible

        def deja(x):
            if x.tipo != "jugar" or x.carta is None or x.carta.tipo == Tipo.ORO:
                return True
            return oro - p.coste_de(yo, x.carta) >= reserva

        if base.tipo == "pasar" or deja(base):
            return base
        ok = [x for x in jugadas if x.tipo in ("jugar", "activar") and deja(x)
              and not (x.tipo == "jugar" and x.carta is not None and x.carta.tipo == Tipo.ORO)]
        return max(ok, key=lambda x: jug._puntaje(p, yo, x)) if ok else pasar
    if plan == "una":
        if estado.get("hechas", 0) >= 1:
            return pasar
        if base.tipo != "pasar":
            estado["hechas"] = estado.get("hechas", 0) + 1
        return base
    # "todo": si la heurística pasa, bajar la mejor carta pagable
    if base.tipo != "pasar":
        return base
    cartas = [x for x in jugadas if x.tipo == "jugar" and x.carta is not None and x.carta.tipo != Tipo.ORO]
    if not cartas:
        return base
    return max(cartas, key=lambda x: jug._puntaje(p, yo, x))


def certeza(valores: list[list[float]], elegido: int) -> dict:
    """Qué tan firme es una desviación: muestras y diferencia pareada en
    errores estándar (`z`). Sirve para separar las lecciones del ruido."""
    d = [a - b for a, b in zip(valores[elegido], valores[0])]
    n = len(d)
    media = sum(d) / n if n else 0.0
    ee = (sum((x - media) ** 2 for x in d) / (n - 1) / n) ** 0.5 if n > 1 else 0.0
    return {"muestras": n, "z": round(media / ee, 1) if ee else 99.0}


def situacion(p, yo) -> dict:
    """Resumen legible del estado para explicar una decisión."""
    from . import habilidades as hab
    mio, suyo = p.j(yo), p.j(1 - yo)
    mesa = lambda j: [f"{a.nombre} ({hab.fuerza(p, a)})" for a in j.aliados]  # noqa: E731
    return {"turno": p.e.turno, "fase": p.e.fase, "mi_mazo": mio.nombre_mazo, "rival": suyo.nombre_mazo,
            "castillo": [len(mio.mazo), len(suyo.mazo)], "oros": mio.oro_disponible,
            "mano": [c.nombre for c in mio.mano], "mano_rival": len(suyo.mano),
            "mi_mesa": mesa(mio), "mesa_rival": mesa(suyo)}


def _texto_jugada(j) -> str:
    if j is None:
        return "pasar"
    if j.tipo == "pasar":
        return "pasar"
    if j.tipo == "activar":
        return f"activar {j.carta.nombre}"
    extra = f" en {j.portador.nombre}" if j.portador else ""
    return f"jugar {j.carta.nombre}{extra}"


class _PlanForzado(Heuristico):
    """En las simulaciones: sigue `plan` en la Vigilia del turno `turno`.
    Con `jugada` (clave) y `objetivo` (uid), la primera decisión es esa
    jugada y su primer objetivo elegido es ese."""

    def __init__(self, seed, plan, turno, estado=None, jugada=None, objetivo=None):
        super().__init__(seed)
        self._plan, self._turno, self._estado = plan, turno, dict(estado or {})
        self._jugada, self._objetivo = jugada, objetivo

    def elegir_jugada(self, p, yo, jugadas, *a, **k):
        if self._jugada is not None:
            clave, self._jugada = self._jugada, None
            j = next((x for x in jugadas if _clave_jugada(x) == clave), None)
            if j is not None:
                if self._plan == "una":
                    self._estado["hechas"] = self._estado.get("hechas", 0) + 1
                return j
            self._objetivo = None
        if _es_vigilia_propia(p, yo) and p.e.turno == self._turno:
            return aplicar_plan(self, p, yo, jugadas, self._plan, self._estado)
        return super().elegir_jugada(p, yo, jugadas, *a, **k)

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        if self._objetivo is not None:
            uid, self._objetivo = self._objetivo, None
            t = next((c for c in candidatos if c.uid == uid), None)
            if t is not None:
                resto = [c for c in super().elegir_objetivos(p, yo, candidatos, n, h) if c is not t]
                return [t] + resto[:max(0, n - 1)]
        return super().elegir_objetivos(p, yo, candidatos, n, h)


def _clave_jugada(j):
    return (j.tipo, j.carta.uid if j.carta else None, j.habilidad,
            j.portador.uid if j.portador else None, j.destino)


_TRAE_PROPIAS = ("jugarDesde", "buscar", "ponerEnJuego")
_REMOCION_SIMULABLE = ("destruir", "desterrar", "subirMano", "barajar", "perderHabilidad")


def _objetivos_en_juego(p, yo, j, maximo: int, quien_ordena=None) -> list:
    """Objetivos distintos que puede elegir la habilidad con objetivo de esta
    jugada (al jugar la carta o al activarla). Vacío si no hay decisión (0–1
    candidatos).

    - Rivales en juego: qué destruir, desterrar o anular.
    - Con `quien_ordena` (la heurística), también mis cartas del Mazo o del
      Cementerio: qué trae Taliesin, qué busca Isengrim. La heurística propone
      (su orden pone primero la de mejor cadena) y la simulación decide entre
      las `maximo` primeras de nombre distinto."""
    if j.tipo not in ("jugar", "activar") or j.carta is None:
        return []
    from . import habilidades as hab

    habs = [j.carta.habilidades[j.habilidad]] if j.tipo == "activar" else [
        h for h in j.carta.habilidades if h.get("cuando") in ("al_jugar", None)]
    for h in habs:
        obj = h.get("objetivo") or {}
        if obj.get("seleccion", "elige") != "elige":
            continue
        propias = (quien_ordena is not None and obj.get("quien") == "propio" and h.get("accion") in _TRAE_PROPIAS
                   and set(hab.zonas_de(obj, "")) <= {"mazo", "cementerio"} and int(h.get("cantidad") or 1) == 1)
        # Martillo Pesado "destruye una carta en juego": quien=cualquiera, pero
        # se simulan solo las del rival (sim. yI09 T9: Saladino o Sir Erec).
        remocion_libre = obj.get("quien") == "cualquiera" and h.get("accion") in _REMOCION_SIMULABLE
        if obj.get("quien") != "oponente" and not propias and not remocion_libre:
            continue
        try:
            cands = hab.candidatos_validos(p, yo, j.carta, h)
        except Exception:  # noqa: BLE001 — habilidades raras: sin búsqueda
            continue
        cands = [c for c in cands if c.uid is not None]
        if remocion_libre:
            cands = [c for c in cands if c.controlador != yo]
        if propias:
            try:
                orden = Heuristico.elegir_objetivos(quien_ordena, p, yo, cands, len(cands), h)
            except Exception:  # noqa: BLE001
                continue
            distintas, nombres = [], set()
            for c in orden:
                if c.nombre not in nombres:
                    nombres.add(c.nombre)
                    distintas.append(c)
            if len(distintas) >= 2:
                return distintas[:maximo]
            continue
        if len(cands) >= 2:
            cands.sort(key=lambda c: (-c.carta.coste, -hab.fuerza(p, c)))
            return cands[:maximo]
    return []


def continuar_vigilia(c: Partida, yo: int, plan: str, horizonte: int, seed: int,
                      aprendido: bool = False, estado=None, jugada=None, objetivo=None) -> float:
    a = c.e.activo
    jugadores = list(c.jugadores)
    jugadores[a] = _PlanForzado(seed * 2 + 3 + a, plan, c.e.turno, estado, jugada, objetivo)
    c.jugadores = tuple(jugadores)
    try:
        c._vigilia(a)
        c.e.fase = "batalla"
        c._batalla(a)
        c._finalizar_turno(a)
        c._cerrar_turno(a)
        for _ in range(horizonte):
            if c.e.terminada:
                break
            c.e.turno += 1
            act = c.e.activo
            c.turnos_propios[act] += 1
            c._turno()
            c._cerrar_turno(act)
    except FinPartida:
        pass
    return valor_estado(c, yo, aprendido)


def continuar_guerra(c: Partida, yo: int, clave, horizonte: int, seed: int,
                     aprendido: bool = False) -> float:
    """Desde una decisión mía en la Guerra de Talismanes: juego `clave` (o
    paso), la Guerra sigue con la heurística y después el combate y los
    turnos siguientes."""
    a = c.e.activo
    d = 1 - a
    try:
        j = next((x for x in c.jugadas_legales(yo, "guerra_talismanes") if _clave_jugada(x) == clave), None)
        if j is None or j.tipo == "pasar":
            pases = 1
        else:
            c.ejecutar_jugada(yo, j)
            pases = 0
        turno = 1 - yo
        for _ in range(40):
            if pases >= 2 or c.e.terminada:
                break
            opciones = c.jugadas_legales(turno, "guerra_talismanes")
            elegida = c.decide(turno).elegir_jugada(c, turno, opciones)
            if elegida.tipo == "pasar":
                pases += 1
            else:
                pases = 0
                c.ejecutar_jugada(turno, elegida)
            turno = 1 - turno
        if not c.e.terminada:
            c._tras_guerra(c.atacantes, c.bloqueos, d)
            c._finalizar_turno(a)
            c._cerrar_turno(a)
        for _ in range(horizonte):
            if c.e.terminada:
                break
            c.e.turno += 1
            act = c.e.activo
            c.turnos_propios[act] += 1
            c._turno()
            c._cerrar_turno(act)
    except FinPartida:
        pass
    return valor_estado(c, yo, aprendido)


def continuar_mano(c: Partida, yo: int, quedarse: bool, horizonte: int, seed: int,
                   aprendido: bool = False) -> float:
    """Desde la decisión de mano inicial: me quedo o hago mulligan (y después
    decide la heurística), el rival arma su mano si le falta y se juegan los
    primeros `horizonte` turnos."""
    from .motor import MAX_MULLIGANS
    from .modelo import Zona
    try:
        jug = c.j(yo)
        n = len(jug.mano)
        hechos = c.mulligans[yo]
        if not quedarse:
            for intento in range(hechos, MAX_MULLIGANS):
                for inst in list(jug.mano):
                    c._sacar(inst)
                    inst.zona = Zona.MAZO
                    jug.mazo.append(inst)
                c.e.rng.shuffle(jug.mazo)
                n -= 1
                c.mulligans[yo] += 1
                c.robar(yo, n, inicial=True)
                if intento + 1 == MAX_MULLIGANS or c.decide(yo).quedarse_mano(c, yo):
                    break
        if not c.j(1 - yo).mano:
            c._mano_inicial(1 - yo)
        for _ in range(horizonte):
            if c.e.terminada:
                break
            c.e.turno += 1
            act = c.e.activo
            c.turnos_propios[act] += 1
            c._turno()
            c._cerrar_turno(act)
    except FinPartida:
        pass
    return valor_estado(c, yo, aprendido)


def continuar_descarte(c: Partida, yo: int, uids: tuple, horizonte: int, seed: int,
                       aprendido: bool = False) -> float:
    """Desde el descarte por exceso de mano (lo último de mi turno): descarto
    `uids`, se cierra el turno y siguen `horizonte` turnos con la heurística."""
    a = c.e.activo
    try:
        for inst in [x for x in c.j(yo).mano if x.uid in uids]:
            c.descartar(inst, por_habilidad=False)  # exceso de mano: regla
        c._cerrar_turno(a)
        for _ in range(horizonte):
            if c.e.terminada:
                break
            c.e.turno += 1
            act = c.e.activo
            c.turnos_propios[act] += 1
            c._turno()
            c._cerrar_turno(act)
    except FinPartida:
        pass
    return valor_estado(c, yo, aprendido)


class BuscadorVigilia(BuscadorAtaques):
    """Vigilia y ataques decididos por simulación; lo demás, heurística."""

    nombre = "busqueda_vigilia"

    def __init__(self, seed: int | None = None, **kw):
        # Valoración con rasgos ampliados (valor_estado_v2.json) al cortar las
        # continuaciones: 55,6% (IC95 51,4–59,9) contra la fórmula fija, 80 pares.
        kw.setdefault("aprendido", 2)
        super().__init__(seed, **kw)
        self.rng_vigilia = random.Random((seed or 0) ^ 0x56494749)
        self._plan_vigilia: tuple[int, str, dict] | None = None
        self.busquedas_vigilia = self.desviaciones_vigilia = 0
        self.planes_elegidos: dict[str, int] = {}
        self.ultimo_analisis_vigilia: dict | None = None
        self.buscar_objetivos = True
        # También qué carta propia traer (Taliesin, Isengrim): la regla propone, la simulación decide.
        self.buscar_objetivos_propios = True
        self.max_objetivos = 4
        # Qué carta jugar (no solo cuántas): la heurística propone las mejores
        # por puntaje y la simulación decide en esta mesa (Conchobar o Fergus).
        self.buscar_carta = False  # 15-11: 45,8% (IC95 38,7–52,9) y 138 s por partida contra 77: apagado
        self.max_cartas = 4
        self.busquedas_carta = self.desviaciones_carta = 0
        self._objetivo_forzado: int | None = None
        self.busquedas_objetivo = self.desviaciones_objetivo = 0
        self.buscar_guerra = True
        self.buscar_mulligan = False  # 13-11: +0,6 pts en 11 cruces (ruido); apagado hasta confirmar
        self.horizonte_mano = 6
        self.busquedas_mano = self.desviaciones_mano = 0
        self.registro: list[dict] | None = None  # lista → anota cada desviación
        self.plan_reservar = False  # neutro en el barrido 13-11 (58,5 → 58,4)
        self.busquedas_guerra = self.desviaciones_guerra = 0
        self.buscar_oro = True  # 2026-11-13: qué Oro bajar, por simulación
        self.max_oros = 4
        self.horizonte_oro: int | None = None  # None: el mismo horizonte que la Vigilia
        self.buscar_activar_oro = True  # activar (o no) habilidades de mis Oros en la Vigilia, por simulación
        self.max_activar_oro = 3
        self._act_oro_vistos: set = set()
        self.busquedas_act_oro = self.desviaciones_act_oro = 0
        self.busquedas_oro = self.desviaciones_oro = 0
        # Bloqueos por simulación, con el mismo criterio pareado que lo demás.
        self.buscar_bloqueos = True
        self.max_bloqueos = 8
        self.busquedas_bloqueo = self.desviaciones_bloqueo = 0
        # Qué descartar al final del turno (mano de más de 8), por simulación.
        self.buscar_descartes = True
        self.max_descartes = 5
        self.busquedas_descarte = self.desviaciones_descarte = 0
        # Turno completo: en cada decisión de la Vigilia se comparan la jugada
        # de la regla, las mejores alternativas (otra carta, activar algo) y
        # pasar; así salen el orden y la combinación de jugadas del turno, no
        # solo cuántas cartas bajar. Reemplaza a los 4 planes fijos.
        # 16-11: 58,8% (IC95 53,0–64,5) contra los 4 planes, 80 pares; con la
        # valoración nueva, 57,0% (52,0–62,0) en otros 100 pares.
        self.buscar_turno = True
        self.max_lineas = 5
        self.busquedas_turno = self.desviaciones_turno = 0

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        referencia = super().elegir_bloqueos(p, yo, atacantes, bloqueadores)
        if not self.buscar_bloqueos or not atacantes or not bloqueadores:
            return referencia
        from .busqueda_ataques import continuar_bloqueo
        from .busqueda_bloqueos import _clave, _opciones

        por_blk = {b.uid: b for b in bloqueadores}
        por_atk = {a.uid: a for a in atacantes}
        usados: set[int] = set()
        limpio = {}
        for atk, blk in referencia.items():  # solo lo que el motor aceptaría
            if (atk in por_atk and blk.uid in por_blk and blk.uid not in usados
                    and p.puede_bloquear(por_atk[atk], blk)):
                limpio[atk] = blk
                usados.add(blk.uid)
        prior = _clave(limpio)
        opciones, _ = _opciones(p, atacantes, bloqueadores, prior, self.rng_vigilia, self.max_bloqueos)
        if len(opciones) < 2 or prior not in opciones:
            return referencia
        base = opciones.index(prior)
        inicio = time.monotonic()
        elegido, valores, conf = self._comparar(
            lambda i, seed: continuar_bloqueo(_copia(p, yo, seed), yo, opciones[i], self.horizonte, self.aprendido),
            len(opciones), self.rng_vigilia, base=base)
        self.busquedas_bloqueo += 1
        self.desviaciones_bloqueo += elegido != base
        self.segundos += time.monotonic() - inicio
        if elegido == base:
            return referencia

        def texto(o):
            return "; ".join(f"{por_blk[b].nombre} bloquea a {por_atk[a].nombre}" for a, b in o) or "no bloquear"

        if self.registro is not None:
            self.registro.append({"tipo": "bloqueo", **situacion(p, yo),
                                  "antes": texto(opciones[base]), "ahora": texto(opciones[elegido]),
                                  "est_antes": round(sum(valores[base]) / len(valores[base]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        return {atk: por_blk[blk] for atk, blk in opciones[elegido]}

    def elegir_descartes(self, p, yo, mano, n):
        referencia = super().elegir_descartes(p, yo, mano, n)
        from .motor import MANO_MAXIMA

        # Solo el descarte por exceso de mano al cerrar mi turno: es lo último
        # del turno, así que la continuación es exacta.
        if (not self.buscar_descartes or p.e.fase != "final" or p.e.activo != yo or n < 1
                or len(mano) != len(p.j(yo).mano) or len(mano) - n != MANO_MAXIMA or len(referencia) != n):
            return referencia
        ref_uids = tuple(sorted(c.uid for c in referencia))
        # Alternativas: cambiar la última descartada por otra carta de la mano
        # (las que la regla descartaría después), sin repetir nombres.
        orden = super().elegir_descartes(p, yo, mano, len(mano))
        fijas = tuple(c.uid for c in orden[:n - 1])
        opciones, vistos = [ref_uids], {c.nombre for c in referencia}
        for c in orden[n:]:
            if c.nombre in vistos:
                continue
            vistos.add(c.nombre)
            opciones.append(tuple(sorted(fijas + (c.uid,))))
            if len(opciones) >= self.max_descartes:
                break
        if len(opciones) < 2:
            return referencia
        inicio = time.monotonic()
        elegido, valores, conf = self._comparar(
            lambda i, seed: continuar_descarte(_copia(p, yo, seed), yo, opciones[i], self.horizonte, seed,
                                               self.aprendido),
            len(opciones), self.rng_vigilia)
        self.busquedas_descarte += 1
        self.desviaciones_descarte += elegido != 0
        self.segundos += time.monotonic() - inicio
        if elegido == 0:
            return referencia
        por_uid = {c.uid: c for c in mano}
        nuevas = [por_uid[u] for u in opciones[elegido]]
        if self.registro is not None:
            self.registro.append({"tipo": "descarte", **situacion(p, yo),
                                  "antes": "descartar " + ", ".join(sorted(c.nombre for c in referencia)),
                                  "ahora": "descartar " + ", ".join(sorted(c.nombre for c in nuevas)),
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        return nuevas

    def elegir_jugada(self, p, yo, jugadas, *a, **k):
        self._objetivo_forzado = None
        if p.e.fase == "guerra_talismanes" and self.buscar_guerra and hasattr(p, "_tras_guerra"):
            return self._guerra(p, yo, jugadas)
        if not _es_vigilia_propia(p, yo):
            return super().elegir_jugada(p, yo, jugadas, *a, **k)
        turno = p.e.turno
        if self.buscar_turno:
            base = Heuristico.elegir_jugada(self, p, yo, jugadas)
            if base.tipo == "oro":
                return self._elegir_oro(p, yo, jugadas, base) if self.buscar_oro else base
            if not _jugables(jugadas) or _pasar(jugadas) is None:
                return base
            j = self._linea(p, yo, jugadas, base)
            return self._con_objetivo(p, yo, j, "heuristica", {})
        if self._plan_vigilia and self._plan_vigilia[0] == turno:
            _, plan, estado = self._plan_vigilia
            antes = dict(estado)
            j = aplicar_plan(self, p, yo, jugadas, plan, estado)
            j = self._activar_oro(p, yo, jugadas, j)
            j = self._elegir_carta(p, yo, jugadas, j, plan, antes)
            return self._con_objetivo(p, yo, j, plan, antes)
        base = Heuristico.elegir_jugada(self, p, yo, jugadas)
        if base.tipo == "oro":
            return self._elegir_oro(p, yo, jugadas, base) if self.buscar_oro else base
        if not _jugables(jugadas) or _pasar(jugadas) is None:
            return base  # sin cartas para jugar no hay nada que decidir
        planes = ["heuristica", "todo"] if base.tipo == "pasar" else list(PLANES)
        if self.plan_reservar and base.tipo != "pasar" and reserva_respuestas(p, yo) > 0:
            planes.append("reservar")  # guardar Oros para responder en el turno rival
        self._base_actual = base
        plan = self._buscar(p, yo, planes)
        estado: dict = {}
        self._plan_vigilia = (turno, plan, estado)
        j = aplicar_plan(self, p, yo, jugadas, plan, estado) if plan != "heuristica" else base
        j = self._activar_oro(p, yo, jugadas, j)
        j = self._elegir_carta(p, yo, jugadas, j, plan, {})
        return self._con_objetivo(p, yo, j, plan, {})

    def _linea(self, p, yo, jugadas, base):
        """La siguiente jugada del turno: la de la regla contra las mejores
        alternativas (por puntaje, sin repetir carta) y contra pasar. Cada
        opción se simula seguida del resto del turno según la regla."""
        def nombre(x):
            return (x.tipo, x.carta.nombre if x.carta else None, x.habilidad,
                    x.portador.nombre if x.portador else None)

        def puntaje(x):
            try:
                return self._puntaje(p, yo, x)
            except Exception:  # noqa: BLE001 - una jugada rara no frena la búsqueda
                return float("-inf")

        vistas = {nombre(base)}
        opciones = [base]
        for x in sorted(_jugables(jugadas), key=lambda x: -puntaje(x)):
            if nombre(x) not in vistas and len(opciones) < self.max_lineas:
                vistas.add(nombre(x))
                opciones.append(x)
        pasar = _pasar(jugadas)
        if base.tipo != "pasar" and pasar is not None:
            opciones.append(pasar)
        if len(opciones) < 2:
            return base
        claves = [_clave_jugada(x) for x in opciones]
        inicio = time.monotonic()
        elegido, valores, conf = self._comparar(
            lambda i, seed: continuar_vigilia(_copia(p, yo, seed), yo, "heuristica", self.horizonte, seed,
                                              self.aprendido, None, claves[i]),
            len(opciones), self.rng_vigilia)
        self.busquedas_turno += 1
        self.desviaciones_turno += elegido != 0
        if self.registro is not None and elegido != 0:
            self.registro.append({"tipo": "turno", **situacion(p, yo),
                                  "antes": _texto_jugada(base), "ahora": _texto_jugada(opciones[elegido]),
                                  "candidatos": [_texto_jugada(x) for x in opciones],
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        return opciones[elegido]

    def _activar_oro(self, p, yo, jugadas, j):
        """Habilidades activadas de mis Oros (Diadema, Milano, Corona, Cruz
        Templaria, Biblioteca...): simula hacer primero cada una frente a la
        jugada elegida, y se aparta solo con ventaja clara. Una vez por
        conjunto de opciones y turno."""
        if not self.buscar_activar_oro or j.tipo == "oro":
            return j
        acts = [x for x in jugadas if x.tipo == "activar" and x.carta is not None
                and x.carta.tipo == Tipo.ORO and x.carta.controlador == yo
                and _clave_jugada(x) != _clave_jugada(j)][:self.max_activar_oro]
        if not acts:
            return j
        clave_vista = (p.e.turno, _clave_jugada(j), tuple(_clave_jugada(x) for x in acts))
        if clave_vista in self._act_oro_vistos:
            return j
        self._act_oro_vistos.add(clave_vista)
        opciones = [j] + acts
        claves = [_clave_jugada(x) for x in opciones]
        inicio = time.monotonic()
        def _valor(i, seed, _lista=claves):
            cl = _lista[i]
            return continuar_vigilia(_copia(p, yo, seed), yo, "heuristica", self.horizonte, seed, self.aprendido, None, cl)

        elegido, valores, conf = self._comparar(_valor, len(claves), self.rng_vigilia)
        n = len(valores[elegido])
        self.busquedas_act_oro += 1
        self.desviaciones_act_oro += elegido != 0
        if self.registro is not None and elegido != 0:
            self.registro.append({"tipo": "activar_oro", **situacion(p, yo),
                                  "antes": str(opciones[0]), "ahora": str(opciones[elegido]),
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        return opciones[elegido]

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        if self._objetivo_forzado is not None:
            uid, self._objetivo_forzado = self._objetivo_forzado, None
            t = next((c for c in candidatos if c.uid == uid), None)
            if t is not None:
                resto = [c for c in super().elegir_objetivos(p, yo, candidatos, n, h) if c is not t]
                return [t] + resto[:max(0, n - 1)]
        return super().elegir_objetivos(p, yo, candidatos, n, h)

    def quedarse_mano(self, p, yo):
        base = Heuristico.quedarse_mano(self, p, yo)
        from .motor import MAX_MULLIGANS
        if not self.buscar_mulligan or p.mulligans[yo] >= MAX_MULLIGANS:
            return base
        opciones = [base, not base]
        inicio = time.monotonic()
        elegido, valores, _ = self._comparar(
            lambda i, seed: continuar_mano(_copia(p, yo, seed), yo, opciones[i], self.horizonte_mano, seed,
                                           self.aprendido),
            2, self.rng_vigilia, muestras=max(8, self.muestras), max_muestras=max(24, self.max_muestras))
        self.busquedas_mano += 1
        self.desviaciones_mano += elegido != 0
        self.segundos += time.monotonic() - inicio
        if self.registro is not None and elegido != 0:
            m = [sum(v) / len(v) for v in valores]
            self.registro.append({"tipo": "mano", **situacion(p, yo),
                                  "antes": "quedarse" if base else "mulligan",
                                  "ahora": "quedarse" if opciones[elegido] else "mulligan",
                                  "est_antes": round(m[0], 3), "est_ahora": round(m[elegido], 3)})
        return opciones[elegido]

    def _guerra(self, p, yo, jugadas):
        """Guerra de Talismanes (mi turno o el del rival): compara la jugada de
        la heurística con pasar y con otras respuestas posibles."""
        base = Heuristico.elegir_jugada(self, p, yo, jugadas)
        otras = [x for x in jugadas if x.tipo != "pasar"]
        if not otras or _pasar(jugadas) is None:
            return base
        opciones = [base]
        if base.tipo != "pasar":
            opciones.append(_pasar(jugadas))
        resto = sorted((x for x in otras if _clave_jugada(x) != _clave_jugada(base)),
                       key=lambda x: -self._puntaje(p, yo, x))
        opciones += resto[:2]
        claves = [_clave_jugada(x) for x in opciones]
        inicio = time.monotonic()
        def _valor(i, seed, _lista=claves):
            cl = _lista[i]
            return continuar_guerra(_copia(p, yo, seed), yo, cl, self.horizonte, seed, self.aprendido)

        elegido, valores, conf = self._comparar(_valor, len(claves), self.rng_vigilia)
        n = len(valores[elegido])
        self.busquedas_guerra += 1
        self.desviaciones_guerra += elegido != 0
        if self.registro is not None and elegido != 0:
            self.registro.append({"tipo": "guerra", **situacion(p, yo),
                                  "antes": _texto_jugada(opciones[0]), "ahora": _texto_jugada(opciones[elegido]),
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        return opciones[elegido]

    def _elegir_oro(self, p, yo, jugadas, base):
        """Qué Oro bajar este turno: con dos o más Oros distintos en la mano,
        simula cada uno (el resto del turno y los siguientes con la
        heurística) y se aparta de la heurística solo con ventaja clara."""
        vistos, opciones = {base.carta.nombre}, [base]
        for x in jugadas:
            if x.tipo == "oro" and x.carta is not None and x.carta.nombre not in vistos:
                vistos.add(x.carta.nombre)
                opciones.append(x)
        if len(opciones) < 2:
            return base
        opciones = opciones[:self.max_oros]
        claves = [_clave_jugada(x) for x in opciones]
        inicio = time.monotonic()
        def _valor(i, seed, _lista=claves):
            cl = _lista[i]
            return continuar_vigilia(_copia(p, yo, seed), yo, "heuristica", self.horizonte_oro or self.horizonte, seed, self.aprendido, None, cl)

        elegido, valores, conf = self._comparar(_valor, len(claves), self.rng_vigilia)
        n = len(valores[elegido])
        self.busquedas_oro += 1
        self.desviaciones_oro += elegido != 0
        if self.registro is not None and elegido != 0:
            self.registro.append({"tipo": "oro", **situacion(p, yo),
                                  "antes": f"Oro {opciones[0].carta.nombre}",
                                  "ahora": f"Oro {opciones[elegido].carta.nombre}",
                                  "oros_en_mano": [x.carta.nombre for x in opciones],
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        return opciones[elegido]

    def _candidatas(self, p, yo, jugadas, j) -> list:
        """Otras cartas que podría jugar en lugar de `j`, las mejores por
        puntaje y sin repetir (dos copias de la misma carta son una opción)."""
        def clave(x):
            return (x.carta.nombre, x.portador.nombre if x.portador else None)

        vistas = {clave(j)}
        cartas = [x for x in jugadas if x.tipo == "jugar" and x.carta is not None and x.carta.tipo != Tipo.ORO]

        def puntaje(x):
            try:
                return self._puntaje(p, yo, x)
            except Exception:  # noqa: BLE001 - una jugada rara no frena la búsqueda
                return float("-inf")

        out = []
        for x in sorted(cartas, key=lambda x: -puntaje(x)):
            if clave(x) not in vistas:
                vistas.add(clave(x))
                out.append(x)
        return out[:max(0, self.max_cartas - 1)]

    def _elegir_carta(self, p, yo, jugadas, j, plan, estado_antes):
        """Si `j` juega una carta, simula también las mejores alternativas y se
        queda con otra solo con ventaja clara (margen y diferencia pareada)."""
        if not self.buscar_carta or j.tipo != "jugar" or j.carta is None or j.carta.tipo == Tipo.ORO:
            return j
        alternativas = self._candidatas(p, yo, jugadas, j)
        if not alternativas:
            return j
        inicio = time.monotonic()
        opciones = [j] + alternativas
        claves = [_clave_jugada(x) for x in opciones]
        def _valor(i, seed, _lista=claves):
            clave = _lista[i]
            return continuar_vigilia(_copia(p, yo, seed), yo, plan, self.horizonte, seed, self.aprendido, estado_antes, clave)

        elegido, valores, conf = self._comparar(_valor, len(claves), self.rng_vigilia)
        n = len(valores[elegido])
        self.busquedas_carta += 1
        self.desviaciones_carta += elegido != 0
        if self.registro is not None and elegido != 0:
            self.registro.append({"tipo": "carta", **situacion(p, yo),
                                  "antes": _texto_jugada(j), "ahora": _texto_jugada(opciones[elegido]),
                                  "candidatos": [_texto_jugada(x) for x in opciones],
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        return opciones[elegido]

    def _con_objetivo(self, p, yo, j, plan, estado_antes):
        """Si `j` elige un objetivo rival entre varios, simula cada uno y
        deja forzado el mejor (solo con ventaja clara sobre la heurística)."""
        if not self.buscar_objetivos:
            return j
        objetivos = _objetivos_en_juego(p, yo, j, self.max_objetivos,
                                        self if self.buscar_objetivos_propios else None)
        if not objetivos:
            return j
        inicio = time.monotonic()
        clave = _clave_jugada(j)
        opciones = [None] + [t.uid for t in objetivos]
        def _valor(i, seed, _lista=opciones):
            uid = _lista[i]
            return continuar_vigilia( _copia(p, yo, seed), yo, plan, self.horizonte, seed, self.aprendido, estado_antes, clave, uid)

        elegido, valores, conf = self._comparar(_valor, len(opciones), self.rng_vigilia)
        n = len(valores[elegido])
        self.busquedas_objetivo += 1
        self.desviaciones_objetivo += elegido != 0
        if self.registro is not None and elegido != 0:
            nombre = {t.uid: t.nombre for t in objetivos}
            self.registro.append({"tipo": "objetivo", **situacion(p, yo), "jugada": _texto_jugada(j),
                                  "antes": "objetivo de la heurística",
                                  "ahora": f"objetivo {nombre[opciones[elegido]]}",
                                  "candidatos": [t.nombre for t in objetivos],
                                  "est_antes": round(sum(valores[0]) / len(valores[0]), 3),
                                  "est_ahora": round(sum(valores[elegido]) / len(valores[elegido]), 3),
                                  **conf})
        self.segundos += time.monotonic() - inicio
        self._objetivo_forzado = opciones[elegido]
        return j

    def _buscar(self, p, yo, planes: list[str]) -> str:
        inicio = time.monotonic()
        def _valor(i, seed, _lista=planes):
            plan = _lista[i]
            return continuar_vigilia(_copia(p, yo, seed), yo, plan, self.horizonte, seed, self.aprendido)

        elegido, valores, conf = self._comparar(_valor, len(planes), self.rng_vigilia)
        n = len(valores[elegido])
        medias = [sum(v) / len(v) for v in valores]
        self.busquedas_vigilia += 1
        self.desviaciones_vigilia += elegido != 0
        if self.registro is not None and elegido != 0:
            base = getattr(self, "_base_actual", None)
            self.registro.append({"tipo": "vigilia", **situacion(p, yo),
                                  "antes": f"plan heurística (empezaba con: {_texto_jugada(base)})",
                                  "ahora": f"plan {planes[elegido]}",
                                  "est_antes": round(medias[0], 3), "est_ahora": round(medias[elegido], 3),
                                  **conf})
        self.planes_elegidos[planes[elegido]] = self.planes_elegidos.get(planes[elegido], 0) + 1
        self.segundos += time.monotonic() - inicio
        self.ultimo_analisis_vigilia = {
            "turno": p.e.turno, "muestras": n,
            "planes": [{"plan": pl, "estimacion": round(m, 3), "elegido": i == elegido}
                       for i, (pl, m) in enumerate(zip(planes, medias))],
        }
        return planes[elegido]


JUGADORES["busqueda_vigilia"] = BuscadorVigilia
