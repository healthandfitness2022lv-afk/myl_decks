"""N partidas entre dos mazos y el informe de resultados."""

from __future__ import annotations

from . import habilidades as hab

from collections import Counter
import math
import random
from typing import Callable

from .datos import Mazo, huella_mazo, guardar_snapshot
from .jugadores import JUGADORES
from .motor import Partida, Registro


def wilson(exitos: float, n: int, z: float = 1.96) -> tuple[float, float]:
    """Intervalo de confianza del 95 % para una proporción."""
    if n == 0:
        return (0.0, 0.0)
    p = exitos / n
    den = 1 + z * z / n
    centro = (p + z * z / (2 * n)) / den
    margen = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (max(0.0, centro - margen), min(1.0, centro + margen))


def intervalo_pareado(conteo: Counter, *, seed: int, replicas: int = 1000):
    """Intervalo para diferencias por pareja sin guardar millones de muestras."""
    n = sum(conteo.values())
    if n == 0:
        return None, "sin_datos"
    if n <= 10000:
        valores = [valor for valor, cantidad in conteo.items() for _ in range(cantidad)]
        rng = random.Random(seed)
        muestras = sorted(sum(rng.choices(valores, k=n)) / n for _ in range(replicas))
        return [muestras[int(replicas * .025)], muestras[min(replicas - 1, int(replicas * .975))]], "bootstrap_pareado"
    media = sum(valor * cantidad for valor, cantidad in conteo.items()) / n
    varianza = sum(cantidad * (valor - media) ** 2 for valor, cantidad in conteo.items()) / (n - 1)
    margen = 1.96 * math.sqrt(varianza / n)
    return [max(-1.0, media - margen), min(1.0, media + margen)], "normal_pareado"


def simular(
    mazo_a: Mazo,
    mazo_b: Mazo,
    n: int,
    *,
    seed: int = 1,
    jugador: str = "heuristico",
    progreso: Callable[[int, dict], None] | None = None,
) -> dict:
    clase = JUGADORES[jugador]
    registros: list[Registro] = []
    for k in range(n):
        # inicial=None: cada partida tira el dado y empieza quien lo gana.
        partida = Partida(
            (mazo_a.cartas, mazo_b.cartas),
            (clase(seed * 100003 + 2 * k), clase(seed * 100003 + 2 * k + 1)),
            nombres=(mazo_a.nombre, mazo_b.nombre),
            inicial=None,
            seed=seed * 1000003 + k,
        )
        registros.append(partida.jugar())
        if progreso:
            # El worker decide cada cuánto lo escribe (no en cada partida).
            progreso(k + 1, lambda: resumen(registros))
    return informe(mazo_a, mazo_b, registros, jugador=jugador, seed=seed)


