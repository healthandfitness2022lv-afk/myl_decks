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

# Esquema 2 (16-11): los mismos rasgos más los que la fórmula fija y el esquema
# 1 no ven: letal a la vista, daño que pasa aunque el rival bloquee con todo,
# Oros disponibles y qué hay en mi mano. Va en otro archivo: el juez y las
# versiones congeladas siguen usando el esquema 1 sin cambios.
ARCHIVO_V2 = Path(__file__).with_name("valor_estado_v2.json")
NOMBRES_V2 = NOMBRES + [
    "oro_disponible_mio", "oro_disponible_rival", "letal_mio", "letal_rival",
    "dano_que_pasa_mio", "dano_que_pasa_rival", "mano_aliados", "mano_talismanes", "mano_oros",
    "coste_mano", "castillo_mio_bajo", "castillo_rival_bajo", "sin_mesa_mia", "sin_mesa_rival",
]
_modelo_v2: dict | None = None


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


def rasgos_v2(p, yo: int) -> list[float]:
    from .modelo import Tipo

    m, r = p.j(yo), p.j(1 - yo)
    fm = sorted((max(0, hab.fuerza(p, a)) for a in m.aliados), reverse=True)
    fr = sorted((max(0, hab.fuerza(p, a)) for a in r.aliados), reverse=True)
    cm, cr = len(m.mazo), len(r.mazo)
    # Daño que pasa si el otro bloquea a mis más fuertes con todos sus Aliados.
    pasa_m, pasa_r = sum(fm[len(fr):]), sum(fr[len(fm):])
    mano = [c for c in m.mano]
    return rasgos(p, yo) + [
        m.oro_disponible / 5, r.oro_disponible / 5,
        1.0 if sum(fm) >= cr else 0.0, 1.0 if sum(fr) >= cm else 0.0,
        min(3.0, pasa_m / (cr + 1)), min(3.0, pasa_r / (cm + 1)),
        sum(1 for c in mano if c.tipo == Tipo.ALIADO) / 3,
        sum(1 for c in mano if c.tipo == Tipo.TALISMAN) / 3,
        sum(1 for c in mano if c.tipo == Tipo.ORO) / 3,
        sum(c.carta.coste for c in mano) / 15,
        1.0 if cm <= 8 else 0.0, 1.0 if cr <= 8 else 0.0,
        1.0 if not fm else 0.0, 1.0 if not fr else 0.0,
    ]


def prob_ganar_v2(p, yo: int) -> float | None:
    """Valoración con el esquema 2; None si no está entrenada."""
    global _modelo_v2
    if _modelo_v2 is None and ARCHIVO_V2.exists():
        _modelo_v2 = json.loads(ARCHIVO_V2.read_text(encoding="utf-8"))
    if _modelo_v2 is None:
        return None
    z = _modelo_v2["sesgo"] + sum(w * x for w, x in zip(_modelo_v2["pesos"], rasgos_v2(p, yo)))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


ARCHIVO_V3 = Path(__file__).with_name("valor_estado_v3.json")
_modelo_v3: dict | None = None


def prob_ganar_v3(p, yo: int) -> float | None:
    """Esquema 2 entrenado con partidas jugadas por la búsqueda (no solo la heurística).
    Sin archivo, cae en el v2."""
    global _modelo_v3
    if _modelo_v3 is None and ARCHIVO_V3.exists():
        _modelo_v3 = json.loads(ARCHIVO_V3.read_text(encoding="utf-8"))
    if _modelo_v3 is None:
        return prob_ganar_v2(p, yo)
    z = _modelo_v3["sesgo"] + sum(w * x for w, x in zip(_modelo_v3["pesos"], rasgos_v2(p, yo)))
    return 1 / (1 + math.exp(-max(-30.0, min(30.0, z))))


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

    cartas_a, cartas_b, seed = args[:3]
    extraer = rasgos_v2 if len(args) > 3 and args[3] == 2 else rasgos

    class Registrada(Partida):
        def _cerrar_turno(self, a):
            super()._cerrar_turno(a)
            self.filas.append((extraer(self, 0), extraer(self, 1)))

    motor = args[4] if len(args) > 4 else "heuristico"
    if motor == "heuristico":
        jugadores = (Heuristico(seed * 2), Heuristico(seed * 2 + 1))
    else:
        from .arena import crear

        jugadores = (crear(motor, seed * 2), crear(motor, seed * 2 + 1))
    p = Registrada((cartas_a, cartas_b), jugadores, inicial=seed % 2, seed=seed)
    p.filas = []
    r = p.jugar()
    if r.ganador not in (0, 1):
        return []
    return [(x0, 1.0 if r.ganador == 0 else 0.0, x1, 1.0 if r.ganador == 1 else 0.0) for x0, x1 in p.filas]


