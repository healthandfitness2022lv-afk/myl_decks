"""Buzón local de los reportes de Héctor, para el agente horario de correcciones.

Los reportes que Héctor deja en el tablero (botón del bicho) viven en Firestore:
`ai_challenges/{id}.reportes` (desafíos contra la IA) y `simulations/{id}.reportes`
(partidas narradas). El worker, que ya corre en el PC con acceso a Firestore,
los copia cada cierto rato a `cache/reportes/` junto con lo necesario para
reproducir la partida (grabación y mazos). El agente horario trabaja solo con
esa copia: no lee ni escribe Firestore.

Uso (desde simulator/, sin red):
    python -m myl_sim.buzon_reportes pendientes            lista lo no atendido
    python -m myl_sim.buzon_reportes ver <clave>           reproduce la mesa del reporte
    python -m myl_sim.buzon_reportes atender <clave> "nota" [--estado corregido|programacion|duda]

Una clave es `<coleccion>/<docId>/<n>`, p. ej. `ai_challenges/dmwP...../2`.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from .datos import CACHE

CARPETA = CACHE / "reportes"
ATENDIDOS = CARPETA / "atendidos.json"
# Lo anterior a esta fecha ya se atendió a mano (último arreglo: commit 8357376,
# reportes IQVB y dmwP, 2026-11-19 00:15 hora de Chile).
DESDE_INICIAL = "2026-11-19T03:15:00+00:00"
COLECCIONES = ("ai_challenges", "simulations")


def _json(x):
    if isinstance(x, datetime):
        return x.astimezone(timezone.utc).isoformat()
    return str(x)


def _escribir(ruta: Path, data) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    tmp = ruta.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1, default=_json), encoding="utf-8")
    tmp.replace(ruta)


def _leer(ruta: Path, defecto):
    try:
        return json.loads(ruta.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return defecto


# ---------------------------------------------------------------- worker (Firestore)

def exportar(cliente=None) -> int:
    """Copia a `cache/reportes/` los documentos cuyos reportes cambiaron.

    Lo llama el worker. Devuelve cuántos documentos actualizó."""
    from .datos import cargar_mazo, db

    cliente = cliente or db()
    cambiados = 0
    for coleccion in COLECCIONES:
        for snap in cliente.collection(coleccion).select(["reportes"]).stream(timeout=60):
            reportes = (snap.to_dict() or {}).get("reportes") or []
            if not reportes:
                continue
            ruta = CARPETA / f"{coleccion}_{snap.id}.json"
            previo = _leer(ruta, {})
            if len(previo.get("reportes") or []) == len(reportes):
                continue
            ref = cliente.collection(coleccion).document(snap.id)
            doc = ref.get().to_dict() or {}
            data = {"coleccion": coleccion, "id": snap.id, "reportes": reportes,
                    "exportado": datetime.now(timezone.utc)}
            if coleccion == "ai_challenges":
                g = ref.collection("grabacion").document("registro").get().to_dict()
                data["grabacion"] = g
                data["resumen"] = {k: doc.get(k) for k in ("status", "deckHumano", "deckIa", "nivel", "seed", "error")}
            else:
                data["simulacion"] = {k: doc.get(k) for k in ("deckA", "deckB", "seed", "jugador", "n", "inicial")}
                try:
                    data["mazos"] = [cargar_mazo(doc["ownerUid"], doc[k]).to_json() for k in ("deckA", "deckB")]
                except Exception as e:  # noqa: BLE001 - el reporte sirve igual sin mazos
                    data["mazos_error"] = str(e)[:300]
            _escribir(ruta, data)
            cambiados += 1
    return cambiados


# ---------------------------------------------------------------- agente (solo local)

def _atendidos() -> dict:
    a = _leer(ATENDIDOS, {})
    a.setdefault("desde", DESDE_INICIAL)
    a.setdefault("claves", {})
    return a


def _fecha(r: dict) -> str:
    return str(r.get("fecha") or r.get("creado") or "")


def todos() -> list[dict]:
    out = []
    for ruta in sorted(CARPETA.glob("*_*.json")):
        d = _leer(ruta, {})
        for n, r in enumerate(d.get("reportes") or []):
            out.append({"clave": f"{d.get('coleccion')}/{d.get('id')}/{n}", "fecha": _fecha(r), "reporte": r,
                        "archivo": str(ruta)})
    return sorted(out, key=lambda x: x["fecha"])


def pendientes() -> list[dict]:
    a = _atendidos()
    return [x for x in todos() if x["clave"] not in a["claves"] and x["fecha"] >= a["desde"]]


def atender(clave: str, nota: str, estado: str = "corregido") -> None:
    a = _atendidos()
    a["claves"][clave] = {"estado": estado, "nota": nota, "fecha": datetime.now(timezone.utc).isoformat()}
    _escribir(ATENDIDOS, a)


def _cargar(clave: str) -> tuple[dict, dict]:
    coleccion, doc_id, n = clave.split("/")
    d = _leer(CARPETA / f"{coleccion}_{doc_id}.json", None)
    if not d:
        sys.exit(f"No está en el buzón: {clave}")
    return d, d["reportes"][int(n)]


def ver(clave: str) -> None:
    d, r = _cargar(clave)
    print(json.dumps(r, ensure_ascii=False, indent=1, default=_json))
    if d["coleccion"] == "ai_challenges":
        from .reportes_desafio import mesa, posicion

        g = d.get("grabacion")
        paso = r.get("pasoGrabacion")
        if not g or not g.get("mazos"):
            print("\nSin grabación con mazos: solo hay el comentario.")
            return
        if paso is None:
            print("\nReporte desde la revisión (sin paso exacto): se muestra el final de la partida.")
            paso = len(g["registro"])
        p = posicion(g, int(paso))
        print("\n" + mesa(p) + "\n\nÚltimo en la partida:")
        for linea in (p.e.log or [])[-20:]:
            print("  ", linea)
    else:
        from .datos import Mazo
        from .simulacion import narrar

        s, mazos = d.get("simulacion") or {}, d.get("mazos")
        if not mazos:
            print(f"\nSin mazos ({d.get('mazos_error')}).")
            return
        inicial = s.get("inicial")
        res = narrar(Mazo.from_json(mazos[0]), Mazo.from_json(mazos[1]), seed=int(s.get("seed") or 1),
                     jugador=str(s.get("jugador") or "heuristico"),
                     inicial=int(inicial) if inicial in (0, 1) else None)
        pasos = res.get("pasos") or []
        i = int(r.get("paso") or 0)
        print(f"\nPasos {max(0, i - 15)}–{i} de la narración reproducida:")
        for x in pasos[max(0, i - 15):i + 1]:
            print("  ", x.get("x") if isinstance(x, dict) else x)


def main(argv=None) -> None:
    for flujo in (sys.stdout, sys.stderr):
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(prog="myl_sim.buzon_reportes")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("pendientes")
    v = sub.add_parser("ver")
    v.add_argument("clave")
    t = sub.add_parser("atender")
    t.add_argument("clave")
    t.add_argument("nota")
    t.add_argument("--estado", default="corregido", choices=["corregido", "programacion", "duda", "no_es_error"])
    a = ap.parse_args(argv)
    if a.cmd == "pendientes":
        xs = pendientes()
        if not xs:
            print("Sin reportes pendientes.")
        for x in xs:
            r = x["reporte"]
            donde = f"T{r.get('turno')} {r.get('fase')}" if r.get("turno") is not None else "revisión"
            print(f"{x['clave']}  {x['fecha'][:16]}  [{r.get('tipo', 'decision')}] {donde}: {r.get('comentario')}")
    elif a.cmd == "ver":
        ver(a.clave)
    elif a.cmd == "atender":
        atender(a.clave, a.nota, a.estado)
        print("Marcado:", a.clave, a.estado)


if __name__ == "__main__":
    main()
