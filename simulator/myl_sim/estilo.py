"""Estilo del rival: cuánto se aparta de la heurística al atacar y bloquear.

`creencias` estima QUÉ cartas tiene el rival; este módulo estima CÓMO juega.
Todo sale de información pública (lo que declaró atacar y con qué bloqueó):

- Cada vez que un jugador declara ataques o bloqueos se le pregunta a la
  heurística, en una copia de la mesa, qué habría hecho. La diferencia
  (atacantes o bloqueos de más o de menos) se acumula por jugador.
- En las simulaciones de la búsqueda el rival juega con `RivalConEstilo`:
  la heurística, corregida en promedio por esa diferencia. Contra un rival que
  juega como la heurística no cambia nada; contra uno más agresivo o más
  conservador (una persona, otra IA), las continuaciones se le parecen más.
- Se puede pasar un estilo previo (partidas anteriores contra ese rival, por
  ejemplo las del mismo match al mejor de 3); pesa como `PESO_PREVIO`
  observaciones y la partida actual lo va corrigiendo.
"""
from __future__ import annotations

import copy
import random

MIN_OBS = 2  # observaciones antes de corregir al rival en las simulaciones
UMBRAL = 0.15  # desvío medio mínimo para que valga la pena corregir
PESO_PREVIO = 4


class Estilo:
    def __init__(self, previo: dict | None = None):
        # por lado: {"ataque": [suma, n], "bloqueo": [suma, n]}
        self.lados = [{"ataque": [0.0, 0], "bloqueo": [0.0, 0]} for _ in range(2)]
        self.previo = previo or {}

    # ── Observar ─────────────────────────────────────────────────────────────
    def _anotar(self, lado: int, tipo: str, desvio: float) -> None:
        s = self.lados[lado][tipo]
        s[0] += desvio
        s[1] += 1

    def observar_ataque(self, p, lado: int, candidatos, atacantes) -> None:
        ref = _referencia(p, lado, "atacantes", candidatos)
        if ref is not None:
            self._anotar(lado, "ataque", len(atacantes) - ref)

    def observar_bloqueo(self, p, lado: int, atacantes, bloqueadores, elegidos) -> None:
        ref = _referencia(p, lado, "bloqueos", atacantes, bloqueadores)
        if ref is not None:
            self._anotar(lado, "bloqueo", len(elegidos) - ref)

    # ── Leer ─────────────────────────────────────────────────────────────────
    def desvio(self, lado: int, tipo: str) -> tuple[float, int]:
        suma, n = self.lados[lado][tipo]
        prev = self.previo.get(tipo)
        if prev is not None:
            suma += prev * PESO_PREVIO
            n += PESO_PREVIO
        return (suma / n if n else 0.0), n

    def resumen(self, lado: int) -> dict:
        return {t: round(self.desvio(lado, t)[0], 3) for t in ("ataque", "bloqueo")}

    def corrige(self, lado: int) -> dict | None:
        """Lo que hay que corregir al simular a `lado`, o None si juega como la heurística."""
        out = {}
        for tipo in ("ataque", "bloqueo"):
            d, n = self.desvio(lado, tipo)
            if n >= MIN_OBS and abs(d) >= UMBRAL:
                out[tipo] = d
        return out or None


def _referencia(p, lado: int, que: str, *listas) -> int | None:
    """Cuántos atacantes/bloqueos declararía la heurística en esta mesa (en una copia)."""
    from .jugadores import Heuristico

    try:
        memo = {id(j): None for j in p.jugadores}
        memo[id(p.pasos)] = []
        memo[id(p.estilo)] = None
        if p.e.log is not None:
            memo[id(p.e.log)] = None
        listas_meta = getattr(p, "meta_listas", None)
        if listas_meta is not None:
            memo[id(listas_meta)] = listas_meta
        c = copy.deepcopy(p, memo)
        c.e.log = None
        c.e.rng = random.Random(0x5E57)
        uids = [[x.uid for x in lista] for lista in listas]
        todas = {x.uid: x for j in c.e.jugadores
                 for z in (j.defensa, j.ataque, j.apoyo) for x in z}
        copias = [[todas[u] for u in us if u in todas] for us in uids]
        h = Heuristico(0x5E57)
        if que == "atacantes":
            return len(h.elegir_atacantes(c, lado, copias[0]))
        return len(h.elegir_bloqueos(c, lado, copias[0], copias[1]))
    except Exception:  # noqa: BLE001 — observar nunca frena la partida
        return None


def _rival_con_estilo_cls():
    from . import habilidades as hab
    from .jugadores import Heuristico

    class RivalConEstilo(Heuristico):
        """La heurística corregida en promedio por el estilo observado."""

        nombre = "rival_con_estilo"

        def __init__(self, seed, corrige: dict):
            super().__init__(seed)
            self.corrige = corrige
            self.rng_estilo = random.Random((seed or 0) ^ 0xE571)

        def _cuantos(self, d: float) -> int:
            entero = int(abs(d))
            return entero + (1 if self.rng_estilo.random() < abs(d) - entero else 0)

        def elegir_atacantes(self, p, yo, candidatos):
            base = list(super().elegir_atacantes(p, yo, candidatos))
            d = self.corrige.get("ataque")
            if not d:
                return base
            k = self._cuantos(d)
            if d > 0:
                resto = sorted((c for c in candidatos if c not in base), key=lambda x: -hab.fuerza(p, x))
                return base + resto[:k]
            quitar = set(id(x) for x in sorted(base, key=lambda x: hab.fuerza(p, x))[:k])
            return [x for x in base if id(x) not in quitar]

        def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
            base = dict(super().elegir_bloqueos(p, yo, atacantes, bloqueadores))
            d = self.corrige.get("bloqueo")
            if not d:
                return base
            k = self._cuantos(d)
            if d > 0:
                usados = set(id(b) for b in base.values())
                for atk in sorted((a for a in atacantes if a.uid not in base), key=lambda x: -hab.fuerza(p, x)):
                    if k <= 0:
                        break
                    libres = [b for b in bloqueadores if id(b) not in usados and p.puede_bloquear(atk, b)]
                    if libres:
                        blk = max(libres, key=lambda x: hab.fuerza(p, x))
                        base[atk.uid] = blk
                        usados.add(id(blk))
                        k -= 1
                return base
            fuerza = {a.uid: hab.fuerza(p, a) for a in atacantes}
            for uid in sorted(base, key=lambda u: fuerza.get(u, 0))[:k]:
                del base[uid]
            return base

    return RivalConEstilo


_CLS = None


def rival(seed: int, corrige: dict):
    global _CLS
    if _CLS is None:
        _CLS = _rival_con_estilo_cls()
    return _CLS(seed, corrige)
