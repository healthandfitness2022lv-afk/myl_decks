"""Precisión de una partida: % de acierto de cada jugador, como en ajedrez.

Recorre todas las decisiones grabadas de los dos lados (jugadas, ataques,
bloqueos y objetivos). En cada una reproduce la partida hasta ese punto,
prueba la opción elegida y sus alternativas con las mismas barajadas, juega
`TURNOS` turnos con la heurística y valora cómo quedó la mesa. La pérdida de
una decisión es cuánto mejor quedaba la mejor alternativa (en puntos de
probabilidad de ganar); solo cuenta si supera el ruido de la medición.

- **exacta**: ninguna alternativa era claramente mejor.
- **imprecisión**: perdió 8–15 puntos · **error**: 15–30 · **error grave**: 30+.
- **acierto**: % de decisiones exactas (entre las que tenían alternativa).
- **precisión**: 0–100 según la pérdida media, con la curva que usa Lichess.

No depende de quién ganó: mide cada decisión contra lo mejor disponible.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.precision <idA> <idB> [--seed 7] [--jugador busqueda_vigilia]
"""

from __future__ import annotations

import argparse
import math
import os

from .autopsia import Horizonte, REVISABLES, _decodificar, alternativas, describir, reproducir

TURNOS = 2
MUESTRAS = 6
MAX_JUGADAS = 8  # alternativas que se prueban en una jugada de la Vigilia
IMPRECISION, ERROR, GRAVE = 0.08, 0.15, 0.30
Z = 1.5  # la diferencia pareada debe superar Z errores estándar


def _opciones(metodo, args, elegida, p):
    if metodo == "elegir_jugada":
        orden = [elegida] + [j for j in args[2] if j is not elegida]
        return [(str(j), j) for j in orden[:MAX_JUGADAS]]
    return alternativas(metodo, args, elegida, p)


def revisar(args) -> dict | None:
    """Pérdida de la decisión k. None si no tenía alternativas o no se pudo reproducir."""
    from .busqueda_ataques import valor_estado

    cartas, nombres, seed, registro, metodos, k, muestras, turnos = args
    entrada = registro[k]
    lado = entrada["lado"]
    textos: list[str] = []

    def elegir(indice):
        def opcion(p, metodo, a):
            opciones = _opciones(metodo, a, _decodificar(p, entrada["v"], a), p)
            if not textos:
                textos.extend(t for t, _ in opciones)
            p.horizonte = p.e.turno + turnos
            return opciones[min(indice, len(opciones) - 1)][1]
        return opcion

    valores: list[list[float]] = []
    indice = 0
    while indice == 0 or indice < len(textos):
        fila = []
        for m in range(muestras):
            try:
                g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=elegir(indice), muestra=m,
                               metodos=metodos)
            except Horizonte as h:
                fila.append(valor_estado(h.partida, lado))
                continue
            if g is None:
                return None
            fila.append(1.0 if g == lado else 0.5 if g == -1 else 0.0)
        if len(textos) < 2:
            return None  # decisión obligada
        valores.append(fila)
        indice += 1
    medias = [sum(v) / len(v) for v in valores]
    mejor = max(range(len(medias)), key=lambda i: medias[i])
    perdida = 0.0
    if mejor != 0:
        d = [a - b for a, b in zip(valores[mejor], valores[0])]
        media = sum(d) / len(d)
        ee = math.sqrt(sum((x - media) ** 2 for x in d) / (len(d) - 1) / len(d)) if len(d) > 1 else 0.0
        if media >= IMPRECISION and media > Z * ee:
            perdida = media
    return {"paso": k, "lado": lado, "turno": entrada.get("turno"), "fase": entrada.get("fase"),
            "tipo": entrada["m"].replace("elegir_", ""), "elegida": textos[0],
            "mejor": textos[mejor] if perdida else textos[0], "perdida": round(perdida, 3),
            "clase": clase(perdida)}


def clase(perdida: float) -> str:
    return ("exacta" if perdida < IMPRECISION else "imprecision" if perdida < ERROR
            else "error" if perdida < GRAVE else "grave")


def curva(perdida_media: float) -> float:
    """Precisión 0–100 a partir de la pérdida media en puntos (curva de Lichess)."""
    return round(max(0.0, min(100.0, 103.1668 * math.exp(-0.04354 * perdida_media * 100) - 3.1669)), 1)


