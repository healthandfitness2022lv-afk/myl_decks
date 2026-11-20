"""Medición de motores de IA al mejor de 3 (como en torneo).

Un **match** son hasta 3 partidas con los mismos mazos: el primero que gana
2 se lleva el match. La primera partida la empieza el jugador que dice la
semilla; después empieza quien perdió la anterior. Cada match se juega dos
veces con los asientos y los mazos intercambiados (par de matches), así un
mazo más fuerte no favorece a ningún motor.

Se reporta el winrate de X por **match** y por **partida**, con IC95.

    python -m myl_sim.medir_bo3 X Y [--pares 6] [--mazos id...] [--seed 1] [--procesos 10]

Motores: los de `arena` (heuristico, busqueda_vigilia, experto, nivelN...) y
`utilidad` / `utilidadN` (IA por utilidad con N rollouts, 6 por defecto).
Solo lee el caché local; guarda en cache/arena/bo3.jsonl.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time

from .arena import CARPETA, crear as crear_arena, identidad

BO3 = CARPETA / "bo3.jsonl"


def crear(motor: str, seed: int):
    if motor.startswith("utilidad"):
        from .busqueda_utilidad import BuscadorUtilidad

        n = int(motor[len("utilidad"):] or 6)
        return BuscadorUtilidad(seed, rollouts=n)
    if motor == "vigilia_estilo":  # la IA buena + estilo del rival (estilo.py)
        j = crear_arena("busqueda_vigilia", seed)
        j.modelar_rival = True
        return j
    if motor == "vigilia_valor3":  # la IA buena con la valoración reentrenada (valor_estado_v3.json)
        from .busqueda_vigilia import BuscadorVigilia

        return BuscadorVigilia(seed, aprendido=3)
    return crear_arena(motor, seed)


def _nombre(motor: str) -> str:
    return motor if motor.startswith("utilidad") or motor in ("vigilia_estilo", "vigilia_valor3") else identidad(motor)


def jugar_match(x: str, y: str, mazo_x, mazo_y, seed: int) -> dict:
    """Un match al mejor de 3: X juega `mazo_x`, Y juega `mazo_y`.
    `r`: 1 gana X, 0 gana Y, 0.5 empate, None anómala."""
    from .motor import Partida

    partidas, gx, gy, inicial, segundos = [], 0, 0, seed % 2, []
    previo: dict = {}
    estilos: list = []
    for k in range(3):
        if gx == 2 or gy == 2:
            break
        s = seed * 7 + k
        inicio = time.monotonic()
        try:
            jugadores = (crear(x, s * 2), crear(y, s * 2 + 1))  # asiento 0 = X
            p = Partida((mazo_x.cartas, mazo_y.cartas), jugadores, nombres=(mazo_x.nombre, mazo_y.nombre),
                        inicial=inicial, seed=s)
            modela = [i for i, j in enumerate(jugadores) if getattr(j, "modelar_rival", False)]
            if modela:
                from .estilo import Estilo

                # lo visto en las partidas anteriores del match sirve de punto de partida
                p.estilo = Estilo(previo.get(1 - modela[0]))
            g = p.jugar().ganador
            if modela:
                for lado in (0, 1):
                    previo[lado] = p.estilo.resumen(lado)
                estilos.append(previo[1 - modela[0]])
        except Exception as e:  # noqa: BLE001
            return {"error": f"{type(e).__name__}: {e}"[:200], "partidas": partidas}
        segundos.append(round(time.monotonic() - inicio, 1))
        r = None if g == -2 else 0.5 if g == -1 else 1.0 if g == 0 else 0.0
        partidas.append({"inicia": "x" if inicial == 0 else "y", "r": r})
        if r == 1.0:
            gx += 1
            inicial = 1  # empieza quien perdió
        elif r == 0.0:
            gy += 1
            inicial = 0
        else:
            gx += 0.5
            gy += 0.5
            inicial = 1 - inicial
    match = 1.0 if gx > gy else 0.0 if gy > gx else 0.5
    out = {"partidas": partidas, "match": match, "seg": segundos}
    if estilos:
        out["estilo_rival"] = estilos
    return out


def jugar_par(args) -> dict:
    x, y, a, b, seed = args
    m1 = jugar_match(x, y, a, b, seed)
    m2 = jugar_match(x, y, b, a, seed)
    return {"x": _nombre(x), "y": _nombre(y), "a": a.id, "b": b.id, "seed": seed,
            "matches": [m1, m2]}


def _ic(p: float, n: int) -> tuple[float, float]:
    if n == 0:
        return (0.0, 1.0)
    e = 1.96 * math.sqrt(max(p * (1 - p), 1e-9) / n)
    return (max(0.0, p - e), min(1.0, p + e))


def resumen(filas: list[dict]) -> dict:
    matches, partidas, errores, seg = [], [], 0, []
    por_inicio = {"x": [], "y": []}
    for f in filas:
        for m in f["matches"]:
            if "error" in m:
                errores += 1
                continue
            matches.append(m["match"])
            seg.extend(m["seg"])
            for pt in m["partidas"]:
                if pt["r"] is not None:
                    partidas.append(pt["r"])
                    por_inicio[pt["inicia"]].append(pt["r"])
    wm = sum(matches) / len(matches) if matches else 0.0
    wp = sum(partidas) / len(partidas) if partidas else 0.0
    return {"matches": len(matches), "wr_match": wm, "ic_match": _ic(wm, len(matches)),
            "partidas": len(partidas), "wr_partida": wp, "ic_partida": _ic(wp, len(partidas)),
            "wr_x_empieza": (sum(por_inicio["x"]) / len(por_inicio["x"])) if por_inicio["x"] else None,
            "errores": errores, "seg_partida": (sum(seg) / len(seg)) if seg else 0.0}


def texto(x: str, y: str, r: dict) -> str:
    pct = lambda v: f"{v * 100:.1f}%"  # noqa: E731
    return (f"{x} vs {y}\n"
            f"  por match:   {pct(r['wr_match'])} (IC95 {pct(r['ic_match'][0])}–{pct(r['ic_match'][1])}) "
            f"en {r['matches']} matches\n"
            f"  por partida: {pct(r['wr_partida'])} (IC95 {pct(r['ic_partida'][0])}–{pct(r['ic_partida'][1])}) "
            f"en {r['partidas']} partidas\n"
            f"  {r['seg_partida']:.0f} s por partida · {r['errores']} matches con error")


def medir(x: str, y: str, mazos: list, pares: int, *, seed: int = 1, procesos: int | None = None,
          progreso=None, guardar: bool = True) -> dict:
    from concurrent.futures import ProcessPoolExecutor

    rng = random.Random(seed)
    trabajos = []
    for k in range(pares):
        a, b = rng.sample(mazos, 2) if len(mazos) > 1 else (mazos[0], mazos[0])
        trabajos.append((x, y, a, b, seed * 1_000_003 + k))
    filas = []
    with ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 2)) as ex:
        for k, f in enumerate(ex.map(jugar_par, trabajos), 1):
            filas.append(f)
            if guardar:
                CARPETA.mkdir(parents=True, exist_ok=True)
                with BO3.open("a", encoding="utf-8") as fh:
                    fh.write(json.dumps(f, ensure_ascii=False) + "\n")
            if progreso:
                progreso(k, len(trabajos))
    return resumen(filas)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.medir_bo3")
    ap.add_argument("x")
    ap.add_argument("y")
    ap.add_argument("--pares", type=int, default=6)
    ap.add_argument("--mazos", nargs="*")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--procesos", type=int)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    from .meta import _mazos_de, raciales_del_cache

    mazos = _mazos_de(args.mazos, True) if args.mazos else raciales_del_cache()
    inicio = time.monotonic()

    def progreso(k, total):
        print(f"{k}/{total} pares de matches · {time.monotonic() - inicio:.0f} s", flush=True)

    r = medir(args.x, args.y, mazos, args.pares, seed=args.seed, procesos=args.procesos, progreso=progreso)
    print(texto(_nombre(args.x), _nombre(args.y), r))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
