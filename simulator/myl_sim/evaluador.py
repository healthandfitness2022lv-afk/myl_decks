"""Evaluador de cartas nuevas: ¿entra en los mazos de su raza?

Para cada mazo completo de la raza y formato de la carta, prueba meter 1, 2
y 3 copias (lo que permita la Ban List) en lugar de cada carta del mismo tipo,
con la misma maquinaria del optimizador: screening corto contra el meta,
successive halving y confirmación con semillas nuevas. Una copia se acepta
solo si mejora con confianza (IC95 > 0); si se aceptó una, prueba la
siguiente.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.evaluador <id_carta>
  .venv/Scripts/python -m myl_sim.evaluador <id_carta> --cache --n0 4 --confirmar 20
"""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

from .datos import CACHE, Mazo, carta_desde_doc
from .meta import CARPETA, raciales_del_cache
from .optimizador import MAX_COPIAS, optimizar


def cargar_carta(cid: str, usar_cache: bool = True):
    """La carta desde algún mazo del caché o, si no está, desde la app."""
    if usar_cache:
        for f in CACHE.glob("mazo_*.json"):
            d = json.loads(f.read_text(encoding="utf-8"))
            for c in d.get("cartas", []) + d.get("side", []):
                if c["id"] == cid:
                    return carta_desde_doc(cid, c)
    from .datos import _cartas_doc

    docs = _cartas_doc([cid])
    if cid not in docs:
        raise ValueError(f"No existe la carta {cid}")
    return carta_desde_doc(cid, docs[cid])


def evaluar(carta, mazos: list[Mazo], rivales: list[Mazo], *, ban: dict | None = None,
            n0: int = 4, n_conf: int = 20, seed: int = 1, jugador: str = "heuristico",
            procesos: int | None = None, log=print) -> dict:
    maximo = min(MAX_COPIAS, (ban or {}).get(carta.id, MAX_COPIAS))
    filas = []
    for m in mazos:
        ya = sum(1 for c in m.cartas if c.id == carta.id)
        if ya >= maximo:
            filas.append({"mazo": m.nombre, "id": m.id, "yaTiene": ya, "copias": 0, "dif": 0.0,
                          "ic95": [0.0, 0.0], "cambios": [], "nota": "ya la usa al máximo"})
            continue
        prueba = copy.copy(m)
        prueba.side = [carta] * (maximo - ya)
        log(f"== {m.nombre}: probando {carta.nombre} (hasta {maximo - ya} copias)")
        r = optimizar(prueba, [x for x in rivales if x.id != m.id], {x.id: 1.0 for x in rivales}, [],
                      rondas=maximo - ya, candidatos=60, n0=n0, n_conf=n_conf, seed=seed,
                      jugador=jugador, procesos=procesos, ban=ban, solo_side=True, log=log)
        aceptadas = [ro for ro in r["rondas"] if ro.get("aceptada")]
        ultima = next((c for c in aceptadas[-1]["confirmadas"] if c["etiqueta"] == aceptadas[-1]["aceptada"]),
                      None) if aceptadas else None
        mejor = r["rondas"][0]["confirmadas"][0] if r["rondas"] and r["rondas"][0]["confirmadas"] else None
        filas.append({
            "mazo": m.nombre, "id": m.id, "yaTiene": ya, "copias": len(aceptadas),
            "cambios": r["cambiosAceptados"],
            "winrateBase": r["rondas"][0]["winrateBase"] if r["rondas"] else None,
            "dif": ultima["dif"] if ultima else (mejor["dif"] if mejor else 0.0),
            "ic95": ultima["ic95"] if ultima else (mejor["ic95"] if mejor else [0.0, 0.0]),
            "mejorIntento": mejor["etiqueta"] if mejor else None,
        })
    entra = [f for f in filas if f["copias"] > 0]
    return {"carta": {"id": carta.id, "nombre": carta.nombre, "raza": carta.raza, "tipo": carta.tipo.value},
            "copiasMaximas": maximo, "rivales": len(rivales), "mazos": filas,
            "veredicto": (f"Entra en {len(entra)} de {len(filas)} mazos de su raza"
                          if entra else f"No mejora ninguno de los {len(filas)} mazos de su raza")}


def informe_md(r: dict) -> str:
    c = r["carta"]
    out = [f"# Evaluación de carta · {c['nombre']}", "",
           f"{c['tipo']} · {c['raza']} · hasta {r['copiasMaximas']} copias · contra {r['rivales']} mazos", "",
           f"**{r['veredicto']}.**", "",
           "| Mazo | Copias que entran | Cambios | Diferencia | IC95 |", "|---|---|---|---|---|"]
    for f in sorted(r["mazos"], key=lambda f: -f["dif"]):
        cambios = " · ".join(f"−{a} +{b}" for a, b in f["cambios"]) or (f.get("nota") or f"mejor intento: {f.get('mejorIntento') or '—'}")
        out.append(f"| {f['mazo']} | {f['copias']} | {cambios} | {f['dif'] * 100:+.1f} pts | "
                   f"{f['ic95'][0] * 100:+.1f} a {f['ic95'][1] * 100:+.1f} |")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="myl_sim.evaluador", description=__doc__.split("\n")[0])
    ap.add_argument("carta", help="id de la carta (cards/{id})")
    ap.add_argument("--n0", type=int, default=4, help="partidas por rival en el primer screening")
    ap.add_argument("--confirmar", type=int, default=20, help="partidas por rival en la confirmación")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jugador", default="heuristico")
    ap.add_argument("--procesos", type=int)
    ap.add_argument("--cache", action="store_true", help="carta, mazos y Ban List desde simulator/cache")
    ap.add_argument("--salida", type=Path)
    a = ap.parse_args(argv)

    carta = cargar_carta(a.carta, usar_cache=True)
    if not carta.programada:
        print(f"Ojo: {carta.nombre} no está marcada como revisada; se evalúa sin su habilidad.")
    if a.cache:
        todos = raciales_del_cache()
    else:
        from .datos import cargar_todos

        from .datos import solo_validos

        todos = solo_validos([m for m in cargar_todos("racial", notables=True) if not m.sin_programar()], avisar=True)
    try:
        from .datos import cargar_ban_list

        ban = cargar_ban_list("racial", usar_cache=a.cache) or None
    except Exception:  # noqa: BLE001 - sin credencial: sin Ban List
        ban = None
    mazos = [m for m in todos if m.raza == carta.raza] if carta.raza else todos
    print(f"{carta.nombre}: {len(mazos)} mazos de su raza, {len(todos)} rivales")
    r = evaluar(carta, mazos, todos, ban=ban, n0=a.n0, n_conf=a.confirmar, seed=a.seed,
                jugador=a.jugador, procesos=a.procesos)
    r["creado"] = datetime.now(timezone.utc).isoformat()
    salida = a.salida or CARPETA / "evaluaciones" / f"carta_{carta.id}_{datetime.now():%Y%m%d_%H%M}"
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.with_suffix(".json").write_text(json.dumps(r, ensure_ascii=False, indent=1), encoding="utf-8")
    salida.with_suffix(".md").write_text(informe_md(r), encoding="utf-8")
    print(r["veredicto"])
    print(f"Informe: {salida.with_suffix('.md')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
