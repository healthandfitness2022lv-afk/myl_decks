"""Aprender de cómo juega la persona en el Desafío IA.

Al terminar un desafío se toman las decisiones de la persona (grabadas) y en
cada una se le pregunta a la heurística qué habría hecho en esa misma
posición. Donde difieren, se reproduce la partida hasta ahí y se juega desde
ese punto con la opción de la persona y con la de la IA (varias muestras,
barajando el futuro). Si la de la persona gana claramente más seguido queda
como lección: "aquí la persona jugó X y rinde más que Y". No se copia el
estilo: solo lo que las simulaciones confirman.

Antes de todo se verifica que la grabación reproduzca la partida idéntica
(mismo ganador y turnos); si no, no se saca ninguna conclusión.
"""

from __future__ import annotations

from typing import Any

from .autopsia import (EXTREMO, REVISABLES, _clave, _decodificar, _Desvio, alternativas, describir,
                       diferencia_clara, reproducir)
from .jugadores import Heuristico
from .motor import FinPartida, Partida

MUESTRAS = 12
EXTRA = 2  # si una parece mejor pero no es firme: hasta EXTRA×MUESTRAS más (pareadas)
MAX_COMPARAR = 8
MARGEN = 0.2  # la opción debe ganar al menos 20 puntos más para ser "mejor"


class _Respuesta(Exception):
    def __init__(self, datos: dict):
        super().__init__("respuesta")
        self.datos = datos


def _opciones_reales(metodo: str, args: tuple) -> bool:
    """Hay algo que decidir (no una sola opción posible)."""
    if metodo == "elegir_jugada":
        return len(args[2]) > 1
    if metodo == "elegir_atacantes":
        return bool(args[2])
    if metodo == "elegir_bloqueos":
        return bool(args[2]) and bool(args[3])
    if metodo == "elegir_objetivos":
        return len(args[2]) > args[3]
    return False


def _semilla_ia(seed: int) -> int:
    return seed * 2  # la heurística "en el lugar de la persona" (lado 0)


def que_haria_la_ia(cartas, nombres, seed: int, registro: list, k: int, metodos=None) -> dict | None:
    """Lo que eligió la persona en la decisión k y lo que habría elegido la IA."""
    entrada = registro[k]

    def opcion(p, metodo, args):
        humano = _decodificar(p, entrada["v"], args)
        if not _opciones_reales(metodo, args):
            raise _Respuesta({"trivial": True})
        ia = getattr(Heuristico(_semilla_ia(seed)), metodo)(*args)
        texto_h, texto_ia = describir(metodo, humano, args), describir(metodo, ia, args)
        raise _Respuesta({
            "trivial": False,
            # Dos copias de la misma carta (Tótem de la Serpiente) son la misma jugada.
            "igual": _clave(humano) == _clave(ia) or texto_h == texto_ia,
            "humano": texto_h,
            "ia": texto_ia,
            "opciones": [t for t, _ in alternativas(metodo, args, humano, p)],
        })

    try:
        reproducir(cartas, nombres, seed, registro, rama=k, opcion=opcion, metodos=metodos, ocultar=False)
    except _Respuesta as r:
        return r.datos
    except _Desvio:
        return None
    return None


def comparar(cartas, nombres, seed: int, registro: list, k: int, metodos=None,
             muestras: int = MUESTRAS, desde: int = 0) -> dict | None:
    """Tasa de victoria de la persona jugando su opción y la de la IA en k."""
    entrada = registro[k]
    lado = entrada["lado"]

    def con(de_la_ia: bool):
        def opcion(p, metodo, args):
            if de_la_ia:
                return getattr(Heuristico(_semilla_ia(seed)), metodo)(*args)
            return _decodificar(p, entrada["v"], args)
        return opcion

    # La muestra m usa los mismos robos y barajados para las dos opciones.
    res = []
    for de_la_ia in (False, True):
        fila = []
        for m in range(desde, desde + muestras):
            g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=con(de_la_ia), muestra=m,
                           metodos=metodos)
            if g is None:
                return None
            fila.append(1.0 if g == lado else 0.5 if g == -1 else 0.0)
        res.append(fila)
    tasas = [sum(r) / len(r) for r in res]
    return {"ganaHumano": round(tasas[0], 2), "ganaIa": round(tasas[1], 2), "_h": res[0], "_ia": res[1]}


