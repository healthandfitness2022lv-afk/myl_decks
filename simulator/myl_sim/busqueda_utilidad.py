"""IA por simulación con utilidad: cada decisión se juega hasta el final.

Usa las mismas decisiones que `busqueda_vigilia` (jugada del turno, Oro,
objetivos, ataques, bloqueos, Guerra de Talismanes, descartes y mulligan),
pero cambia dos cosas:

1. Cada candidata se prueba con varias partidas completas (rollouts con la
   heurística en ambos lados y la mano rival estimada con `creencias`), no
   con un horizonte corto y una valoración del estado.
2. Se elige la candidata de mayor **utilidad esperada**, sin preferir la
   regla: ganar vale más si es rápido y con más cartas en el Mazo Castillo;
   perder vale menos si es rápido.

Cada decisión queda anotada en `bitacora` (candidatas, rollouts, winrate,
utilidad y por qué se eligió); `bitacora_texto` la deja legible en español.
"""

from __future__ import annotations

import sys
import time

from .busqueda_vigilia import BuscadorVigilia, _texto_jugada, situacion
from .jugadores import JUGADORES

TAMANO_CASTILLO = 49

# Utilidad (0–1): gana ∈ [0,6 ; 1], pierde ∈ [0 ; 0,2], empate 0,5.
GANA_BASE, GANA_RAPIDEZ, GANA_CASTILLO = 0.6, 0.2, 0.2
PIERDE_LENTITUD = 0.2
TURNOS_RAPIDO, TURNOS_LENTO = 4, 14  # turnos propios: ≤4 es lo más rápido, ≥14 lo más lento

_ultimo: dict = {}  # resultado del último rollout (para el winrate de la bitácora)


def rapidez(turnos: int) -> float:
    return max(0.0, min(1.0, (TURNOS_LENTO - turnos) / (TURNOS_LENTO - TURNOS_RAPIDO)))


def utilidad(p, yo: int) -> float:
    """Utilidad de `yo` al terminar un rollout."""
    global _ultimo
    turnos = p.turnos_propios[yo]
    castillo = len(p.j(yo).mazo)
    if p.e.terminada and p.e.ganador in (0, 1):
        if p.e.ganador == yo:
            u = GANA_BASE + GANA_RAPIDEZ * rapidez(turnos) + GANA_CASTILLO * castillo / TAMANO_CASTILLO
            _ultimo = {"r": "gana", "turnos": turnos, "castillo": castillo}
        else:
            # perder rápido es peor: rapidez del rival = rapidez de la derrota
            u = PIERDE_LENTITUD * (1 - rapidez(p.turnos_propios[1 - yo]))
            _ultimo = {"r": "pierde", "turnos": turnos, "castillo": castillo}
        return u
    if p.e.terminada:
        _ultimo = {"r": "empate", "turnos": turnos, "castillo": castillo}
        return 0.5
    # Rollout cortado (límite de turnos de la simulación): utilidad esperada
    # según la probabilidad de ganar estimada.
    from .busqueda_ataques import valor_estado

    q = valor_estado(p, yo, 2)
    _ultimo = {"r": "corte", "turnos": turnos, "castillo": castillo, "q": q}
    return 0.1 + 0.7 * q


