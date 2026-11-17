"""Precisión de una partida: % de acierto de cada jugador, como en ajedrez.

Recorre las decisiones grabadas de los dos lados (jugadas, ataques, bloqueos
y objetivos). En cada una reproduce la partida hasta ese punto, prueba la
opción elegida y sus alternativas con las mismas barajadas, juega `TURNOS`
turnos con la heurística y valora cómo quedó la mesa. La pérdida de una
decisión es cuánto mejor quedaba la mejor alternativa (en puntos de
probabilidad de ganar).

El juez no ve la mano del rival: en cada muestra el rival recibe otra mano de
las que podía tener (`autopsia.reproducir(ocultar=True)`). Una decisión se
juzga con lo que su autor sabía, no por cómo salió esa vez.

- **exacta**: ninguna alternativa era claramente mejor.
- **imprecisión**: perdió 8–15 puntos · **error**: 15–30 · **error grave**: 30+.
- **acierto**: % de decisiones exactas (entre las que tenían alternativa).
- **puntos perdidos por decisión**: la medida sin sesgo, con su IC95.

No depende de quién ganó: mide cada decisión contra lo mejor disponible.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.precision partida <idA> <idB> [--seed 7] [--jugador busqueda_vigilia]
  .venv/Scripts/python -m myl_sim.precision nota [motores…] --partidas 20 --salida calibracion
"""

from __future__ import annotations

import argparse
import math
import os

from .autopsia import Horizonte, REVISABLES, _decodificar, alternativas, reproducir

TURNOS = 4
MUESTRAS = 6        # primera ronda, por opción
MAX_MUESTRAS = 24   # las finalistas llegan hasta aquí
MAX_JUGADAS = 10    # alternativas que se prueban en una jugada de la Vigilia
IMPRECISION, ERROR, GRAVE = 0.08, 0.15, 0.30
Z = 2.0  # la diferencia pareada debe superar Z errores estándar
NIVELES_CALIBRACION = ("aleatorio", "nivel1", "nivel2", "nivel3", "heuristico", "busqueda_vigilia")


class _NoReproduce(Exception):
    pass


def _opciones(metodo, args, elegida, p):
    if metodo == "elegir_jugada":
        orden = [elegida] + [j for j in args[2] if j is not elegida]
        return [(str(j), j) for j in orden[:MAX_JUGADAS]]
    return alternativas(metodo, args, elegida, p)


def _media(v) -> float:
    return sum(v) / len(v) if v else 0.0