def resumen(revisiones: list[dict], nombres) -> dict:
    lados = []
    for lado in (0, 1):
        r = [x for x in revisiones if x["lado"] == lado]
        cuenta = {c: sum(x["clase"] == c for x in r) for c in ("exacta", "imprecision", "error", "grave")}
        media = sum(x["perdida"] for x in r) / len(r) if r else 0.0
        lados.append({"lado": lado, "nombre": nombres[lado], "decisiones": len(r), **cuenta,
                      "acierto": round(cuenta["exacta"] / len(r) * 100, 1) if r else None,
                      "precision": curva(media) if r else None,
                      "perdidaMedia": round(media * 100, 1)})
    fallas = sorted((x for x in revisiones if x["clase"] != "exacta"), key=lambda x: -x["perdida"])
    return {"lados": lados, "jugadas": fallas, "turnos": TURNOS, "muestras": MUESTRAS}


def precision_partida(cartas, nombres, seed: int, registro: list, metodos=None, *,
                      muestras: int = MUESTRAS, turnos: int = TURNOS, procesos: int | None = None,
                      progreso=None) -> dict:
    """Informe de precisión de una partida grabada (Desafío o IA contra IA)."""
    pasos = [k for k, e in enumerate(registro) if e["m"] in REVISABLES]
    tareas = [(cartas, nombres, seed, registro, metodos, k, muestras, turnos) for k in pasos]
    revisiones = []
    if procesos == 1:
        iterador = map(revisar, tareas)
        cerrar = lambda: None  # noqa: E731
    else:
        from concurrent.futures import ProcessPoolExecutor

        ex = ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1))
        iterador = ex.map(revisar, tareas, chunksize=4)
        cerrar = ex.shutdown
    try:
        for n, r in enumerate(iterador, 1):
            if r is not None:
                revisiones.append(r)
            if progreso:
                progreso(n, len(tareas))
    finally:
        cerrar()
    return resumen(revisiones, nombres)


def informe_md(inf: dict, top: int = 10) -> str:
    lineas = ["| Jugador | Acierto | Precisión | Decisiones | Imprecisiones | Errores | Graves |",
              "|---|---|---|---|---|---|---|"]
    for x in inf["lados"]:
        lineas.append(f"| {x['nombre']} | {x['acierto']}% | {x['precision']} | {x['decisiones']} "
                      f"| {x['imprecision']} | {x['error']} | {x['grave']} |")
    if inf["jugadas"]:
        lineas += ["", "| Turno | Jugador | Decisión | Eligió | Mejor | Perdió |", "|---|---|---|---|---|---|"]
        for j in inf["jugadas"][:top]:
            lineas.append(f"| {j['turno']} | {inf['lados'][j['lado']]['nombre']} | {j['tipo']} | {j['elegida']} "
                          f"| {j['mejor']} | {j['perdida'] * 100:.0f} pts |")
    return "\n".join(lineas)


def jugar_grabada(mazo_a, mazo_b, seed: int, jugador: str = "heuristico"):
    """Partida IA contra IA con las decisiones grabadas, para medir su precisión."""
    from .autopsia import Grabadora, metodos_de
    from .jugadores import JUGADORES
    from .motor import FinPartida, Partida

    registro: list = []
    ref: list = [None]
    base = (JUGADORES[jugador](seed * 2), JUGADORES[jugador](seed * 2 + 1))
    metodos = [metodos_de(j) for j in base]
    p = Partida((mazo_a.cartas, mazo_b.cartas),
                tuple(Grabadora(j, i, registro, ref, revisable=True) for i, j in enumerate(base)),
                nombres=(mazo_a.nombre, mazo_b.nombre), inicial=None, seed=seed)
    ref[0] = p
    try:
        ganador = p.jugar().ganador
    except FinPartida:
        ganador = p.e.ganador
    return ganador, registro, metodos


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.precision")
    ap.add_argument("mazo_a")
    ap.add_argument("mazo_b")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jugador", default="heuristico")
    ap.add_argument("--procesos", type=int)
    args = ap.parse_args(argv)
    from . import busqueda_vigilia  # noqa: F401 - registra los buscadores
    from .meta import _mazos_de

    a, b = _mazos_de([args.mazo_a, args.mazo_b], True)
    ganador, registro, metodos = jugar_grabada(a, b, args.seed, args.jugador)
    inf = precision_partida((a.cartas, b.cartas), (a.nombre, b.nombre), args.seed, registro, metodos,
                            procesos=args.procesos)
    print(f"Ganó {(a.nombre, b.nombre)[ganador] if ganador in (0, 1) else 'nadie'}")
    print(informe_md(inf))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
