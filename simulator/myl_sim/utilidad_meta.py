"""Un mazo contra todo el meta con la IA por utilidad en ambos lados.

    python -m myl_sim.utilidad_meta <id> [--partidas 2] [--rollouts 24] [--procesos 10] [--salida dir]

Rivales: los raciales válidos del caché (49 cartas, Ban List, Únicas, todo
programado). Una bitácora legible por partida y `resumen.md` con el winrate
por cruce. Solo lee el caché local.
"""

from __future__ import annotations

import argparse
import json
import time
from multiprocessing import Pool
from pathlib import Path

from .busqueda_utilidad import BuscadorUtilidad, bitacora_texto
from .datos import CACHE, Mazo
from .meta import raciales_del_cache
from .motor import Partida
from .prueba_utilidad import cargar


def _unicas_ok(m: Mazo) -> bool:
    conteo: dict[str, int] = {}
    for c in m.cartas:
        if "única" in (c.texto or "").lower():
            conteo[c.nombre] = conteo.get(c.nombre, 0) + 1
    return all(k <= 1 for k in conteo.values())


def _cargar(mid: str) -> Mazo:
    m = Mazo.from_json(json.loads((CACHE / f"mazo_{mid}.json").read_text(encoding="utf-8")))
    if m.nombre == m.id:  # mazos sin nombre: como en la matriz del meta
        m.nombre = f"{m.raza} ({m.id[:4]})"
    return m


def _jugar(args) -> dict:
    a_id, b_id, k, seed, rollouts, salida = args
    a, b = _cargar(a_id), _cargar(b_id)
    jug = (BuscadorUtilidad(seed * 2, rollouts=rollouts), BuscadorUtilidad(seed * 2 + 1, rollouts=rollouts))
    jug[1].bitacora = jug[0].bitacora
    inicio = time.monotonic()
    try:
        p = Partida((a.cartas, b.cartas), jug, nombres=(a.nombre, b.nombre), inicial=k % 2, seed=seed)
        g = p.jugar().ganador
        error = None
    except Exception as e:  # noqa: BLE001
        g, error, p = -2, f"{type(e).__name__}: {e}"[:200], None
    seg = time.monotonic() - inicio
    out = {"rival": b.nombre, "rival_id": b_id, "seed": seed, "empieza": "A" if k % 2 == 0 else "rival",
           "gano": g == 0, "ganador": g, "min": round(seg / 60, 1), "decisiones": len(jug[0].bitacora)}
    if p is not None:
        out.update(turnos=p.turnos_propios, castillos=[len(p.j(0).mazo), len(p.j(1).mazo)])
        titulo = (f"{a.nombre} (J0) contra {b.nombre} (J1) · empieza {out['empieza']} · semilla {seed}\n"
                  f"Ganador: {a.nombre if g == 0 else b.nombre if g == 1 else 'empate'} · turnos propios "
                  f"{p.turnos_propios} · castillos {out['castillos']} · {out['min']} min · "
                  f"{out['decisiones']} decisiones, {rollouts} rollouts por candidata")
        nombre = f"{b_id}_{seed}"
        (Path(salida) / f"{nombre}.txt").write_text(bitacora_texto(jug[0].bitacora, titulo), encoding="utf-8")
    if error:
        out["error"] = error
    return out


def resumen_md(a: Mazo, filas: list[dict], rollouts: int) -> str:
    por: dict[str, list[dict]] = {}
    for f in filas:
        por.setdefault(f["rival"], []).append(f)
    validas = [f for f in filas if "error" not in f]
    g = sum(f["gano"] for f in validas)
    out = [f"# {a.nombre} contra el meta · IA por utilidad ({rollouts} rollouts por candidata)", "",
           f"{len(validas)} partidas · ganó {g} ({g / max(1, len(validas)):.0%}) · "
           f"{len(por)} rivales", "",
           "| Rival | Partidas | Ganadas | Turnos (victorias) | Castillo propio al ganar |", "|---|---|---|---|---|"]
    for rival, fs in sorted(por.items(), key=lambda x: (sum(f["gano"] for f in x[1]) / len(x[1]), x[0])):
        gan = [f for f in fs if f["gano"]]
        tv = f"{sum(f['turnos'][0] for f in gan) / len(gan):.1f}" if gan else "—"
        cv = f"{sum(f['castillos'][0] for f in gan) / len(gan):.1f}" if gan else "—"
        err = " (error)" if any("error" in f for f in fs) else ""
        out.append(f"| {rival}{err} | {len(fs)} | {len(gan)} | {tv} | {cv} |")
    return "\n".join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("--partidas", type=int, default=2)
    ap.add_argument("--rollouts", type=int, default=24)
    ap.add_argument("--procesos", type=int, default=10)
    ap.add_argument("--seed", type=int, default=100)
    ap.add_argument("--salida", default=str(CACHE / "utilidad_meta"))
    args = ap.parse_args(argv)
    cargar(args.a)  # valida Ban List y Únicas
    a = _cargar(args.a)
    rivales = [m for m in raciales_del_cache() if m.id != a.id and _unicas_ok(m)]
    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)
    tareas = [(a.id, m.id, k, args.seed + 1000 * i + k, args.rollouts, str(salida))
              for i, m in enumerate(rivales) for k in range(args.partidas)]
    print(f"{a.nombre}: {len(rivales)} rivales, {len(tareas)} partidas", flush=True)
    filas, inicio = [], time.monotonic()
    with Pool(args.procesos) as pool:
        for f in pool.imap_unordered(_jugar, tareas):
            filas.append(f)
            g = sum(x["gano"] for x in filas)
            print(json.dumps({"hechas": len(filas), "total": len(tareas), "ganadas": g,
                              "min": round((time.monotonic() - inicio) / 60, 1), **f}, ensure_ascii=False), flush=True)
            (salida / "resumen.json").write_text(json.dumps(filas, ensure_ascii=False, indent=1), encoding="utf-8")
            (salida / "resumen.md").write_text(resumen_md(a, filas, args.rollouts), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