def revisar(args) -> dict | None:
    """Pérdida de la decisión k. None si no tenía alternativas o no se pudo reproducir.

    - El rival recibe en cada muestra otra mano de las que podía tener.
    - Eliminación por rondas: todas las opciones parten con `muestras`; en
      cada ronda sigue la mitad mejor (más la elegida) y se doblan las muestras.
    - Sin sesgo de selección: las muestras pares eligen a la mejor alternativa
      y las impares miden cuánto le gana a la elegida. Elegir y medir con las
      mismas muestras infla la pérdida (la mejor de 8 siempre «gana» algo)."""
    from .busqueda_ataques import valor_estado

    cartas, nombres, seed, registro, metodos, k, muestras, turnos = args[:8]
    max_muestras = max(muestras, args[8] if len(args) > 8 else MAX_MUESTRAS)
    desde = args[9] if len(args) > 9 else 0  # otras barajadas: confirmación independiente
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

    def una(indice: int, m: int) -> float:
        try:
            g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=elegir(indice), muestra=desde + m,
                           metodos=metodos)
        except Horizonte as h:
            return valor_estado(h.partida, lado)
        if g is None:
            raise _NoReproduce()
        return 1.0 if g == lado else 0.5 if g == -1 else 0.0

    def eligen(v):
        return v[0::2]

    def miden(v):
        return v[1::2]

    try:
        valores: dict[int, list[float]] = {0: [una(0, m) for m in range(muestras)]}
        unicas: dict[str, int] = {}
        for i, t in enumerate(textos):
            unicas.setdefault(t, i)  # dos copias de la misma carta son la misma jugada
        rivales = [i for i in unicas.values() if i != 0]
        if not rivales:
            return None  # decisión obligada
        for i in rivales:
            valores[i] = [una(i, m) for m in range(muestras)]
        n = muestras
        while n < max_muestras:
            rivales.sort(key=lambda i: -_media(eligen(valores[i])))
            rivales = rivales[:max(1, len(rivales) // 2)]
            extra = min(n, max_muestras - n)
            for i in [0] + rivales:
                valores[i] += [una(i, m) for m in range(n, n + extra)]
            n += extra
    except _NoReproduce:
        return None
    mejor = max(rivales, key=lambda i: _media(eligen(valores[i])))
    perdida = ee = 0.0
    if _media(eligen(valores[mejor])) > _media(eligen(valores[0])):
        d = [a - b for a, b in zip(miden(valores[mejor]), miden(valores[0]))]
        perdida = _media(d)
        ee = math.sqrt(sum((x - perdida) ** 2 for x in d) / (len(d) - 1) / len(d)) if len(d) > 1 else 0.0
    firme = perdida >= IMPRECISION and perdida > Z * ee
    return {"paso": k, "lado": lado, "turno": entrada.get("turno"), "fase": entrada.get("fase"),
            "tipo": entrada["m"].replace("elegir_", ""), "elegida": textos[0],
            "mejor": textos[mejor] if firme else textos[0],
            "candidata": textos[mejor] if perdida > 0 else None,
            "perdida": round(perdida, 3), "ee": round(ee, 3), "muestras": n, "opciones": len(unicas),
            "ganaElegida": round(_media(valores[0]), 3), "ganaMejor": round(_media(valores[mejor]), 3),
            "clase": clase(perdida) if firme else "exacta"}


def clase(perdida: float) -> str:
    return ("exacta" if perdida < IMPRECISION else "imprecision" if perdida < ERROR
            else "error" if perdida < GRAVE else "grave")


def curva(perdida_media: float) -> float:
    """Precisión 0–100 a partir de la pérdida media en puntos (curva de Lichess)."""
    return round(max(0.0, min(100.0, 103.1668 * math.exp(-0.04354 * perdida_media * 100) - 3.1669)), 1)


def _nota(r: list[dict]) -> dict:
    """Nota de un grupo de decisiones revisadas. `perdidaMedia` (puntos de
    probabilidad de ganar que se dejan por decisión) es la medida sin sesgo:
    puede salir apenas negativa cuando no hay nada que mejorar."""
    cuenta = {c: sum(x["clase"] == c for x in r) for c in ("exacta", "imprecision", "error", "grave")}
    n = len(r)
    media = _media([x["perdida"] for x in r])
    ee = math.sqrt(sum((x["perdida"] - media) ** 2 for x in r) / (n - 1) / n) if n > 1 else 0.0
    return {"decisiones": n, **cuenta,
            "acierto": round(cuenta["exacta"] / n * 100, 1) if n else None,
            "precision": curva(max(0.0, media)) if n else None,
            "perdidaMedia": round(media * 100, 2),
            "ic95": [round((media - 1.96 * ee) * 100, 2), round((media + 1.96 * ee) * 100, 2)]}


def resumen(revisiones: list[dict], nombres) -> dict:
    lados = [{"lado": lado, "nombre": nombres[lado], **_nota([x for x in revisiones if x["lado"] == lado])}
             for lado in (0, 1)]
    tipos = sorted({x["tipo"] for x in revisiones})
    fallas = sorted((x for x in revisiones if x["clase"] != "exacta"), key=lambda x: -x["perdida"])
    return {"lados": lados, "total": _nota(revisiones),
            "porTipo": {t: _nota([x for x in revisiones if x["tipo"] == t]) for t in tipos},
            "jugadas": fallas, "turnos": TURNOS, "muestras": MUESTRAS}


def tareas_de(cartas, nombres, seed: int, registro: list, metodos=None, *, muestras: int = MUESTRAS,
              turnos: int = TURNOS, max_muestras: int = MAX_MUESTRAS, max_decisiones: int | None = None) -> list:
    """Una tarea de `revisar` por decisión (o por una muestra al azar de ellas)."""
    import random

    pasos = [k for k, e in enumerate(registro) if e["m"] in REVISABLES]
    if max_decisiones is not None and len(pasos) > max_decisiones:
        pasos = sorted(random.Random(seed).sample(pasos, max_decisiones))
    return [(cartas, nombres, seed, registro, metodos, k, muestras, turnos, max_muestras) for k in pasos]


def precision_partida(cartas, nombres, seed: int, registro: list, metodos=None, *,
                      muestras: int = MUESTRAS, turnos: int = TURNOS, procesos: int | None = None,
                      progreso=None, max_muestras: int = MAX_MUESTRAS,
                      max_decisiones: int | None = None) -> dict:
    """Informe de precisión de una partida grabada (Desafío o IA contra IA)."""
    tareas = tareas_de(cartas, nombres, seed, registro, metodos, muestras=muestras, turnos=turnos,
                       max_muestras=max_muestras, max_decisiones=max_decisiones)
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
    lineas = ["| Jugador | Acierto | Puntos perdidos por decisión (IC95) | Decisiones | Imprecisiones | Errores | Graves |",
              "|---|---|---|---|---|---|---|"]
    for x in inf["lados"]:
        lineas.append(f"| {x['nombre']} | {x['acierto']}% | {x['perdidaMedia']} "
                      f"({x['ic95'][0]} a {x['ic95'][1]}) | {x['decisiones']} "
                      f"| {x['imprecision']} | {x['error']} | {x['grave']} |")
    if inf["jugadas"]:
        lineas += ["", "| Turno | Jugador | Decisión | Eligió | Mejor | Perdió |", "|---|---|---|---|---|---|"]
        for j in inf["jugadas"][:top]:
            lineas.append(f"| {j['turno']} | {inf['lados'][j['lado']]['nombre']} | {j['tipo']} | {j['elegida']} "
                          f"| {j['mejor']} | {j['perdida'] * 100:.0f} pts |")
    return "\n".join(lineas)


def jugar_grabada(mazo_a, mazo_b, seed: int, jugador: str = "heuristico"):
    """Partida IA contra IA con las decisiones grabadas, para medir su precisión.
    `jugador`: un motor de la arena (`nivel2`, `busqueda_vigilia`, `heuristico@v1115b`…)."""
    from . import arena
    from .autopsia import Grabadora, metodos_de
    from .jugadores import JUGADORES
    from .motor import FinPartida, Partida

    registro: list = []
    ref: list = [None]
    if jugador.partition("@")[0] in arena.MOTORES:
        base = (arena.crear(jugador, seed * 2), arena.crear(jugador, seed * 2 + 1))
    else:
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


# ── Nota de un motor y calibración: la pérdida debe bajar con la fuerza ──────
def _carpeta():
    from .datos import CACHE

    return CACHE / "precision"


def _partida_motor(args):
    motor, mazo_a, mazo_b, seed, muestras, turnos, max_muestras, max_decisiones = args
    try:
        _, registro, metodos = jugar_grabada(mazo_a, mazo_b, seed, motor)
    except Exception:  # noqa: BLE001 - una partida rota no detiene la medición
        return []
    return tareas_de((mazo_a.cartas, mazo_b.cartas), (mazo_a.nombre, mazo_b.nombre), seed, registro, metodos,
                     muestras=muestras, turnos=turnos, max_muestras=max_muestras, max_decisiones=max_decisiones)


def _revisar_seguro(tarea):
    try:
        r = revisar(tarea)
    except Exception:  # noqa: BLE001
        return None
    if r is not None:
        r["mazo"] = tarea[1][r["lado"]]
        r["seed"] = tarea[2]
    return r


def revisiones_motor(motor: str, partidas: int, *, seed: int = 1, mazos: list | None = None,
                     max_decisiones: int | None = 12, muestras: int = MUESTRAS, turnos: int = TURNOS,
                     max_muestras: int = MAX_MUESTRAS, procesos: int | None = None, log=None,
                     con_tareas: bool = False):
    """Juega `partidas` del motor contra sí mismo (mismos mazos y semillas para
    todos los motores) y revisa una muestra al azar de decisiones de cada una."""
    import random
    from concurrent.futures import ProcessPoolExecutor

    from .meta import raciales_del_cache

    mazos = mazos or raciales_del_cache()
    rng = random.Random(seed)
    juegos = []
    for n in range(partidas):
        a, b = rng.sample(mazos, 2)
        juegos.append((motor, a, b, seed * 1_000_003 + n, muestras, turnos, max_muestras, max_decisiones))
    revisiones, pares = [], []
    with ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1)) as ex:
        tareas = [t for ts in ex.map(_partida_motor, juegos) for t in ts]
        if log:
            log(f"{motor}: {partidas} partidas jugadas, {len(tareas)} decisiones por revisar")
        for n, (t, r) in enumerate(zip(tareas, ex.map(_revisar_seguro, tareas, chunksize=2)), 1):
            if r is not None:
                revisiones.append(r)
                pares.append((t, r))
            if log and n % 100 == 0:
                log(f"{motor}: {n}/{len(tareas)}")
    return pares if con_tareas else revisiones