def generar(mazos: list, partidas: int, seed: int = 1, procesos: int | None = None,
            esquema: int = 1, jugador: str = "heuristico") -> list[list]:
    """Una lista por partida de (rasgos, ganó) desde ambos lados."""
    import os
    from concurrent.futures import ProcessPoolExecutor

    rng = random.Random(seed)
    trabajos = []
    for k in range(partidas):
        a, b = rng.sample(mazos, 2)
        trabajos.append((a.cartas, b.cartas, seed * 1_000_003 + k, esquema, jugador))
    with ProcessPoolExecutor(procesos or os.cpu_count() or 1) as ex:
        out = []
        for n, filas in enumerate(ex.map(_jugar_registrando, trabajos,
                                         chunksize=8 if jugador == "heuristico" else 1), 1):
            if jugador != "heuristico" and n % 10 == 0:
                print(f"{n}/{partidas} partidas de {jugador}", flush=True)
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
    return {"esquema": 2 if k == len(NOMBRES_V2) else 1,
            "rasgos": NOMBRES_V2 if k == len(NOMBRES_V2) else NOMBRES, "pesos": w, "sesgo": b}


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
    e.add_argument("--esquema", type=int, choices=(1, 2), default=1,
                   help="2: rasgos ampliados, se guarda en valor_estado_v2.json")
    e.add_argument("--validos", action="store_true", help="solo mazos válidos (49 cartas y Ban List)")
    e.add_argument("--jugador", default="heuristico",
                   help="motor de la arena que juega las partidas (ej. busqueda_vigilia); "
                        "con otro que la heurística se guarda en valor_estado_v3.json (esquema 2)")
    e.add_argument("--base", type=int, default=0,
                   help="con --jugador: partidas de heurística que se suman al entrenamiento")
    e.add_argument("--procesos", type=int)
    args = ap.parse_args(argv)

    from .datos import CACHE, Mazo

    if args.ids:
        from .auditoria import _cargar

        mazos = _cargar(args.ids, args.cache)
    else:
        mazos = [Mazo.from_json(json.loads(f.read_text(encoding="utf-8")))
                 for f in sorted(CACHE.glob("mazo_*.json"))]
        mazos = [m for m in mazos if m.formato == "racial" and not m.sin_programar()]
    if args.validos:
        from .datos import solo_validos

        mazos = solo_validos(mazos)
    if args.jugador != "heuristico":
        args.esquema = 2
    juegos = generar(mazos, args.partidas, seed=args.seed, esquema=args.esquema, jugador=args.jugador,
                     procesos=args.procesos)
    corte = int(len(juegos) * 0.8)
    train = [f for j in juegos[:corte] for f in j]
    test = [f for j in juegos[corte:] for f in j]  # la validación es solo con partidas de `--jugador`
    if args.jugador != "heuristico" and args.base:
        base = generar(mazos, args.base, seed=args.seed + 7919, esquema=2, procesos=args.procesos)
        train += [f for j in base for f in j]
    modelo = entrenar(train, seed=args.seed)
    modelo["mazos"] = [m.nombre for m in mazos]
    modelo["partidas"] = len(juegos)
    modelo["validacion"] = evaluar(modelo, test, _prob_modelo)
    if args.esquema == 2:
        # Referencia: el esquema 1 entrenado con las mismas partidas (primeros 22 rasgos).
        k1 = len(NOMBRES)
        m1 = entrenar([(x[:k1], y) for x, y in train], seed=args.seed)
        modelo["validacionEsquema1"] = evaluar(m1, [(x[:k1], y) for x, y in test], _prob_modelo)
    modelo["jugador"] = args.jugador
    if args.jugador != "heuristico" and ARCHIVO_V2.exists():
        # Referencia: el v2 de hoy (entrenado con heurística) sobre las mismas partidas de prueba.
        modelo["validacionV2"] = evaluar(json.loads(ARCHIVO_V2.read_text(encoding="utf-8")), test, _prob_modelo)
        print("v2 de hoy sobre estas partidas:", json.dumps(modelo["validacionV2"]))
    destino = ARCHIVO_V3 if args.jugador != "heuristico" else ARCHIVO_V2 if args.esquema == 2 else ARCHIVO
    destino.write_text(json.dumps(modelo, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(modelo["validacion"]), json.dumps(modelo.get("validacionEsquema1")),
          f"{len(train)} estados de entrenamiento en {destino}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
