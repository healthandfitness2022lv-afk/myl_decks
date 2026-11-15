"""Arena: motores de IA enfrentados entre sí, con ranking Elo.

Las simulaciones normales ponen la MISMA IA en los dos asientos: miden mazos,
no qué tan bien juega la IA. La arena mide la IA:

- **Motor**: una forma de decidir. `aleatorio`, `nivel1`…`nivel3` (heurística
  con errores al azar, como en el Desafío), `heuristico` (nivel 4, "IA
  rápida"), `experto` (nivel 5 de hoy: heurística + bloqueos por búsqueda),
  `busqueda_ataques`, `busqueda_completa` y `busqueda_vigilia` ("IA buena").
- **Par**: dos partidas con los mismos mazos, la misma semilla y el mismo
  jugador inicial, intercambiando los motores. La suerte del robo y la ventaja
  del mazo se cancelan; lo que queda es la diferencia de juego.
- **Versiones congeladas**: `congelar <etiqueta>` guarda una copia de los
  archivos de IA de hoy (`cache/arena/versiones/`). `heuristico@<etiqueta>`
  juega con esa copia sobre las reglas actuales, así cada cambio de la IA se
  mide contra la de ayer, igual que las versiones de un motor de ajedrez.
- **Elo**: ajuste Bradley-Terry (máxima verosimilitud) sobre todas las
  partidas guardadas en `cache/arena/partidas.jsonl`. El ancla vale 1500. Un
  motor sin congelar se identifica por la huella de sus archivos
  (`heuristico#3fa2c1`): si la IA cambia, aparece como un motor nuevo.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.arena congelar base
  .venv/Scripts/python -m myl_sim.arena jugar heuristico heuristico@base --pares 200
  .venv/Scripts/python -m myl_sim.arena jugar busqueda_vigilia heuristico --pares 40
  .venv/Scripts/python -m myl_sim.arena ranking
"""

from __future__ import annotations

import argparse
import functools
import hashlib
import importlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import sys
import time

from .datos import CACHE

CARPETA = CACHE / "arena"
PARTIDAS = CARPETA / "partidas.jsonl"
DESVIACIONES = CARPETA / "desviaciones.jsonl"
PRECISION = CARPETA / "precision.jsonl"
VERSIONES = CARPETA / "versiones"
CONFIG = CARPETA / "config.json"
# Los archivos que deciden cómo juega la IA. Lo demás (reglas, cartas) lo
# comparten los dos lados de una partida.
ARCHIVOS_IA = ("jugadores.py", "creencias.py", "valor.py", "valor_estado.json",
               "busqueda_ataques.py", "busqueda_bloqueos.py", "busqueda_vigilia.py")
MOTORES = ("aleatorio", "nivel1", "nivel2", "nivel3", "heuristico", "experto",
           "busqueda_ataques", "busqueda_completa", "busqueda_vigilia", "vigilia_valor", "vigilia_x2",
           "vigilia_h8")
# Variantes de la "IA buena": con la valoración aprendida (valor.py) al cortar
# las continuaciones, y con el doble de muestras por decisión.
_VIGILIA = {"busqueda_vigilia": {}, "vigilia_valor": {"aprendido": True},
            "vigilia_x2": {"muestras": 8, "max_muestras": 32}, "vigilia_h8": {"horizonte": 8}}
ELO_ANCLA = 1500.0
_K = math.log(10) / 400

_INIT_CONGELADO = '''"""Copia congelada de la IA (myl_sim.arena). Las reglas son las actuales."""
import importlib
import sys

for _n in ("modelo", "motor", "habilidades", "datos", "entrenamiento", "simulacion",
           "informe_entrenamiento", "auditoria"):
    _m = importlib.import_module("myl_sim." + _n)
    sys.modules[__name__ + "." + _n] = _m
    globals()[_n] = _m
'''


# ── Motores ───────────────────────────────────────────────────────────────────
@functools.lru_cache(maxsize=None)
def huella_ia(raiz: Path | None = None) -> str:
    """Se calcula una vez por proceso: una corrida larga no cambia de
    identidad aunque alguien edite la IA mientras tanto."""
    raiz = raiz or Path(__file__).resolve().parent
    h = hashlib.sha256()
    for nombre in ARCHIVOS_IA:
        f = raiz / nombre
        if f.exists():
            h.update(nombre.encode() + b"\0" + f.read_bytes().replace(b"\r\n", b"\n"))
    return h.hexdigest()[:6]