def _describir(nombre: str, loc: dict) -> tuple[str, list[str]]:
    """(tipo de decisión, texto de cada candidata) a partir de las variables
    de la función que pidió la comparación."""
    ops = loc.get("opciones") or loc.get("planes") or []
    if nombre == "elegir_atacantes":
        por = {c.uid: c.nombre for c in loc["candidatos"]}
        return "Ataque", ["atacar con " + ", ".join(por[u] for u in o) if o else "no atacar" for o in ops]
    if nombre == "elegir_bloqueos":
        pb, pa = loc["por_blk"], loc["por_atk"]
        return "Bloqueo", ["; ".join(f"{pb[b].nombre} bloquea a {pa[a].nombre}" for a, b in o) or "no bloquear"
                           for o in ops]
    if nombre == "elegir_descartes":
        por = {c.uid: c.nombre for c in loc["mano"]}
        return "Descarte (mano llena)", ["descartar " + ", ".join(por[u] for u in o) for o in ops]
    if nombre == "quedarse_mano":
        return "Mano inicial", ["quedarse con la mano" if o else "mulligan" for o in ops]
    if nombre == "_con_objetivo":
        por = {t.uid: t.nombre for t in loc["objetivos"]}
        jug = _texto_jugada(loc["j"])
        return f"Objetivo de «{jug}»", ["el que elige la regla" if u is None else por[u] for u in ops]
    tipo = {"_linea": "Vigilia (siguiente jugada)", "_elegir_oro": "Qué Oro bajar",
            "_activar_oro": "Activar Oro", "_guerra": "Guerra de Talismanes",
            "_elegir_carta": "Qué carta jugar", "_buscar": "Plan de Vigilia"}.get(nombre, nombre)
    def texto(o):
        if isinstance(o, str):
            return o
        if getattr(o, "tipo", None) == "oro":
            return f"bajar Oro {o.carta.nombre}"
        return _texto_jugada(o)

    return tipo, [texto(o) for o in ops]


class BuscadorUtilidad(BuscadorVigilia):
    """Monte Carlo por decisión: rollouts hasta el final y máxima utilidad."""

    nombre = "busqueda_utilidad"

    def __init__(self, seed: int | None = None, *, rollouts: int = 6, horizonte_total: int = 80, **kw):
        super().__init__(seed, **kw)
        self.aprendido = "utilidad"  # las continuaciones devuelven `utilidad`
        # turnos de simulación: en la práctica, hasta el final de la partida
        self.horizonte = self.horizonte_oro = self.horizonte_mano = horizonte_total
        self.rollouts = rollouts
        self.buscar_mulligan = True
        self.bitacora: list[dict] = []

    def _comparar(self, evaluar, cuantas, rng, *, base: int = 0, muestras=None, max_muestras=None):
        marco = sys._getframe(1)
        nombre, loc = marco.f_code.co_name, marco.f_locals
        inicio = time.monotonic()
        valores = [[] for _ in range(cuantas)]
        resultados = [[] for _ in range(cuantas)]
        for _ in range(self.rollouts):
            seed = rng.randrange(1, 2**31)  # misma muestra para todas (pareadas)
            for i in range(cuantas):
                valores[i].append(evaluar(i, seed))
                resultados[i].append(dict(_ultimo))
        medias = [sum(v) / len(v) for v in valores]
        elegido = max(range(cuantas), key=lambda i: (round(medias[i], 6), i == base))
        try:
            self._anotar(nombre, loc, base, elegido, medias, resultados, time.monotonic() - inicio)
        except Exception as e:  # noqa: BLE001 — la bitácora nunca frena la partida
            self.bitacora.append({"error_bitacora": f"{nombre}: {type(e).__name__}: {e}"})
        return elegido, valores, {"muestras": self.rollouts, "z": None}

    def _anotar(self, nombre, loc, base, elegido, medias, resultados, segundos):
        p, yo = loc["p"], loc["yo"]
        tipo, textos = _describir(nombre, loc)
        filas = []
        for i, (t, m, rs) in enumerate(zip(textos, medias, resultados)):
            gana = [r for r in rs if r["r"] == "gana"]
            pierde = [r for r in rs if r["r"] == "pierde"]
            filas.append({
                "candidata": t, "regla": i == base, "elegida": i == elegido, "rollouts": len(rs),
                "gana": len(gana), "pierde": len(pierde), "otros": len(rs) - len(gana) - len(pierde),
                "winrate": round(len(gana) / len(rs), 3),
                "utilidad": round(m, 3),
                "turnos_victoria": round(sum(r["turnos"] for r in gana) / len(gana), 1) if gana else None,
                "castillo_victoria": round(sum(r["castillo"] for r in gana) / len(gana), 1) if gana else None,
                "turnos_derrota": round(sum(r["turnos"] for r in pierde) / len(pierde), 1) if pierde else None,
            })
        self.bitacora.append({"tipo": tipo, **situacion(p, yo), "jugador": yo, "candidatas": filas,
                              "elegida": elegido, "regla": base, "segundos": round(segundos, 1)})


