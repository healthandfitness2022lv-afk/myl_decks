"""Valoración aprendida del estado: probabilidad de ganar desde una mesa.

Se entrena con partidas de autojuego: al cerrar cada turno se guardan los
rasgos de la mesa desde los dos lados y, al final, quién ganó. El modelo es
una regresión logística (sin dependencias: los coeficientes van en
`valor_estado.json` junto a este archivo). La búsqueda de ataques y bloqueos
la usa para valorar las continuaciones que no llegan al final.

Entrenar (desde simulator/):
  .venv/Scripts/python -m myl_sim.valor entrenar --partidas 3000 --cache
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import random

from . import habilidades as hab

ARCHIVO = Path(__file__).with_name("valor_estado.json")
NOMBRES = [
    "castillo_mio", "castillo_rival", "mano_mia", "mano_rival", "oros_mios", "oros_rival",
    "aliados_mios", "aliados_rival", "fuerza_mia", "fuerza_rival", "max_fuerza_mia",
    "max_fuerza_rival", "apoyo_mio", "apoyo_rival", "cementerio_mio", "cementerio_rival",
    "turno", "me_toca", "inv_castillo_mio", "inv_castillo_rival",
    "presion_rival", "presion_mia",
]
_modelo: dict | None = None


def rasgos(p, yo: int) -> list[float]:
    m, r = p.j(yo), p.j(1 - yo)

    def fuerzas(j):
        return [max(0, hab.fuerza(p, a)) for a in j.aliados]

    fm, fr = fuerzas(m), fuerzas(r)
    cm, cr = len(m.mazo), len(r.mazo)
    return [
        cm / 10, cr / 10, len(m.mano) / 5, len(r.mano) / 5,
        (len(m.reserva) + len(m.pagado)) / 5, (len(r.reserva) + len(r.pagado)) / 5,
        len(fm) / 3, len(fr) / 3, sum(fm) / 10, sum(fr) / 10,
        max(fm, default=0) / 5, max(fr, default=0) / 5,
        len(m.apoyo) / 2, len(r.apoyo) / 2, len(m.cementerio) / 10, len(r.cementerio) / 10,
        p.e.turno / 20, 1.0 if p.e.activo == yo else 0.0,
        1 / (cm + 1), 1 / (cr + 1),
        min(3.0, sum(fr) / (cm + 1)), min(3.0, sum(fm) / (cr + 1)),
    ]


def cargar() -> dict | None:
    global _modelo
    if _modelo is None and ARCHIVO.exists():
        _modelo = json.loads(ARCHIVO.read_text(encoding="utf-8"))
    return _modelo


def prob_ganar(p, yo: int) -> float | None:
    """None si no hay modelo entrenado."""
    m = cargar()
    if m is None:
        return None
    z = m["sesgo"] + sum(w * x for w, x in zip(m["pesos"], rasgos(p, yo)))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


# ── Datos y entrenamiento ─────────────────────────────────────────────────────
def _jugar_registrando(args):
    from .jugadores import Heuristico
    from .motor import Partida

    cartas_a, cartas_b, seed = args

    class Registrada(Partida):
        def _cerrar_turno(self, a):
            super()._cerrar_turno(a)
            self.filas.append((rasgos(self, 0), rasgos(self, 1)))

    p = Registrada((cartas_a, cartas_b), (Heuristico(seed * 2), Heuristico(seed * 2 + 1)),
                   inicial=seed % 2, seed=seed)
    p.filas = []
    r = p.jugar()
    if r.ganador not in (0, 1):
        return []
    return [(x0, 1.0 if r.ganador == 0 else 0.0, x1, 1.0 if r.ganador == 1 else 0.0) for x0, x1 in p.filas]


def generar(mazos: list, partidas: int, seed: int = 1, procesos: int | None = None) -> list[list]:
    """Una lista por partida de (rasgos, ganó) desde ambos lados."""
    import os
    from concurrent.futures import ProcessPoolExecutor

    rng = random.Random(seed)
    trabajos = []
    for k in range(partidas):
        a, b = rng.sample(mazos, 2)
        trabajos.append((a.cartas, b.cartas, seed * 1_000_003 + k))
    with ProcessPoolExecutor(procesos or os.cpu_count() or 1) as ex:
        out = []
        for filas in ex.map(_jugar_registrando, trabajos, chunksize=8):
            juego = []
            for x0, y0, x1, y1 in filas:
                juego += [(x0, y0), (x1, y1)]
            out.append(juego)
    return out


def entrenar(datos: list[tuple[list[float], float]], *, epocas: int = 30, tasa: float = 0.05,
             l2: float = 1e-4, seed: int = 1) -> dict:
    """Regresión logística por descenso de gradiente estocástico."""
    rng = random.Random(seed)
    k = len(datos[0][0])
    w, b = [0.0] * k, 0.0
    orden = list(range(len(datos)))
    for ep in range(epocas):
        rng.shuffle(orden)
        t = tasa / (1 + ep * 0.2)
        for i in orden:
            x, y = datos[i]
            z = b + sum(wi * xi for wi, xi in zip(w, x))
            g = 1 / (1 + math.exp(-max(-30.0, min(30.0, z)))) - y
            b -= t * g
            for j in range(k):
                w[j] -= t * (g * x[j] + l2 * w[j])
    return {"esquema": 1, "rasgos": NOMBRES, "pesos": w, "sesgo": b}


def evaluar(modelo: dict, datos, prob) -> dict:
    perdida = aciertos = 0.0
    for x, y in datos:
        q = min(1 - 1e-6, max(1e-6, prob(modelo, x)))
        perdida -= y * math.log(q) + (1 - y) * math.log(1 - q)
        aciertos += (q >= 0.5) == (y == 1.0)
    return {"logloss": round(perdida / len(datos), 4), "acierto": round(aciertos / len(datos), 4)}


def _prob_modelo(m, x):
    z = m["sesgo"] + sum(w * v for w, v in zip(m["pesos"], x))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.valor")
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("entrenar")
    e.add_argument("ids", nargs="*", help="mazos (por defecto todos los racial del caché)")
    e.add_argument("--partidas", type=int, default=3000)
    e.add_argument("--seed", type=int, default=1)
    e.add_argument("--cache", action="store_true")
    args = ap.parse_args(argv)

    from .datos import CACHE, Mazo

    if args.ids:
        from .auditoria import _cargar

        mazos = _cargar(args.ids, args.cache)
    else:
        mazos = [Mazo.from_json(json.loads(f.read_text(encoding="utf-8")))
                 for f in sorted(CACHE.glob("mazo_*.json"))]
        mazos = [m for m in mazos if m.formato == "racial" and not m.sin_programar()]
    juegos = generar(mazos, args.partidas, seed=args.seed)
    corte = int(len(juegos) * 0.8)
    train = [f for j in juegos[:corte] for f in j]
    test = [f for j in juegos[corte:] for f in j]
    modelo = entrenar(train, seed=args.seed)
    modelo["mazos"] = [m.nombre for m in mazos]
    modelo["partidas"] = len(juegos)
    modelo["validacion"] = evaluar(modelo, test, _prob_modelo)
    ARCHIVO.write_text(json.dumps(modelo, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(modelo["validacion"]), f"{len(train)} estados de entrenamiento → {ARCHIVO}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