TURNOS_HORIZONTE = 2
MARGEN_ESTIMACION = 0.08


def comparar_a_horizonte(cartas, nombres, seed: int, registro: list, k: int, metodos=None,
                         muestras: int = MUESTRAS, turnos: int = TURNOS_HORIZONTE) -> dict | None:
    """Cuando las dos opciones pierden (o ganan) siempre, el final no dice
    nada: la IA juega por la persona desde ahí y juega peor que ella (T11 del
    desafío PzofIK: "ninguna gana" y la persona ganó). Se compara entonces
    cómo queda la partida `turnos` turnos después de cada opción."""
    from .autopsia import Horizonte
    from .busqueda_ataques import valor_estado

    entrada = registro[k]
    lado = entrada["lado"]

    def con(de_la_ia: bool):
        def opcion(p, metodo, args):
            p.horizonte = p.e.turno + turnos
            if de_la_ia:
                return getattr(Heuristico(_semilla_ia(seed)), metodo)(*args)
            return _decodificar(p, entrada["v"], args)
        return opcion

    medias = []
    for de_la_ia in (False, True):
        total = 0.0
        for m in range(muestras):
            try:
                g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=con(de_la_ia), muestra=m,
                               metodos=metodos)
            except Horizonte as h:
                total += valor_estado(h.partida, lado)
                continue
            if g is None:
                return None
            total += 1 if g == lado else 0.5 if g == -1 else 0
        medias.append(total / muestras)
    return {"estimaHumano": round(medias[0], 3), "estimaIa": round(medias[1], 3), "turnos": turnos}


def comparar_ritmo(cartas, nombres, seed: int, registro: list, k: int, metodos=None,
                   muestras: int = MUESTRAS) -> dict | None:
    """Héctor: si las dos opciones ganan (o pierden) siempre, gana la que
    cierra antes la partida (o la que resiste más). Turnos desde la decisión."""
    from .autopsia import ULTIMA_PARTIDA

    entrada = registro[k]
    lado, t0 = entrada["lado"], entrada.get("turno") or 0

    def con(de_la_ia: bool):
        def opcion(p, metodo, args):
            if de_la_ia:
                return getattr(Heuristico(_semilla_ia(seed)), metodo)(*args)
            return _decodificar(p, entrada["v"], args)
        return opcion

    out, porm = [], []
    for de_la_ia in (False, True):
        gana, pierde, fila = [], [], []
        for m in range(muestras):
            g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=con(de_la_ia), muestra=m,
                           metodos=metodos)
            if g is None:
                return None
            t = ULTIMA_PARTIDA[0].e.turno - t0
            (gana if g == lado else pierde).append(t)
            fila.append((g == lado, t))
        porm.append(fila)
        out.append((sum(gana) / len(gana) if gana else None, sum(pierde) / len(pierde) if pierde else None))
    # Pares (misma muestra) en que las dos ganan: turnos de cada una.
    pares = [(a[1], b[1]) for a, b in zip(*porm) if a[0] and b[0]]
    return {"turnosGanaHumano": out[0][0], "turnosGanaIa": out[1][0],
            "turnosPierdeHumano": out[0][1], "turnosPierdeIa": out[1][1],
            "_th": [a for a, _ in pares], "_tia": [b for _, b in pares]}


MARGEN_TURNOS = 0.75  # cerrar la partida casi un turno antes ya es mejor


def verificar_reproduccion(cartas, nombres, seed: int, registro: list, metodos, ganador: int | None,
                           turnos: int | None = None) -> tuple[bool, str]:
    """La grabación debe reproducir la misma partida: si no, cualquier
    conclusión sobre una posición podría ser de otra partida."""
    from .autopsia import Reproductor

    ref: list = [None]
    jugadores = tuple(Reproductor(i, registro, ref, rama=None, seed=seed, metodos=(metodos or [None, None])[i])
                      for i in (0, 1))
    p = Partida(cartas, jugadores, nombres=nombres, inicial=None, seed=seed)
    p.cursor, p.cursor_rama = 0, None
    p.al_ramificar = lambda *a: None
    ref[0] = p
    try:
        r = p.jugar()
        g, t = r.ganador, r.turnos
    except FinPartida:
        g, t = p.e.ganador, p.e.turno
    except _Desvio:
        return False, f"la reproducción se separó de lo grabado en la decisión {p.cursor}"
    if g != ganador:
        return False, f"al reproducir ganó {g} y en la partida ganó {ganador}"
    if turnos is not None and t != turnos:
        return False, f"al reproducir duró {t} turnos y la partida {turnos}"
    if p.cursor != len(registro):
        return False, f"se reprodujeron {p.cursor} de {len(registro)} decisiones"
    return True, "ok"