def _paquete(etiqueta: str) -> str:
    return f"myl_ia_{etiqueta}"


def congelar(etiqueta: str) -> Path:
    """Copia los archivos de IA de hoy como versión `etiqueta`."""
    if not etiqueta.isidentifier():
        raise ValueError("La etiqueta solo puede tener letras, números y _")
    destino = VERSIONES / _paquete(etiqueta)
    if destino.exists():
        raise FileExistsError(f"Ya existe la versión «{etiqueta}»")
    destino.mkdir(parents=True)
    raiz = Path(__file__).resolve().parent
    for nombre in ARCHIVOS_IA:
        if (raiz / nombre).exists():
            shutil.copy2(raiz / nombre, destino / nombre)
    (destino / "__init__.py").write_text(_INIT_CONGELADO, encoding="utf-8")
    return destino


def versiones() -> list[str]:
    if not VERSIONES.exists():
        return []
    return sorted(d.name[len("myl_ia_"):] for d in VERSIONES.iterdir() if d.name.startswith("myl_ia_"))


def _modulo(etiqueta: str | None, nombre: str):
    if etiqueta is None:
        return importlib.import_module(f"myl_sim.{nombre}")
    if str(VERSIONES) not in sys.path:
        sys.path.insert(0, str(VERSIONES))
    if not (VERSIONES / _paquete(etiqueta)).exists():
        raise ValueError(f"No existe la versión congelada «{etiqueta}»")
    return importlib.import_module(f"{_paquete(etiqueta)}.{nombre}")


def partes(motor: str) -> tuple[str, str | None]:
    nombre, _, etiqueta = motor.partition("@")
    if nombre not in MOTORES:
        raise ValueError(f"Motor desconocido: {nombre}. Opciones: {', '.join(MOTORES)}")
    return nombre, etiqueta or None


def _etiqueta_de_huella() -> dict[str, str]:
    return {huella_ia(VERSIONES / _paquete(e)): e for e in reversed(versiones())}


def identidad(motor: str) -> str:
    """Nombre con el que el motor entra al ranking. La IA actual, si es
    idéntica a una versión congelada, cuenta como esa versión."""
    nombre, etiqueta = partes(motor)
    if etiqueta or nombre == "aleatorio":
        return motor
    return _normalizar(f"{nombre}#{huella_ia()}", _etiqueta_de_huella())


def _normalizar(identidad_: str, etiquetas: dict[str, str]) -> str:
    nombre, _, huella = identidad_.partition("#")
    return f"{nombre}@{etiquetas[huella]}" if huella in etiquetas else identidad_


def crear(motor: str, seed: int):
    """El jugador de `motor`. Sin límites de tiempo: mismo resultado en cada corrida."""
    nombre, etiqueta = partes(motor)
    jug = _modulo(etiqueta, "jugadores")
    if nombre == "aleatorio":
        return jug.Aleatorio(seed)
    if nombre == "heuristico":
        return jug.Heuristico(seed)
    if nombre.startswith("nivel"):
        from .desafio import PoliticaDificultad

        return PoliticaDificultad(jug.Heuristico(seed), int(nombre[5:]), seed + 3)
    if nombre == "experto":
        bloqueos = _modulo(etiqueta, "busqueda_bloqueos")
        return bloqueos.PoliticaConBusqueda(jug.Heuristico(seed), seed, max_segundos=None)
    if nombre in _VIGILIA:
        return _modulo(etiqueta, "busqueda_vigilia").BuscadorVigilia(seed, **_VIGILIA[nombre])
    return getattr(_modulo(etiqueta, "busqueda_ataques"),
                   "BuscadorAtaques" if nombre == "busqueda_ataques" else "BuscadorCompleto")(seed)


