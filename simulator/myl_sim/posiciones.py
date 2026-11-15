"""Posiciones fijadas: cada lección corregida queda como test.

Una posición guarda los mazos (tal como se jugaron), la semilla y las
decisiones grabadas hasta la decisión `paso`. El test reproduce la partida
hasta ahí y le pregunta a la heurística de hoy qué haría: debe elegir `debe`
(o, al menos, no `noDebe`). Así un cambio posterior en la IA que vuelva a
cometer el error se detecta de inmediato.

Uso:
    python -m myl_sim.posiciones fijar --mineria <id> [--debe TEXTO] [--nombre N]
    python -m myl_sim.posiciones fijar --leccion <id de ia_lecciones> [--debe TEXTO]
    python -m myl_sim.posiciones revisar

Una posición fijada cuando la IA aún comete el error queda `pendiente`
(fallo esperado en pytest); al corregir la IA se le quita la marca.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from .autopsia import _clave, _decodificar, _Desvio, alternativas, describir, reproducir
from .datos import Mazo
from .jugadores import Heuristico

CARPETA = Path(__file__).resolve().parents[1] / "tests" / "posiciones"


class _Respuesta(Exception):
    def __init__(self, hoy: str, opciones: list[str]):
        super().__init__(hoy)
        self.hoy, self.opciones = hoy, opciones


class PosicionObsoleta(Exception):
    """El motor ya no llega a la misma decisión con lo grabado."""


def decision_actual(pos: dict) -> tuple[str, list[str]]:
    """(lo que elige hoy la heurística, descripciones de las alternativas)."""
    mazos = [Mazo.from_json(m) for m in pos["mazos"]]
    k = pos["paso"]
    registro = pos["registro"]
    entrada = registro[k]

    def opcion(p, metodo, args):
        elegida = _decodificar(p, entrada["v"], args)
        opciones = alternativas(metodo, args, elegida, p)
        hoy = getattr(Heuristico(pos.get("semillaIa", pos["seed"])), metodo)(*args)
        clave = _clave(hoy)
        texto = next((t for t, v in opciones if _clave(v) == clave), None) or describir(metodo, hoy, args)
        raise _Respuesta(texto, [t for t, _ in opciones])

    try:
        reproducir(tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos), pos["seed"],
                   registro, rama=k, opcion=opcion, metodos=pos.get("metodos"))
    except _Respuesta as r:
        return r.hoy, r.opciones
    except _Desvio:
        pass
    raise PosicionObsoleta(pos.get("nombre", "?"))


def cumple(pos: dict) -> tuple[bool, str]:
    hoy, _ = decision_actual(pos)
    if pos.get("debe") is not None and hoy != pos["debe"]:
        return False, f"elige «{hoy}», debía «{pos['debe']}»"
    if pos.get("noDebe") is not None and hoy == pos["noDebe"]:
        return False, f"vuelve a elegir «{hoy}»"
    return True, f"elige «{hoy}»"


def cargar_todas() -> list[tuple[Path, dict]]:
    return [(f, json.loads(f.read_text(encoding="utf-8"))) for f in sorted(CARPETA.glob("*.json"))]


def _nombre_archivo(texto: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", texto.lower()).strip("_")[:60] or "posicion"


def fijar(base: dict, *, debe: str | None, no_debe: str | None, nombre: str | None) -> Path:
    """Guarda la posición; `base` trae mazos, seed, registro, metodos, paso y revision."""
    r = base["revision"]
    k = r["paso"]
    if debe is None and no_debe is None:
        # Error: basta con no repetirlo (puede haber más de una opción buena).
        # Acierto: debe seguir eligiendo lo mismo.
        no_debe, debe = (r["elegida"], None) if r["error"] else (None, r["elegida"])
    pos = {
        "nombre": nombre or f"{base.get('origen', 'leccion')} T{r.get('turno')} {r['tipo']}: {r['mejor']}",
        "origen": base.get("origen"),
        "id": base.get("id"),
        "lado": r.get("lado", 1),
        "paso": k,
        "tipo": r["tipo"],
        "debe": debe,
        "noDebe": no_debe,
        "revision": r,
        "seed": base["seed"],
        "semillaIa": base.get("semillaIa", base["seed"]),
        "metodos": base.get("metodos"),
        "mazos": base["mazos"],
        "registro": base["registro"][: k + 1],
    }
    # Si la IA todavía comete el error queda pendiente (xfail) hasta corregirla.
    pos["pendiente"] = not cumple(pos)[0]
    CARPETA.mkdir(parents=True, exist_ok=True)
    destino = CARPETA / f"{_nombre_archivo(pos['nombre'])}.json"
    destino.write_text(json.dumps(pos, ensure_ascii=False), encoding="utf-8")
    return destino


def _desde_mineria(ident: str) -> dict:
    from .mineria import buscar_leccion

    leccion = buscar_leccion(ident)
    if leccion is None:
        raise SystemExit(f"No existe la lección de minería {ident}")
    return leccion


def _desde_firestore(ident: str) -> dict:
    from .datos import cargar_mazo, db

    doc = db().collection("ia_lecciones").document(ident).get()
    if not doc.exists:
        raise SystemExit(f"No existe ia_lecciones/{ident}")
    d = doc.to_dict()
    g = db().collection("ai_challenges").document(d["desafio"]).collection("grabacion").document("registro").get()
    g = g.to_dict() or {}
    mazos = g.get("mazos") or [cargar_mazo(d["ownerUid"], d["deckHumano"]).to_json(),
                               cargar_mazo(d["ownerUid"], d["deckIa"]).to_json()]
    return {"origen": "desafio", "id": ident, "seed": g["seed"], "semillaIa": g["seed"] * 2 + 1,
            "metodos": g.get("metodos"), "registro": g["registro"], "mazos": mazos, "revision": d["revision"]}


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="myl_sim.posiciones")
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fijar")
    g = f.add_mutually_exclusive_group(required=True)
    g.add_argument("--mineria")
    g.add_argument("--leccion")
    f.add_argument("--debe")
    f.add_argument("--no-debe")
    f.add_argument("--nombre")
    sub.add_parser("revisar")
    a = ap.parse_args(argv)
    if a.cmd == "fijar":
        base = _desde_mineria(a.mineria) if a.mineria else _desde_firestore(a.leccion)
        destino = fijar(base, debe=a.debe, no_debe=a.no_debe, nombre=a.nombre)
        pos = json.loads(destino.read_text(encoding="utf-8"))
        ok, texto = cumple(pos)
        print(f"Guardada {destino.name}: hoy {texto} ({'pasa' if ok else 'pendiente: falta corregir la IA'})")
        return
    fallas = 0
    for archivo, pos in cargar_todas():
        try:
            ok, texto = cumple(pos)
        except PosicionObsoleta:
            ok, texto = True, "obsoleta (el motor ya no llega a esa decisión)"
        if pos.get("pendiente"):
            print(f"{'LISTA' if ok else 'pend.'} {archivo.stem}: {texto}"
                  + (" → quitar 'pendiente' del archivo" if ok else ""))
            continue
        fallas += not ok
        print(f"{'ok ' if ok else 'MAL'} {archivo.stem}: {texto}")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
