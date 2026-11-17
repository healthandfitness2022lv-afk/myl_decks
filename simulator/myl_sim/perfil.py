"""Qué hace un mazo, calculado solo desde las habilidades programadas.

Es el mismo cálculo que `lib/domain/analisis_mazo/` de la app (Dart). Los dos
se prueban contra `test/fixtures/perfil_casos.json`; si cambias una regla o un
peso aquí, cámbialo también allá y regenera los casos:

  .venv/Scripts/python -m myl_sim.perfil casos      (reescribe el archivo de casos)
  .venv/Scripts/python -m myl_sim.perfil mazos      (tabla de los mazos del caché)

Cada efecto (una habilidad o un "luego") aporta puntos a uno o más **roles**.
Los puntos dependen de qué hace, a cuántas cartas, si se repite, cuánto cuesta
activarlo y si tiene condición. Una carta suma como máximo `TOPE_CARTA` por
rol. El mazo suma los puntos de cada copia.

El **índice de velocidad** (0 = control puro, 100 = agro puro) combina la
presión, el manejo de mesa y la curva de coste.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROLES = ("presion", "dano_directo", "remocion", "control", "respuesta", "proteccion",
         "ventaja", "economia", "recursion", "disrupcion")

NOMBRES = {
    "presion": "Presión", "dano_directo": "Daño directo", "remocion": "Remoción", "control": "Control",
    "respuesta": "Respuesta", "proteccion": "Protección", "ventaja": "Ventaja de cartas",
    "economia": "Economía de Oros", "recursion": "Recursión", "disrupcion": "Disrupción de mano",
}

TOPE_CARTA = 2.0
MANO_INICIAL = 8

_RIVAL = ("oponente", "cualquiera", "disparadora", "ambos")
_PROPIO = ("propio", "esta_carta", "proximo")
_EN_JUEGO = ("en_juego", "linea_defensa", "linea_ataque", "linea_apoyo")
# Propiedades fijas de la carta: siempre continuas y sin costo (igual que la app).
_PROPIEDADES = ("imbloqueable", "indestructible", "indesterrable", "noAnulable", "furia", "guardian", "errante",
                "retador", "sinLimiteArmas")
_REPETIBLE = ("activada",)
_DISPARO_REPETIDO = ("al_atacar", "al_hacer_dano", "al_inicio_fase", "al_bloquear", "propia_entra",
                     "propia_sale", "propio_ataca", "propia_juega")
_RESPUESTA = ("oponente_juega", "habilidad_oponente")
_PROTEGE = ("indestructible", "indesterrable", "inmunidad", "noAnulable")
_AGRESIVO = ("furia", "imbloqueable", "retador")

# Pesos del índice de velocidad (ver `indice_velocidad`). Calibrados el 17-11-2026 contra el
# turno medio de victoria de 49 mazos (1.200 partidas de la heurística): correlación -0,77;
# cada 10 puntos de índice son unos 0,6 turnos menos. Los cortes equivalen a ganar antes
# del turno 7 (Agro) o después del 8,4 (Control).
PESO_PRESION = 1.0
PESO_MANEJO = 1.0
PESO_CURVA = 0.4
ESCALA_PRESION = 0.8  # puntos de presión por carta no-Oro que saturan
ESCALA_MANEJO = 1.3  # ídem para el manejo de mesa
CURVA_BAJA, CURVA_ALTA = 1.6, 3.2
CORTE_AGRO, CORTE_CONTROL = 62, 38


def _entero(v, defecto=0) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return defecto


def _alcance(e: dict) -> float:
    """Cuántas cartas toca: una, varias o todas."""
    obj = e.get("objetivo") or {}
    if obj.get("seleccion") == "todos":
        return 1.6
    n = _entero(e.get("cantidad"), 1)
    return 1.0 if n <= 1 else min(1.0 + 0.3 * (n - 1), 1.6)


def _factor(e: dict, cuando: str) -> float:
    """Repetición, costo de activación y condición."""
    f = 1.0
    costo = e.get("costo") or {}
    if str(e.get("accion") or "") in _PROPIEDADES:
        cuando, costo = "continua", {}
    se_gasta = any(costo.get(k) for k in ("destruirEstaCarta", "desterrarEstaCarta", "barajarEstaCarta",
                                          "fondoMazoEstaCarta"))
    if cuando in _REPETIBLE and not se_gasta and not e.get("unaVez"):
        f *= 1.3
    elif cuando == "continua":
        f *= 1.2
    elif cuando in _DISPARO_REPETIDO:
        f *= 1.1
    f *= max(0.6, 1.0 - 0.1 * _entero(costo.get("oros")))
    otros = sum(_entero(costo.get(k)) for k in ("descartar", "destruirAliados", "desterrarAliados", "barajarMano"))
    if otros:
        f *= 0.85
    if str((e.get("condicion") or {}).get("tipo") or "ninguna") != "ninguna":
        f *= 0.85
    return f


def roles_de_efecto(e: dict, cuando: str) -> dict[str, float]:
    """Puntos por rol de un efecto. `cuando` es el de la habilidad que lo contiene."""
    accion = str(e.get("accion") or "")
    obj = e.get("objetivo") or {}
    # Mismos valores por defecto que el modelo de la app.
    quien = str(obj.get("quien") or "oponente")
    zona = str(obj.get("zona") or "en_juego")
    zonas = {zona, *(obj.get("zonas") or [])}
    tipos = obj.get("tipos") or []
    modo = str(e.get("modo") or "")
    valor = _entero(e.get("valor"))
    destino = str(e.get("zonaDestino") or "")
    cantidad = max(1, _entero(e.get("cantidad"), 1))
    rival = quien in _RIVAL
    propio = quien in _PROPIO
    en_juego = zona in _EN_JUEGO
    out: dict[str, float] = {}

    def suma(rol: str, puntos: float) -> None:
        out[rol] = out.get(rol, 0.0) + puntos

    if accion in ("destruir", "desterrar") and rival and en_juego:
        suma("remocion", 1.0 * _alcance(e))
    if accion == "barajar" and rival and en_juego:
        suma("remocion", 0.9 * _alcance(e))
    if accion == "subirMano" and rival and en_juego:
        suma("remocion", 0.6 * _alcance(e))
    if accion == "ganarControl":
        suma("remocion", 0.8)
        suma("presion", 0.4)
    if accion in ("perderHabilidad", "restriccion", "encarecer", "noAgrupar") and not propio:
        suma("control", 0.8 * _alcance(e))
    if accion == "restringirCombate":
        if modo == "puede_atacar_este_turno":
            suma("presion", 0.6)
        elif not propio:
            suma("control", 0.7 * _alcance(e))
    if accion == "modificarFuerza":
        if valor > 0 and not rival:
            suma("presion", min(0.3 + 0.15 * valor, 0.9) * (_alcance(e) if quien == "propio" else 1.0))
        elif valor < 0 and not propio:
            suma("control", min(0.3 + 0.15 * -valor, 0.9) * _alcance(e))
    if accion == "robar" and quien != "oponente":
        suma("ventaja", min(0.5 * cantidad, 1.5))
    if accion in ("mirarTope", "mostrar"):
        suma("ventaja", 0.5)
    if accion == "mirar":
        suma("disrupcion" if rival else "ventaja", 0.3)
    if accion == "botar" and quien in ("oponente", "ambos", "cualquiera"):
        suma("dano_directo", min(0.4 * cantidad, 2.0))
    es_oro = "Oro" in tipos and len(tipos) == 1
    if accion == "generarOro" or (accion in ("buscar", "jugarDesde", "ponerEnJuego")
                                  and (destino == "reserva_oro" or es_oro)):
        suma("economia", 1.0)
    elif accion in ("buscar", "jugarDesde", "ponerEnJuego") and "mazo" in zonas:
        suma("ventaja", 0.9)
    if accion == "modificarCoste" and valor < 0:
        suma("economia", 0.6)
    if accion == "agrupar" and not rival:
        suma("economia", 0.5)
    if (accion in ("barajar", "subirMano", "jugarDesde", "buscar", "ponerEnJuego", "mover")
            and propio and "cementerio" in zonas):
        suma("recursion", 0.9 * (1.0 if accion != "barajar" else 0.6))
    if accion in ("anular", "cancelarAtaque", "cancelarHabilidad", "redirigir") or cuando in _RESPUESTA:
        suma("respuesta", 1.0)
    if accion in ("prevenir", "reducirDano", "protegerHabilidad") or accion in _PROTEGE or (
            accion == "otorgarPropiedad" and modo in _PROTEGE):
        suma("proteccion", 0.7)
    if accion in _AGRESIVO or (accion == "otorgarPropiedad" and modo in _AGRESIVO):
        suma("presion", 0.8)
    if accion == "descartar" and quien in ("oponente", "ambos"):
        suma("disrupcion", min(0.7 * cantidad, 1.6))

    f = _factor(e, cuando)
    return {k: v * f for k, v in out.items()}


def roles_de_carta(habilidades) -> dict[str, float]:
    """Puntos por rol de una carta (sus habilidades y sus "luego"), con tope."""
    out: dict[str, float] = {}
    for h in habilidades or ():
        if not isinstance(h, dict):
            continue
        cuando = str(h.get("cuando") or "")
        for e in (h, *[x for x in (h.get("luego") or []) if isinstance(x, dict)]):
            for rol, p in roles_de_efecto(e, cuando).items():
                out[rol] = out.get(rol, 0.0) + p
    return {k: round(min(v, TOPE_CARTA), 3) for k, v in out.items() if v > 0}


def _tipo(c: dict) -> str:
    t = str(c.get("tipo") or "").lower()
    for a, b in (("á", "a"), ("ó", "o")):
        t = t.replace(a, b)
    return t


def hipergeometrica(total: int, exitos: int, muestra: int, minimo: int = 1) -> float:
    """P(al menos `minimo` éxitos) al sacar `muestra` cartas de `total` con `exitos` buenas."""
    muestra = min(muestra, total)
    if total <= 0 or exitos <= 0 or minimo <= 0:
        return 1.0 if minimo <= 0 else 0.0
    p = 0.0
    for k in range(minimo, min(exitos, muestra) + 1):
        p += math.comb(exitos, k) * math.comb(total - exitos, muestra - k) / math.comb(total, muestra)
    return min(1.0, p)


def indice_velocidad(presion: float, manejo: float, no_oros: int, coste_medio: float) -> int:
    """0 = control, 100 = agro. `presion` y `manejo` son puntos totales del mazo."""
    if no_oros <= 0:
        return 50
    dp = min(presion / no_oros / ESCALA_PRESION, 1.0)
    dm = min(manejo / no_oros / ESCALA_MANEJO, 1.0)
    curva = (CURVA_ALTA - coste_medio) / (CURVA_ALTA - CURVA_BAJA)
    curva = max(0.0, min(1.0, curva)) * 2 - 1  # -1 cara … +1 barata
    bruto = (PESO_PRESION * dp - PESO_MANEJO * dm + PESO_CURVA * curva) / (
        max(PESO_PRESION, PESO_MANEJO) + PESO_CURVA)
    return int(math.floor(max(0.0, min(100.0, 50 + 50 * bruto)) + 0.5))


def perfil_de(indice: int, roles: dict[str, float], no_oros: int) -> str:
    motor = roles.get("ventaja", 0) + roles.get("economia", 0) + roles.get("recursion", 0)
    resto = sum(roles.values()) - motor
    if no_oros and motor / no_oros >= 0.75 and motor > resto * 1.25:
        return "Combo"
    if indice >= CORTE_AGRO:
        return "Agro"
    if indice <= CORTE_CONTROL:
        return "Control"
    return "Medio"


def analizar(entradas) -> dict:
    """`entradas`: lista de (carta, copias); carta = dict con tipo, coste, fuerza,
    habilidades y (opcional) habilidad/habilidadTextoIA/habilidadesRevisadas."""
    roles = {r: 0.0 for r in ROLES}
    copias_rol = {r: 0 for r in ROLES}
    aportes: dict[str, list] = {r: [] for r in ROLES}
    total = oros = no_oros = con_coste = suma_coste = 0
    aliados = fuerza = coste_aliados = sin_programar = 0
    curva: dict[int, int] = {}
    for c, n in entradas:
        if n <= 0:
            continue
        total += n
        if _tipo(c).startswith("oro"):
            oros += n
        else:
            no_oros += n
            coste = _entero(c.get("coste"), -1)
            if coste >= 0:
                suma_coste += coste * n
                con_coste += n
                curva[coste] = curva.get(coste, 0) + n
            if _tipo(c) == "aliado":
                aliados += n
                fuerza += _entero(c.get("fuerza")) * n
                coste_aliados += max(coste, 0) * n
        habs = c.get("habilidades") or ()
        texto = str(c.get("habilidadTextoIA") or c.get("habilidad") or "").strip(" .")
        if not habs and texto and not c.get("habilidadesRevisadas"):
            sin_programar += n
        for rol, p in roles_de_carta(habs).items():
            roles[rol] += p * n
            copias_rol[rol] += n
            aportes[rol].append((round(p * n, 3), str(c.get("nombre") or ""), n))
    coste_medio = suma_coste / con_coste if con_coste else 0.0
    presion = roles["presion"] + roles["dano_directo"]
    manejo = (roles["remocion"] + roles["control"] + roles["respuesta"]
              + 0.5 * roles["ventaja"] + 0.5 * roles["recursion"])
    indice = indice_velocidad(presion, manejo, no_oros, coste_medio)
    return {
        "total": total, "oros": oros, "noOros": no_oros,
        "costeMedio": round(coste_medio, 3),
        "fuerzaMedia": round(fuerza / aliados, 3) if aliados else 0.0,
        "fuerzaPorOro": round(fuerza / coste_aliados, 3) if coste_aliados else 0.0,
        "curva": {str(k): v for k, v in sorted(curva.items())},
        "roles": {r: round(v, 3) for r, v in roles.items()},
        "copiasPorRol": copias_rol,
        "aportes": {r: [[n, c, p] for p, n, c in sorted(a, key=lambda x: (-x[0], x[1]))[:6]]
                    for r, a in aportes.items() if a},
        "presion": round(presion, 3), "manejo": round(manejo, 3),
        "indice": indice, "perfil": perfil_de(indice, roles, no_oros),
        "sinProgramar": sin_programar,
        "consistencia": {
            "orosTurno2": round(hipergeometrica(total, oros, MANO_INICIAL + 1, 2), 4),
            "orosTurno3": round(hipergeometrica(total, oros, MANO_INICIAL + 2, 3), 4),
            "orosTurno4": round(hipergeometrica(total, oros, MANO_INICIAL + 3, 4), 4),
            "remocionInicial": round(hipergeometrica(total, copias_rol["remocion"], MANO_INICIAL), 4),
            "respuestaInicial": round(hipergeometrica(total, copias_rol["respuesta"], MANO_INICIAL), 4),
            "ventajaInicial": round(hipergeometrica(total, copias_rol["ventaja"], MANO_INICIAL), 4),
        },
    }


def analizar_mazo(mazo) -> dict:
    """Análisis de un `datos.Mazo` (una entrada por copia)."""
    por_id: dict[str, list] = {}
    for c in mazo.cartas:
        d = por_id.setdefault(c.id, [{"nombre": c.nombre, "tipo": c.tipo.value, "coste": c.coste,
                                      "fuerza": c.fuerza, "habilidades": list(c.habilidades),
                                      "habilidad": c.texto, "habilidadesRevisadas": c.revisada}, 0])
        d[1] += 1
    return analizar([(c, n) for c, n in por_id.values()])


# ── Casos compartidos con la app ─────────────────────────────────────────────
ARCHIVO_CASOS = Path(__file__).resolve().parents[2] / "test" / "fixtures" / "perfil_casos.json"


def _entradas_json(d: dict) -> list:
    por_id: dict[str, list] = {}
    for c in d["cartas"]:
        e = por_id.setdefault(c["id"], [{k: c.get(k) for k in ("nombre", "tipo", "coste", "fuerza", "habilidades",
                                                              "habilidad", "habilidadesRevisadas")}, 0])
        e[1] += 1
    return [(c, n) for c, n in por_id.values()]


def generar_casos(maximo: int = 8) -> dict:
    """Mazos reales del caché (sin nombre de su dueño), con su análisis esperado."""
    from .datos import CACHE

    casos = []
    for k, ruta in enumerate(sorted(CACHE.glob("mazo_*.json"))[:maximo * 4:4], 1):
        d = json.loads(ruta.read_text(encoding="utf-8"))
        entradas = _entradas_json(d)
        for c, _ in entradas:  # el texto solo importa por si está vacío
            c["habilidad"] = "x" if str(c.get("habilidad") or "").strip(" .") else ""
        casos.append({"nombre": f"Caso {k} ({d.get('raza') or 'sin raza'})",
                      "cartas": [{**c, "copias": n} for c, n in entradas], "esperado": analizar(entradas)})
    return {"version": 1, "casos": casos}


def main(argv=None) -> int:
    import argparse
    import sys

    sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(prog="myl_sim.perfil")
    ap.add_argument("comando", choices=("casos", "mazos"))
    a = ap.parse_args(argv)
    if a.comando == "casos":
        ARCHIVO_CASOS.parent.mkdir(parents=True, exist_ok=True)
        ARCHIVO_CASOS.write_text(json.dumps(generar_casos(), ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"Casos escritos en {ARCHIVO_CASOS}")
        return 0
    from .datos import CACHE

    print("| Mazo | Raza | Perfil | Índice | Coste | Presión | Manejo |\n|---|---|---|---|---|---|---|")
    filas = []
    for ruta in sorted(CACHE.glob("mazo_*.json")):
        d = json.loads(ruta.read_text(encoding="utf-8"))
        r = analizar(_entradas_json(d))
        filas.append((r["indice"], d.get("nombre", ""), d.get("raza", ""), r))
    for indice, nombre, raza, r in sorted(filas, key=lambda x: -x[0]):
        print(f"| {nombre[:28]} | {raza} | {r['perfil']} | {indice} | {r['costeMedio']:.2f} | "
              f"{r['presion']:.1f} | {r['manejo']:.1f} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