# ── Partidas ──────────────────────────────────────────────────────────────────
def jugar_par(args) -> dict:
    """Dos partidas con los motores intercambiados. `r`: puntos de X en cada
    una (1 gana, 0 pierde, 0.5 empate, None anómala o con error)."""
    from .motor import Partida

    x, y, mazo_a, mazo_b, seed = args
    puntos, segundos, error, desviaciones, precision = [], [], None, [], []
    for lado_x in (0, 1):
        motores = (x, y) if lado_x == 0 else (y, x)
        inicio = time.monotonic()
        try:
            jugadores = (crear(motores[0], seed * 2), crear(motores[1], seed * 2 + 1))
            for lado, jug in enumerate(jugadores):
                # Los buscadores anotan cada vez que se apartan de la heurística.
                if "@" not in motores[lado] and getattr(jug, "registro", 0) is None:
                    jug.registro = []
            p = Partida((mazo_a.cartas, mazo_b.cartas), jugadores, nombres=(mazo_a.nombre, mazo_b.nombre),
                        inicial=seed % 2, seed=seed)
            g = p.jugar().ganador
            puntos.append(None if g == -2 else 0.5 if g == -1 else 1.0 if g == lado_x else 0.0)
            for lado, jug in enumerate(jugadores):
                registro = getattr(jug, "registro", None)
                for d in registro or []:
                    desviaciones.append({**d, "motor": identidad(motores[lado]), "seed": seed,
                                         "gano": g == lado})
                if registro is not None:
                    precision.append({"motor": identidad(motores[lado]), "mazo": (mazo_a, mazo_b)[lado].nombre,
                                      "seed": seed, "revisadas": _conteos(jug, "busquedas"),
                                      "distintas": _conteos(jug, "desviaciones"),
                                      "puntos": round(sum(d["est_ahora"] - d["est_antes"] for d in registro), 3)})
        except Exception as e:  # una versión congelada puede no entender reglas nuevas
            puntos.append(None)
            error = f"{type(e).__name__}: {e}"[:200]
        segundos.append(round(time.monotonic() - inicio, 2))
    out = {"x": identidad(x), "y": identidad(y), "a": mazo_a.id, "b": mazo_b.id, "seed": seed,
           "r": puntos, "seg": segundos}
    if error:
        out["error"] = error
    if desviaciones:
        out["desviaciones"] = desviaciones
    if precision:
        out["precision"] = precision
    return out


def jugar(motores: list[str], mazos: list, pares: int, *, seed: int = 1,
          procesos: int | None = None, guardar: bool = True, progreso=None) -> list[dict]:
    """Todos contra todos entre `motores`, `pares` pares por enfrentamiento.
    Cada enfrentamiento usa los mismos mazos y semillas."""
    from concurrent.futures import ProcessPoolExecutor

    for m in motores:
        partes(m)
    rng = random.Random(seed)
    sorteos = []
    for k in range(pares):
        a, b = rng.sample(mazos, 2) if len(mazos) > 1 else (mazos[0], mazos[0])
        sorteos.append((a, b, seed * 1_000_003 + k))
    trabajos = [(x, y, a, b, s)
                for i, x in enumerate(motores) for y in motores[i + 1:] for a, b, s in sorteos]
    out = []
    if procesos == 1:
        iterador = map(jugar_par, trabajos)
        cerrar = lambda: None  # noqa: E731
    else:
        ex = ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1))
        iterador = ex.map(jugar_par, trabajos)
        cerrar = ex.shutdown
    try:
        for k, r in enumerate(iterador, 1):
            desviaciones = r.pop("desviaciones", [])
            precision = r.pop("precision", [])
            out.append(r)
            if guardar:
                CARPETA.mkdir(parents=True, exist_ok=True)
                with PARTIDAS.open("a", encoding="utf-8") as f:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
                with DESVIACIONES.open("a", encoding="utf-8") as f:
                    for d in desviaciones:
                        f.write(json.dumps(d, ensure_ascii=False) + "\n")
                with PRECISION.open("a", encoding="utf-8") as f:
                    for d in precision:
                        f.write(json.dumps(d, ensure_ascii=False) + "\n")
            if progreso:
                progreso(k, len(trabajos))
    finally:
        cerrar()
    return out


_DECISIONES = {"ataque": "", "vigilia": "_vigilia", "objetivo": "_objetivo", "guerra": "_guerra",
               "oro": "_oro", "activar_oro": "_act_oro", "mano": "_mano"}


