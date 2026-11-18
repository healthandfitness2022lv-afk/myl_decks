"""Escalera del modo Entrenamiento: rivales ordenados por dificultad.

Cada rival es un mazo del meta jugado por un nivel de IA. Su rating sale de
dos mediciones que ya existen:

- el **Elo del nivel de IA** en la arena (`cache/arena/ranking.json`);
- la **fuerza del mazo** contra el meta (`score` del informe de `myl_sim.meta`),
  convertida a puntos Elo: 400·log10(s / (1 − s)), con tope de ±200.

La app (`lib/domain/entrenamiento.dart`) actualiza el rating del jugador con la
fórmula Elo contra el rating del rival, y le ofrece el rival más cercano.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.escalera                       (último informe, mazos del caché)
  .venv/Scripts/python -m myl_sim.escalera --app --publicar      (mazos de la app; lo muestra en la app)

`--publicar` escribe en Firestore (`config/escalera_entrenamiento`). Los mazos
rivales quedan guardados en `cache/entrenamiento/` y el worker los carga desde
ahí con el id `escalera:<id del mazo>`; el dueño de cada mazo no se publica.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import sys

from .datos import CACHE, Mazo

CARPETA = CACHE / "entrenamiento"
PREFIJO = "escalera:"
# Motor de la arena que corresponde a cada nivel del Desafío (ver desafio.NIVELES).
MOTOR_NIVEL = {1: ("nivel1",), 2: ("nivel2",), 3: ("nivel3",), 4: ("heuristico",),
               5: ("vigilia_turno_valor2", "busqueda_vigilia")}
# Si la arena aún no midió un nivel (medidos el 17-11-2026).
ELO_POR_DEFECTO = {1: 1034, 2: 1236, 3: 1365, 4: 1504, 5: 1660}
TOPE_MAZO = 200
ROMANOS = ("", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X")


def elo_niveles(ranking: dict | None) -> dict[int, int]:
    """Elo de cada nivel de IA: de cada motor, la medición con más partidas."""
    out = dict(ELO_POR_DEFECTO)
    filas = (ranking or {}).get("ranking") or []
    for nivel, motores in MOTOR_NIVEL.items():
        for motor in motores:
            medidas = [f for f in filas if str(f.get("motor", "")).split("#")[0].split("@")[0] == motor]
            if medidas:
                out[nivel] = int(round(max(medidas, key=lambda f: f.get("partidas", 0))["elo"]))
                break
    # Un nivel más alto nunca queda por debajo del anterior.
    for n in range(2, 6):
        out[n] = max(out[n], out[n - 1] + 1)
    return out


def ajuste_mazo(score: float) -> int:
    """Puntos Elo que suma o resta un mazo según su winrate contra el meta."""
    s = min(0.99, max(0.01, float(score)))
    return int(round(max(-TOPE_MAZO, min(TOPE_MAZO, 400 * math.log10(s / (1 - s))))))


def generar(informe: dict, ranking_arena: dict | None = None) -> dict:
    """Escalera a partir de un informe de `myl_sim.meta` (esquema 3)."""
    elos = elo_niveles(ranking_arena)
    usados: dict[str, int] = {}
    rivales = []
    for f in sorted(informe["ranking"], key=lambda f: -f["score"]):
        base = " ".join(x for x in (f.get("raza") or "Mazo", f.get("perfil") or "") if x)
        k = usados.get(base, 0)
        usados[base] = k + 1
        nombre = base + (ROMANOS[k] if k < len(ROMANOS) else f" {k + 1}")
        ajuste = ajuste_mazo(f["score"])
        for nivel in sorted(elos):
            rivales.append({
                "id": f"{f['id']}|{nivel}", "deck": f["id"], "nombre": nombre, "raza": f.get("raza") or "",
                "perfil": f.get("perfil") or "", "indice": f.get("indice"), "nivel": nivel,
                "rating": elos[nivel] + ajuste,
            })
    rivales.sort(key=lambda r: (r["rating"], r["id"]))
    return {
        "esquema": 1, "creado": datetime.now(timezone.utc).isoformat(), "meta": informe.get("meta", ""),
        "eloNiveles": {str(k): v for k, v in elos.items()},
        # El jugador parte un poco por encima del rival más fácil.
        "ratingInicial": (rivales[0]["rating"] + 100) if rivales else 1000,
        "rivales": rivales,
    }


def guardar_mazos(mazos: list[Mazo], escalera: dict) -> int:
    """Deja en `cache/entrenamiento/` la lista de cada mazo rival, para que el
    worker la cargue con `escalera:<id>`."""
    CARPETA.mkdir(parents=True, exist_ok=True)
    ids = {r["deck"] for r in escalera["rivales"]}
    n = 0
    for m in mazos:
        if m.id in ids:
            (CARPETA / f"mazo_{m.id}.json").write_text(json.dumps(m.to_json(), ensure_ascii=False), encoding="utf-8")
            n += 1
    return n


def cargar_mazo_rival(ref: str) -> Mazo:
    """Mazo de un rival de la escalera (`escalera:<id>`), desde el caché local."""
    deck_id = ref.removeprefix(PREFIJO)
    if not deck_id or any(c in deck_id for c in "/\\."):
        raise ValueError(f"Rival de entrenamiento inválido: {ref}")
    ruta = CARPETA / f"mazo_{deck_id}.json"
    if not ruta.exists():
        raise ValueError("Este rival ya no está en la escalera. Vuelve a Entrenamiento y elige otro.")
    return Mazo.from_json(json.loads(ruta.read_text(encoding="utf-8")))


def publicar(escalera: dict) -> None:
    """Escribe la escalera en `config/escalera_entrenamiento` (Firestore)."""
    from firebase_admin import firestore

    from .datos import db

    db().collection("config").document("escalera_entrenamiento").set(
        {**escalera, "publicado": firestore.SERVER_TIMESTAMP})


def escalera_md(e: dict) -> str:
    out = ["# Escalera de entrenamiento", "",
           f"{len(e['rivales'])} rivales · rating inicial del jugador {e['ratingInicial']} · "
           f"Elo de los niveles de IA: " + ", ".join(f"{k}: {v}" for k, v in e["eloNiveles"].items()), "",
           "| Rating | Rival | Nivel de IA | Estilo |", "|---|---|---|---|"]
    for r in e["rivales"]:
        out.append(f"| {r['rating']} | {r['nombre']} | {r['nivel']} | {r['perfil']} {r.get('indice') or ''} |")
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(prog="myl_sim.escalera", description=__doc__.split("\n")[0])
    ap.add_argument("--informe", type=Path, help="informe .json de myl_sim.meta (por defecto, el más reciente)")
    ap.add_argument("--app", action="store_true", help="mazos de la app + notables (lee Firestore)")
    ap.add_argument("--formato", default="racial")
    ap.add_argument("--publicar", action="store_true", help="publica la escalera en la app (escribe en Firestore)")
    a = ap.parse_args(argv)

    from .meta import CARPETA as META, raciales_del_cache

    ruta = a.informe or max((META / "informes").glob("*.json"), key=lambda p: p.stat().st_mtime, default=None)
    if ruta is None:
        print("No hay informes de meta. Corre antes: python -m myl_sim.meta matriz")
        return 1
    informe = json.loads(Path(ruta).read_text(encoding="utf-8"))
    if "metaPerfil" not in informe:
        print(f"{ruta} es un informe antiguo (sin estilo de los mazos). Genera uno nuevo con myl_sim.meta matriz.")
        return 1
    arena = CACHE / "arena" / "ranking.json"
    ranking = json.loads(arena.read_text(encoding="utf-8")) if arena.exists() else None
    escalera = generar(informe, ranking)
    if a.app:
        from .datos import cargar_todos

        mazos = cargar_todos(a.formato, notables=True)
    else:
        mazos = raciales_del_cache()
    guardados = guardar_mazos(mazos, escalera)
    faltan = {r["deck"] for r in escalera["rivales"]} - {m.id for m in mazos}
    if faltan:
        # Sin su lista el worker no puede jugarlos: no se ofrecen.
        escalera["rivales"] = [r for r in escalera["rivales"] if r["deck"] not in faltan]
        print(f"Aviso: {len(faltan)} mazos del informe no están disponibles y quedan fuera.")
    (CARPETA / "escalera.json").write_text(json.dumps(escalera, ensure_ascii=False, indent=1), encoding="utf-8")
    (CARPETA / "escalera.md").write_text(escalera_md(escalera), encoding="utf-8")
    r = escalera["rivales"]
    print(f"Escalera: {len(r)} rivales ({guardados} mazos) · rating {r[0]['rating']} a {r[-1]['rating']} · "
          f"el jugador parte en {escalera['ratingInicial']}")
    print(f"Detalle: {CARPETA / 'escalera.md'}")
    if a.publicar:
        publicar(escalera)
        print("Publicada en la app: Entrenamiento")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
