"""Modelo de la mano oculta del rival.

La IA no ve la mano ni el orden del Mazo Castillo rival. Este módulo estima
qué puede tener a partir de información pública:

- **Listas candidatas** (`p.meta_listas`): las barajas que la IA conoce del
  meta (propias, notables). Cada una se pondera por qué tan bien explica las
  cartas que el rival ya mostró. Si no se entregan listas, se usa la lista
  real del rival (comportamiento anterior: "conoce la lista").
- **Cartas vistas**: en mesa (aunque las controle otro), Cementerio,
  Destierro, Armas portadas y cartas reveladas de su mano.
- **Copias restantes** = copias de la lista − vistas. Con eso se calcula la
  probabilidad hipergeométrica de que tenga al menos una carta de un tipo en
  la mano, y se pueden muestrear manos plausibles para simular.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from math import comb
import random

from .modelo import ORO_INICIAL, Carta, Instancia, Zona

# Peso relativo de una lista por cada copia vista que no puede explicar.
PENALIZACION_INCOMPATIBLE = 0.05


@dataclass
class Hipotesis:
    peso: float
    restantes: Counter  # carta.id → copias que quedan entre Mano oculta + Mazo
    cartas: dict  # carta.id → Carta


def _instancias_de(p, quien: int) -> list[Instancia]:
    out = []
    for j in p.e.jugadores:
        for zona in (j.reserva, j.pagado, j.defensa, j.ataque, j.apoyo):
            out += [x for x in zona if x.dueno == quien]
    out += [x for x in p.e.portadas if x.dueno == quien]
    r = p.j(quien)
    out += r.cementerio + r.destierro
    out += [x for x in r.mano if getattr(x, "revelada", False)]
    return out


def vistas(p, quien: int) -> Counter:
    """Copias de cada carta del rival que ya son públicas."""
    return Counter(x.carta.id for x in _instancias_de(p, quien) if x.carta.id != ORO_INICIAL.id)


def ocultas(p, quien: int) -> tuple[int, int]:
    """(cartas ocultas en mano, cartas en el Mazo Castillo)."""
    r = p.j(quien)
    return sum(1 for x in r.mano if not getattr(x, "revelada", False)), len(r.mazo)


def _lista_real(p, quien: int) -> list[Carta]:
    todas = []
    for j in p.e.jugadores:
        for zona in (j.mazo, j.mano, j.reserva, j.pagado, j.defensa, j.ataque, j.apoyo,
                     j.cementerio, j.destierro):
            todas += [x.carta for x in zona if x.dueno == quien]
    todas += [x.carta for x in p.e.portadas if x.dueno == quien]
    return [c for c in todas if c.id != ORO_INICIAL.id]


def hipotesis(p, quien: int) -> list[Hipotesis]:
    """Listas candidatas del rival con su peso normalizado."""
    listas = getattr(p, "meta_listas", None) or [_lista_real(p, quien)]
    vis = vistas(p, quien)
    out = []
    for lista in listas:
        conteo = Counter(c.id for c in lista if c.id != ORO_INICIAL.id)
        cartas = {c.id: c for c in lista}
        incompatibles = sum(max(0, k - conteo.get(cid, 0)) for cid, k in vis.items())
        peso = PENALIZACION_INCOMPATIBLE ** incompatibles
        restantes = Counter({cid: k - vis.get(cid, 0) for cid, k in conteo.items()
                             if k - vis.get(cid, 0) > 0})
        out.append(Hipotesis(peso, restantes, cartas))
    total = sum(h.peso for h in out) or 1.0
    for h in out:
        h.peso /= total
    return out


def _prob_al_menos_una(exitos: int, poblacion: int, mano: int) -> float:
    if mano <= 0 or exitos <= 0 or poblacion <= 0:
        return 0.0
    exitos = min(exitos, poblacion)
    mano = min(mano, poblacion)
    return 1.0 - comb(poblacion - exitos, mano) / comb(poblacion, mano)


def prob_en_mano(p, yo: int, predicado) -> float:
    """Probabilidad de que el rival de `yo` tenga en la mano oculta al menos
    una carta que cumpla `predicado(Carta)`. Cuenta las reveladas como seguras."""
    quien = 1 - yo
    rival = p.j(quien)
    if any(getattr(x, "revelada", False) and predicado(x.carta) for x in rival.mano):
        return 1.0
    mano, mazo = ocultas(p, quien)
    poblacion = mano + mazo
    total = 0.0
    for h in hipotesis(p, quien):
        exitos = sum(k for cid, k in h.restantes.items() if predicado(h.cartas[cid]))
        total += h.peso * _prob_al_menos_una(exitos, poblacion, mano)
    return total


def muestrear(p, quien: int, rng: random.Random) -> tuple[list[Carta], list[Carta]]:
    """Una mano oculta y un Mazo Castillo plausibles para `quien`
    (mismo tamaño que los reales), elegidos según las listas candidatas."""
    mano, mazo = ocultas(p, quien)
    hs = hipotesis(p, quien)
    h = rng.choices(hs, weights=[x.peso for x in hs])[0]
    bolsa = [h.cartas[cid] for cid, k in sorted(h.restantes.items()) for _ in range(k)]
    rng.shuffle(bolsa)
    necesarias = mano + mazo
    if len(bolsa) < necesarias:
        # La lista candidata no alcanza (el rival mostró cartas fuera de ella):
        # se completa con cartas de la misma lista al azar.
        base = list(h.cartas.values()) or [ORO_INICIAL]
        bolsa += [rng.choice(base) for _ in range(necesarias - len(bolsa))]
    return bolsa[:mano], bolsa[mano:necesarias]


def reemplazar_ocultas(p, quien: int, rng: random.Random) -> None:
    """Sustituye la mano oculta y el Mazo de `quien` en una COPIA de la partida
    por una muestra del modelo (las reveladas se conservan)."""
    r = p.j(quien)
    mano, mazo = muestrear(p, quien, rng)
    reveladas = [x for x in r.mano if getattr(x, "revelada", False)]

    def nueva(carta: Carta, zona: Zona) -> Instancia:
        return Instancia(uid=p.e.nuevo_uid(), carta=carta, dueno=quien, controlador=quien, zona=zona)

    r.mano = reveladas + [nueva(c, Zona.MANO) for c in mano]
    r.mazo = [nueva(c, Zona.MAZO) for c in mazo]