def _impacto(registro: list, ks: list[int]) -> dict[int, float]:
    """Cuánto cambió la estimación de la persona desde esa decisión a su
    siguiente: las de más impacto se comparan primero."""
    out = {}
    for a, b in zip(ks, ks[1:] + [None]):
        va = registro[a].get("valor")
        vb = registro[b].get("valor") if b is not None else None
        out[a] = abs(va - vb) if va is not None and vb is not None else 0.0
    return out


def informe(cartas, nombres, seed: int, registro: list, metodos, ganador: int | None,
            turnos: int | None = None, *, maximo: int = MAX_COMPARAR, muestras: int = MUESTRAS,
            confirmaciones: dict | None = None) -> dict:
    ok, motivo = verificar_reproduccion(cartas, nombres, seed, registro, metodos, ganador, turnos)
    if not ok:
        return {"reproduccionOk": False, "motivo": motivo, "comparadas": 0, "diferencias": [],
                "resumen": f"No se analizaron tus jugadas: {motivo}."}
    ks = [k for k, e in enumerate(registro) if e["lado"] == 0 and e["m"] in REVISABLES]
    distintas = []
    for k in ks:
        d = que_haria_la_ia(cartas, nombres, seed, registro, k, metodos)
        if d and not d["trivial"] and not d["igual"]:
            distintas.append((k, d))
    impacto = _impacto(registro, ks)
    elegidas = sorted(distintas, key=lambda x: -impacto.get(x[0], 0.0))[:maximo]
    diferencias = []
    for k, d in sorted(elegidas):
        c = comparar(cartas, nombres, seed, registro, k, metodos, muestras)
        if c is None:
            continue
        veredicto = _veredicto(c, MARGEN)
        if veredicto == "parejo" and abs(c["ganaHumano"] - c["ganaIa"]) >= MARGEN:
            # Parece mejor pero puede ser suerte: más muestras, mismas semillas para las dos.
            mas = comparar(cartas, nombres, seed, registro, k, metodos, muestras * EXTRA, desde=muestras)
            if mas is not None:
                c["_h"] += mas["_h"]
                c["_ia"] += mas["_ia"]
                c["ganaHumano"] = round(sum(c["_h"]) / len(c["_h"]), 2)
                c["ganaIa"] = round(sum(c["_ia"]) / len(c["_ia"]), 2)
                veredicto = _veredicto(c, MARGEN)
        c["muestras"] = len(c["_h"])
        if max(c["ganaHumano"], c["ganaIa"]) <= EXTREMO:
            # Héctor: si las dos pierden siempre, el resultado es el mismo: no hay
            # mejor ni peor (tampoco "la IA acierta").
            veredicto = "parejo"
        elif veredicto == "parejo" and min(c["ganaHumano"], c["ganaIa"]) >= 1 - EXTREMO:
            # Las dos ganan: ¿cuál cierra antes la partida? (Héctor: "con esta
            # pegas 10 y con la otra 18"). Solo con diferencia firme.
            r = comparar_ritmo(cartas, nombres, seed, registro, k, metodos, muestras)
            if r is not None and r["turnosGanaHumano"] is not None and r["turnosGanaIa"] is not None:
                th, tia = r.pop("_th"), r.pop("_tia")
                c.update(r)
                veredicto = ("humano" if diferencia_clara(th, tia, MARGEN_TURNOS)
                             else "ia" if diferencia_clara(tia, th, MARGEN_TURNOS) else "parejo")
        for clave in ("_h", "_ia"):
            c.pop(clave, None)
        e = registro[k]
        x = {
            "paso": k, "lado": 0, "turno": e.get("turno"), "fase": e.get("fase"),
            "tipo": e["m"].replace("elegir_", ""),
            "humano": d["humano"], "ia": d["ia"], **c, "mejor": veredicto,
            "confirmacion": (confirmaciones or {}).get(str(k)),
        }
        x["explicacion"] = explicar(x)
        diferencias.append(x)
    # Héctor: solo lo que de verdad es distinto y deja algo que aprender (tu
    # jugada mejor, o la de la IA mejor); lo "parejo" no se muestra.
    parejas = len([x for x in diferencias if x["mejor"] == "parejo"])
    diferencias = [x for x in diferencias if x["mejor"] != "parejo" and x["humano"] != x["ia"]]
    mejores = [x for x in diferencias if x["mejor"] == "humano"]
    if mejores:
        resumen = (f"En {len(mejores)} jugada(s) tu opción rindió claramente más que la de la IA: "
                   "quedan como lecciones pendientes; la IA cambia cuando se aplican (confirma si reflejan tu idea de juego).")
    elif diferencias:
        resumen = "En las jugadas en que la IA habría elegido distinto, la suya rendía más (abajo, para que veas cuáles)."
    else:
        resumen = (f"Sin nada que aprender: en las {parejas} jugadas distintas que se simularon, las dos opciones "
                   "rendían parecido." if parejas else "La IA habría jugado igual que tú en las posiciones que importaban.")
    return {"reproduccionOk": True, "comparadas": len(diferencias) + parejas, "parejas": parejas,
            "distintas": len(distintas),
            "decisiones": len(ks), "diferencias": diferencias, "resumen": resumen}