def _conteos(jugador, prefijo: str) -> dict[str, int]:
    return {tipo: getattr(jugador, prefijo + sufijo, 0) for tipo, sufijo in _DECISIONES.items()}


def precision_md(filas: list[dict]) -> str:
    """Precisión de la heurística: en cuántas decisiones revisadas por la
    búsqueda la jugada de la heurística era también la de la búsqueda. La
    búsqueda solo se aparta con ventaja clara, así que cada «distinta» es un
    error probable de la heurística."""
    def fila(nombre, grupo, tipos=tuple(_DECISIONES)):
        rev = sum(f["revisadas"][t] for f in grupo for t in tipos)
        dis = sum(f["distintas"][t] for f in grupo for t in tipos)
        return rev, dis, f"| {nombre} | {rev} | {dis} | {(1 - dis / rev) * 100 if rev else 100:.1f}% |"

    lineas = ["| Decisión | Revisadas | Distintas | Precisión |", "|---|---|---|---|"]
    lineas += [fila(t, filas, (t,))[2] for t in _DECISIONES]
    lineas.append(fila("**total**", filas)[2])
    por_mazo: dict[str, list[dict]] = {}
    for f in filas:
        por_mazo.setdefault(f["mazo"], []).append(f)
    lineas += ["", "| Mazo | Partidas | Revisadas | Distintas | Precisión | Errores por partida | Puntos perdidos por partida |",
               "|---|---|---|---|---|---|---|"]
    orden = sorted(por_mazo.items(), key=lambda x: -sum(sum(f["distintas"].values()) for f in x[1]) / len(x[1]))
    for mazo, g in orden:
        rev, dis, texto = fila(mazo, g)
        partes_ = texto.split(" | ")
        lineas.append(f"| {mazo} | {len(g)} | {rev} | {dis} | {partes_[-1].rstrip(' |')} | {dis / len(g):.1f} "
                      f"| {sum(f['puntos'] for f in g) / len(g) * 100:.0f} |")
    return "\n".join(lineas)


def leer_precision(motor: str | None = None) -> list[dict]:
    if not PRECISION.exists():
        return []
    filas = [json.loads(x) for x in PRECISION.read_text(encoding="utf-8").splitlines() if x.strip()]
    return [f for f in filas if not motor or f["motor"] == motor]


def leer_partidas() -> list[dict]:
    if not PARTIDAS.exists():
        return []
    etiquetas = _etiqueta_de_huella()
    out = []
    for linea in PARTIDAS.read_text(encoding="utf-8").splitlines():
        if linea.strip():
            r = json.loads(linea)
            r["x"], r["y"] = _normalizar(r["x"], etiquetas), _normalizar(r["y"], etiquetas)
            out.append(r)
    return out


# ── Resultados ────────────────────────────────────────────────────────────────
def duelo(registros: list[dict], x: str, y: str) -> dict | None:
    """Resultado de X contra Y por pares (IC95 pareado)."""
    por_par = []
    errores = 0
    for r in registros:
        if {r["x"], r["y"]} != {x, y} or r["x"] == r["y"]:
            continue
        if None in r["r"]:
            errores += 1
            continue
        medio = sum(r["r"]) / 2
        por_par.append(medio if r["x"] == x else 1 - medio)
    n = len(por_par)
    if not n:
        return None
    media = sum(por_par) / n
    var = sum((v - media) ** 2 for v in por_par) / (n - 1) if n > 1 else 0.25
    margen = 1.96 * math.sqrt(var / n)
    return {"x": x, "y": y, "pares": n, "descartados": errores, "puntos": round(media, 4),
            "ic95": [round(media - margen, 4), round(media + margen, 4)],
            "elo": round(_dif_elo(media)), "claro": media - margen > 0.5 or media + margen < 0.5}


def _dif_elo(puntos: float) -> float:
    q = min(0.999, max(0.001, puntos))
    return -400 * math.log10(1 / q - 1)


