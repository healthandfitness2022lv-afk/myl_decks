"""Búsqueda por simulación para decidir con qué atacar.

En cada declaración de ataque genera alternativas (la de la heurística, no
atacar, atacar con todos, quitar o dejar a cada uno…), y para cada una juega
varias continuaciones con el motor real: bloqueos del rival, Guerra de
Talismanes, habilidades al morir o salir, Oros, Tótems y los turnos
siguientes. La mano oculta del rival se muestrea con `creencias` (lo que
puede tener según las listas conocidas y lo que ya mostró), no con su mano
real. Todas las alternativas usan las mismas muestras (comparación pareada).

Las continuaciones son cortas (`horizonte` turnos); si la partida no terminó
se valora el estado (castillos, mesa y mano).
"""

from __future__ import annotations

import copy
from itertools import combinations
import math
import random
import time

from . import creencias
from . import habilidades as hab
from .jugadores import JUGADORES, Heuristico
from .motor import FinPartida, Partida


def _copia(p: Partida, yo: int, seed: int) -> Partida:
    memo = {id(j): None for j in p.jugadores}
    memo[id(p.pasos)] = []
    estilo_ = getattr(p, "estilo", None)
    if estilo_ is not None:
        memo[id(estilo_)] = None
    if p.e.log is not None:
        memo[id(p.e.log)] = None
    listas = getattr(p, "meta_listas", None)
    if listas is not None:
        memo[id(listas)] = listas
    for j in p.e.jugadores:
        for zona in (j.mazo, j.mano, j.reserva, j.pagado, j.defensa, j.ataque, j.apoyo,
                     j.cementerio, j.destierro):
            for x in zona:
                memo[id(x.carta)] = x.carta
    for x in p.e.portadas:
        memo[id(x.carta)] = x.carta
    c = copy.deepcopy(p, memo)
    c.__class__ = Partida  # sin auditoría ni otros ganchos en las simulaciones
    c.e.log = None
    c.pasos = []
    rng = random.Random(seed)
    c.e.rng = random.Random(seed ^ 0x415441)
    propio = c.j(yo)
    propio.mazo.sort(key=lambda x: (x.carta.id, x.uid))
    rng.shuffle(propio.mazo)
    creencias.reemplazar_ocultas(c, 1 - yo, rng)
    jugadores = [Heuristico(seed * 2 + 1), Heuristico(seed * 2 + 2)]
    corrige = estilo_.corrige(1 - yo) if estilo_ is not None else None
    if corrige:
        from .estilo import rival

        jugadores[1 - yo] = rival(seed * 2 + 2 - yo, corrige)
    c.jugadores = tuple(jugadores)
    return c


class _Forzado(Heuristico):
    """Declara exactamente los atacantes indicados la primera vez."""

    def __init__(self, seed, uids):
        super().__init__(seed)
        self._uids = set(uids)
        self._usado = False

    def elegir_atacantes(self, p, yo, candidatos):
        if self._usado:
            return super().elegir_atacantes(p, yo, candidatos)
        self._usado = True
        return [c for c in candidatos if c.uid in self._uids]


def valor_estado(p: Partida, yo: int, aprendido: bool = True) -> float:
    """0–1: estimación de victoria para `yo` cuando la simulación se corta.
    Usa la valoración entrenada (`valor.py`) si existe.
    `aprendido="utilidad"`: la utilidad de `busqueda_utilidad` (rapidez y castillo)."""
    if aprendido == "utilidad":
        from .busqueda_utilidad import utilidad

        return utilidad(p, yo)
    if p.e.terminada:
        g = p.e.ganador
        return 1.0 if g == yo else 0.5 if g == -1 else 0.0
    if aprendido:
        from .valor import prob_ganar, prob_ganar_v2, prob_ganar_v3

        q = (prob_ganar_v3(p, yo) if aprendido == 3 else prob_ganar_v2(p, yo) if aprendido == 2
             else prob_ganar(p, yo))
        if q is not None:
            return q
    mio, suyo = p.j(yo), p.j(1 - yo)
    fuerza = lambda j: sum(max(0, hab.fuerza(p, a)) for a in j.aliados)  # noqa: E731
    x = ((len(mio.mazo) - len(suyo.mazo)) / 12
         + (fuerza(mio) - fuerza(suyo)) / 15
         + (len(mio.mano) - len(suyo.mano)) / 10
         + (len(mio.reserva) + len(mio.pagado) - len(suyo.reserva) - len(suyo.pagado)) / 12)
    return 0.5 + 0.5 * math.tanh(x)


def continuar(c: Partida, yo: int, uids: tuple[int, ...], horizonte: int, seed: int,
              aprendido: bool = True) -> float:
    a = c.e.activo
    jugadores = list(c.jugadores)
    jugadores[a] = _Forzado(seed * 2 + 3 + a, uids)
    c.jugadores = tuple(jugadores)
    try:
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


