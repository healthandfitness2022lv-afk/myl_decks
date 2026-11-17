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
# Respuestas de una persona que el juez contradice: no son tests; se revisan a mano.
DISPUTA = Path(__file__).resolve().parents[1] / "tests" / "posiciones_en_disputa"
MARGEN_DISPUTA = 0.05


class _Respuesta(Exception):
    def __init__(self, hoy: str, opciones: list[str]):
        super().__init__(hoy)
        self.hoy, self.opciones = hoy, opciones


class PosicionObsoleta(Exception):
    """El motor ya no llega a la misma decisión con lo grabado."""


def decision_actual(pos: dict, clase=None) -> tuple[str, list[str]]:
    """(lo que elige hoy la heurística —o el jugador `clase`—, descripciones de
    las alternativas)."""
    mazos = [Mazo.from_json(m) for m in pos["mazos"]]
    k = pos["paso"]
    registro = pos["registro"]
    entrada = registro[k]

    def opcion(p, metodo, args):
        elegida = _decodificar(p, entrada["v"], args)
        opciones = alternativas(metodo, args, elegida, p)
        hoy = getattr((clase or Heuristico)(pos.get("semillaIa", pos["seed"])), metodo)(*args)
        clave = _clave(hoy)
        texto = next((t for t, v in opciones if _clave(v) == clave), None) or describir(metodo, hoy, args)
        raise _Respuesta(texto, [t for t, _ in opciones])

    try:
        reproducir(tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos), pos["seed"],
                   registro, rama=k, opcion=opcion, metodos=pos.get("metodos"), ocultar=False)
    except _Respuesta as r:
        return r.hoy, r.opciones
    except _Desvio:
        pass
    raise PosicionObsoleta(pos.get("nombre", "?"))


def turno_actual(pos: dict, clase=None) -> list[str]:
    """Cómo juega hoy el turno completo desde la posición (decisiones ordenadas)."""
    from . import turnos

    mazos = [Mazo.from_json(m) for m in pos["mazos"]]
    try:
        r = turnos.jugar(tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos), pos["seed"],
                         pos["registro"], pos["paso"], pos.get("metodos"), pos.get("lado", 1),
                         (clase or Heuristico)(pos.get("semillaIa", pos["seed"])))
    except _Desvio as e:
        raise PosicionObsoleta(pos.get("nombre", "?")) from e
    return sorted(turnos.resumen(r["decisiones"]))


def cumple(pos: dict, clase=None) -> tuple[bool, str]:
    if pos.get("turnoDebe") is not None:
        # Posición de turno completo (dudas resueltas en el tablero).
        hoy = turno_actual(pos, clase)
        if hoy == sorted(pos["turnoDebe"]):
            return True, f"juega «{' → '.join(hoy)}»"
        return False, f"juega «{' → '.join(hoy)}», debía «{' → '.join(sorted(pos['turnoDebe']))}»"
    hoy, _ = decision_actual(pos, clase)
    if pos.get("debe") is not None and hoy != pos["debe"]:
        return False, f"elige «{hoy}», debía «{pos['debe']}»"
    if pos.get("noDebe") is not None and hoy == pos["noDebe"]:
        return False, f"vuelve a elegir «{hoy}»"
    return True, f"elige «{hoy}»"


def cargar_todas() -> list[tuple[Path, dict]]:
    return [(f, json.loads(f.read_text(encoding="utf-8"))) for f in sorted(CARPETA.glob("*.json"))]