def _veredicto(c: dict, margen: float) -> str:
    """Mejor solo si la diferencia es firme con muestras pareadas (no suerte)."""
    if diferencia_clara(c["_ia"], c["_h"], margen):
        return "humano"
    if diferencia_clara(c["_h"], c["_ia"], margen):
        return "ia"
    return "parejo"


def explicar(x: dict) -> str:
    t = f"T{x['turno']} ({str(x['fase']).replace('_', ' ')})"
    fin = {"humano": "tu jugada fue mejor.", "ia": "la de la IA era mejor.", "parejo": "parejo."}[x["mejor"]]
    if x.get("turnosGanaHumano") is not None and x.get("turnosGanaIa") is not None:
        return (f"{t}: tú «{x['humano']}» · la IA «{x['ia']}» · las dos ganan, pero con la tuya en "
                f"{x['turnosGanaHumano']:.1f} turnos y con la de la IA en {x['turnosGanaIa']:.1f} → {fin}")
    if x.get("turnosPierdeHumano") is not None and x.get("turnosPierdeIa") is not None:
        return (f"{t}: tú «{x['humano']}» · la IA «{x['ia']}» · las dos pierden, pero con la tuya resistías "
                f"{x['turnosPierdeHumano']:.1f} turnos y con la de la IA {x['turnosPierdeIa']:.1f} → {fin}")
    if "estimaHumano" in x:
        # El final no distinguía: se comparó cómo quedaba la partida a 2 turnos.
        base = (f"{t}: tú «{x['humano']}» · la IA «{x['ia']}» · a {x['turnos']} turnos la partida "
                f"te quedaba {x['estimaHumano']:.0%} contra {x['estimaIa']:.0%}")
        return base + {"humano": " → tu jugada fue mejor.", "ia": " → la de la IA dejaba mejor la partida.",
                       "parejo": " → parejo."}[x["mejor"]]
    base = f"{t}: tú «{x['humano']}» ({x['ganaHumano']:.0%}) · la IA «{x['ia']}» ({x['ganaIa']:.0%})"
    if x["mejor"] == "parejo" and max(x["ganaHumano"], x["ganaIa"]) <= 0.1:
        return base + " → con la IA jugando por ti desde ahí, ninguna ganaba: no dice cuál era mejor."
    if x["mejor"] == "parejo" and min(x["ganaHumano"], x["ganaIa"]) >= 0.9:
        return base + " → con la IA jugando por ti desde ahí, las dos ganaban: no dice cuál era mejor."
    return base + {"humano": " → tu jugada fue mejor.", "ia": " → la de la IA rendía más.",
                   "parejo": " → parejo."}[x["mejor"]]


def lecciones(informe_h: dict) -> list[dict[str, Any]]:
    """Las diferencias donde la persona jugó claramente mejor (o que confirmó)."""
    return [x for x in informe_h.get("diferencias", [])
            if x["mejor"] == "humano" or x.get("confirmacion") == "si"]