def informe(mazo_a: Mazo, mazo_b: Mazo, regs: list[Registro], *, jugador: str, seed: int) -> dict:
    snapshot_a = guardar_snapshot(mazo_a)
    snapshot_b = guardar_snapshot(mazo_b)
    validas = [r for r in regs if r.ganador != -2]
    anomalas = len(regs) - len(validas)
    n = len(validas)
    gana_a = sum(1 for r in validas if r.ganador == 0)
    gana_b = sum(1 for r in validas if r.ganador == 1)
    empates = sum(1 for r in validas if r.ganador == -1)
    # Empates cuentan medio punto para el winrate.
    puntos_a = gana_a + empates / 2
    lo, hi = wilson(puntos_a, n)

    def por_inicial(quien: int) -> dict:
        rs = [r for r in validas if r.inicial == quien]
        g = sum(1 for r in rs if r.ganador == 0) + sum(1 for r in rs if r.ganador == -1) / 2
        lo_, hi_ = wilson(g, len(rs))
        return {"partidas": len(rs), "winrateA": g / len(rs) if rs else 0, "ic95": [lo_, hi_]}

    gana_inicial = sum(1 for r in validas if r.ganador == r.inicial)
    causas = Counter((r.causa, r.ganador) for r in validas if r.ganador in (0, 1))

    return {
        "jugador": jugador,
        "seed": seed,
        "partidas": len(regs),
        "validas": n,
        "anomalas": anomalas,
        "mazoA": {"id": mazo_a.id, "nombre": mazo_a.nombre},
        "mazoB": {"id": mazo_b.id, "nombre": mazo_b.nombre},
        "versiones": {
            "mazoA": {"huella": huella_mazo(mazo_a), "snapshot": str(snapshot_a)},
            "mazoB": {"huella": huella_mazo(mazo_b), "snapshot": str(snapshot_b)},
        },
        "victoriasA": gana_a,
        "victoriasB": gana_b,
        "empates": empates,
        "winrateA": puntos_a / n if n else 0,
        "ic95A": [lo, hi],
        "ventajaInicial": {
            "winrateDelQueEmpieza": gana_inicial / n if n else 0,
            # Quien gana el dado empieza: dadosA/dadosB = partidas que empezó cada uno.
            "dadosA": sum(1 for r in validas if r.inicial == 0),
            "dadosB": sum(1 for r in validas if r.inicial == 1),
            "aEmpieza": por_inicial(0),
            "bEmpieza": por_inicial(1),
        },
        "turnos": _turnos(validas),
        **resumen(regs),
        "causas": [
            {"ganador": "A" if g == 0 else "B", "causa": c, "partidas": k}
            for (c, g), k in causas.most_common()
        ],
        "impactoA": _impacto(validas, 0),
        "impactoB": _impacto(validas, 1),
        "sinProgramarA": mazo_a.sin_programar(),
        "sinProgramarB": mazo_b.sin_programar(),
        "faltantesA": mazo_a.faltantes,
        "faltantesB": mazo_b.faltantes,
    }


def rondas(r: Registro) -> int:
    """Un turno completo es cuando ambos jugaron (el motor cuenta medios)."""
    return (r.turnos + 1) // 2


def resumen(regs: list[Registro]) -> dict:
    """Métricas que la app muestra en vivo mientras se simula."""
    validas = [r for r in regs if r.ganador != -2]
    n = len(validas)

    def lado(k: int) -> dict:
        evaluadas = [r.oros_turno4[k] for r in validas if r.oros_turno4[k] is not None]
        return {
            "fallaCurva": sum(1 for x in evaluadas if x < 5),
            "evaluadasCurva": len(evaluadas),
            "conMulligan": sum(1 for r in validas if r.mulligans[k] > 0),
            "mulligans": sum(r.mulligans[k] for r in validas),
            "ganaDado": sum(1 for r in validas if r.inicial == k),
        }

    gana_dado = sum(1 for r in validas if r.ganador == r.inicial)
    return {
        "jugadas": len(regs),
        "victoriasA": sum(1 for r in validas if r.ganador == 0),
        "victoriasB": sum(1 for r in validas if r.ganador == 1),
        "empates": sum(1 for r in validas if r.ganador == -1),
        "winrateGanaDado": gana_dado / n if n else 0,
        "rondasPromedio": sum(rondas(r) for r in validas) / n if n else 0,
        "ladoA": lado(0),
        "ladoB": lado(1),
        # Una letra por partida: A, B, E (empate) o X (anómala).
        "resultados": "".join(
            "A" if r.ganador == 0 else "B" if r.ganador == 1 else "E" if r.ganador == -1 else "X" for r in regs
        ),
    }