def _nombre_archivo(texto: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", texto.lower()).strip("_")[:60] or "posicion"


def fijar(base: dict, *, debe: str | None, no_debe: str | None, nombre: str | None, clase=None) -> Path:
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
    # (`clase`: el jugador que la cometió; por defecto la heurística.)
    try:
        pos["pendiente"] = not cumple(pos, clase)[0]
    except PosicionObsoleta:
        pos["pendiente"] = True
    if clase is not None:
        pos["jugador"] = getattr(clase, "nombre", None) or "heuristico"
    CARPETA.mkdir(parents=True, exist_ok=True)
    destino = CARPETA / f"{_nombre_archivo(pos['nombre'])}.json"
    destino.write_text(json.dumps(pos, ensure_ascii=False), encoding="utf-8")
    return destino


# ── Banco: cosecha automática y puntaje ───────────────────────────────────────
MARGEN_CONFIRMAR = 0.20


def _cosechar(args) -> list[dict]:
    """Errores del perdedor de una partida, reconfirmados con más muestras."""
    from .autopsia import revisar_decision
    from .mineria import minar_partida

    mazo_a, mazo_b, seed, revisar, muestras, confirmar = args
    out = []
    try:
        lecciones = minar_partida(mazo_a, mazo_b, seed, revisar=revisar, muestras=muestras)
        for x in lecciones:
            r = revisar_decision((mazo_a.cartas, mazo_b.cartas), (mazo_a.nombre, mazo_b.nombre), seed,
                                 x["registro"], x["revision"]["paso"], muestras=confirmar, metodos=x["metodos"])
            if r is None:
                continue
            r.pop("_elegir", None)
            # Firme: con más muestras sigue habiendo una opción claramente mejor.
            if r["error"] and r["ganaMejor"] - r["ganaElegida"] >= MARGEN_CONFIRMAR:
                out.append({**x, "revision": {**x["revision"], **r, "muestras": confirmar},
                            "mazos": [mazo_a.to_json(), mazo_b.to_json()]})
    except Exception:  # noqa: BLE001 - una partida rota no detiene la cosecha
        return []
    return out


def cosechar(partidas: int, *, seed: int = 1, revisar: int = 3, muestras: int = 10, confirmar: int = 40,
             procesos: int | None = None, log=print) -> list[Path]:
    """Juega heurística contra heurística entre los mazos válidos, busca los
    errores del perdedor y fija como posición solo los que se confirman."""
    import os
    import random
    from concurrent.futures import ProcessPoolExecutor

    from .meta import raciales_del_cache

    mazos = raciales_del_cache()
    rng = random.Random(seed)
    tareas = []
    for k in range(partidas):
        a, b = rng.sample(mazos, 2)
        tareas.append((a, b, seed * 1_000_003 + k, revisar, muestras, confirmar))
    guardadas, ya = [], {pos.get("id") for _, pos in cargar_todas()}
    with ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1)) as ex:
        for n, lecciones in enumerate(ex.map(_cosechar, tareas, chunksize=2), 1):
            for x in lecciones:
                if x["id"] in ya:
                    continue
                r = x["revision"]
                nombre = f"{x['mazo']} T{r.get('turno')} {r['tipo']} {x['id']}"
                guardadas.append(fijar(x, debe=None, no_debe=None, nombre=nombre))
                ya.add(x["id"])
            if n % 20 == 0 or n == partidas:
                log(f"{n}/{partidas} partidas · {len(guardadas)} posiciones nuevas")
    return guardadas


def _confirmar_juez(args):
    """Segunda revisión de un error, con otras barajadas y el doble de muestras."""
    from . import precision

    tarea, primera = args
    try:
        r = precision.revisar((*tarea[:6], 12, tarea[7], 48, 1000))
    except Exception:  # noqa: BLE001
        return None
    if r is None or r["clase"] == "exacta" or r["mejor"] != primera["mejor"]:
        return None
    return r