def elo(registros: list[dict], ancla: str | None = None) -> list[dict]:
    """Ranking Bradley-Terry en escala Elo, con `ancla` fija en 1500. Cada
    motor recibe además un empate virtual contra un rival de 1500 para que un
    100 % no dé un Elo infinito (y un grupo sin cruces con el ancla quede cerca)."""
    puntos: dict[tuple[str, str], list[float]] = {}  # (i, j) → [puntos de i, partidas]
    for r in registros:
        if r["x"] == r["y"]:
            continue
        for v in r["r"]:
            if v is None:
                continue
            for i, j, s in ((r["x"], r["y"], v), (r["y"], r["x"], 1 - v)):
                c = puntos.setdefault((i, j), [0.0, 0])
                c[0] += s
                c[1] += 1
    motores = sorted({i for i, _ in puntos})
    if not motores:
        return []
    e = {m: ELO_ANCLA for m in motores}
    info = dict.fromkeys(motores, 0.0)
    for _ in range(500):
        cambio = 0.0
        for i in motores:
            esperado = 1 / (1 + 10 ** ((ELO_ANCLA - e[i]) / 400))
            grad, inf = 0.5 - esperado, esperado * (1 - esperado)  # el empate virtual contra 1500
            for (a, j), (s, n) in puntos.items():
                if a != i:
                    continue
                q = 1 / (1 + 10 ** ((e[j] - e[i]) / 400))
                grad += s - n * q
                inf += n * q * (1 - q)
            info[i] = inf
            if i == ancla:
                continue
            paso = max(-200.0, min(200.0, grad / (inf * _K)))
            e[i] += paso
            cambio = max(cambio, abs(paso))
        if cambio < 0.01:
            break
    out = []
    for m in motores:
        n = sum(c[1] for (a, _), c in puntos.items() if a == m)
        s = sum(c[0] for (a, _), c in puntos.items() if a == m)
        out.append({"motor": m, "elo": round(e[m]),
                    "margen": round(1.96 / (_K * math.sqrt(info[m]))),
                    "partidas": n, "puntos": round(s / n, 3)})
    return sorted(out, key=lambda x: -x["elo"])


def desviaciones_md(filas: list[dict], top: int = 15) -> str:
    """Dónde la búsqueda se aparta de la heurística: cada patrón repetido es
    una regla candidata para la heurística (y luego se mide en la arena)."""
    grupos: dict[tuple, list[dict]] = {}
    por_tipo: dict[str, list[dict]] = {}
    for d in filas:
        grupos.setdefault((d["tipo"], d["mi_mazo"], d["antes"], d["ahora"]), []).append(d)
        por_tipo.setdefault(d["tipo"], []).append(d)
    ganancia = lambda g: sum(d["est_ahora"] - d["est_antes"] for d in g) / len(g) * 100  # noqa: E731
    lineas = ["| Decisión | Veces | Ganancia estimada |", "|---|---|---|"]
    for tipo, g in sorted(por_tipo.items(), key=lambda x: -len(x[1])):
        lineas.append(f"| {tipo} | {len(g)} | +{ganancia(g):.0f} pts |")
    lineas += ["", "| Veces | Mazo | Decisión | La heurística | La búsqueda | Ganancia |", "|---|---|---|---|---|---|"]
    orden = sorted(grupos.items(), key=lambda x: -len(x[1]) * ganancia(x[1]))
    for (tipo, mazo, antes, ahora), g in orden[:top]:
        lineas.append(f"| {len(g)} | {mazo} | {tipo} | {antes} | {ahora} | +{ganancia(g):.0f} pts |")
    return "\n".join(lineas)


def leer_desviaciones() -> list[dict]:
    if not DESVIACIONES.exists():
        return []
    return [json.loads(x) for x in DESVIACIONES.read_text(encoding="utf-8").splitlines() if x.strip()]


def ancla_guardada() -> str | None:
    if CONFIG.exists():
        return json.loads(CONFIG.read_text(encoding="utf-8")).get("ancla")
    return None