def nota_motor(motor: str, partidas: int, **kw) -> dict:
    """Nota del juez para un motor."""
    revisiones = revisiones_motor(motor, partidas, **kw)
    tipos = sorted({x["tipo"] for x in revisiones})
    return {"motor": motor, "partidas": partidas, "seed": kw.get("seed", 1), **_nota(revisiones),
            "porTipo": {t: _nota([x for x in revisiones if x["tipo"] == t]) for t in tipos},
            "peores": sorted((x for x in revisiones if x["clase"] != "exacta"), key=lambda x: -x["perdida"])[:20]}


def notas_md(notas: list[dict]) -> str:
    lineas = ["| Motor | Decisiones | Acierto | Puntos perdidos por decisión (IC95) | Imprecisiones | Errores | Graves |",
              "|---|---|---|---|---|---|---|"]
    for x in notas:
        lineas.append(f"| {x['motor']} | {x['decisiones']} | {x['acierto']}% | {x['perdidaMedia']} "
                      f"({x['ic95'][0]} a {x['ic95'][1]}) | {x['imprecision']} | {x['error']} | {x['grave']} |")
    tipos = sorted({t for x in notas for t in x["porTipo"]})
    lineas += ["", "Puntos perdidos por decisión (y decisiones revisadas), por tipo:", "",
               "| Motor | " + " | ".join(tipos) + " |", "|---|" + "---|" * len(tipos)]
    for x in notas:
        celdas = [f"{x['porTipo'][t]['perdidaMedia']} ({x['porTipo'][t]['decisiones']})" if t in x["porTipo"] else "—"
                  for t in tipos]
        lineas.append(f"| {x['motor']} | " + " | ".join(celdas) + " |")
    return "\n".join(lineas)


