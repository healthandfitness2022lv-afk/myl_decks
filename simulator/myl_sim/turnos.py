"""Jugar, reproducir y valorar un turno completo desde una posición grabada.

Una posición es una partida grabada hasta la decisión `k`. Desde ahí:

- `jugar`: alguien (una persona por el tablero, o un jugador automático)
  toma todas las decisiones de su lado hasta que cambia el turno; el otro lado
  responde con la heurística. El orden del mazo queda fijo (misma barajada
  para todos los que jueguen ese turno) y todo lo decidido se graba.
- `valorar`: repite un turno grabado, y al terminar baraja de nuevo lo que no
  se ve y deja jugar a la heurística `TURNOS` turnos más; devuelve la
  estimación de victoria. Así se comparan dos formas de jugar el mismo turno
  por cómo queda la partida después, con las mismas barajadas.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import random
from typing import Any

from .autopsia import Horizonte, REVISABLES, Reproductor, _codificar, _decodificar, _Desvio, describir
from .jugadores import Heuristico
from .motor import FinPartida, Partida

TURNOS = 3


class FinTurno(Exception):
    """Cambió el turno: quien jugaba ya terminó el suyo."""


def _barajar(p: Partida, semilla: int, lado: int | None = None, args: tuple = ()) -> None:
    """Con `lado`, su rival recibe además otra mano de las que podía tener."""
    from .autopsia import remuestrear_ocultas

    rng = random.Random(semilla)
    for j in p.e.jugadores:
        if lado is not None and j.indice == 1 - lado:
            remuestrear_ocultas(p, j.indice, rng, args)
        else:
            rng.shuffle(j.mazo)
    p.e.rng = random.Random(rng.random())


def metodos_de_humano() -> list[str]:
    from .autopsia import metodos_de
    from .desafio import HumanoRemoto

    return metodos_de(HumanoRemoto(lambda *a: None))


def metodos_de_heuristica() -> list[str]:
    from .autopsia import metodos_de

    return metodos_de(Heuristico(0))


@dataclass
class _Contexto:
    registro: list            # lo grabado; en `jugar` crece con el turno
    k: int                    # decisión donde empieza el turno a jugar
    seed: int
    metodos_pre: list         # qué decisiones sabía tomar cada lado antes de k
    metodos_turno: list       # ídem durante el turno (persona o heurística)
    despues: tuple = ()       # quién decide cada lado al pasar lo grabado
    grabar: bool = False      # `jugar`: anota y corta al cambiar el turno
    muestra: int | None = None  # `valorar`: barajada del futuro
    lado: int | None = None     # `valorar`: desde quién se juzga (su rival recibe otra mano)
    p: Any = None
    reps: tuple = ()
    barajado: bool = False
    futuro: bool = False
    turno: int | None = None
    horizonte: int | None = None
    textos: list = field(default_factory=list)  # (lado, tipo, texto) de lo decidido en el turno


class _Asiento:
    """Un lado de la mesa: lo grabado antes de `k`, el turno (grabado o en
    vivo) y, al valorar, la heurística hasta el horizonte."""

    nombre = "turno"

    def __init__(self, lado: int, ctx: _Contexto):
        self._lado, self._ctx = lado, ctx

    def _tramo(self) -> str:
        ctx = self._ctx
        c = ctx.p.cursor if ctx.p is not None else 0
        if c < ctx.k:
            return "pre"
        return "turno" if (c < len(ctx.registro) or ctx.grabar) else "futuro"

    def __getattr__(self, nombre):
        if nombre.startswith("_"):
            raise AttributeError(nombre)
        ctx, lado = self._ctx, self._lado
        tramo = self._tramo()
        if tramo == "pre":
            attr = getattr(ctx.reps[lado], nombre)  # AttributeError si no la sabía tomar
            if not callable(attr):
                return attr
        elif tramo == "turno":
            if nombre == "elige_ninguna":
                return "elige_ninguna" in ctx.metodos_turno[lado]
            if nombre not in ctx.metodos_turno[lado]:
                raise AttributeError(nombre)
        else:
            if not callable(getattr(ctx.despues[lado], nombre, None)):
                raise AttributeError(nombre)

        def decidir(*args, **kw):
            p = ctx.p
            if p.cursor < ctx.k:
                return getattr(ctx.reps[lado], nombre)(*args, **kw)
            if not ctx.barajado:
                # Mismo orden de mazo para todos los que jueguen este turno.
                _barajar(p, ctx.seed * 7919)
                ctx.barajado, ctx.turno = True, p.e.turno
            if p.cursor < len(ctx.registro):
                entrada = ctx.registro[p.cursor]
                if entrada["lado"] != lado or entrada["m"] != nombre:
                    raise _Desvio()
                p.cursor += 1
                try:
                    return _decodificar(p, entrada["v"], args)
                except (IndexError, StopIteration) as e:
                    raise _Desvio() from e
            if ctx.grabar:
                if p.e.turno != ctx.turno:
                    raise FinTurno()
                valor = getattr(ctx.despues[lado], nombre)(*args, **kw)
                ctx.registro.append({"lado": lado, "m": nombre, "v": _codificar(valor, args)})
                p.cursor += 1
                if nombre in REVISABLES:
                    ctx.textos.append((lado, nombre.replace("elegir_", ""), describir(nombre, valor, args)))
                return valor
            if not ctx.futuro:
                _barajar(p, ctx.seed * 7919 + 1000 + (ctx.muestra or 0), ctx.lado, args)
                ctx.futuro, ctx.horizonte = True, p.e.turno + TURNOS
            if p.e.turno >= ctx.horizonte:
                raise Horizonte(p)
            return getattr(ctx.despues[lado], nombre)(*args, **kw)

        return decidir


def _partida(cartas, nombres, ctx: _Contexto, *, log: bool = False) -> Partida:
    ref: list = [None]
    ctx.reps = tuple(Reproductor(i, ctx.registro, ref, rama=None, metodos=ctx.metodos_pre[i]) for i in (0, 1))
    p = Partida(cartas, (_Asiento(0, ctx), _Asiento(1, ctx)), nombres=nombres, inicial=None, seed=ctx.seed, log=log)
    p.cursor, p.cursor_rama = 0, None
    ref[0] = ctx.p = p
    return p


class _PrimeraForzada:
    """La primera decisión es la grabada; después decide `base`."""

    def __init__(self, base, codificado):
        self._base, self._codificado = base, codificado

    def __getattr__(self, nombre):
        attr = getattr(self._base, nombre)
        if not callable(attr) or self._codificado is None:
            return attr

        def decidir(*args, **kw):
            codificado, self._codificado = self._codificado, None
            try:
                return _decodificar(args[0], codificado, args)
            except Exception:  # noqa: BLE001 - si ya no aplica, decide la base
                return attr(*args, **kw)
        return decidir


def jugar(cartas, nombres, seed: int, registro: list, k: int, metodos, lado: int, quien, *,
          metodos_quien: list[str] | None = None, al_crear=None) -> dict:
    """`quien` juega desde la decisión `k` hasta que cambia el turno. Devuelve
    el registro con el turno agregado, lo que decidió y cómo quedó."""
    turno = [set(metodos_de_heuristica()), set(metodos_de_heuristica())]
    turno[lado] = set(metodos_quien) if metodos_quien is not None else turno[lado]
    despues = [Heuristico(seed * 31 + 7), Heuristico(seed * 31 + 8)]
    despues[lado] = quien
    ctx = _Contexto(registro=list(registro[:k]), k=k, seed=seed, metodos_pre=list(metodos or [None, None]),
                    metodos_turno=[sorted(x) for x in turno], despues=tuple(despues), grabar=True)
    p = _partida(cartas, nombres, ctx, log=True)
    if al_crear:
        al_crear(p)
    ganador = None
    try:
        ganador = p.jugar().ganador
    except FinTurno:
        pass
    except FinPartida:
        ganador = p.e.ganador
    if not ctx.barajado:
        raise _Desvio()  # no se llegó a la decisión k con lo grabado
    return {"registro": ctx.registro, "metodosTurno": ctx.metodos_turno, "partida": p, "ganador": ganador,
            "decisiones": [(tipo, texto) for l, tipo, texto in ctx.textos if l == lado]}


def resumen(decisiones: list[tuple[str, str]]) -> list[str]:
    """El turno en palabras: lo que se jugó y con qué se atacó (sin los «pasar»)."""
    out = []
    for tipo, t in decisiones:
        if tipo == "jugada" and t.strip().lower() == "pasar":
            continue
        out.append(f"elige {t}" if tipo == "objetivos" else t)
    return out or ["pasar"]


def valorar(cartas, nombres, seed: int, registro: list, k: int, metodos, metodos_turno, lado: int,
            muestras: int) -> float | None:
    """Estimación de victoria de `lado` tras ese turno (registro con el turno incluido)."""
    from .busqueda_ataques import valor_estado

    total, hechas = 0.0, 0
    for m in range(muestras):
        ctx = _Contexto(registro=registro, k=k, seed=seed, metodos_pre=list(metodos or [None, None]),
                        metodos_turno=metodos_turno, muestra=m, lado=lado,
                        despues=(Heuristico(seed * 53 + 2 * m), Heuristico(seed * 53 + 2 * m + 1)))
        p = _partida(cartas, nombres, ctx)
        try:
            g = p.jugar().ganador
        except Horizonte as h:
            total += valor_estado(h.partida, lado)
            hechas += 1
            continue
        except FinPartida:
            g = p.e.ganador
        except _Desvio:
            continue
        total += 1.0 if g == lado else 0.5 if g == -1 else 0.0
        hechas += 1
    return round(total / hechas, 3) if hechas >= max(1, muestras // 2) else None