def _por_que(d: dict) -> str:
    f = d["candidatas"]
    e, b = f[d["elegida"]], f[d["regla"]]
    otras = sorted((x for x in f if x is not e), key=lambda x: -x["utilidad"])
    segunda = otras[0] if otras else None
    if segunda is None:
        return "única opción"
    dif = e["utilidad"] - segunda["utilidad"]
    if dif < 1e-9:
        return "empate de utilidad: se queda la de la regla"
    motivo = []
    if e["winrate"] > segunda["winrate"]:
        motivo.append(f"gana más ({e['winrate']:.0%} contra {segunda['winrate']:.0%})")
    elif e["winrate"] == segunda["winrate"]:
        if (e["turnos_victoria"] or 99) < (segunda["turnos_victoria"] or 99):
            motivo.append(f"gana antes ({e['turnos_victoria']} turnos contra {segunda['turnos_victoria']})")
        elif (e["castillo_victoria"] or 0) > (segunda["castillo_victoria"] or 0):
            motivo.append(f"gana con más castillo ({e['castillo_victoria']} cartas contra {segunda['castillo_victoria']})")
        else:
            motivo.append("mismo winrate, pero sus derrotas son más lentas o sus cortes mejor valorados")
    else:
        motivo.append(f"gana menos ({e['winrate']:.0%} contra {segunda['winrate']:.0%}) pero sus victorias son "
                      "más rápidas/con más castillo y compensan")
    regla = "es la de la regla" if e is b else f"se aparta de la regla ({b['candidata']}: {b['utilidad']:.3f})"
    return f"mayor utilidad ({e['utilidad']:.3f}, +{dif:.3f} sobre «{segunda['candidata']}»): {motivo[0]}; {regla}"


def bitacora_texto(bitacora: list[dict], titulo: str = "") -> str:
    out = [titulo] if titulo else []
    for k, d in enumerate(bitacora, 1):
        if "error_bitacora" in d:
            out.append(f"\n[{k}] (no se pudo anotar: {d['error_bitacora']})")
            continue
        out.append(f"\n[{k}] Turno {d['turno']} · {d['mi_mazo']} · {d['tipo']}  ({d['segundos']} s)")
        out.append(f"    Castillo {d['castillo'][0]} vs {d['castillo'][1]} · Oros {d['oros']} · "
                   f"mano: {', '.join(d['mano']) or '—'} · mano rival: {d['mano_rival']} cartas")
        out.append(f"    Mi mesa: {', '.join(d['mi_mesa']) or '—'} · Mesa rival: {', '.join(d['mesa_rival']) or '—'}")
        for i, f in enumerate(d["candidatas"], 1):
            marca = "►" if f["elegida"] else " "
            extra = []
            if f["turnos_victoria"] is not None:
                extra.append(f"gana en ~{f['turnos_victoria']} turnos con ~{f['castillo_victoria']} en castillo")
            if f["turnos_derrota"] is not None:
                extra.append(f"pierde en ~{f['turnos_derrota']} turnos")
            if f["otros"]:
                extra.append(f"{f['otros']} sin terminar")
            out.append(f"  {marca} {i}. {f['candidata']}{' (regla)' if f['regla'] else ''}: "
                       f"{f['gana']}/{f['rollouts']} ganados ({f['winrate']:.0%}) · utilidad {f['utilidad']:.3f}"
                       + (f" · {'; '.join(extra)}" if extra else ""))
        out.append(f"    Elegida: {d['candidatas'][d['elegida']]['candidata']} — {_por_que(d)}")
    return "\n".join(out)


JUGADORES["busqueda_utilidad"] = BuscadorUtilidad