def ranking_md(tabla: list[dict], ancla: str | None) -> str:
    lineas = ["| # | Motor | Elo | ± | Partidas | Puntos |", "|---|---|---|---|---|---|"]
    for k, f in enumerate(tabla, 1):
        marca = " (ancla)" if f["motor"] == ancla else ""
        lineas.append(f"| {k} | {f['motor']}{marca} | {f['elo']} | {f['margen']} | {f['partidas']} "
                      f"| {f['puntos'] * 100:.1f}% |")
    return "\n".join(lineas)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.arena")
    sub = ap.add_subparsers(dest="cmd", required=True)
    j = sub.add_parser("jugar", help="todos contra todos entre los motores indicados")
    j.add_argument("motores", nargs="+")
    j.add_argument("--pares", type=int, default=40)
    j.add_argument("--mazos", nargs="*", help="ids del caché (por defecto, todos los raciales completos)")
    j.add_argument("--seed", type=int, default=1)
    j.add_argument("--procesos", type=int)
    c = sub.add_parser("congelar", help="guarda la IA de hoy como versión")
    c.add_argument("etiqueta")
    c.add_argument("--ancla", action="store_true", help="heuristico@<etiqueta> pasa a valer 1500")
    sub.add_parser("ranking")
    d = sub.add_parser("desviaciones", help="dónde la búsqueda corrige a la heurística")
    d.add_argument("--top", type=int, default=15)
    d.add_argument("--motor", help="solo las de este motor (ej. busqueda_vigilia#3fa2c1)")
    pr = sub.add_parser("precision", help="en cuántas decisiones la heurística coincide con la búsqueda")
    pr.add_argument("--motor")
    sub.add_parser("motores")
    args = ap.parse_args(argv)

    if args.cmd == "congelar":
        print(congelar(args.etiqueta))
        if args.ancla:
            CONFIG.write_text(json.dumps({"ancla": f"heuristico@{args.etiqueta}"}), encoding="utf-8")
        return 0
    if args.cmd == "precision":
        filas = leer_precision(args.motor)
        print(precision_md(filas) if filas else "Todavía no hay partidas con búsqueda guardadas.")
        return 0
    if args.cmd == "desviaciones":
        filas = [d for d in leer_desviaciones() if not args.motor or d["motor"] == args.motor]
        print(desviaciones_md(filas, args.top) if filas else "Todavía no hay desviaciones guardadas.")
        return 0
    if args.cmd == "motores":
        print("Motores:", ", ".join(MOTORES))
        print("Versiones congeladas:", ", ".join(versiones()) or "ninguna", "· IA actual:", huella_ia())
        return 0
    if args.cmd == "jugar":
        from .meta import _mazos_de, raciales_del_cache

        mazos = _mazos_de(args.mazos, True) if args.mazos else raciales_del_cache()
        if len(args.motores) < 2 or not mazos:
            ap.error("Se necesitan al menos dos motores y un mazo")
        inicio = time.monotonic()

        def progreso(k, total):
            if k % 10 == 0 or k == total:
                print(f"{k}/{total} pares · {time.monotonic() - inicio:.0f} s", flush=True)

        nuevos = jugar(args.motores, mazos, args.pares, seed=args.seed, procesos=args.procesos,
                       progreso=progreso)
        ids = [identidad(m) for m in args.motores]
        for i, x in enumerate(ids):
            for y in ids[i + 1:]:
                d = duelo(nuevos, x, y)
                if d:
                    nota = "" if d["claro"] else " · sin diferencia clara"
                    if d["descartados"]:
                        nota += f" · {d['descartados']} pares descartados"
                    print(f"{x} vs {y}: {d['puntos'] * 100:.1f}% (IC95 {d['ic95'][0] * 100:.1f}–"
                          f"{d['ic95'][1] * 100:.1f}) en {d['pares']} pares → {d['elo']:+d} Elo{nota}")
        seg: dict[str, list[float]] = {}
        for r in nuevos:
            seg.setdefault(f"{r['x']} vs {r['y']}", []).extend(r["seg"])
        for k, v in seg.items():
            print(f"  {k}: {sum(v) / len(v):.1f} s por partida")
    ancla = ancla_guardada()
    tabla = elo(leer_partidas(), ancla)
    texto = ranking_md(tabla, ancla)
    if tabla:
        (CARPETA / "ranking.md").write_text(texto + "\n", encoding="utf-8")
        (CARPETA / "ranking.json").write_text(json.dumps({"ancla": ancla, "ranking": tabla}, ensure_ascii=False,
                                                         indent=1), encoding="utf-8")
    print(texto if tabla else "Todavía no hay partidas en la arena.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