def alternativas(p, candidatos, referencia, maximo: int) -> list[tuple[int, ...]]:
    uids = [c.uid for c in candidatos]
    clave = lambda xs: tuple(sorted(xs))  # noqa: E731
    out = [clave(c.uid for c in referencia), (), clave(uids)]
    if len(uids) <= 4:
        for k in range(1, len(uids)):
            out += [clave(x) for x in combinations(uids, k)]
    else:
        orden = sorted(candidatos, key=lambda c: -hab.fuerza(p, c))
        out += [clave(c.uid for c in orden[:k]) for k in range(1, len(orden))]
        out += [clave(u for u in uids if u != x) for x in uids]
    vistas, unicas = set(), []
    for o in out:
        if o not in vistas:
            vistas.add(o)
            unicas.append(o)
    return unicas[:maximo]


def _decidir(valores: list[list[float]], base: int, margen: float, z: float) -> tuple[int, bool]:
    """Elige la mejor opción solo si supera a `base` por `margen` y con
    diferencia pareada significativa (media > z·error estándar)."""
    cand = elegido_dudoso(valores, base, margen)
    if cand is None:
        return base, False
    d = [a - b for a, b in zip(valores[cand], valores[base])]
    n = len(d)
    media = sum(d) / n
    var = sum((x - media) ** 2 for x in d) / (n - 1) if n > 1 else float("inf")
    ee = math.sqrt(var / n)
    if media > z * ee:
        return cand, True
    return base, False


def elegido_dudoso(valores, base, margen):
    """La mejor opción por media si supera a `base` por `margen`; si no, None."""
    medias = [sum(v) / len(v) for v in valores]
    mejor = max(range(len(valores)), key=lambda i: medias[i])
    if mejor == base or medias[mejor] < medias[base] + margen:
        return None
    return mejor


MIN_FRESCAS = 8  # pares nuevos (no usados para elegir candidata) antes de apartarse


def comparar_opciones(evaluar, cuantas: int, rng, *, muestras: int, max_muestras: int, margen: float,
                      z: float, base: int = 0, limite: float | None = None,
                      min_frescas: int = MIN_FRESCAS) -> tuple[int, list[list[float]], dict]:
    """Elige entre `cuantas` opciones; `evaluar(i, seed)` da el valor 0–1 de la
    opción `i` en la muestra `seed` (pareadas: misma semilla para todas).

    1. Criba: `muestras` muestras a todas. Siguen como finalistas las (hasta) 2
       mejores que superan a `base` por `margen`. Sin finalistas, gana `base`.
    2. Confirmación con muestras NUEVAS solo para `base` y las finalistas. La
       decisión usa solo esas: elegir a la mejor de 8 y medirla con las mismas
       muestras infla la ventaja (así salían desviaciones de puro ruido).
    3. Se aparta de `base` solo con al menos `min_frescas` pares nuevos, ventaja
       ≥ `margen` y diferencia pareada > `z` errores estándar. Una finalista que
       no va ganando con los pares nuevos se descarta.

    `limite`: instante (time.monotonic) en que se corta; sin confirmación, `base`.
    Devuelve (elegida, valores por opción, {"muestras", "z"} de la confirmación)."""
    valores: list[list[float]] = [[] for _ in range(cuantas)]

    def tanda(indices, k):
        for _ in range(k):
            seed = rng.randrange(1, 2**31)
            for i in indices:
                valores[i].append(evaluar(i, seed))

    tanda(range(cuantas), muestras)
    medias = [sum(v) / len(v) for v in valores]
    finalistas = sorted((i for i in range(cuantas) if i != base and medias[i] >= medias[base] + margen),
                        key=lambda i: -medias[i])[:2]
    info = {"muestras": 0, "z": None}
    tope = max(min_frescas, max_muestras - muestras)
    frescas = 0
    while finalistas and frescas < tope:
        if limite is not None and time.monotonic() >= limite:
            break
        k = min(4, tope - frescas)
        tanda([base] + finalistas, k)
        frescas += k
        if frescas < min_frescas:
            continue
        datos = {}
        for i in finalistas:
            d = [a - b for a, b in zip(valores[i][muestras:], valores[base][muestras:])]
            media = sum(d) / len(d)
            ee = math.sqrt(sum((x - media) ** 2 for x in d) / (len(d) - 1) / len(d)) if len(d) > 1 else 0.0
            datos[i] = (media, ee)
        mejor = max(finalistas, key=lambda i: datos[i][0])
        media, ee = datos[mejor]
        if media >= margen and media > z * ee:
            return mejor, valores, {"muestras": frescas, "z": round(media / ee, 1) if ee else 99.0}
        finalistas = [i for i in finalistas if datos[i][0] > 0]
    info["muestras"] = frescas
    return base, valores, info