def cosechar_juez(partidas: int, *, jugador: str = "busqueda_vigilia", seed: int = 1, decisiones: int = 12,
                  procesos: int | None = None, log=print) -> list[Path]:
    """Banco desde el juez: juega `jugador` contra sí mismo, el juez (que no ve
    la mano rival) revisa una muestra de decisiones y cada error se confirma
    con otras barajadas. Solo los que se repiten en las dos revisiones quedan
    como posición: «no debe» repetir la jugada mala (cualquier otra que no sea
    esa vale, no se exige un texto exacto)."""
    import os
    from concurrent.futures import ProcessPoolExecutor

    from . import precision

    pares = precision.revisiones_motor(jugador, partidas, seed=seed, max_decisiones=decisiones,
                                       procesos=procesos, log=log, con_tareas=True)
    sospechas = [(t, r) for t, r in pares if r["clase"] != "exacta"]
    log(f"{len(pares)} decisiones revisadas · {len(sospechas)} errores por confirmar")
    guardadas, ya = [], {pos.get("id") for _, pos in cargar_todas()}
    with ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1)) as ex:
        for (tarea, primera), r in zip(sospechas, ex.map(_confirmar_juez, sospechas)):
            if r is None:
                continue
            cartas, nombres, semilla, registro, metodos, k = tarea[:6]
            ident = f"juez_{jugador.partition('@')[0]}_{semilla}_{k}"
            if ident in ya:
                continue
            from .datos import Mazo

            mazos = [Mazo(f"m{i}", nombres[i], "racial", "", list(cartas[i]), []).to_json() for i in (0, 1)]
            revision = {"paso": k, "lado": r["lado"], "turno": r["turno"], "fase": r["fase"], "tipo": r["tipo"],
                        "elegida": r["elegida"], "mejor": r["mejor"], "error": True,
                        "ganaElegida": r["ganaElegida"], "ganaMejor": r["ganaMejor"],
                        "perdida": r["perdida"], "ee": r["ee"], "muestras": r["muestras"],
                        "perdidaPrimera": primera["perdida"], "juez": "manoOculta"}
            base = {"origen": "juez", "id": ident, "seed": semilla, "semillaIa": semilla * 2 + r["lado"],
                    "metodos": metodos, "registro": registro, "mazos": mazos, "revision": revision}
            nombre = f"juez {nombres[r['lado']]} T{r['turno']} {r['tipo']} {semilla}_{k}"
            guardadas.append(fijar(base, debe=None, no_debe=r["elegida"], nombre=nombre, clase=_clase_de(jugador)))
            ya.add(ident)
    return guardadas


def _clase_de(jugador: str):
    """Fábrica `seed → jugador` para un motor de la arena o de JUGADORES."""
    from . import arena, busqueda_vigilia  # noqa: F401 - registra los buscadores
    from .jugadores import JUGADORES

    if jugador in JUGADORES:
        return JUGADORES[jugador]

    def crear(seed):
        return arena.crear(jugador, seed)

    crear.nombre = jugador
    return crear


def en_disputa(pos: dict) -> bool:
    """Respuesta de una persona que la simulación contradice con margen."""
    r = pos.get("revision") or {}
    if pos.get("origen") != "duda" or not r.get("error"):
        return False
    tuya, ia = r.get("ganaMejor"), r.get("ganaElegida")
    return tuya is not None and ia is not None and ia >= tuya + MARGEN_DISPUTA


def apartar_disputas(log=print) -> list[Path]:
    """Saca del banco las respuestas que el juez contradice y deja la lista
    para revisarlas con la persona (`en_disputa.md`)."""
    DISPUTA.mkdir(parents=True, exist_ok=True)
    movidas = []
    for archivo, pos in cargar_todas():
        if en_disputa(pos):
            destino = DISPUTA / archivo.name
            archivo.replace(destino)
            movidas.append(destino)
    lineas = ["# Posiciones en disputa", "",
              "Respuestas tuyas que la simulación contradice. No son tests: hay que revisarlas una por una.",
              "Si tu jugada era la buena, el juez tiene un punto ciego ahí; si no, se descartan.", "",
              "| Posición | Tu jugada | La de la IA | Tuya | IA |", "|---|---|---|---|---|"]
    for f in sorted(DISPUTA.glob("*.json")):
        r = json.loads(f.read_text(encoding="utf-8"))["revision"]
        lineas.append(f"| {f.stem} | {r['mejor']} | {r['elegida']} | {r['ganaMejor'] * 100:.0f}% "
                      f"| {r['ganaElegida'] * 100:.0f}% |")
    (DISPUTA / "en_disputa.md").write_text("\n".join(lineas) + "\n", encoding="utf-8")
    log(f"{len(movidas)} posiciones pasaron a {DISPUTA.name}/")
    return movidas


