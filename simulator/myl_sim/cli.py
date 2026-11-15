"""Uso desde myl_decks/simulator/:

    .venv/Scripts/python -m myl_sim.cli mazos
    .venv/Scripts/python -m myl_sim.cli simular <deckA> <deckB> -n 1000
    .venv/Scripts/python -m myl_sim.cli partida <deckA> <deckB>     (una partida narrada)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

from .datos import cargar_mazo, exigir_validos, listar_mazos, uid_por_email
from .jugadores import JUGADORES
from .motor import Partida
from .simulacion import simular
from .entrenamiento import generar_episodios

DUENO = "hecturnicolas@gmail.com"


def _pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def imprimir_informe(r: dict) -> None:
    a, b = r["mazoA"]["nombre"], r["mazoB"]["nombre"]
    lo, hi = r["ic95A"]
    print(f"\n{a}  vs  {b}   ({r['validas']} partidas, jugador {r['jugador']})")
    print(f"  Winrate {a}: {_pct(r['winrateA'])}  (IC 95 %: {_pct(lo)} – {_pct(hi)})")
    print(f"  Victorias A/B/empates: {r['victoriasA']} / {r['victoriasB']} / {r['empates']}")
    if r["anomalas"]:
        print(f"  ⚠ {r['anomalas']} partidas anómalas (superaron el límite de turnos)")
    v = r["ventajaInicial"]
    print(f"  Gana el que empieza: {_pct(v['winrateDelQueEmpieza'])}")
    print(f"    {a} cuando empieza A: {_pct(v['aEmpieza']['winrateA'])} · cuando empieza B: {_pct(v['bEmpieza']['winrateA'])}")
    t = r["turnos"]
    print(f"  Turnos: promedio {t['promedio']:.1f}, mediana {t.get('mediana', 0)}, rango {t['min']}–{t['max']}")
    print("  Causas de victoria:")
    for c in r["causas"]:
        print(f"    {c['ganador']} por {c['causa']}: {c['partidas']}")
    for lado, nombre in (("A", a), ("B", b)):
        imp = r[f"impacto{lado}"]
        if imp:
            print(f"  Impacto por carta ({nombre}) – mejores y peores:")
            for x in imp[:5] + ([{"carta": "…"}] if len(imp) > 10 else []) + imp[-5:]:
                if "diferencia" not in x:
                    print("    …")
                    continue
                print(f"    {x['carta']:<32} {x['diferencia'] * 100:+6.1f} pts  (jugada en {x['jugadaEn']})")
        pend = r[f"sinProgramar{lado}"]
        if pend:
            total = sum(k for _, k in pend)
            print(f"  ⚠ {nombre}: {len(pend)} cartas ({total} copias) con texto aún sin programar")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("mazos")
    for nombre in ("simular", "partida"):
        s = sub.add_parser(nombre)
        s.add_argument("a")
        s.add_argument("b")
        s.add_argument("-n", type=int, default=1000)
        s.add_argument("--seed", type=int, default=1)
        s.add_argument("--jugador", choices=sorted(JUGADORES), default="heuristico")
        s.add_argument("--cache", action="store_true", help="usar mazos guardados en simulator/cache")
        s.add_argument("--json", action="store_true")
    e = sub.add_parser("recolectar", help="generar episodios locales para entrenamiento")
    e.add_argument("a")
    e.add_argument("b")
    e.add_argument("-n", type=int, default=1000)
    e.add_argument("--seed", type=int, default=1)
    e.add_argument("--salida", default="cache/entrenamiento/episodios.jsonl")
    e.add_argument("--cache", action="store_true", help="usar mazos guardados en simulator/cache")
    args = ap.parse_args(argv)

    uid = uid_por_email(DUENO)
    if args.cmd == "mazos":
        for did, nombre, fmt in listar_mazos(uid):
            print(f"{did}  {fmt:<12} {nombre}")
        return 0

    ma = cargar_mazo(uid, args.a, usar_cache=args.cache)
    mb = cargar_mazo(uid, args.b, usar_cache=args.cache)
    exigir_validos(ma, mb)
    if args.cmd == "recolectar":
        r = generar_episodios(ma, mb, args.n, seed=args.seed, salida=Path(args.salida))
        print(f"{r.partidas} partidas · {r.decisiones} decisiones")
        print(f"Archivo: {r.archivo}")
        print(f"Huellas A/B: {r.huella_a} / {r.huella_b}")
        return 0
    if args.cmd == "partida":
        clase = JUGADORES[args.jugador]
        p = Partida((ma.cartas, mb.cartas), (clase(args.seed), clase(args.seed + 1)), nombres=(ma.nombre, mb.nombre), seed=args.seed, log=True)
        r = p.jugar()
        print("\n".join(p.e.log))
        print(f"\nGanador: {['A', 'B'][r.ganador] if r.ganador in (0, 1) else 'empate'} · {r.turnos} turnos · {r.causa}")
        return 0

    t0 = time.time()
    r = simular(ma, mb, args.n, seed=args.seed, jugador=args.jugador)
    r["segundos"] = round(time.time() - t0, 1)
    if args.json:
        json.dump(r, sys.stdout, ensure_ascii=False, indent=1)
    else:
        imprimir_informe(r)
        print(f"\n  ({r['segundos']} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