class BuscadorAtaques(Heuristico):
    """Heurística en todo, salvo la declaración de ataque, que se simula."""

    nombre = "busqueda_ataques"

    def __init__(self, seed: int | None = None, *, muestras: int = 4, horizonte: int = 4,
                 max_opciones: int = 8, margen: float = 0.04, max_segundos: float | None = None,
                 aprendido: bool = False, max_muestras: int = 16, z: float = 2.0):
        super().__init__(seed)
        self.max_muestras, self.z = max(muestras, max_muestras), z
        self.aprendido = aprendido
        self.muestras, self.horizonte = muestras, horizonte
        self.max_opciones, self.margen, self.max_segundos = max_opciones, margen, max_segundos
        self.rng_busqueda = random.Random(seed)
        self.busquedas = self.desviaciones = 0
        self.segundos = 0.0
        self.ultimo_analisis: dict | None = None

    def _comparar(self, evaluar, cuantas: int, rng, *, base: int = 0, muestras: int | None = None,
                  max_muestras: int | None = None):
        """`comparar_opciones` con el presupuesto de este jugador."""
        limite = None if self.max_segundos is None else time.monotonic() + self.max_segundos
        return comparar_opciones(evaluar, cuantas, rng, muestras=muestras or self.muestras,
                                 max_muestras=max_muestras or self.max_muestras, margen=self.margen,
                                 z=self.z, base=base, limite=limite)

    def elegir_atacantes(self, p, yo, candidatos):
        referencia = super().elegir_atacantes(p, yo, candidatos)
        opciones = alternativas(p, candidatos, referencia, self.max_opciones)
        if len(opciones) < 2:
            return referencia
        inicio = time.monotonic()
        elegido, valores, conf = self._comparar(
            lambda i, seed: continuar(_copia(p, yo, seed), yo, opciones[i], self.horizonte, seed, self.aprendido),
            len(opciones), self.rng_busqueda)
        n = len(valores[elegido])
        medias = [sum(v) / len(v) for v in valores]
        self.busquedas += 1
        self.desviaciones += elegido != 0
        self.segundos += time.monotonic() - inicio
        por_uid = {c.uid: c for c in candidatos}
        self.ultimo_analisis = {
            "turno": p.e.turno, "muestras": n,
            "opciones": [{"atacantes": [por_uid[u].nombre for u in o], "estimacion": round(m, 3),
                          "heuristica": i == 0, "elegida": i == elegido}
                         for i, (o, m) in enumerate(zip(opciones, medias))],
        }
        return [por_uid[u] for u in opciones[elegido]]


# ── Bloqueos ──────────────────────────────────────────────────────────────────
def continuar_bloqueo(c: Partida, yo: int, opcion: tuple, horizonte: int,
                      aprendido: bool = True) -> float:
    """Resuelve el combate con `opcion` ((atacante, bloqueador) por uid) y sigue."""
    por_uid = {b.uid: b for b in c.j(yo).defensa}
    bloqueos = dict(c.bloqueos)
    bloqueos.update({atk: por_uid[blk] for atk, blk in opcion if blk in por_uid})
    activo = c.e.activo
    try:
        c._resolver_bloqueos(c.atacantes, bloqueos, yo)
        c._finalizar_turno(activo)
        c._cerrar_turno(activo)
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


class BuscadorCompleto(BuscadorAtaques):
    """Ataques y bloqueos decididos por simulación; lo demás, heurística."""

    nombre = "busqueda_completa"

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        from .busqueda_bloqueos import _clave, _opciones

        referencia = super().elegir_bloqueos(p, yo, atacantes, bloqueadores)
        prior = _clave(referencia)
        opciones, _ = _opciones(p, atacantes, bloqueadores, prior, self.rng_busqueda, self.max_opciones)
        if len(opciones) < 2:
            return referencia
        indice_prior = opciones.index(prior)
        inicio = time.monotonic()
        suma = [0.0] * len(opciones)
        n = 0
        for _ in range(self.muestras):
            seed = self.rng_busqueda.randrange(1, 2**31)
            for i, o in enumerate(opciones):
                suma[i] += continuar_bloqueo(_copia(p, yo, seed), yo, o, self.horizonte, self.aprendido)
            n += 1
        medias = [s / n for s in suma]
        mejor = max(range(len(opciones)), key=lambda i: medias[i])
        elegido = mejor if medias[mejor] >= medias[indice_prior] + self.margen else indice_prior
        self.busquedas += 1
        self.desviaciones += elegido != indice_prior
        self.segundos += time.monotonic() - inicio
        por_blk = {b.uid: b for b in bloqueadores}
        return {atk: por_blk[blk] for atk, blk in opciones[elegido]}


JUGADORES["busqueda_ataques"] = BuscadorAtaques
JUGADORES["busqueda_completa"] = BuscadorCompleto
