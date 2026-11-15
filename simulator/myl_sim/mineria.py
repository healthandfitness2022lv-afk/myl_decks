"""Minería de errores: la autopsia aplicada a lotes de partidas IA contra IA.

Se juegan partidas heurística contra heurística entre los mazos de una
cuenta, grabando todas las decisiones. En cada partida se revisan las
decisiones del perdedor que más bajaron su estimación de victoria: se
reproduce la partida, se prueban las alternativas y, si una gana claramente
más seguido, queda como error. Los errores se agrupan por patrón (tipo de
decisión + qué eligió + qué convenía) y los que más se repiten son los que
conviene convertir en reglas; cada uno se puede fijar como test de posición
(`myl_sim.posiciones fijar --mineria <id>`).

Uso:
    python -m myl_sim.mineria --email X [--formato racial] [--partidas 200] [--revisar 2] [--muestras 10]
    python -m myl_sim.mineria --resumen
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import time
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

from .autopsia import Grabadora, decisiones_a_revisar, explicar, metodos_de, revisar_decision
from .jugadores import Heuristico
from .motor import FinPartida, Partida

SALIDA = Path(__file__).resolve().parents[1] / "cache" / "mineria"
LECCIONES = SALIDA / "lecciones.jsonl"
RESUMEN = SALIDA / "resumen.json"


def jugar_grabada(mazo_a, mazo_b, seed: int) -> tuple[int | None, list, list]:
    """Partida heurística contra heurística con las decisiones de ambos lados grabadas."""
    registro: list = []
    ref: list = [None]
    base = (Heuristico(seed * 2), Heuristico(seed * 2 + 1))
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


def minar_partida(mazo_a, mazo_b, seed: int, *, revisar: int = 2, muestras: int = 10) -> list[dict]:
    """Errores del perdedor en una partida (lista vacía si no hubo o fue empate)."""
    ganador, registro, metodos = jugar_grabada(mazo_a, mazo_b, seed)
    if ganador not in (0, 1):
        return []
    perdedor = 1 - ganador
    cartas = (mazo_a.cartas, mazo_b.cartas)
    nombres = (mazo_a.nombre, mazo_b.nombre)
    out = []
    for k in decisiones_a_revisar(registro, True, [], maximo=revisar, lado=perdedor):
        r = revisar_decision(cartas, nombres, seed, registro, k, muestras=muestras, metodos=metodos)
        if r is not None:
            r.pop("_elegir", None)
        if r is None or not r["error"]:
            continue
        r["explicacion"] = explicar(r)
        out.append({
            "id": f"{seed}_{k}",
            "origen": "mineria",
            "patron": patron(r),
            "categoria": categoria(r),
            "mazo": nombres[perdedor],
            "rival": nombres[ganador],
            "deckIds": [mazo_a.id, mazo_b.id],
            "seed": seed,
            "semillaIa": seed * 2 + perdedor,
            "metodos": metodos,
            "registro": registro[: k + 1],
            "revision": r,
        })
    return out


def _generico(texto: str) -> str:
    # "jugar Foo (2 oros)" y "jugar Foo" son el mismo patrón.
    return re.sub(r"\s*\(.*?\)", "", texto).strip()


def patron(r: dict) -> str:
    """Detalle con cartas: «elegida» → «mejor»."""
    return f"{r['tipo']}: «{_generico(r['elegida'])}» → «{_generico(r['mejor'])}»"


def _forma(tipo: str, texto: str) -> str:
    texto = _generico(texto)
    if tipo == "atacantes":
        return "no atacar" if texto == "no atacar" else f"atacar con {len(texto[len('atacar con '):].split(', '))}"
    if tipo == "bloqueos":
        return "no bloquear" if texto == "no bloquear" else f"bloquear {len(texto.split('; '))}"
    if tipo == "jugada":
        return texto.split(" ")[0]  # pasar / jugar / activar …
    return "otro"


def categoria(r: dict) -> str:
    """Patrón general (sin cartas), para agrupar errores parecidos."""
    a, b = _forma(r["tipo"], r["elegida"]), _forma(r["tipo"], r["mejor"])
    if r["tipo"] == "atacantes":
        a, b = ("no atacar" if x == "no atacar" else "atacar" for x in (a, b))
        if a == b:
            return "atacantes: atacar con otros"
    if r["tipo"] == "bloqueos":
        a, b = ("no bloquear" if x == "no bloquear" else "bloquear" for x in (a, b))
        if a == b:
            return "bloqueos: bloquear distinto"
    if r["tipo"] == "objetivos":
        return "objetivos: otro objetivo"
    return f"{r['tipo']}: {a} → {b}"


# ── Lote en paralelo ─────────────────────────────────────────────────────────
_MAZOS: dict = {}


def _tarea(rutas: tuple[str, str], seed: int, revisar: int, muestras: int) -> list[dict]:
    from .datos import Mazo

    mazos = []
    for ruta in rutas:
        if ruta not in _MAZOS:
            _MAZOS[ruta] = Mazo.from_json(json.loads(Path(ruta).read_text(encoding="utf-8")))
        mazos.append(_MAZOS[ruta])
    try:
        return minar_partida(mazos[0], mazos[1], seed, revisar=revisar, muestras=muestras)
    except Exception as e:  # noqa: BLE001 - una partida rota no detiene el lote
        return [{"id": f"{seed}_falla", "origen": "mineria", "falla": f"{type(e).__name__}: {e}"[:300],
                 "deckIds": [Path(r).stem for r in rutas], "seed": seed}]


def lote(email: str, formato: str, partidas: int, revisar: int, muestras: int) -> None:
    from .datos import cargar_mazo, listar_mazos, problemas_mazo, uid_por_email

    uid = uid_por_email(email)
    ids = [i for i, _, f in listar_mazos(uid) if not formato or f == formato]
    carpeta = SALIDA / "mazos"
    carpeta.mkdir(parents=True, exist_ok=True)
    rutas = []
    for i in ids:
        mazo = cargar_mazo(uid, i)
        if problemas_mazo(mazo):
            print(f"Fuera (49 cartas / Ban List): {mazo.nombre}", flush=True)
            continue
        ruta = carpeta / f"{i}.json"
        ruta.write_text(json.dumps(mazo.to_json(), ensure_ascii=False), encoding="utf-8")
        rutas.append(str(ruta))
    rng = random.Random()
    tareas = [(tuple(rng.sample(rutas, 2)), rng.randint(1, 10**9)) for _ in range(partidas)]
    print(f"{len(rutas)} mazos, {partidas} partidas", flush=True)
    t0, encontrados = time.time(), 0
    with ProcessPoolExecutor(max_workers=max(2, (os.cpu_count() or 4) - 1)) as ex, \
            LECCIONES.open("a", encoding="utf-8") as salida:
        futs = [ex.submit(_tarea, r, s, revisar, muestras) for r, s in tareas]
        for n, f in enumerate(as_completed(futs), 1):
            for leccion in f.result():
                salida.write(json.dumps(leccion, ensure_ascii=False) + "\n")
                encontrados += "falla" not in leccion
            salida.flush()
            if n % 20 == 0 or n == partidas:
                print(f"{n}/{partidas} partidas, {encontrados} errores, {time.time() - t0:.0f} s", flush=True)
    imprimir_resumen()


# ── Lecciones guardadas ──────────────────────────────────────────────────────
def leer_lecciones() -> list[dict]:
    if not LECCIONES.exists():
        return []
    return [json.loads(x) for x in LECCIONES.read_text(encoding="utf-8").splitlines() if x.strip()]


def buscar_leccion(ident: str) -> dict | None:
    """La lección con sus mazos (para fijarla como test de posición)."""
    x = next((x for x in leer_lecciones() if x.get("id") == ident), None)
    if x is not None:
        x["mazos"] = [json.loads((SALIDA / "mazos" / f"{i}.json").read_text(encoding="utf-8"))
                      for i in x["deckIds"]]
    return x


def resumen(lecciones: list[dict] | None = None) -> dict:
    """Patrones ordenados por cuánto le cuestan a la IA (veces × puntos perdidos)."""
    lecciones = leer_lecciones() if lecciones is None else lecciones
    grupos: dict[str, list[dict]] = defaultdict(list)
    for x in lecciones:
        if "falla" not in x:
            grupos[x.get("categoria") or categoria(x["revision"])].append(x)
    patrones = []
    for clave, xs in grupos.items():
        perdida = sum(x["revision"]["ganaMejor"] - x["revision"]["ganaElegida"] for x in xs)
        xs = sorted(xs, key=lambda x: x["revision"]["ganaElegida"] - x["revision"]["ganaMejor"])
        patrones.append({
            "patron": clave,
            "veces": len(xs),
            "puntosPerdidos": round(perdida, 2),
            "mazos": sorted({x["mazo"] for x in xs}),
            "ejemplos": [{"id": x["id"], "detalle": x["patron"], "mazo": x["mazo"],
                          "turno": x["revision"].get("turno"),
                          "gana": [x["revision"]["ganaElegida"], x["revision"]["ganaMejor"]]} for x in xs[:8]],
        })
    patrones.sort(key=lambda p: -p["puntosPerdidos"])
    fallas = [x for x in lecciones if "falla" in x]
    return {"errores": sum(len(v) for v in grupos.values()), "fallas": len(fallas), "patrones": patrones}


def imprimir_resumen(top: int = 25) -> None:
    r = resumen()
    SALIDA.mkdir(parents=True, exist_ok=True)
    RESUMEN.write_text(json.dumps(r, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\n{r['errores']} errores en {len(r['patrones'])} patrones ({r['fallas']} partidas con falla)")
    for p in r["patrones"][:top]:
        print(f"\n{p['veces']:>3}× −{p['puntosPerdidos']:.1f}  {p['patron']}  ({len(p['mazos'])} mazos)")
        for e in p["ejemplos"][:4]:
            print(f"      {e['id']}  T{e['turno']} {e['mazo']}: {e['detalle']} "
                  f"({e['gana'][0]:.0%} → {e['gana'][1]:.0%})")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="myl_sim.mineria")
    ap.add_argument("--email")
    ap.add_argument("--formato", default="racial")
    ap.add_argument("--partidas", type=int, default=200)
    ap.add_argument("--revisar", type=int, default=2, help="decisiones del perdedor a revisar por partida")
    ap.add_argument("--muestras", type=int, default=10)
    ap.add_argument("--resumen", action="store_true")
    a = ap.parse_args(argv)
    if a.resumen:
        imprimir_resumen()
        return
    if not a.email:
        ap.error("falta --email")
    SALIDA.mkdir(parents=True, exist_ok=True)
    lote(a.email, a.formato, a.partidas, a.revisar, a.muestras)


if __name__ == "__main__":
    main()