def puntaje(clase=None) -> dict:
    """Cuántas posiciones del banco resuelve un jugador (por defecto la
    heurística): la nota de exactitud que se compara entre versiones."""
    total = bien = obsoletas = 0
    por_tipo: dict[str, list[int]] = {}
    por_origen: dict[str, list[int]] = {}
    fallas = []
    for archivo, pos in cargar_todas():
        try:
            ok, texto = cumple(pos, clase)
        except PosicionObsoleta:
            obsoletas += 1
            continue
        total += 1
        bien += ok
        t = por_tipo.setdefault(pos.get("tipo", "?"), [0, 0])
        t[0] += ok
        t[1] += 1
        o = por_origen.setdefault(pos.get("origen") or "?", [0, 0])
        o[0] += ok
        o[1] += 1
        if not ok:
            fallas.append(f"{archivo.stem}: {texto}")
    return {"resueltas": bien, "total": total, "obsoletas": obsoletas,
            "porcentaje": round(bien / total * 100, 1) if total else None,
            "porTipo": {k: f"{a}/{b}" for k, (a, b) in sorted(por_tipo.items())},
            "porOrigen": {k: f"{a}/{b}" for k, (a, b) in sorted(por_origen.items())}, "fallas": fallas}


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
    c = sub.add_parser("cosechar", help="jugar, buscar errores firmes y fijarlos solos")
    c.add_argument("--partidas", type=int, default=300)
    c.add_argument("--seed", type=int, default=1)
    c.add_argument("--confirmar", type=int, default=40)
    c.add_argument("--procesos", type=int)
    cj = sub.add_parser("cosechar-juez", help="errores de un motor confirmados por el juez (mano rival oculta)")
    cj.add_argument("--jugador", default="busqueda_vigilia")
    cj.add_argument("--partidas", type=int, default=40)
    cj.add_argument("--decisiones", type=int, default=12)
    cj.add_argument("--seed", type=int, default=1)
    cj.add_argument("--procesos", type=int)
    sub.add_parser("disputa", help="aparta las respuestas de dudas que el juez contradice")
    pt = sub.add_parser("puntaje", help="cuántas posiciones resuelve un jugador")
    pt.add_argument("--jugador", default="heuristico")
    pt.add_argument("--fallas", action="store_true")
    a = ap.parse_args(argv)
    if a.cmd == "cosechar":
        nuevas = cosechar(a.partidas, seed=a.seed, confirmar=a.confirmar, procesos=a.procesos)
        print(f"{len(nuevas)} posiciones nuevas en {CARPETA}")
        return
    if a.cmd == "cosechar-juez":
        nuevas = cosechar_juez(a.partidas, jugador=a.jugador, seed=a.seed, decisiones=a.decisiones,
                               procesos=a.procesos)
        print(f"{len(nuevas)} posiciones nuevas en {CARPETA}")
        return
    if a.cmd == "disputa":
        apartar_disputas()
        return
    if a.cmd == "puntaje":
        r = puntaje(_clase_de(a.jugador))
        print(f"{a.jugador}: {r['resueltas']} de {r['total']} posiciones ({r['porcentaje']}%)"
              f" · por tipo {r['porTipo']} · por origen {r['porOrigen']} · obsoletas {r['obsoletas']}")
        if a.fallas:
            print("\n".join(r["fallas"]))
        return
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
