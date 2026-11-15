"""Optimizador progresivo de un mazo contra el meta.

Ronda (se repite sumando los cambios aceptados):
1. **Mutaciones**: cambiar 1 carta por otra del mismo tipo (Oro por Oro,
   Aliado por Aliado, el resto entre sí). Con `--side`, las cartas a probar
   salen del side deck del mazo; si no, de los mazos del caché de esa raza y
   formato. Copias máximas según la Ban List del formato (Firestore).
2. **Screening**: todas las variantes y el mazo base juegan las MISMAS
   partidas (mismas semillas y salida) contra cada mazo del meta.
3. **Successive halving**: se queda la mitad mejor y se duplica el número de
   partidas, hasta que quedan pocas.
4. **Confirmación** con semillas nuevas: diferencia pareada contra el base
   con IC95. Solo se acepta si el límite inferior es > 0.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.optimizador PP3fUsB57Y3tdFoOvzAr --rondas 2
  .venv/Scripts/python -m myl_sim.optimizador PP3fUsB57Y3tdFoOvzAr --meta "BL 2026-11"
  .venv/Scripts/python -m myl_sim.optimizador PP3fUsB57Y3tdFoOvzAr --meta evolutivo
  .venv/Scripts/python -m myl_sim.optimizador PP3fUsB57Y3tdFoOvzAr --side   (prueba el side deck)
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import random
import sys
import time

from .datos import CACHE, Mazo, huella_mazo
from .meta import CARPETA, _jugar, cargar_meta, raciales_del_cache, seed_cruce, _mazos_de
from .modelo import ORO_INICIAL, Tipo

MAX_COPIAS = 3


def _grupo(c) -> str:
    return "oro" if c.tipo == Tipo.ORO else "aliado" if c.tipo == Tipo.ALIADO else "soporte"


@dataclass
class Variante:
    cartas: list
    cambios: list = field(default_factory=list)  # [(sale, entra)] por nombre
    resultados: dict = field(default_factory=dict)  # rival → "1e0x…"

    @property
    def etiqueta(self) -> str:
        return " · ".join(f"−{a} +{b}" for a, b in self.cambios) or "base"


def pool_de(base: Mazo, mazos: list[Mazo], *, ban: dict | None = None,
            solo_side: bool = False, provisionales: bool = False) -> tuple[dict, dict]:
    """Cartas que se pueden probar y su máximo de copias en el mazo.

    - `solo_side`: solo las del side deck del mazo base.
    - si no: las de los mazos del caché de la misma raza y formato.
    Copias máximas: la Ban List (`ban`, carta → máximo; 3 si no aparece) o,
    sin ella, las que se ven en esos mazos (≤ 3)."""
    cartas, maximo = {}, Counter()
    if solo_side:
        cartas = {c.id: c for c in base.side}
    else:
        # El side deck siempre entra (Héctor: "no sea excluyente").
        for c in base.side:
            cartas[c.id] = c
            maximo[c.id] = MAX_COPIAS
        for m in mazos:
            # Un mazo con cartas pendientes igual aporta sus cartas programadas.
            if m.raza != base.raza or m.formato != base.formato:
                continue
            for cid, k in Counter(c.id for c in m.cartas).items():
                maximo[cid] = max(maximo[cid], min(MAX_COPIAS, k))
            for c in m.cartas:
                cartas[c.id] = c
    for cid, k in Counter(c.id for c in base.cartas).items():
        maximo[cid] = max(maximo[cid], k)
    if ban is not None or solo_side:
        for cid in cartas:
            maximo[cid] = min(MAX_COPIAS, (ban or {}).get(cid, MAX_COPIAS))
    cartas.update({c.id: c for c in base.cartas})
    cartas.pop(ORO_INICIAL.id, None)
    # Sin programar solo juegan sus estadísticas: fuera, salvo `provisionales`.
    if not provisionales:
        cartas = {cid: c for cid, c in cartas.items() if c.programada or cid in {x.id for x in base.cartas}}
    return cartas, maximo


def mutaciones(base: list, pool: dict, maximo: Counter, rng: random.Random, cuantas: int,
               prioridad: set = frozenset()) -> list[tuple]:
    """Hasta `cuantas` cambios (sale_id, entra_id) válidos y distintos."""
    conteo = Counter(c.id for c in base)
    salen = sorted({c.id for c in base if c.id != ORO_INICIAL.id})
    por_id = {c.id: c for c in base}
    todas = []
    for s in salen:
        for e, carta in pool.items():
            if e == s or _grupo(carta) != _grupo(por_id[s]) or conteo[e] >= maximo[e]:
                continue
            todas.append((s, e))
    rng.shuffle(todas)
    # Primero las que meten cartas del side deck, después el resto al azar.
    todas.sort(key=lambda x: x[1] not in prioridad)
    return todas[:cuantas]


def aplicar(cartas: list, sale: str, entra, pool: dict) -> list:
    out = list(cartas)
    i = next(k for k in range(len(out) - 1, -1, -1) if out[k].id == sale)
    out[i] = pool[entra]
    return out


def jugar_contra_meta(variantes: list[Variante], rivales: list[Mazo], n: int, seed: int,
                      jugador: str, procesos: int | None) -> None:
    """Completa hasta n partidas por rival en cada variante, con las mismas
    semillas para todas (comparación pareada)."""
    from concurrent.futures import ProcessPoolExecutor

    trabajos = []
    for vi, v in enumerate(variantes):
        for r in rivales:
            hechas = len(v.resultados.get(r.id, ""))
            s = seed_cruce(huella_mazo(r), "opt", seed)
            for desde in range(hechas, n, 8):
                trabajos.append((vi, r.id, desde, (v.cartas, r.cartas, s, desde, min(n, desde + 8), jugador, None)))
    if not trabajos:
        return
    with ProcessPoolExecutor(procesos or os.cpu_count() or 1) as ex:
        res = list(ex.map(_jugar, [t[3] for t in trabajos], chunksize=4))
    trozos: dict = {}
    for (vi, rid, desde, _), r in zip(trabajos, res):
        trozos.setdefault((vi, rid), []).append((desde, "".join(r)))
    for (vi, rid), partes in trozos.items():
        variantes[vi].resultados[rid] = variantes[vi].resultados.get(rid, "") + "".join(x for _, x in sorted(partes))


def _punto(c: str) -> float | None:
    return None if c == "x" else 1.0 if c == "1" else 0.5 if c == "e" else 0.0


def diferencia(v: Variante, base: Variante, rivales: list[Mazo], pesos: dict) -> dict:
    """Diferencia pareada ponderada por el meta (variante − base)."""
    total = sum(pesos[r.id] for r in rivales) or 1.0
    media = var = 0.0
    por_rival = {}
    for r in rivales:
        d = [a - b for a, b in ((_punto(x), _punto(y)) for x, y in zip(v.resultados[r.id], base.resultados[r.id]))
             if a is not None and b is not None]
        if not d:
            continue
        w = pesos[r.id] / total
        m = sum(d) / len(d)
        s2 = sum((x - m) ** 2 for x in d) / max(1, len(d) - 1)
        media += w * m
        var += w * w * s2 / len(d)
        por_rival[r.nombre] = m
    ee = math.sqrt(var)
    return {"dif": media, "ic95": [media - 1.96 * ee, media + 1.96 * ee], "porRival": por_rival}


def winrate(v: Variante, rivales: list[Mazo], pesos: dict) -> float:
    total = sum(pesos[r.id] for r in rivales) or 1.0
    out = 0.0
    for r in rivales:
        ps = [p for p in map(_punto, v.resultados[r.id]) if p is not None]
        out += pesos[r.id] / total * (sum(ps) / len(ps) if ps else 0.5)
    return out


def ronda(base: Variante, pool: dict, maximo: Counter, rivales: list[Mazo], pesos: dict, *,
          prioridad: set = frozenset(),
          candidatos: int, n0: int, n_conf: int, quedan: int, seed: int, jugador: str,
          procesos: int | None, log=print) -> dict:
    rng = random.Random(seed)
    nombres = {c.id: c.nombre for c in pool.values()}
    variantes = [Variante(base.cartas, list(base.cambios))]
    for s, e in mutaciones(base.cartas, pool, maximo, rng, candidatos, prioridad):
        variantes.append(Variante(aplicar(base.cartas, s, e, pool), base.cambios + [(nombres[s], nombres[e])]))
    n = n0
    vivos = variantes
    historial = []
    while True:
        t0 = time.time()
        jugar_contra_meta(vivos, rivales, n, seed, jugador, procesos)
        difs = sorted(((diferencia(v, vivos[0], rivales, pesos)["dif"], k) for k, v in enumerate(vivos) if k),
                      reverse=True)
        historial.append({"partidasPorRival": n, "variantes": len(vivos) - 1})
        log(f"  screening {len(vivos) - 1} variantes × {n} partidas/rival ({time.time() - t0:.0f}s); "
            f"mejor {difs[0][0] * 100:+.1f} pts" if difs else "  sin variantes")
        if len(vivos) - 1 <= quedan or not difs:
            break
        mitad = max(quedan, (len(vivos) - 1) // 2)
        vivos = [vivos[0]] + [vivos[k] for _, k in difs[:mitad]]
        n *= 2
    # Confirmación con semillas nuevas, solo las que van ganando.
    finalistas = [vivos[k] for d, k in difs if d > 0]
    conf_base = Variante(base.cartas, list(base.cambios))
    conf = [Variante(v.cartas, v.cambios) for v in finalistas]
    t0 = time.time()
    jugar_contra_meta([conf_base] + conf, rivales, n_conf, seed + 7919, jugador, procesos)
    resultados = []
    for v in conf:
        d = diferencia(v, conf_base, rivales, pesos)
        resultados.append({"cambios": v.cambios, "etiqueta": v.etiqueta, **d,
                           "winrate": winrate(v, rivales, pesos), "cartas": v.cartas})
    resultados.sort(key=lambda x: -x["dif"])
    log(f"  confirmación {len(conf)} finalistas × {n_conf} partidas/rival ({time.time() - t0:.0f}s)")
    for r in resultados:
        log(f"    {r['etiqueta']}: {r['dif'] * 100:+.1f} pts [{r['ic95'][0] * 100:+.1f}, {r['ic95'][1] * 100:+.1f}]")
    return {"winrateBase": winrate(conf_base, rivales, pesos), "screening": historial,
            "confirmadas": resultados}


def optimizar(base: Mazo, rivales: list[Mazo], pesos: dict, pool_mazos: list[Mazo], *, rondas: int = 1,
              candidatos: int = 24, n0: int = 6, n_conf: int = 40, quedan: int = 3, seed: int = 1,
              jugador: str = "heuristico", procesos: int | None = None, ban: dict | None = None,
              solo_side: bool = False, log=print) -> dict:
    pool, maximo = pool_de(base, pool_mazos, ban=ban, solo_side=solo_side)
    actual = Variante(list(base.cartas))
    salida = {"base": {"id": base.id, "nombre": base.nombre, "huella": huella_mazo(base)},
              "rivales": [r.nombre for r in rivales], "pool": len(pool),
              "origenPool": "side deck" if solo_side else
              ("side deck (primero) + mazos de la raza" if base.side else "mazos de la raza"),
              "banList": ban is not None, "rondas": []}
    for k in range(rondas):
        log(f"Ronda {k + 1}: {base.nombre} · {' · '.join(f'−{a} +{b}' for a, b in actual.cambios) or 'lista original'}")
        r = ronda(actual, pool, maximo, rivales, pesos, prioridad={c.id for c in base.side},
                  candidatos=candidatos, n0=n0, n_conf=n_conf,
                  quedan=quedan, seed=seed + 1000 * k, jugador=jugador, procesos=procesos, log=log)
        aceptada = next((x for x in r["confirmadas"] if x["ic95"][0] > 0), None)
        r["aceptada"] = aceptada["etiqueta"] if aceptada else None
        salida["rondas"].append({**r, "confirmadas": [{x: y for x, y in c.items() if x != "cartas"}
                                                       for c in r["confirmadas"]]})
        if not aceptada:
            log("  ningún cambio supera al base con confianza; se detiene")
            break
        actual = Variante(aceptada["cartas"], aceptada["cambios"])
    salida["cambiosAceptados"] = actual.cambios
    salida["lista"] = sorted(Counter(c.nombre for c in actual.cartas).items())
    return salida


def informe_md(r: dict) -> str:
    out = [f"# Optimización · {r['base']['nombre']}", "",
           f"Rivales: {len(r['rivales'])} mazos del meta · cartas a probar: {r['origenPool']} · "
           f"copias máximas: {'Ban List' if r.get('banList') else 'según los mazos del caché'}", ""]
    for k, ro in enumerate(r["rondas"], 1):
        out += [f"## Ronda {k}", "", f"Winrate base contra el meta: {ro['winrateBase'] * 100:.1f}%", "",
                "| Cambio | Diferencia | IC95 | Dónde gana / pierde más |", "|---|---|---|---|"]
        for c in ro["confirmadas"]:
            pr = sorted(c["porRival"].items(), key=lambda x: x[1])
            donde = ", ".join(f"{n} {d * 100:+.0f}" for n, d in (pr[-2:][::-1] + pr[:2]))
            out.append(f"| {c['etiqueta']} | {c['dif'] * 100:+.1f} pts | "
                       f"{c['ic95'][0] * 100:+.1f} a {c['ic95'][1] * 100:+.1f} | {donde} |")
        out += ["", f"**Aceptado:** {ro['aceptada'] or 'ninguno (sin ventaja significativa)'}", ""]
    if r["cambiosAceptados"]:
        out += ["## Lista final", ""] + [f"- {k}× {n}" for n, k in r["lista"]]
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="myl_sim.optimizador", description=__doc__.split("\n")[0])
    ap.add_argument("mazo", help="id del mazo a optimizar")
    ap.add_argument("--meta", help='meta guardado, o "evolutivo" (por defecto: raciales del caché, pesos iguales)')
    ap.add_argument("--rondas", type=int, default=1)
    ap.add_argument("--candidatos", type=int, default=24)
    ap.add_argument("--n0", type=int, default=6, help="partidas por rival en el primer screening")
    ap.add_argument("--confirmar", type=int, default=40, help="partidas por rival en la confirmación")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jugador", default="heuristico")
    ap.add_argument("--procesos", type=int)
    ap.add_argument("--side", action="store_true", help="(el side deck siempre se prueba primero)")
    ap.add_argument("--solo-side", action="store_true", help="probar SOLO cartas del side deck")
    ap.add_argument("--notables", action="store_true", help="(siempre incluidas sin --cache)")
    ap.add_argument("--cache", action="store_true", help="mazos y Ban List desde simulator/cache")
    ap.add_argument("--salida", type=Path)
    ap.add_argument("--incluir-pendientes", action="store_true",
                    help="no excluir rivales con cartas sin programar (esas cartas juegan sin habilidad)")
    a = ap.parse_args(argv)

    from .auditoria import _cargar

    todos = raciales_del_cache()
    # El side deck y la Ban List vienen de Firestore (el caché viejo no trae el side).
    base = (_cargar([a.mazo], a.cache)[0] if not a.cache else None) \
        or next((m for m in todos if m.id == a.mazo), None) or _cargar([a.mazo], a.cache)[0]
    try:
        from .datos import cargar_ban_list

        ban = cargar_ban_list(base.formato, usar_cache=a.cache) or None
    except Exception as e:  # sin credencial o sin red: se sigue sin Ban List
        print(f"Ban List no disponible ({e.__class__.__name__}); copias máximas según los mazos del caché")
        ban = None
    if not base.side:
        print(f"{base.nombre} no tiene side deck: se prueban cartas de los mazos de la raza")
    solo_side = a.solo_side and bool(base.side)
    if base.side:
        a.candidatos = max(a.candidatos, 60)
    if a.meta == "evolutivo":
        # Pesos del meta evolutivo de la matriz de raciales (usa el caché de cruces).
        from .meta import _tabla, matriz, pesos_evolutivos, winrates

        rivales = todos
        w = _tabla(winrates(todos, matriz(todos, 40, jugador=a.jugador, procesos=a.procesos)))
        pesos = dict(zip((m.id for m in todos), pesos_evolutivos(w)))
    elif a.meta:
        meta = cargar_meta(a.meta)
        rivales = _mazos_de([x["id"] for x in meta["mazos"]], a.cache)
        pesos = {m.id: float(x.get("peso", 1)) for m, x in zip(rivales, meta["mazos"])}
    else:
        rivales, pesos = todos, {m.id: 1.0 for m in todos}
    if not a.cache and a.meta is None:
        # Rivales frescos desde la app: mazos de todos los jugadores + notables del formato.
        from .datos import cargar_todos

        rivales = cargar_todos(base.formato, notables=True)
        pesos = {m.id: 1.0 for m in rivales}
    fuera = [r.nombre for r in rivales if r.sin_programar()]
    if fuera and a.incluir_pendientes:
        print(f"Incluidos con cartas sin programar (juegan sin su habilidad): {', '.join(fuera)}")
    elif fuera:
        print(f"Sin cartas programadas, quedan fuera: {', '.join(fuera)}")
    rivales = [r for r in rivales if r.id != base.id and (a.incluir_pendientes or not r.sin_programar())]
    from .datos import exigir_validos, solo_validos

    exigir_validos(base, ban=ban)
    rivales = solo_validos(rivales, avisar=True)
    print(f"Rivales: {len(rivales)}")
    pool_mazos = [Mazo.from_json(json.loads(f.read_text(encoding="utf-8"))) for f in CACHE.glob("mazo_*.json")]
    pool_mazos += rivales
    r = optimizar(base, rivales, pesos, pool_mazos, rondas=a.rondas, candidatos=a.candidatos, n0=a.n0,
                  n_conf=a.confirmar, seed=a.seed, jugador=a.jugador, procesos=a.procesos,
                  ban=ban, solo_side=solo_side)
    r["creado"] = datetime.now(timezone.utc).isoformat()
    salida = a.salida or CARPETA / "optimizacion" / f"opt_{base.id}_{datetime.now():%Y%m%d_%H%M}"
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.with_suffix(".json").write_text(json.dumps(r, ensure_ascii=False, indent=1), encoding="utf-8")
    salida.with_suffix(".md").write_text(informe_md(r), encoding="utf-8")
    print(f"Informe: {salida.with_suffix('.md')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
