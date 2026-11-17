"""Cobertura de tests por carta: qué cartas de los mazos válidos tienen al
menos un test que las nombra.

Una decisión no puede ser exacta si la simulación resuelve mal una carta. La
auditoría automática revisa invariantes (cartas que desaparecen, Oros
negativos…), no que cada carta haga lo que dice su texto: eso solo lo cubre un
test por carta. Este informe dice cuáles faltan, ordenadas por cuántos mazos
válidos las juegan.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.cobertura_cartas [--top 40]
"""

from __future__ import annotations

import argparse
from pathlib import Path
import unicodedata

from .datos import CACHE

TESTS = Path(__file__).resolve().parents[1] / "tests"
SALIDA = CACHE / "cobertura_cartas.md"


def _plano(texto: str) -> str:
    sin = "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")
    return sin.casefold()


def cobertura() -> dict:
    from .meta import raciales_del_cache

    fuente = _plano("\n".join(f.read_text(encoding="utf-8") for f in sorted(TESTS.glob("test_*.py"))))
    cartas: dict[str, dict] = {}
    for mazo in raciales_del_cache():
        for nombre in {c.nombre for c in mazo.cartas}:
            carta = next(c for c in mazo.cartas if c.nombre == nombre)
            if not carta.habilidades and not (carta.texto or "").strip(". "):
                continue  # sin habilidad no hay nada que probar
            d = cartas.setdefault(nombre, {"mazos": set(), "tipo": carta.tipo.value})
            d["mazos"].add(mazo.nombre)
    con, sin = [], []
    for nombre, d in cartas.items():
        (con if f'"{_plano(nombre)}"' in fuente or f"'{_plano(nombre)}'" in fuente else sin).append(
            {"carta": nombre, "tipo": d["tipo"], "mazos": len(d["mazos"])})
    sin.sort(key=lambda x: (-x["mazos"], x["carta"]))
    total = len(con) + len(sin)
    return {"total": total, "conTest": len(con), "sinTest": sin,
            "porcentaje": round(len(con) / total * 100, 1) if total else None}


def informe_md(c: dict, top: int | None = None) -> str:
    lineas = [f"# Cobertura de tests por carta",
              "",
              f"{c['conTest']} de {c['total']} cartas con habilidad de los mazos válidos tienen un test que las "
              f"nombra ({c['porcentaje']}%). Faltan {len(c['sinTest'])}.",
              "",
              "| Carta sin test | Tipo | Mazos válidos que la juegan |", "|---|---|---|"]
    for x in c["sinTest"][:top]:
        lineas.append(f"| {x['carta']} | {x['tipo']} | {x['mazos']} |")
    return "\n".join(lineas)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.cobertura_cartas")
    ap.add_argument("--top", type=int, default=40)
    args = ap.parse_args(argv)
    c = cobertura()
    SALIDA.write_text(informe_md(c) + "\n", encoding="utf-8")
    print(informe_md(c, args.top))
    print(f"\nLista completa en {SALIDA}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
