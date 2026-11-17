"""Dudas de la IA: posiciones donde no sabe qué jugar y le pregunta a una persona.

La IA juega contra sí misma (heurística contra heurística, mazos válidos) con
todas las decisiones grabadas. En cada decisión con alternativas simula cada
opción con las mismas barajadas (`MUESTRAS` muestras, `TURNOS` turnos) y se
queda con las posiciones donde **duda**:

- la partida no está decidida (ni ganada ni perdida de antemano), y
- hay dos opciones que la simulación no logra separar, o la simulación
  prefiere otra jugada que la que eligió la regla sin diferencia firme.

Cada duda guarda lo necesario para reproducirla. En la app (`atender_desafio`)
la persona se sienta en el asiento del jugador y juega en el tablero **todo lo
que queda de ese turno**; el rival responde con la heurística. Después la IA
juega ese mismo turno desde la misma posición y con el mismo orden de mazo, y
se comparan las dos mesas resultantes simulando hacia adelante (`turnos`). El
turno de la persona queda fijado en el banco (`tests/posiciones/`) como el
correcto; si la simulación prefiere el de la IA, ahí hay un punto ciego del
juez o una trampa de la posición. Por consola (`responder`) se contesta solo
la decisión puntual.

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.dudas generar --partidas 20 --max 12
  .venv/Scripts/python -m myl_sim.dudas ver
  .venv/Scripts/python -m myl_sim.dudas responder <id> <letra> [--porque "texto"]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random

from .autopsia import Horizonte, REVISABLES, _decodificar, reproducir
from .datos import CACHE
from .precision import _opciones, jugar_grabada

CARPETA = CACHE / "dudas"
PENDIENTES = CARPETA / "pendientes.jsonl"
RESPUESTAS = CARPETA / "respuestas.jsonl"
MUESTRAS = 10
TURNOS = 3
CERCA = 0.05           # dos opciones a menos de 5 puntos: la simulación no decide
RANGO = (0.20, 0.80)   # fuera de esto la partida ya está resuelta
IMPORTA = 0.10         # alguna opción debe ser claramente peor: si todas rinden igual, da lo mismo
LETRAS = "abcdefgh"


def _situacion(p, yo: int) -> dict:
    from . import habilidades as hab

    mio, suyo = p.j(yo), p.j(1 - yo)
    mesa = lambda j: [f"{a.nombre} ({hab.fuerza(p, a)})" for a in j.aliados]  # noqa: E731
    oros = lambda j: sorted(x.nombre for x in j.reserva + j.pagado)  # noqa: E731
    otras = lambda j: sorted(x.nombre for x in j.apoyo) + sorted(  # noqa: E731
        f"{a.nombre} (arma)" for a in p.e.portadas if a.controlador == j.indice)
    return {
        "turno": p.e.turno, "fase": p.e.fase, "mazo": mio.nombre_mazo, "rival": suyo.nombre_mazo,
        "miCastillo": len(mio.mazo), "suCastillo": len(suyo.mazo),
        "misOrosDisponibles": mio.oro_disponible, "susOrosDisponibles": suyo.oro_disponible,
        "miMano": sorted(c.nombre for c in mio.mano), "suMano": len(suyo.mano),
        "miMesa": mesa(mio), "suMesa": mesa(suyo), "misOros": oros(mio), "susOros": oros(suyo),
        "misOtras": otras(mio), "susOtras": otras(suyo),
        "miCementerio": sorted(c.nombre for c in mio.cementerio)[:40],
        "suCementerio": sorted(c.nombre for c in suyo.cementerio)[:40],
    }


def examinar(args) -> dict | None:
    """La decisión k como duda, o None si no lo es."""
    from .busqueda_ataques import valor_estado

    cartas, nombres, seed, registro, metodos, k, muestras, turnos = args
    entrada = registro[k]
    lado = entrada["lado"]
    textos: list[str] = []
    situacion: dict = {}

    def elegir(indice):
        def opcion(p, metodo, a):
            opciones = _opciones(metodo, a, _decodificar(p, entrada["v"], a), p)
            if not textos:
                textos.extend(t for t, _ in opciones)
                try:
                    situacion.update(_situacion(p, lado))
                    if metodo == "elegir_objetivos":
                        # De qué carta es la habilidad que está eligiendo y qué hace.
                        fuente = getattr(p, "ctx_fuente_habilidad", None)
                        h = a[4] if len(a) > 4 and isinstance(a[4], dict) else {}
                        situacion["habilidad"] = {"carta": getattr(fuente, "nombre", None),
                                                  "accion": h.get("featureName") or h.get("accion"),
                                                  "zona": (h.get("objetivo") or {}).get("zona")}
                except Exception:  # noqa: BLE001 - sin situación no hay pregunta
                    pass
            p.horizonte = p.e.turno + turnos
            return opciones[min(indice, len(opciones) - 1)][1]
        return opcion

    valores: list[list[float]] = []
    indice = 0
    while indice == 0 or indice < len(textos):
        fila = []
        for m in range(muestras):
            try:
                g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=elegir(indice), muestra=m,
                               metodos=metodos)
            except Horizonte as h:
                fila.append(valor_estado(h.partida, lado))
                continue
            if g is None:
                return None
            fila.append(1.0 if g == lado else 0.5 if g == -1 else 0.0)
        if len(textos) < 2 or not situacion:
            return None
        valores.append(fila)
        indice += 1
    # Opciones con el mismo texto (dos copias de la misma carta) son la misma jugada.
    unicas: dict[str, int] = {}
    for i, t in enumerate(textos):
        unicas.setdefault(t, i)
    if len(unicas) < 2:
        return None
    medias = {t: sum(valores[i]) / len(valores[i]) for t, i in unicas.items()}
    orden = sorted(unicas, key=lambda t: -medias[t])
    mejor, segunda, elegida = orden[0], orden[1], textos[0]
    if not RANGO[0] <= medias[mejor] <= RANGO[1] or medias[mejor] - medias[orden[-1]] < IMPORTA:
        return None
    if medias[elegida] < RANGO[0] / 2:
        return None  # con la jugada de la IA ya estaba perdida: no es una duda, es un error (va al juez)
    motivo = None
    if medias[mejor] - medias[segunda] <= CERCA:
        motivo = "la simulación no separa las dos mejores opciones"
    elif mejor != elegida:
        d = [a - b for a, b in zip(valores[unicas[mejor]], valores[0])]
        media = sum(d) / len(d)
        ee = math.sqrt(sum((x - media) ** 2 for x in d) / (len(d) - 1) / len(d)) if len(d) > 1 else 0.0
        if not ee or media < 2 * ee:
            motivo = "la simulación prefiere otra jugada que la regla, sin diferencia firme"
    if motivo is None:
        return None
    opciones = orden[:len(LETRAS)]
    if elegida not in opciones:
        opciones[-1] = elegida
    random.Random(seed * 131 + k).shuffle(opciones)  # sin pista de cuál prefiere la IA
    return {
        "id": f"{seed}_{k}", "motivo": motivo, "tipo": entrada["m"].replace("elegir_", ""),
        "situacion": situacion, "opciones": opciones, "eligioIa": elegida,
        "estimaciones": {t: round(medias[t], 3) for t in opciones},
        "brecha": round(medias[mejor] - medias[segunda], 3),
        "lado": lado, "paso": k, "seed": seed, "semillaIa": seed * 2 + lado, "metodos": metodos,
        "registro": registro[: k + 1],
    }


def _partida(args) -> list[dict]:
    mazo_a, mazo_b, seed, muestras, turnos, por_partida = args[:6]
    jugador = args[6] if len(args) > 6 else "heuristico"
    try:
        ganador, registro, metodos = jugar_grabada(mazo_a, mazo_b, seed, jugador)
        cartas, nombres = (mazo_a.cartas, mazo_b.cartas), (mazo_a.nombre, mazo_b.nombre)
        pasos = [k for k, e in enumerate(registro) if e["m"] in REVISABLES and e.get("turno", 0) >= 3]
        random.Random(seed).shuffle(pasos)
        out = []
        for k in pasos[:40]:
            d = examinar((cartas, nombres, seed, registro, metodos, k, muestras, turnos))
            if d is not None:
                out.append({**d, "mazos": [mazo_a.to_json(), mazo_b.to_json()]})
                if len(out) >= por_partida:
                    break
        return out
    except Exception:  # noqa: BLE001 - una partida rota no detiene la cola
        return []


def generar(partidas: int, maximo: int, *, seed: int = 1, mazos: list | None = None, por_partida: int = 2,
            procesos: int | None = None, log=print, jugador: str = "heuristico") -> list[dict]:
    """Agrega hasta `maximo` dudas nuevas a la cola. A lo más `por_partida`
    por partida y una por tipo de decisión y mazo, para que sean variadas.
    `jugador`: quién juega las partidas (con `busqueda_vigilia` las dudas son
    las de la IA buena: más lentas de generar, pero son las que importan)."""
    from concurrent.futures import ProcessPoolExecutor

    from .meta import raciales_del_cache

    todos = raciales_del_cache()
    propios = mazos or todos
    rng = random.Random(seed)
    tareas = []
    for n in range(partidas):
        a = rng.choice(propios)
        b = rng.choice([m for m in todos if m.id != a.id])
        tareas.append((a, b, seed * 1_000_003 + n, MUESTRAS, TURNOS, por_partida, jugador))
    ya = {d["id"] for d in leer()} | {r["id"] for r in respuestas()}
    vistos, nuevas = set(), []
    CARPETA.mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(procesos or max(1, (os.cpu_count() or 2) - 1)) as ex:
        for n, dudas in enumerate(ex.map(_partida, tareas), 1):
            for d in dudas:
                clave = (d["situacion"]["mazo"], d["tipo"])
                if d["id"] in ya or clave in vistos or len(nuevas) >= maximo:
                    continue
                vistos.add(clave)
                nuevas.append(d)
                with PENDIENTES.open("a", encoding="utf-8") as f:
                    f.write(json.dumps(d, ensure_ascii=False) + "\n")
            if n % 5 == 0 or n == partidas:
                log(f"{n}/{partidas} partidas · {len(nuevas)} dudas")
            if len(nuevas) >= maximo:
                break
    return nuevas


def _leer(archivo) -> list[dict]:
    if not archivo.exists():
        return []
    return [json.loads(x) for x in archivo.read_text(encoding="utf-8").splitlines() if x.strip()]


def respuestas() -> list[dict]:
    return _leer(RESPUESTAS)


def leer() -> list[dict]:
    """Dudas sin responder."""
    hechas = {r["id"] for r in respuestas()}
    return [d for d in _leer(PENDIENTES) if d["id"] not in hechas]


def texto(d: dict, numero: int | None = None) -> str:
    """La pregunta como la ve la persona: sin porcentajes ni la jugada de la IA."""
    s = d["situacion"]
    lista = lambda xs: ", ".join(xs) if xs else "—"  # noqa: E731
    lineas = [
        f"### {'Duda ' + str(numero) + ' · ' if numero else ''}{s['mazo']} contra {s['rival']} · turno {s['turno']} "
        f"({str(s['fase']).replace('_', ' ')}) · `{d['id']}`",
        f"- **Castillos:** tú {s['miCastillo']} · rival {s['suCastillo']}",
        f"- **Tu mano:** {lista(s['miMano'])}",
        f"- **Tu mesa:** {lista(s['miMesa'])}" + (f" · {lista(s['misOtras'])}" if s["misOtras"] else ""),
        f"- **Tus Oros** ({s['misOrosDisponibles']} disponibles): {lista(s['misOros'])}",
        f"- **Mesa rival:** {lista(s['suMesa'])}" + (f" · {lista(s['susOtras'])}" if s["susOtras"] else ""),
        f"- **Rival:** {s['suMano']} cartas en mano · {s['susOrosDisponibles']} Oros disponibles ({lista(s['susOros'])})",
        f"- **Tu Cementerio:** {lista(s['miCementerio'])}",
        f"- **Cementerio rival:** {lista(s['suCementerio'])}",
        "", _pregunta(d),
    ]
    lineas += [f"- **{LETRAS[i]})** {o}" for i, o in enumerate(d["opciones"])]
    return "\n".join(lineas)


def _pregunta(d: dict) -> str:
    h = d["situacion"].get("habilidad") or {}
    if d["tipo"] == "objetivos":
        de = f" de **{h['carta']}**" if h.get("carta") else ""
        que = f" ({h['accion']}" + (f", desde {h['zona']}" if h.get("zona") else "") + ")" if h.get("accion") else ""
        return f"**¿Qué eliges para la habilidad{de}?**{que}"
    return {"jugada": "**¿Cuál es tu siguiente jugada?**", "atacantes": "**¿Con quién atacas?**",
            "bloqueos": "**¿Cómo bloqueas?**"}.get(d["tipo"], "**¿Qué haces?**")


def responder(ident: str, letra: str, porque: str = "", *, confirmar: int = 30, fijar: bool = True) -> dict:
    """Respuesta por letra (consola): la opción elegida entre las listadas."""
    d = next((x for x in _leer(PENDIENTES) if x["id"] == ident), None)
    if d is None:
        raise ValueError(f"No existe la duda {ident}")
    i = LETRAS.index(letra.lower())
    if i >= len(d["opciones"]):
        raise ValueError(f"La duda {ident} no tiene la opción {letra}")
    elegida = d["opciones"][i]
    return registrar(d, elegida, _por_texto(d, elegida), porque, confirmar=confirmar, fijar=fijar)


def _por_texto(d: dict, texto_opcion: str):
    entrada = d["registro"][d["paso"]]

    def elegir(p, metodo, a):
        opciones = _opciones(metodo, a, _decodificar(p, entrada["v"], a), p)
        return next((v for t, v in opciones if t == texto_opcion), opciones[0][1])
    return elegir


def _por_valor(codificado):
    return lambda p, metodo, a: _decodificar(p, codificado, a)


def comparar(d: dict, selectores: dict, muestras: int) -> dict[str, float]:
    """Estimación de cada jugada (nombre → cómo elegirla) con las mismas barajadas."""
    from .busqueda_ataques import valor_estado
    from .datos import Mazo

    mazos = [Mazo.from_json(m) for m in d["mazos"]]
    cartas, nombres = tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos)
    out: dict[str, float] = {}
    for nombre, elegir in selectores.items():
        def opcion(p, metodo, a, _e=elegir):
            p.horizonte = p.e.turno + TURNOS
            return _e(p, metodo, a)
        total = 0.0
        for m in range(muestras):
            try:
                g = reproducir(cartas, nombres, d["seed"], d["registro"], rama=d["paso"], opcion=opcion,
                               muestra=1000 + m, metodos=d["metodos"])
            except Horizonte as h:
                total += valor_estado(h.partida, d["lado"])
                continue
            if g is None:
                return {}
            total += 1.0 if g == d["lado"] else 0.5 if g == -1 else 0.0
        out[nombre] = round(total / muestras, 3)
    return out


def registrar(d: dict, jugada: str, elegir, porque: str = "", *, confirmar: int = 30, fijar: bool = True) -> dict:
    """Guarda la jugada de la persona, la compara con la de la IA en una
    simulación larga y la fija en el banco de posiciones como la correcta."""
    entrada = d["registro"][d["paso"]]
    coincide = jugada == d["eligioIa"]
    estimas = {} if coincide else comparar(d, {"tuya": elegir, "ia": _por_valor(entrada["v"])}, confirmar)
    tuya, ia = estimas.get("tuya"), estimas.get("ia")
    if coincide:
        veredicto = "Coincides con la IA: habría jugado lo mismo."
    elif tuya is None or ia is None:
        veredicto = "Tu jugada quedó guardada; no se pudo simular la comparación."
    elif tuya >= ia + CERCA:
        veredicto = (f"La simulación apoya tu jugada ({tuya * 100:.0f}% contra {ia * 100:.0f}% de la IA). "
                     "Queda como lección para la IA.")
    elif ia >= tuya + CERCA:
        veredicto = (f"La simulación prefiere la jugada de la IA ({ia * 100:.0f}% contra {tuya * 100:.0f}%). "
                     "Queda en disputa para revisarla juntos: puede ser un punto ciego del juez.")
    else:
        veredicto = (f"La simulación no distingue entre las dos ({tuya * 100:.0f}% y {ia * 100:.0f}%). "
                     "Tu jugada queda como la referencia.")
    s = d["situacion"]
    out = {"id": d["id"], "respuesta": jugada, "porque": porque, "eligioIa": d["eligioIa"],
           "coincideConIa": coincide, "estimaTuya": tuya, "estimaIa": ia, "veredicto": veredicto,
           "tipo": d["tipo"], "mazo": s["mazo"], "rival": s["rival"], "turno": s["turno"]}
    if fijar:
        from . import posiciones

        base = {"origen": "duda", "id": d["id"], "seed": d["seed"], "semillaIa": d["semillaIa"],
                "metodos": d["metodos"], "registro": d["registro"], "mazos": d["mazos"],
                "revision": {"paso": d["paso"], "lado": d["lado"], "turno": s["turno"], "tipo": d["tipo"],
                             "elegida": d["eligioIa"], "mejor": jugada, "error": not coincide, "porque": porque,
                             "ganaElegida": ia if ia is not None else 0.0,
                             "ganaMejor": tuya if tuya is not None else 0.0}}
        destino = posiciones.fijar(
            base, debe=jugada, no_debe=None, nombre=f"duda {s['mazo']} T{s['turno']} {d['tipo']} {d['id']}")
        pos = json.loads(destino.read_text(encoding="utf-8"))
        out["enDisputa"] = posiciones.en_disputa(pos)
        if out["enDisputa"]:  # la simulación prefiere la jugada de la IA: no es test
            posiciones.DISPUTA.mkdir(parents=True, exist_ok=True)
            destino = destino.replace(posiciones.DISPUTA / destino.name)
        out["posicion"] = destino.name
    CARPETA.mkdir(parents=True, exist_ok=True)
    with RESPUESTAS.open("a", encoding="utf-8") as f:
        f.write(json.dumps(out, ensure_ascii=False) + "\n")
    return out


# ── En la app: una duda es un desafío de un turno completo ───────────────────
def _vista(partida, lado: int) -> dict:
    """La mesa para la app, con la persona siempre como el lado 0."""
    from .desafio import vista_desafio

    estado = vista_desafio(partida, lado)
    if lado == 1:
        estado["lados"].reverse()
        estado["activo"] = 1 - estado["activo"]
        estado["log"] = [x.replace("Tú", "\0").replace("IA", "Tú").replace("\0", "IA") for x in estado["log"]]
    return estado


def veredicto_turno(coincide: bool, tuya: float | None, ia: float | None) -> str:
    if coincide:
        return "Coincides con la IA: habría jugado el turno igual."
    if tuya is None or ia is None:
        return "Tu turno quedó guardado; no se pudo simular la comparación."
    if tuya >= ia + CERCA:
        return (f"La simulación apoya tu turno ({tuya * 100:.0f}% contra {ia * 100:.0f}% de la IA). "
                "Queda como lección para la IA.")
    if ia >= tuya + CERCA:
        return (f"La simulación prefiere el turno de la IA ({ia * 100:.0f}% contra {tuya * 100:.0f}%). "
                "Queda en disputa para revisarlo juntos: puede ser un punto ciego del juez.")
    return (f"La simulación no distingue entre los dos turnos ({tuya * 100:.0f}% y {ia * 100:.0f}%). "
            "Tu turno queda como la referencia.")


def registrar_turno(d: dict, humano: dict, *, confirmar: int = 24, fijar: bool = True, porque: str = "") -> dict:
    """Compara el turno de la persona (`turnos.jugar`) con el de la IA desde la
    misma posición, lo guarda y lo fija en el banco como el turno correcto."""
    from . import turnos
    from .datos import Mazo

    mazos = [Mazo.from_json(m) for m in d["mazos"]]
    cartas, nombres = tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos)
    lado, k, entrada = d["lado"], d["paso"], d["registro"][d["paso"]]
    ia = turnos.jugar(cartas, nombres, d["seed"], d["registro"], k, d["metodos"], lado,
                      turnos._PrimeraForzada(turnos.Heuristico(d["semillaIa"]), entrada["v"]))
    mio, suyo = turnos.resumen(humano["decisiones"]), turnos.resumen(ia["decisiones"])
    coincide = sorted(mio) == sorted(suyo)
    tuya = ia_estima = None
    if not coincide:
        tuya = turnos.valorar(cartas, nombres, d["seed"], humano["registro"], k, d["metodos"],
                              humano["metodosTurno"], lado, confirmar)
        ia_estima = turnos.valorar(cartas, nombres, d["seed"], ia["registro"], k, d["metodos"],
                                   ia["metodosTurno"], lado, confirmar)
    s = d["situacion"]
    out = {"id": d["id"], "turno": True, "respuesta": mio, "eligioIa": suyo, "porque": porque,
           "coincideConIa": coincide, "estimaTuya": tuya, "estimaIa": ia_estima,
           "veredicto": veredicto_turno(coincide, tuya, ia_estima),
           "tipo": d["tipo"], "mazo": s["mazo"], "rival": s["rival"], "turnoPartida": s["turno"]}
    if fijar:
        from . import posiciones

        pos = {"nombre": f"turno {s['mazo']} T{s['turno']} {d['id']}", "origen": "duda", "id": d["id"],
               "lado": lado, "paso": k, "tipo": "turno", "turnoDebe": sorted(mio), "debe": None, "noDebe": None,
               "revision": {"paso": k, "lado": lado, "turno": s["turno"], "tipo": "turno",
                            "elegida": " → ".join(suyo), "mejor": " → ".join(mio), "error": not coincide,
                            "ganaElegida": ia_estima or 0.0, "ganaMejor": tuya or 0.0, "porque": porque},
               "seed": d["seed"], "semillaIa": d["semillaIa"], "metodos": d["metodos"], "mazos": d["mazos"],
               "registro": d["registro"][: k + 1]}
        pos["pendiente"] = not posiciones.cumple(pos)[0]
        # Si la simulación prefiere el turno de la IA, no se fija como test:
        # queda en disputa para revisarlo con la persona.
        carpeta = posiciones.DISPUTA if posiciones.en_disputa(pos) else posiciones.CARPETA
        out["enDisputa"] = carpeta is posiciones.DISPUTA
        carpeta.mkdir(parents=True, exist_ok=True)
        destino = carpeta / f"{posiciones._nombre_archivo(pos['nombre'])}.json"
        destino.write_text(json.dumps(pos, ensure_ascii=False), encoding="utf-8")
        out["posicion"] = destino.name
    CARPETA.mkdir(parents=True, exist_ok=True)
    with RESPUESTAS.open("a", encoding="utf-8") as f:
        f.write(json.dumps(out, ensure_ascii=False) + "\n")
    return out


def atender_desafio(ref, data: dict, *, pausa: float = 0.35, confirmar: int = 24) -> dict:
    """Atiende `ai_challenges/{id}` con `modo: "duda"`: toma la siguiente duda
    de la cola, reproduce la partida hasta esa decisión y la persona juega en
    el tablero todo lo que queda de ese turno."""
    import time

    from google.cloud import firestore

    from . import turnos
    from .datos import Mazo
    from .desafio import HumanoRemoto, _urls_imagenes, reintentar_red, respuesta_valida

    pendientes = leer()
    if not pendientes:
        reintentar_red(lambda: ref.update({"avisoDuda": "La IA está jugando partidas para encontrar dudas…"}))
        generar(10, 5, seed=int(time.time()) % 100000, procesos=4, log=lambda *_: None)
        pendientes = leer()
    if not pendientes:
        raise ValueError("La IA no encontró dudas en esta tanda. Prueba de nuevo en un momento.")
    d = pendientes[0]
    s = d["situacion"]
    mazos = [Mazo.from_json(m) for m in d["mazos"]]
    cartas, nombres = tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos)
    lado = d["lado"]
    try:
        imagenes = _urls_imagenes({c.id for m in mazos for c in m.cartas})
    except Exception:  # noqa: BLE001 - sin imágenes previas la app las pide igual
        imagenes = {}
    reintentar_red(lambda: ref.update({
        "dudaId": d["id"], "mazoDuda": s["mazo"], "rivalDuda": s["rival"], "tipoDuda": d["tipo"],
        **({"imagenes": imagenes} if imagenes else {}),
    }))
    partida_ref: list = [None]
    secuencia = [0]

    def pedir(tipo: str, opciones: list[dict], config: dict):
        secuencia[0] += 1
        decision = str(secuencia[0])
        estado = _vista(partida_ref[0], lado)
        reintentar_red(lambda: ref.update({
            "status": "esperando", "estado": estado, "respuesta": None,
            "decision": {"id": decision, "tipo": tipo, "opciones": opciones, **config},
        }))
        while True:
            actual = reintentar_red(lambda: ref.get()).to_dict() or {}
            respuesta = actual.get("respuesta") or {}
            if str(respuesta.get("decisionId")) == decision:
                valor = respuesta.get("valor")
                if not respuesta_valida(tipo, opciones, config, valor):
                    reintentar_red(lambda: ref.update({
                        "respuesta": None, "errorDecision": "Selección inválida; vuelve a elegir."}))
                    continue
                reintentar_red(lambda: ref.update({"status": "jugando", "respuesta": None, "decision": None}))
                return valor
            if actual.get("status") == "abandonado":
                raise RuntimeError("Desafío abandonado por el jugador")
            time.sleep(pausa)

    humano = turnos.jugar(cartas, nombres, d["seed"], d["registro"], d["paso"], d["metodos"], lado,
                          HumanoRemoto(pedir), metodos_quien=turnos.metodos_de_humano(),
                          al_crear=lambda p: partida_ref.__setitem__(0, p))
    # El turno terminó: la mesa como quedó, mientras se compara con el de la IA.
    final = _vista(humano["partida"], lado)
    reintentar_red(lambda: ref.update({"status": "jugando", "estado": final, "decision": None,
                                       "avisoDuda": "Comparando tu turno con el de la IA…"}))
    r = registrar_turno(d, humano, confirmar=confirmar)
    salida = {"tuJugada": " → ".join(r["respuesta"]), "jugadaIa": " → ".join(r["eligioIa"]),
              "tuTurno": r["respuesta"], "turnoIa": r["eligioIa"],
              "coincide": r["coincideConIa"], "estimaTuya": r["estimaTuya"], "estimaIa": r["estimaIa"],
              "veredicto": r["veredicto"], "mazo": s["mazo"], "rival": s["rival"], "turno": s["turno"],
              "tipo": "turno", "quedan": len(leer()), "enDisputa": bool(r.get("enDisputa"))}
    reintentar_red(lambda: ref.update({
        "status": "terminado", "resultadoDuda": salida, "decision": None, "avisoDuda": None,
        "finishedAt": firestore.SERVER_TIMESTAMP}))
    return salida


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.dudas")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generar")
    g.add_argument("--partidas", type=int, default=20)
    g.add_argument("--max", type=int, default=12)
    g.add_argument("--seed", type=int, default=1)
    g.add_argument("--mazos", nargs="*", help="ids de los mazos que te interesa entrenar (por defecto, todos)")
    g.add_argument("--procesos", type=int)
    g.add_argument("--jugador", default="busqueda_vigilia", help="quién juega las partidas de donde salen las dudas")
    sub.add_parser("ver")
    r = sub.add_parser("responder")
    r.add_argument("id")
    r.add_argument("letra")
    r.add_argument("--porque", default="")
    args = ap.parse_args(argv)
    if args.cmd == "generar":
        from .meta import _mazos_de

        mazos = _mazos_de(args.mazos, True) if args.mazos else None
        nuevas = generar(args.partidas, args.max, seed=args.seed, mazos=mazos, procesos=args.procesos,
                         jugador=args.jugador)
        print(f"{len(nuevas)} dudas nuevas · {len(leer())} sin responder")
        return 0
    if args.cmd == "ver":
        pendientes = leer()
        print("\n\n".join(texto(d, n) for n, d in enumerate(pendientes, 1)) or "No hay dudas pendientes.")
        return 0
    out = responder(args.id, args.letra, args.porque)
    print(f"Tu jugada: «{out['respuesta']}» · la IA había elegido «{out['eligioIa']}»")
    print(out["veredicto"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
