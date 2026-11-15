"""Reportes de los desafíos IA (en vivo o desde la revisión) para revisarlos.

Un reporte en vivo guarda `pasoGrabacion`: cuántas decisiones iban grabadas
en ese momento. Se reproduce la partida justo hasta ahí y se muestra la mesa
completa (ambas manos y mazos), con lo último que pasó, para ver si el motor
aplicó mal una regla o la IA decidió mal.

Uso:
    python -m myl_sim.reportes_desafio                 (lista los reportes)
    python -m myl_sim.reportes_desafio <desafio> [n]   (reproduce el reporte n)
"""

from __future__ import annotations

import argparse
import sys

from .autopsia import Reproductor, _Desvio
from .datos import Mazo, db
from .motor import FinPartida, Partida


def posicion(g: dict, paso: int) -> Partida:
    """La partida reproducida hasta la decisión `paso` (exclusive)."""
    mazos = [Mazo.from_json(m) for m in g["mazos"]]
    registro = g["registro"][:paso]
    ref: list = [None]
    metodos = g.get("metodos") or [None, None]
    jugadores = tuple(Reproductor(i, registro, ref, rama=None, seed=g["seed"], metodos=metodos[i]) for i in (0, 1))
    p = Partida(tuple(m.cartas for m in mazos), jugadores, nombres=tuple(m.nombre for m in mazos), inicial=None,
                seed=g["seed"], log=True)
    p.cursor, p.cursor_rama = 0, None
    p.al_ramificar = lambda: None
    ref[0] = p
    try:
        p.jugar()
    except (_Desvio, FinPartida):
        pass
    return p


def mesa(p: Partida) -> str:
    def nombres(xs):
        return ", ".join(x.nombre for x in xs) or "—"

    out = [f"T{p.e.turno} {p.e.fase} · activo J{p.e.activo}"]
    for i, j in enumerate(p.e.jugadores):
        out += [
            f"J{i} {j.nombre_mazo}: castillo {len(j.mazo)} · cementerio {len(j.cementerio)} · destierro {len(j.destierro)}",
            f"   mano: {nombres(j.mano)}",
            f"   reserva: {nombres(j.reserva)} · pagados: {nombres(j.pagado)}",
            f"   defensa: {', '.join(f'{a.nombre}' for a in j.defensa) or '—'} · ataque: {nombres(j.ataque)}"
            f" · apoyo: {nombres(j.apoyo)}",
            f"   cementerio: {nombres(j.cementerio)}",
        ]
    return "\n".join(out)


def listar() -> None:
    for d in db().collection("ai_challenges").stream():
        for n, r in enumerate((d.to_dict() or {}).get("reportes") or []):
            donde = f"T{r.get('turno')} {r.get('fase')}" if r.get("enVivo") else "revisión"
            print(f"{d.id} {n}  [{r.get('tipo', 'decision')}] {donde}: {str(r.get('comentario'))[:90]}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="myl_sim.reportes_desafio")
    ap.add_argument("desafio", nargs="?")
    ap.add_argument("n", nargs="?", type=int, default=0)
    a = ap.parse_args(argv)
    if not a.desafio:
        listar()
        return
    ref = db().collection("ai_challenges").document(a.desafio)
    r = ((ref.get().to_dict() or {}).get("reportes") or [])[a.n]
    print(f"Reporte: {r.get('comentario')}\n")
    g = ref.collection("grabacion").document("registro").get().to_dict()
    if not g or not g.get("mazos"):
        sys.exit("El desafío no tiene grabación con mazos (terminó con error o es anterior).")
    paso = r.get("pasoGrabacion")
    if paso is None:
        sys.exit("El reporte no es en vivo: no guarda el punto exacto.")
    p = posicion(g, int(paso))
    print(mesa(p))
    print("\nÚltimo en la partida:")
    for linea in (p.e.log or [])[-15:]:
        print("  ", linea)
    vista = r.get("estado") or {}
    if vista.get("turno") not in (None, p.e.turno) or vista.get("fase") not in (None, p.e.fase):
        print(f"\nOJO: la app veía T{vista.get('turno')} {vista.get('fase')} y la reproducción llegó a "
              f"T{p.e.turno} {p.e.fase}.")


if __name__ == "__main__":
    main()