def calibrado(notas: list[dict]) -> bool:
    """Los motores vienen de más débil a más fuerte: la pérdida debe bajar."""
    p = [x["perdidaMedia"] for x in notas]
    return all(a > b for a, b in zip(p, p[1:]))


def main(argv=None) -> int:
    import json
    import time

    ap = argparse.ArgumentParser(prog="myl_sim.precision")
    sub = ap.add_subparsers(dest="cmd", required=True)
    u = sub.add_parser("partida", help="precisión de una partida entre dos mazos")
    u.add_argument("mazo_a")
    u.add_argument("mazo_b")
    u.add_argument("--seed", type=int, default=1)
    u.add_argument("--jugador", default="heuristico")
    u.add_argument("--procesos", type=int)
    n = sub.add_parser("nota", help="nota del juez para uno o más motores (de débil a fuerte)")
    n.add_argument("motores", nargs="*", default=list(NIVELES_CALIBRACION))
    n.add_argument("--partidas", type=int, default=20)
    n.add_argument("--decisiones", type=int, default=12, help="decisiones revisadas por partida")
    n.add_argument("--seed", type=int, default=1)
    n.add_argument("--muestras", type=int, default=MUESTRAS)
    n.add_argument("--max-muestras", type=int, default=MAX_MUESTRAS)
    n.add_argument("--turnos", type=int, default=TURNOS)
    n.add_argument("--procesos", type=int)
    n.add_argument("--salida", help="nombre del archivo en cache/precision/ (sin extensión)")
    args = ap.parse_args(argv)
    from . import busqueda_vigilia  # noqa: F401 - registra los buscadores

    if args.cmd == "nota":
        notas = []
        inicio = time.monotonic()
        for motor in args.motores:
            r = nota_motor(motor, args.partidas, seed=args.seed, max_decisiones=args.decisiones,
                           muestras=args.muestras, max_muestras=args.max_muestras, turnos=args.turnos,
                           procesos=args.procesos, log=lambda t: print(t, flush=True))
            notas.append(r)
            print(f"{motor}: pierde {r['perdidaMedia']} pts por decisión (IC95 {r['ic95'][0]} a {r['ic95'][1]}) "
                  f"en {r['decisiones']} decisiones · {time.monotonic() - inicio:.0f} s", flush=True)
            if args.salida:
                _carpeta().mkdir(parents=True, exist_ok=True)
                (_carpeta() / f"{args.salida}.json").write_text(
                    json.dumps(notas, ensure_ascii=False, indent=1), encoding="utf-8")
                (_carpeta() / f"{args.salida}.md").write_text(notas_md(notas) + "\n", encoding="utf-8")
        print(notas_md(notas))
        if len(notas) > 1:
            print("Calibrado: la pérdida baja con cada nivel." if calibrado(notas)
                  else "SIN CALIBRAR: la pérdida no baja de forma ordenada con el nivel.")
        return 0
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
