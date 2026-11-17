"""Los tres filtros que debe pasar un cambio de IA antes de adoptarse.

1. **Arena**: el motor nuevo contra el de referencia, por pares (mismos mazos,
   semilla e inicial). Pasa si no pierde con claridad (el IC95 no queda entero
   bajo 50%) y se adopta como mejora solo si queda entero sobre 50%.
2. **Juez**: puntos perdidos por decisión (`precision.nota_motor`, el rival con
   la mano oculta). Pasa si no empeora con claridad.
3. **Banco**: posiciones resueltas (`posiciones.puntaje`). Pasa si no baja.

Con búsqueda hacen falta al menos 300 pares para ver diferencias de 3 puntos;
con menos, el resultado dice «sin diferencia clara» y no alcanza para adoptar.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.filtro vigilia_turno busqueda_vigilia --pares 300
  .venv/Scripts/python -m myl_sim.filtro heuristico heuristico@v1115b --pares 600 --partidas-juez 60
"""

from __future__ import annotations

import argparse
import json
import time

from .datos import CACHE


def evaluar(nuevo: str, referencia: str, *, pares: int = 300, partidas_juez: int = 40, decisiones: int = 12,
            seed: int = 1, procesos: int | None = None, log=print) -> dict:
    from . import arena, posiciones, precision
    from .meta import raciales_del_cache

    inicio = time.monotonic()
    partidas = arena.jugar([nuevo, referencia], raciales_del_cache(), pares, seed=seed, procesos=procesos)
    d = arena.duelo(partidas, arena.identidad(nuevo), arena.identidad(referencia)) or {}
    log(f"Arena: {d.get('puntos', 0) * 100:.1f}% (IC95 {d.get('ic95', [0, 0])[0] * 100:.1f}–"
        f"{d.get('ic95', [0, 0])[1] * 100:.1f}) en {d.get('pares', 0)} pares · {time.monotonic() - inicio:.0f} s")
    notas = {}
    for motor in (nuevo, referencia):
        n = precision.nota_motor(motor, partidas_juez, seed=seed, max_decisiones=decisiones, procesos=procesos)
        notas[motor] = {k: n[k] for k in ("decisiones", "perdidaMedia", "ic95", "acierto")}
        log(f"Juez {motor}: pierde {n['perdidaMedia']} pts por decisión (IC95 {n['ic95'][0]} a {n['ic95'][1]}) "
            f"en {n['decisiones']} decisiones")
    banco = {}
    for motor in (nuevo, referencia):
        b = posiciones.puntaje(posiciones._clase_de(motor))
        banco[motor] = {"resueltas": b["resueltas"], "total": b["total"]}
        log(f"Banco {motor}: {b['resueltas']} de {b['total']}")
    ic = d.get("ic95", [0.0, 1.0])
    pasa_arena = ic[1] >= 0.5
    pasa_juez = notas[nuevo]["ic95"][0] <= notas[referencia]["ic95"][1]
    pasa_banco = banco[nuevo]["resueltas"] >= banco[referencia]["resueltas"]
    mejora = ic[0] > 0.5 or notas[nuevo]["ic95"][1] < notas[referencia]["ic95"][0]
    veredicto = ("NO ADOPTAR: empeora" if not (pasa_arena and pasa_juez and pasa_banco)
                 else "ADOPTAR: mejora medida" if mejora
                 else "SIN DIFERENCIA CLARA: adoptar solo si corrige posiciones del banco sin costo")
    out = {"nuevo": nuevo, "referencia": referencia, "arena": d, "juez": notas, "banco": banco,
           "pasa": {"arena": pasa_arena, "juez": pasa_juez, "banco": pasa_banco}, "veredicto": veredicto}
    carpeta = CACHE / "filtro"
    carpeta.mkdir(parents=True, exist_ok=True)
    nombre = f"{nuevo}_vs_{referencia}_{seed}".replace("@", "-").replace("#", "-")
    (carpeta / f"{nombre}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    log(veredicto)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.filtro")
    ap.add_argument("nuevo")
    ap.add_argument("referencia")
    ap.add_argument("--pares", type=int, default=300)
    ap.add_argument("--partidas-juez", type=int, default=40)
    ap.add_argument("--decisiones", type=int, default=12)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--procesos", type=int)
    a = ap.parse_args(argv)
    evaluar(a.nuevo, a.referencia, pares=a.pares, partidas_juez=a.partidas_juez, decisiones=a.decisiones,
            seed=a.seed, procesos=a.procesos, log=lambda t: print(t, flush=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
