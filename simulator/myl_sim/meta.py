"""Matriz del meta v2: todos contra todos, ponderada por frecuencia.

- **Meta**: lista de mazos (propios y notables) con un peso de frecuencia,
  versionada por Ban List (`cache/meta/meta_<nombre>.json`). Sin pesos, todos
  valen lo mismo.
- **Caché por huellas**: cada cruce se guarda por huella de los dos mazos,
  huella del motor (reglas + IA) y jugador. Si nada cambió no se vuelve a
  simular; si se piden más partidas, solo se juegan las que faltan.
- **Semillas estables**: la semilla de un cruce sale de las huellas, no del
  orden de la lista, y la salida se alterna (mitad empieza cada uno).
- **score_meta**: winrate esperado contra el meta = Σ peso·winrate, con IC95.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.meta crear "BL 2026-11" ID1 ID2 ... --peso ID1=3
  .venv/Scripts/python -m myl_sim.meta matriz "BL 2026-11" -n 40
  .venv/Scripts/python -m myl_sim.meta matriz -n 40          (todos los raciales del caché)
  .venv/Scripts/python -m myl_sim.meta matriz --app -n 40 --publicar   (y lo muestra en la app)

El informe incluye qué tan agro o control está el meta: el estilo de cada mazo
sale de `myl_sim.perfil` y se contrasta con la duración medida de sus partidas.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import sys

from .datos import CACHE, Mazo, huella_mazo, solo_validos

CARPETA = CACHE / "meta"
CRUCES = CARPETA / "cruces"
ARCHIVOS_MOTOR = ("modelo.py", "motor.py", "habilidades.py", "jugadores.py", "creencias.py",
                  "busqueda_ataques.py", "busqueda_bloqueos.py", "busqueda_vigilia.py", "valor.py",
                  "valor_estado.json")
SEED_BASE = 20261112


def huella_motor() -> str:
    """Reglas + IA: si cambia cualquiera, los cruces guardados ya no valen."""
    raiz = Path(__file__).resolve().parent
    h = hashlib.sha256()
    for nombre in ARCHIVOS_MOTOR:
        h.update(nombre.encode() + b"\0" + (raiz / nombre).read_bytes().replace(b"\r\n", b"\n"))
    return h.hexdigest()[:16]


def seed_cruce(ha: str, hb: str, base: int = SEED_BASE) -> int:
    return int(hashlib.sha256(f"{base}:{ha}:{hb}".encode()).hexdigest()[:8], 16)


# ── Partidas ──────────────────────────────────────────────────────────────────
def _jugar(args) -> list[str]:
    """Partidas [desde, hasta) de un cruce. Resultado por partida desde A:
    "1" gana, "0" pierde, "e" empate, "x" anómala."""
    return _jugar_con_turnos(args)[0]


def _jugar_con_turnos(args) -> tuple[list[str], list[int]]:
    """Como `_jugar`, más las rondas completas que duró cada partida."""
    from .jugadores import JUGADORES
    from .motor import Partida

    cartas_a, cartas_b, seed, desde, hasta, jugador, listas = args
    clase = JUGADORES[jugador]
    out, turnos = [], []
    for k in range(desde, hasta):
        s = seed + k
        p = Partida((cartas_a, cartas_b), (clase(s * 2), clase(s * 2 + 1)), inicial=k % 2, seed=s)
        if listas:
            p.meta_listas = listas
        r = p.jugar()
        out.append("x" if r.ganador == -2 else "1" if r.ganador == 0 else "0" if r.ganador == 1 else "e")
        turnos.append((r.turnos + 1) // 2)
    return out, turnos


def _archivo_cruce(ha, hb, motor, jugador, base) -> Path:
    return CRUCES / f"{ha}_{hb}_{motor}_{jugador}_{base}.json"


def _leer(path: Path) -> str:
    try:
        return json.loads(path.read_text(encoding="utf-8"))["resultados"]
    except (OSError, ValueError, KeyError):
        return ""


def _leer_turnos(path: Path, n: int) -> list[int]:
    """Turnos guardados de un cruce, alineados con sus resultados. Las partidas
    jugadas antes de que se midiera la duración quedan en 0 (sin dato)."""
    try:
        t = [int(x) for x in json.loads(path.read_text(encoding="utf-8")).get("turnos") or []]
    except (OSError, ValueError, TypeError):
        t = []
    return (t + [0] * n)[:n]


def resumen_cruce(resultados: str) -> dict:
    validos = [c for c in resultados if c != "x"]
    n = len(validos)
    puntos = validos.count("1") + validos.count("e") / 2
    wr = puntos / n if n else 0.5
    return {"partidas": n, "anomalas": len(resultados) - n, "winrate": wr,
            "victorias": validos.count("1"), "derrotas": validos.count("0"),
            "empates": validos.count("e")}


def matriz(mazos: list[Mazo], n: int, *, jugador: str = "heuristico", procesos: int | None = None,
           base: int = SEED_BASE, usar_cache: bool = True, progreso=None, turnos: dict | None = None) -> dict:
    """Juega (o reutiliza) n partidas por cada par distinto. Devuelve
    {(i, j): resultados desde i} para i < j. Si se pasa `turnos` (un dict
    vacío), queda con {(i, j): [turnos de cada partida]} (0 = sin dato)."""
    from concurrent.futures import ProcessPoolExecutor

    motor = huella_motor()
    huellas = [huella_mazo(m) for m in mazos]
    listas = [m.cartas for m in mazos] if jugador != "heuristico" else None
    CRUCES.mkdir(parents=True, exist_ok=True)
    pares, trabajos, previos = [], [], {}
    for i in range(len(mazos)):
        for j in range(i + 1, len(mazos)):
            if huellas[i] == huellas[j]:
                continue
            # Orden canónico por huella: A–B y B–A son el mismo cruce.
            a, b = (i, j) if huellas[i] < huellas[j] else (j, i)
            ruta = _archivo_cruce(huellas[a], huellas[b], motor, jugador, base)
            hechos = _leer(ruta) if usar_cache else ""
            previos[(a, b)] = hechos
            pares.append((a, b))
            seed = seed_cruce(huellas[a], huellas[b], base)
            # Bloques de 10 partidas para repartir bien entre núcleos.
            for desde in range(len(hechos), n, 10):
                trabajos.append(((a, b), (mazos[a].cartas, mazos[b].cartas, seed, desde,
                                          min(n, desde + 10), jugador, listas)))
    nuevos: dict = {par: {} for par in pares}
    if trabajos:
        with ProcessPoolExecutor(procesos or os.cpu_count() or 1) as ex:
            for k, ((par, args), res) in enumerate(zip(trabajos, ex.map(_jugar_con_turnos, [t[1] for t in trabajos]))):
                nuevos[par][args[3]] = res
                if progreso:
                    progreso(k + 1, len(trabajos))
    out = {}
    for a, b in pares:
        ruta = _archivo_cruce(huellas[a], huellas[b], motor, jugador, base)
        hechos = previos[(a, b)]
        bloques = [nuevos[(a, b)][d] for d in sorted(nuevos[(a, b)])]
        res = hechos[:n] + "".join("".join(r) for r, _ in bloques)
        dur = _leer_turnos(ruta, len(hechos)) + [t for _, ts in bloques for t in ts]
        if len(res) > len(hechos):
            ruta.write_text(json.dumps({
                "a": {"id": mazos[a].id, "nombre": mazos[a].nombre, "huella": huellas[a]},
                "b": {"id": mazos[b].id, "nombre": mazos[b].nombre, "huella": huellas[b]},
                "motor": motor, "jugador": jugador, "seedBase": base, "resultados": res, "turnos": dur,
            }, ensure_ascii=False), encoding="utf-8")
        out[(a, b)] = res
        if turnos is not None:
            turnos[(a, b)] = dur[:len(res)]
    return out


def velocidad(mazos: list[Mazo], cruces: dict, turnos: dict) -> list[dict]:
    """Por mazo: turno mediano en que gana y en que pierde (None sin datos)."""
    gana: list[list[int]] = [[] for _ in mazos]
    pierde: list[list[int]] = [[] for _ in mazos]
    for (a, b), res in cruces.items():
        for c, t in zip(res, turnos.get((a, b)) or []):
            if t <= 0 or c not in "10":
                continue
            ganador, perdedor = (a, b) if c == "1" else (b, a)
            gana[ganador].append(t)
            pierde[perdedor].append(t)

    def mediana(xs: list[int]):
        xs = sorted(xs)
        return None if not xs else (xs[len(xs) // 2] + xs[(len(xs) - 1) // 2]) / 2

    return [{"turnoVictoria": mediana(g), "turnoDerrota": mediana(p), "partidasMedidas": len(g) + len(p)}
            for g, p in zip(gana, pierde)]


ESTILOS = ("Agro", "Medio", "Control", "Combo")


def _correlacion(xs: list[float], ys: list[float]):
    if len(xs) < 5:
        return None
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    sx = sum((x - mx) ** 2 for x in xs)
    sy = sum((y - my) ** 2 for y in ys)
    return None if not sx or not sy else sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / math.sqrt(sx * sy)


def meta_perfil(filas: list[dict], t: list[list[dict | None]]) -> dict:
    """Qué tan agro o control está el meta. `filas` en el mismo orden que la
    tabla `t`, cada una con su `perfil`, `indice`, pesos y `turnoVictoria`."""
    def reparto(clave: str) -> dict:
        total = sum(f[clave] for f in filas) or 1.0
        return {e: round(sum(f[clave] for f in filas if f["perfil"] == e) / total, 4) for e in ESTILOS}

    def indice(clave: str) -> float:
        total = sum(f[clave] for f in filas) or 1.0
        return round(sum(f[clave] * f["indice"] for f in filas) / total, 1)

    entre: dict = {}
    for i, fi in enumerate(filas):
        for j, fj in enumerate(filas):
            c = t[i][j]
            if c is None or i == j:
                continue
            d = entre.setdefault(fi["perfil"], {}).setdefault(fj["perfil"], [0.0, 0])
            d[0] += c["winrate"] * c["partidas"]
            d[1] += c["partidas"]
    medidos = [f for f in filas if f.get("turnoVictoria") is not None]
    r = _correlacion([f["indice"] for f in medidos], [f["turnoVictoria"] for f in medidos])
    # Qué estilo rinde más contra el meta actual (score medio de sus mazos).
    rinde = {e: round(sum(f["score"] for f in filas if f["perfil"] == e)
                      / max(1, sum(1 for f in filas if f["perfil"] == e)), 4)
             for e in ESTILOS if any(f["perfil"] == e for f in filas)}
    return {
        "mazos": {e: sum(1 for f in filas if f["perfil"] == e) for e in ESTILOS},
        "reparto": {"jugado": reparto("peso"), "evolutivo": reparto("pesoEvolutivo"),
                    "equilibrio": reparto("equilibrio")},
        "indiceMedio": {"jugado": indice("peso"), "evolutivo": indice("pesoEvolutivo"),
                        "equilibrio": indice("equilibrio")},
        "scorePorEstilo": rinde,
        "entreEstilos": {a: {b: {"winrate": round(w / n, 4), "partidas": n} for b, (w, n) in fila.items() if n}
                         for a, fila in entre.items()},
        "correlacionIndiceTurno": None if r is None else round(r, 3),
        "mazosMedidos": len(medidos),
    }


def winrates(mazos: list[Mazo], cruces: dict) -> list[list[dict | None]]:
    """Tabla [i][j] desde i (None en la diagonal y en espejos idénticos)."""
    k = len(mazos)
    t: list[list[dict | None]] = [[None] * k for _ in range(k)]
    for (a, b), res in cruces.items():
        r = resumen_cruce(res)
        t[a][b] = r
        t[b][a] = {**r, "winrate": 1 - r["winrate"], "victorias": r["derrotas"], "derrotas": r["victorias"]}
    return t


def score_meta(fila: list[dict | None], pesos: list[float], yo: int) -> dict:
    """Winrate esperado contra el meta. El espejo cuenta 50 %."""
    total = sum(pesos) or 1.0
    media = var = 0.0
    for j, (c, w) in enumerate(zip(fila, pesos)):
        w /= total
        if c is None or j == yo:
            media += w * 0.5
            continue
        wr, n = c["winrate"], max(1, c["partidas"])
        media += w * wr
        var += w * w * max(wr * (1 - wr), 0.25 / n) / n
    ee = math.sqrt(var)
    return {"score": media, "ic95": [max(0.0, media - 1.96 * ee), min(1.0, media + 1.96 * ee)]}


# ── Definición del meta ───────────────────────────────────────────────────────
def ruta_meta(nombre: str) -> Path:
    limpio = "".join(c if c.isalnum() or c in "-_" else "_" for c in nombre.strip().lower())
    return CARPETA / f"meta_{limpio}.json"


def cargar_meta(nombre: str) -> dict:
    p = Path(nombre)
    p = p if p.suffix == ".json" and p.exists() else ruta_meta(nombre)
    return json.loads(p.read_text(encoding="utf-8"))


def raciales_del_cache() -> list[Mazo]:
    out = []
    for f in sorted(CACHE.glob("mazo_*.json")):
        m = Mazo.from_json(json.loads(f.read_text(encoding="utf-8")))
        if m.formato == "racial" and not m.sin_programar():
            out.append(m)
    return solo_validos(out)


def _mazos_de(ids: list[str], usar_cache: bool) -> list[Mazo]:
    from .auditoria import _cargar

    return solo_validos(_cargar(ids, usar_cache), avisar=True)


def _tabla(t: list[list[dict | None]]) -> list[list[float]]:
    return [[0.5 if c is None else c["winrate"] for c in fila] for fila in t]


def pesos_evolutivos(w: list[list[float]], pasos: int = 10, base: list[float] | None = None,
                     piso: float = 0.01) -> list[float]:
    """Meta estimado sin datos de torneo: partiendo de `base` (iguales), en
    cada "generación" los jugadores se pasan a los mazos que ganan más contra
    el meta del momento (dinámica del replicador). Pocos pasos = meta que se
    está moviendo; `piso` deja un mínimo para cada mazo."""
    n = len(w)
    x = list(base or [1.0 / n] * n)
    for _ in range(pasos):
        f = [sum(w[i][j] * x[j] for j in range(n)) for i in range(n)]
        media = sum(a * b for a, b in zip(x, f)) or 1.0
        x = [x[i] * f[i] / media for i in range(n)]
    x = [max(piso, v) for v in x]
    total = sum(x)
    return [v / total for v in x]


def equilibrio(w: list[list[float]], iteraciones: int = 20000) -> list[float]:
    """Mezcla de mazos que ningún mazo de la lista le gana en promedio
    (equilibrio del juego de suma cero, por juego ficticio)."""
    n = len(w)
    c = [0] * n
    c[0] = 1
    f = [w[i][0] for i in range(n)]
    for _ in range(iteraciones):
        k = max(range(n), key=lambda i: f[i])
        c[k] += 1
        f = [f[i] + w[i][k] for i in range(n)]
    total = sum(c)
    return [v / total for v in c]


# ── Informe ───────────────────────────────────────────────────────────────────
def informe(mazos: list[Mazo], pesos: list[float], cruces: dict, *, n: int, jugador: str,
            nombre_meta: str, turnos: dict | None = None) -> dict:
    # Nombres repetidos ("Faraon", "Druida") o vacíos: se distinguen con el id.
    from collections import Counter

    from .perfil import analizar_mazo

    repetidos = Counter(m.nombre for m in mazos)
    for m in mazos:
        if repetidos[m.nombre] > 1 or m.nombre == m.id:
            m.nombre = f"{m.nombre if m.nombre != m.id else m.raza or 'Sin nombre'} ({m.id[:4]})"
    t = winrates(mazos, cruces)
    w = _tabla(t)
    evol = pesos_evolutivos(w, base=[p / (sum(pesos) or 1) for p in pesos])
    eq = equilibrio(w)
    vel = velocidad(mazos, cruces, turnos or {})
    filas = []
    for i, m in enumerate(mazos):
        s = score_meta(t[i], pesos, i)
        s_evol = score_meta(t[i], evol, i)
        rivales = [(mazos[j].nombre, t[i][j]["winrate"]) for j in range(len(mazos)) if t[i][j]]
        rivales.sort(key=lambda x: x[1])
        estilo = analizar_mazo(m)
        filas.append({"id": m.id, "nombre": m.nombre, "raza": m.raza, "huella": huella_mazo(m),
                      "peso": pesos[i], **s, "pesoEvolutivo": evol[i], "scoreEvolutivo": s_evol["score"],
                      "equilibrio": eq[i],
                      "perfil": estilo["perfil"], "indice": estilo["indice"], **vel[i],
                      "peores": rivales[:3], "mejores": rivales[::-1][:3]})
    orden = sorted(range(len(mazos)), key=lambda i: -filas[i]["score"])
    return {
        "esquema": 3, "creado": datetime.now(timezone.utc).isoformat(), "meta": nombre_meta,
        "motor": huella_motor(), "jugador": jugador, "partidasPorCruce": n,
        "metaPerfil": meta_perfil(filas, t),
        "ranking": [filas[i] for i in orden],
        "matriz": {"mazos": [mazos[i].nombre for i in orden],
                   "winrate": [[None if t[i][j] is None else round(t[i][j]["winrate"], 3) for j in orden]
                               for i in orden]},
    }


def informe_md(r: dict) -> str:
    out = [f"# Matriz del meta · {r['meta']}", "",
           f"{len(r['ranking'])} mazos · {r['partidasPorCruce']} partidas por cruce · jugador "
           f"`{r['jugador']}` · motor `{r['motor']}`", "",
           "## Ranking (winrate esperado contra el meta)", "",
           "Score: contra los pesos del meta (iguales si no hay datos). Meta evolutivo: "
           "contra el meta que resulta si los jugadores se pasan a lo que gana (10 generaciones); "
           "% evol = cuánto se jugaría cada mazo.", "",
           "| # | Mazo | Score | IC95 | Meta evolutivo | % evol | Peores cruces |",
           "|---|---|---|---|---|---|---|"]
    for k, f in enumerate(r["ranking"], 1):
        peores = ", ".join(f"{n} {w * 100:.0f}%" for n, w in f["peores"])
        out.append(f"| {k} | {f['nombre']} | {f['score'] * 100:.1f}% | "
                   f"{f['ic95'][0] * 100:.1f}–{f['ic95'][1] * 100:.1f} | {f['scoreEvolutivo'] * 100:.1f}% | "
                   f"{f['pesoEvolutivo'] * 100:.0f}% | {peores} |")
    eq = sorted((f for f in r["ranking"] if f["equilibrio"] >= 0.01), key=lambda f: -f["equilibrio"])
    out += ["", "## Equilibrio (la mezcla que nadie de la lista le gana)", "",
            ", ".join(f"{f['nombre']} {f['equilibrio'] * 100:.0f}%" for f in eq)]
    mp = r.get("metaPerfil")
    if mp:
        def pct(d: dict) -> str:
            return " · ".join(f"{e} {d[e] * 100:.0f}%" for e in ESTILOS if d.get(e))

        out += ["", "## Qué tan agro o control está el meta", "",
                "Estilo de cada mazo según sus habilidades programadas (`myl_sim.perfil`). "
                "Índice: 0 = control, 100 = agro.", "",
                "| | Reparto | Índice medio |", "|---|---|---|",
                f"| Lo que se juega (pesos del meta) | {pct(mp['reparto']['jugado'])} | {mp['indiceMedio']['jugado']} |",
                f"| Si todos se pasan a lo que gana | {pct(mp['reparto']['evolutivo'])} | "
                f"{mp['indiceMedio']['evolutivo']} |",
                f"| Equilibrio | {pct(mp['reparto']['equilibrio'])} | {mp['indiceMedio']['equilibrio']} |", "",
                "Winrate esperado contra el meta por estilo: "
                + " · ".join(f"{e} {v * 100:.1f}%" for e, v in mp["scorePorEstilo"].items()), ""]
        estilos = [e for e in ESTILOS if e in mp["entreEstilos"]]
        out += ["Winrate de la fila contra la columna:", "",
                "| | " + " | ".join(estilos) + " |", "|---" * (len(estilos) + 1) + "|"]
        for a in estilos:
            celdas = [mp["entreEstilos"][a].get(b) for b in estilos]
            out.append(f"| {a} | " + " | ".join("—" if c is None else f"{c['winrate'] * 100:.0f}% ({c['partidas']})"
                                               for c in celdas) + " |")
        if mp.get("correlacionIndiceTurno") is not None:
            out += ["", f"Correlación entre el índice y el turno mediano de victoria medido "
                        f"({mp['mazosMedidos']} mazos): {mp['correlacionIndiceTurno']}. "
                        "Debe ser claramente negativa (más agro, gana antes); si se acerca a 0, "
                        "recalibrar los pesos de `myl_sim/perfil.py`."]
        out += ["", "| Mazo | Estilo | Índice | Gana en el turno | Pierde en el turno |", "|---|---|---|---|---|"]
        for f in sorted(r["ranking"], key=lambda f: -f["indice"]):
            def turno(v):
                return "—" if v is None else f"{v:g}"
            out.append(f"| {f['nombre']} | {f['perfil']} | {f['indice']} | {turno(f.get('turnoVictoria'))} | "
                       f"{turno(f.get('turnoDerrota'))} |")
    m = r["matriz"]
    corto = [n[:10] for n in m["mazos"]]
    out += ["", "## Matriz (winrate de la fila contra la columna)", "",
            "| | " + " | ".join(corto) + " |", "|---" * (len(corto) + 1) + "|"]
    for nombre, fila in zip(m["mazos"], m["winrate"]):
        out.append(f"| {nombre} | " + " | ".join("—" if x is None else f"{x * 100:.0f}" for x in fila) + " |")
    return "\n".join(out) + "\n"


def publicar(r: dict) -> None:
    """Deja el resumen del informe en `config/meta_simulador`, que la app
    muestra a todos en «Meta y tendencias → Lo que gana». Escribe en Firestore."""
    from firebase_admin import firestore

    from .datos import db
    from .trabajos import resumen

    db().collection("config").document("meta_simulador").set(
        {**resumen("meta_matriz", r), "publicado": firestore.SERVER_TIMESTAMP})


def pendientes_md(mazos: list[Mazo], formato: str) -> str:
    """Cartas sin programar (y sin catálogo) ordenadas por cuántos mazos
    destraban: primero las que, al programarse, completan más mazos."""
    from collections import Counter, defaultdict

    usos, copias, raza = Counter(), Counter(), {}
    destraba = Counter()  # mazos a los que solo les falta esta carta
    por_mazo = defaultdict(set)
    for m in mazos:
        faltan = {n for n, _ in m.sin_programar()} | set(m.faltantes)
        por_mazo[m.nombre] = faltan
        for c in m.cartas:
            if not c.programada:
                raza.setdefault(c.nombre, c.raza)
        for n in faltan:
            usos[n] += 1
        for n, k in m.sin_programar():
            copias[n] += k
        if len(faltan) == 1:
            destraba[next(iter(faltan))] += 1
    listos = sum(1 for f in por_mazo.values() if not f)
    out = [f"# Cartas por programar · {formato}", "",
           f"{len(mazos)} mazos en la app (todos los jugadores + notables) · "
           f"{listos} listos para simular · {len(mazos) - listos} con cartas pendientes", "",
           "| Carta | Raza | Mazos que la usan | Copias | Mazos que completa sola |", "|---|---|---|---|---|"]
    for n, k in sorted(usos.items(), key=lambda x: (-destraba[x[0]], -x[1], x[0])):
        out.append(f"| {n} | {raza.get(n, '¿sin catálogo?')} | {k} | {copias[n]} | {destraba[n]} |")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="myl_sim.meta", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crear", help="guardar un meta (mazos y pesos)")
    c.add_argument("nombre", help='por ejemplo "BL 2026-11"')
    c.add_argument("ids", nargs="+", help="ids de mazo (o notable:<id>)")
    c.add_argument("--peso", action="append", default=[], help="ID=peso (por defecto 1)")
    c.add_argument("--banlist", default="")
    m = sub.add_parser("matriz", help="todos contra todos + ranking")
    m.add_argument("meta", nargs="?", help="nombre del meta guardado (vacío: raciales del caché)")
    m.add_argument("-n", type=int, default=40, help="partidas por cruce")
    m.add_argument("--jugador", default="heuristico")
    m.add_argument("--procesos", type=int)
    m.add_argument("--cache", action="store_true", help="mazos desde simulator/cache")
    m.add_argument("--app", action="store_true",
                   help="sin meta: todos los mazos completos de la app + notables (en vez del caché)")
    m.add_argument("--formato", default="racial", help="formato para --app")
    m.add_argument("--salida", type=Path)
    m.add_argument("--publicar", action="store_true",
                   help="publica el resumen en la app (config/meta_simulador); escribe en Firestore")
    pe = sub.add_parser("pendientes", help="cartas sin programar en los mazos de la app")
    pe.add_argument("--formato", default="racial")
    a = ap.parse_args(argv)

    if a.cmd == "pendientes":
        from .datos import cargar_todos

        mazos = cargar_todos(a.formato, notables=True)
        md = pendientes_md(mazos, a.formato)
        CARPETA.mkdir(parents=True, exist_ok=True)
        ruta = CARPETA / f"pendientes_{a.formato}.md"
        ruta.write_text(md, encoding="utf-8")
        print(md)
        print(f"Informe: {ruta}")
        return 0

    if a.cmd == "crear":
        pesos = dict(x.split("=", 1) for x in a.peso)
        datos = {"nombre": a.nombre, "banlist": a.banlist or a.nombre,
                 "creado": datetime.now(timezone.utc).isoformat(),
                 "mazos": [{"id": i, "peso": float(pesos.get(i, 1))} for i in a.ids]}
        CARPETA.mkdir(parents=True, exist_ok=True)
        ruta_meta(a.nombre).write_text(json.dumps(datos, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"Meta: {ruta_meta(a.nombre)}")
        return 0

    if a.meta:
        meta = cargar_meta(a.meta)
        mazos = _mazos_de([x["id"] for x in meta["mazos"]], a.cache)
        pesos = [float(x.get("peso", 1)) for x in meta["mazos"]]
        nombre = meta["nombre"]
    elif a.app:
        from .datos import cargar_todos

        mazos = solo_validos([x for x in cargar_todos(a.formato, notables=True) if not x.sin_programar()],
                             avisar=True)
        pesos = [1.0] * len(mazos)
        nombre = f"mazos de la app ({a.formato})"
    else:
        mazos = raciales_del_cache()
        pesos = [1.0] * len(mazos)
        nombre = "raciales del caché"

    def prog(k, total):
        if k % 25 == 0 or k == total:
            print(f"{k}/{total} bloques", flush=True)

    turnos: dict = {}
    cruces = matriz(mazos, a.n, jugador=a.jugador, procesos=a.procesos, progreso=prog, turnos=turnos)
    r = informe(mazos, pesos, cruces, n=a.n, jugador=a.jugador, nombre_meta=nombre, turnos=turnos)
    salida = a.salida or CARPETA / "informes" / f"matriz_{datetime.now():%Y%m%d_%H%M}"
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.with_suffix(".json").write_text(json.dumps(r, ensure_ascii=False, indent=1), encoding="utf-8")
    salida.with_suffix(".md").write_text(informe_md(r), encoding="utf-8")
    for k, f in enumerate(r["ranking"][:10], 1):
        print(f"{k:2}. {f['nombre']:<30} {f['score'] * 100:5.1f}%")
    print(f"Informe: {salida.with_suffix('.md')}")
    if a.publicar:
        publicar(r)
        print("Publicado en la app: Meta y tendencias → Lo que gana")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