def _turnos(regs: list[Registro]) -> dict:
    """Duración en turnos completos (ambos jugaron)."""
    if not regs:
        return {"promedio": 0, "min": 0, "max": 0}
    t = sorted(rondas(r) for r in regs)
    return {"promedio": sum(t) / len(t), "mediana": t[len(t) // 2], "min": t[0], "max": t[-1]}


def _impacto(regs: list[Registro], lado: int, minimo: int = 20) -> list[dict]:
    """Winrate del mazo cuando la carta fue jugada vs. cuando no.

    Es una correlación, no causalidad: una carta cara aparece más en partidas
    largas. Se omiten cartas con menos de `minimo` partidas de cada lado.
    """
    def gano(r: Registro) -> float:
        return 1.0 if r.ganador == lado else 0.5 if r.ganador == -1 else 0.0

    nombres = set().union(*(r.jugadas[lado] for r in regs)) if regs else set()
    out = []
    for nombre in nombres:
        con = [gano(r) for r in regs if nombre in r.jugadas[lado]]
        sin = [gano(r) for r in regs if nombre not in r.jugadas[lado]]
        if len(con) < minimo or len(sin) < minimo:
            continue
        wr_con = sum(con) / len(con)
        wr_sin = sum(sin) / len(sin)
        out.append(
            {
                "carta": nombre,
                "jugadaEn": len(con),
                "winrateJugada": wr_con,
                "winrateNoJugada": wr_sin,
                "diferencia": wr_con - wr_sin,
            }
        )
    return sorted(out, key=lambda x: -x["diferencia"])


def narrar(
    mazo_a: Mazo, mazo_b: Mazo, *, seed: int = 1, jugador: str = "heuristico", inicial: int | None = None
) -> dict:
    """Una sola partida con su narración turno a turno. `inicial` fija quién
    empieza (repetir una partida anterior al dado); si no, se tira el dado."""
    clase = JUGADORES[jugador]
    partida = Partida(
        (mazo_a.cartas, mazo_b.cartas),
        (clase(seed * 2), clase(seed * 2 + 1)),
        nombres=(mazo_a.nombre, mazo_b.nombre),
        inicial=inicial,
        seed=seed,
        log=True,
    )
    registro = partida.jugar()
    r = informe(mazo_a, mazo_b, [registro], jugador=jugador, seed=seed)
    nombres = {"J0": mazo_a.nombre, "J1": mazo_b.nombre}
    lineas = []
    for linea in partida.e.log or []:
        linea = hab.sin_marcas(linea)
        for j, nombre in nombres.items():
            linea = linea.replace(j, nombre)
        lineas.append(linea)
    r["narracion"] = lineas[:3000]  # tope por tamaño del documento
    # Tablero: una foto de la mesa por jugada + nombres de las cartas.
    pasos = []
    for paso in partida.pasos[:1500]:
        texto = paso["x"]
        for j, nombre in nombres.items():
            texto = texto.replace(j, nombre)
        pasos.append({**paso, "x": texto})
    ids = {c.id: c.nombre for c in mazo_a.cartas + mazo_b.cartas}
    ids[ORO_INICIAL_ID] = "Oro inicial"
    # Firestore no acepta claves "__…__" (reservadas): el Oro inicial se
    # guarda con otro id.
    r["pasos"] = _sin_ids_reservados(_solo_cambios(pasos))
    r["cartas"] = {_id_guardable(k): v for k, v in ids.items()}
    r["ganador"] = (
        mazo_a.nombre if registro.ganador == 0 else mazo_b.nombre if registro.ganador == 1 else "Empate"
    )
    r["empieza"] = mazo_a.nombre if registro.inicial == 0 else mazo_b.nombre
    if registro.dado:
        r["dado"] = {"A": registro.dado[0], "B": registro.dado[1], "gana": r["empieza"]}
    return r


ORO_INICIAL_ID = "__oro_inicial__"


def _solo_cambios(pasos: list[dict]) -> list[dict]:
    """Cementerio y Destierro completos ("cl", "dl") solo en los pasos donde
    cambian, para no pasar el tope de 1 MB del documento. La app los arrastra
    desde el último paso que los trae."""
    previos: dict = {}
    out = []
    for paso in pasos:
        jugadores = []
        for k, j in enumerate(paso["j"]):
            j = dict(j)
            for clave in ("cl", "dl"):
                if clave not in j:
                    continue
                if previos.get((k, clave)) == j[clave]:
                    del j[clave]
                else:
                    previos[(k, clave)] = j[clave]
            jugadores.append(j)
        out.append({**paso, "j": jugadores})
    return out


def _id_guardable(cid):
    return "oro_inicial" if cid == ORO_INICIAL_ID else cid


def _sin_ids_reservados(valor):
    if isinstance(valor, str):
        return _id_guardable(valor)
    if isinstance(valor, list):
        return [_sin_ids_reservados(v) for v in valor]
    if isinstance(valor, dict):
        return {k: (v if k == "x" else _sin_ids_reservados(v)) for k, v in valor.items()}
    return valor

