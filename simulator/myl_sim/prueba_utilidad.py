"""Prueba de `busqueda_utilidad`: mazo A contra mazo B, ambos con la IA por
utilidad, con bitácora legible de cada decisión.

    python -m myl_sim.prueba_utilidad <id_a> <id_b> [--partidas 1] [--rollouts 6] [--seed 1] [--salida dir]

Solo lee el caché local (cache/mazo_<id>.json); no toca Firestore.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from .busqueda_utilidad import BuscadorUtilidad, bitacora_texto
from .datos import CACHE, Mazo, problemas_mazo
from .motor import Partida


def cargar(mid: str) -> Mazo:
    m = Mazo.from_json(json.loads((CACHE / f"mazo_{mid}.json").read_text(encoding="utf-8")))
    problemas = problemas_mazo(m)
    conteo: dict[str, int] = {}
    for c in m.cartas:
        if "única" in (c.texto or "").lower():
            conteo[c.nombre] = conteo.get(c.nombre, 0) + 1
    problemas += [f"{n} ×{k} (Única)" for n, k in conteo.items() if k > 1]
    if problemas:
        raise SystemExit(f"{m.nombre} fuera de reglamento: {'; '.join(problemas)}")
    return m


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--partidas", type=int, default=1)
    ap.add_argument("--rollouts", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--salida", default=str(CACHE / "utilidad"))
    args = ap.parse_args(argv)
    a, b = cargar(args.a), cargar(args.b)
    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    resumen = []
    for k in range(args.partidas):
        seed = args.seed + k
        jug = (BuscadorUtilidad(seed * 2, rollouts=args.rollouts), BuscadorUtilidad(seed * 2 + 1, rollouts=args.rollouts))
        jug[1].bitacora = jug[0].bitacora  # una sola bitácora, en orden real
        inicio = time.monotonic()
        p = Partida((a.cartas, b.cartas), jug, nombres=(a.nombre, b.nombre), inicial=k % 2, seed=seed)
        r = p.jugar()
        seg = time.monotonic() - inicio
        g = r.ganador
        ganador = a.nombre if g == 0 else b.nombre if g == 1 else "empate"
        bit = jug[0].bitacora
        titulo = (f"Partida {k + 1}: {a.nombre} (J0) contra {b.nombre} (J1) · empieza J{k % 2} · semilla {seed}\n"
                  f"Ganador: {ganador} · turnos propios {p.turnos_propios} · castillos al final "
                  f"{len(p.j(0).mazo)} / {len(p.j(1).mazo)} · {seg / 60:.1f} min · "
                  f"{len(bit)} decisiones simuladas, {args.rollouts} rollouts por candidata")
        (salida / f"partida_{seed}.txt").write_text(bitacora_texto(bit, titulo), encoding="utf-8")
        (salida / f"partida_{seed}.json").write_text(json.dumps(bit, ensure_ascii=False, indent=1), encoding="utf-8")
        resumen.append({"seed": seed, "ganador": ganador, "turnos": p.turnos_propios,
                        "castillos": [len(p.j(0).mazo), len(p.j(1).mazo)], "minutos": round(seg / 60, 1),
                        "decisiones": len(bit), "causa": getattr(p.e, "causa", None)})
        print(json.dumps(resumen[-1], ensure_ascii=False), flush=True)
    (salida / "resumen.json").write_text(json.dumps(resumen, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
