"""Sinergias de un mazo: qué puede conseguir, de qué depende y qué le falta.

Lee las habilidades programadas de las cartas (no hay reglas por carta) y arma:

- **Cadenas**: cartas que al entrar ponen otras en juego sin pagar, sumadas
  hasta el final (Taliesin → Dama del Lago → Escudo Tryamour → Dame Tryamour
  → Morgana: 4 Oros pagados, 19 en cartas). Se calculan sobre una mesa ideal:
  todo el mazo disponible y una copia de cada carta en el Cementerio.
- **Llaves**: cartas que inician la mejor cadena o que la buscan, y la
  probabilidad de tener al menos una en cada turno.
- **Eslabones frágiles**: piezas de la cadena con pocas copias o topadas por
  la Ban List, y las que dependen de tener algo en el Cementerio.
- **Sugerencias**: cartas del catálogo (misma raza y ediciones del mazo,
  dentro de la Ban List) que alargan una cadena, buscan una llave o alimentan
  el Cementerio. `--validar` las prueba jugando contra el meta con el
  optimizador (screening, successive halving y confirmación con IC95).

Uso (desde simulator/):
  .venv/Scripts/python -m myl_sim.sinergias <id_mazo> [--validar] [--refrescar]
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from math import comb

from . import habilidades as hab
from .datos import CACHE, Mazo, carta_desde_doc
from .jugadores import Aleatorio, _trae_gratis
from .modelo import ORO_INICIAL, Tipo, Zona
from .motor import MANO_INICIAL, Partida

CATALOGO = CACHE / "catalogo.json"
NIVELES = 5


# ── Catálogo ──────────────────────────────────────────────────────────────────
def documentos(refrescar: bool = False) -> dict[str, dict]:
    """cards/{id} completos. Se guardan en cache/catalogo.json."""
    if CATALOGO.exists() and not refrescar:
        return json.loads(CATALOGO.read_text(encoding="utf-8"))
    from .datos import db

    campos = ("nombre", "tipo", "coste", "fuerza", "raza", "habilidad", "habilidadTextoIA", "habilidades",
              "habilidadesRevisadas", "notasSimulador", "edicion", "edition", "soloLibre")
    docs = {d.id: {k: v for k, v in (d.to_dict() or {}).items() if k in campos}
            for d in db().collection("cards").stream()}
    CATALOGO.write_text(json.dumps(docs, ensure_ascii=False), encoding="utf-8")
    return docs


def _edicion(doc: dict) -> str:
    return str(doc.get("edicion") or doc.get("edition") or "")


# ── Cadenas ───────────────────────────────────────────────────────────────────
def mesa_ideal(cartas: list, extra: list = ()) -> Partida:
    """Todo el mazo disponible y una copia de cada carta en el Cementerio."""
    todas = list(cartas) + list(extra)
    p = Partida((todas, list(cartas)), (Aleatorio(1), Aleatorio(2)), inicial=0, seed=1)
    yo = p.j(0)
    vistas = set()
    for c in todas:
        if c.id not in vistas:
            vistas.add(c.id)
            yo.cementerio.append(p._instancia(c, 0, Zona.CEMENTERIO))
    return p


def cadena(p: Partida, c, usadas: frozenset = frozenset(), nivel: int = 0) -> tuple[int, list[dict]]:
    """(Oros en cartas que `c` trae gratis, eslabones en orden)."""
    total, ruta = 0, []
    if nivel >= NIVELES:
        return total, ruta
    for h in c.habilidades:
        if not _trae_gratis(h):
            continue
        mejor = None
        vistos = set()
        for x in hab.candidatos_validos(p, 0, c, h):
            if x is c or x.uid in usadas or x.nombre == c.nombre or (x.nombre, x.zona) in vistos:
                continue
            vistos.add((x.nombre, x.zona))
            v, r = cadena(p, x, usadas | {c.uid, x.uid}, nivel + 1)
            v += x.carta.coste
            zonas = hab.zonas_de(h.get("objetivo") or {}, "mazo")
            paso = {"carta": x.nombre, "id": x.carta.id, "coste": x.carta.coste, "trae": c.nombre,
                    "soloCementerio": zonas == ["cementerio"]}
            # A igual valor, desde el Mazo: no depende de haber perdido la carta antes.
            if mejor is None or (v, x.zona == Zona.MAZO) > (mejor[0], mejor[2]):
                mejor = (v, [paso] + r, x.zona == Zona.MAZO)
        if mejor:
            total += mejor[0]
            ruta += mejor[1]
    return total, ruta


def _instancias(p: Partida) -> dict:
    return {x.carta.id: x for x in p.j(0).mazo}


def _busca(h: dict) -> bool:
    """Lleva a la mano (o juega pagando) una carta elegida del Mazo."""
    obj = h.get("objetivo") or {}
    if obj.get("quien", "propio") != "propio" or "mazo" not in hab.zonas_de(obj, ""):
        return False
    return h.get("accion") == "buscar" or (h.get("accion") == "jugarDesde" and h.get("modo") == "pagando")


def _alimenta_cementerio(carta) -> bool:
    for h in carta.habilidades:
        costo = h.get("costo") or {}
        if costo.get("destruirAliados") or costo.get("descartar"):
            return True
        if h.get("accion") in ("descartar", "botar") and (h.get("objetivo") or {}).get("quien") == "propio":
            return True
    return False


def prob_al_menos_una(copias: int, vistas: int, mazo: int) -> float:
    vistas = min(vistas, mazo)
    return 1 - comb(mazo - copias, vistas) / comb(mazo, vistas) if copias else 0.0


# ── Análisis ──────────────────────────────────────────────────────────────────
def analizar(mazo: Mazo, ban: dict | None = None, docs: dict | None = None) -> dict:
    copias = Counter(c.id for c in mazo.cartas)
    p = mesa_ideal(mazo.cartas)
    inst = _instancias(p)
    cadenas = []
    for cid, x in inst.items():
        v, ruta = cadena(p, x)
        if v:
            cadenas.append({"carta": x.nombre, "id": cid, "coste": x.carta.coste, "trae": v,
                            "total": x.carta.coste + v, "ruta": ruta, "copias": copias[cid]})
    cadenas.sort(key=lambda c: (-c["total"], c["coste"]))
    out = {"mazo": mazo.nombre, "id": mazo.id, "cadenas": cadenas, "llaves": [], "eslabones": [],
           "sugerencias": []}
    if not cadenas:
        return out
    mejor = cadenas[0]
    # Llaves: inician una cadena casi tan buena como la mejor, o buscan a una que lo hace.
    inician = {c["id"] for c in cadenas if c["total"] >= 0.7 * mejor["total"]}
    llaves = {cid: "inicia la cadena" for cid in inician}
    for cid, x in inst.items():
        if cid in llaves:
            continue
        for h in x.habilidades:
            if _busca(h) and any(y.carta.id in inician for y in hab.candidatos_validos(p, 0, x, h)):
                llaves[cid] = "busca una carta que la inicia"
    n = len(mazo.cartas)
    k = sum(copias[c] for c in llaves)
    out["llaves"] = [{"carta": inst[c].nombre, "copias": copias[c], "papel": papel} for c, papel in llaves.items()]
    out["probLlave"] = {f"turno {t}": round(prob_al_menos_una(k, MANO_INICIAL + t - 1, n), 3) for t in (1, 2, 4, 6)}
    # Eslabones de la mejor cadena.
    limite = lambda cid: (ban or {}).get(cid, 3)  # noqa: E731
    alimentan = [x.nombre for cid, x in inst.items() if _alimenta_cementerio(x.carta)]
    for paso in [{"carta": mejor["carta"], "id": mejor["id"], "soloCementerio": False}] + mejor["ruta"]:
        cid = paso["id"]
        notas = []
        if copias[cid] >= limite(cid):
            notas.append(f"ya está en el máximo de la Ban List ({limite(cid)})")
        if copias[cid] == 1:
            notas.append("una sola copia")
        if paso["soloCementerio"]:
            notas.append("debe estar en el Cementerio; lo alimentan: " + (", ".join(alimentan) or "nada"))
        out["eslabones"].append({"carta": paso["carta"], "copias": copias[cid], "maximo": limite(cid),
                                 "notas": notas})
    if docs:
        out["sugerencias"] = sugerir(mazo, out, ban or {}, docs, inician)
    return out


def sugerir(mazo: Mazo, analisis: dict, ban: dict, docs: dict, inician: set) -> list[dict]:
    """Cartas legales fuera del mazo (o bajo su máximo) que encajan en sus sinergias."""
    copias = Counter(c.id for c in mazo.cartas)
    ediciones = {_edicion(docs[c.id]) for c in mazo.cartas if c.id in docs}
    mejor = analisis["cadenas"][0]
    pide_cementerio = any(e["notas"] and "Cementerio" in " ".join(e["notas"]) for e in analisis["eslabones"])
    out = []
    for cid, d in docs.items():
        carta = carta_desde_doc(cid, d)
        if cid == ORO_INICIAL.id or not carta.programada or copias[cid] >= ban.get(cid, 3) or d.get("soloLibre"):
            continue
        if copias[cid] and "única" in carta.texto.lower():
            continue  # carta Única: una sola copia aunque la Ban List no la nombre
        if _edicion(d) not in ediciones:
            continue
        if carta.raza not in ("", mazo.raza) or (carta.tipo == Tipo.ALIADO and carta.raza != mazo.raza):
            continue
        p = mesa_ideal(mazo.cartas, [carta])
        x = next(i for i in p.j(0).mazo if i.carta.id == cid)
        motivos = []
        trae, ruta = cadena(p, x)
        if trae and copias[cid] == 0:
            motivos.append(f"al entrar trae {trae} Oros en cartas ({' → '.join(r['carta'] for r in ruta)})")
        for h in x.habilidades:
            if _busca(h) and copias[cid] < 3:
                halla = sorted({y.nombre for y in hab.candidatos_validos(p, 0, x, h) if y.carta.id in inician})
                if halla:
                    motivos.append("busca " + ", ".join(halla))
        if pide_cementerio and _alimenta_cementerio(carta) and copias[cid] == 0:
            motivos.append("alimenta el Cementerio")
        # ¿Alguna cadena del mazo la trae y gana valor con ella?
        if copias[cid] == 0:
            nuevo = max((cadena(p, i)[0] + i.carta.coste for i in p.j(0).mazo if i.carta.id == mejor["id"]), default=0)
            if nuevo > mejor["total"]:
                motivos.append(f"alarga la mejor cadena de {mejor['total']} a {nuevo} Oros")
        if motivos:
            out.append({"carta": carta.nombre, "id": cid, "tipo": carta.tipo.value, "coste": carta.coste,
                        "enMazo": copias[cid], "maximo": ban.get(cid, 3), "motivos": motivos,
                        "texto": carta.texto[:220]})
    return sorted(out, key=lambda s: (-len(s["motivos"]), s["coste"]))


def validar(mazo: Mazo, sugerencias: list[dict], docs: dict, ban: dict, *, candidatos: int = 36,
            n0: int = 4, n_conf: int = 30, procesos: int | None = None, log=print) -> dict:
    """Prueba meter cada sugerencia en lugar de una carta del mismo tipo."""
    from .meta import raciales_del_cache
    from .optimizador import MAX_COPIAS, Variante, ronda

    rivales = [m for m in raciales_del_cache() if m.id != mazo.id]
    pool = {c.id: c for c in mazo.cartas}
    nuevas = {s["id"]: carta_desde_doc(s["id"], docs[s["id"]]) for s in sugerencias}
    pool.update(nuevas)
    pool.pop(ORO_INICIAL.id, None)
    maximo = Counter({cid: min(MAX_COPIAS, ban.get(cid, MAX_COPIAS)) for cid in pool})
    # Solo cambios que meten una sugerencia: las cartas del mazo no entran por otra del mazo.
    for cid in set(pool) - set(nuevas):
        maximo[cid] = min(maximo[cid], sum(c.id == cid for c in mazo.cartas))
    return ronda(Variante(list(mazo.cartas)), pool, maximo, rivales, {r.id: 1.0 for r in rivales},
                 prioridad=set(nuevas), candidatos=candidatos, n0=n0, n_conf=n_conf, quedan=4, seed=1,
                 jugador="heuristico", procesos=procesos, log=log)


def informe_md(a: dict) -> str:
    lineas = [f"# Sinergias de {a['mazo']}", ""]
    if not a["cadenas"]:
        return "\n".join(lineas + ["No se encontraron cadenas de cartas que se jueguen gratis unas a otras."])
    lineas += ["| Pagas | Carta | Entran en total | Cadena |", "|---|---|---|---|"]
    for c in a["cadenas"]:
        ruta = " → ".join(r["carta"] + (" (del Cementerio)" if r["soloCementerio"] else "") for r in c["ruta"])
        lineas.append(f"| {c['coste']} | {c['carta']} ×{c['copias']} | {c['total']} Oros | {ruta} |")
    lineas += ["", "**Llaves** (inician la mejor cadena o la buscan): "
               + ", ".join(f"{x['carta']} ×{x['copias']} ({x['papel']})" for x in a["llaves"]),
               "Probabilidad de tener una: " + " · ".join(f"{t} {v * 100:.0f}%" for t, v in a["probLlave"].items()),
               "", "| Eslabón de la mejor cadena | Copias | Máximo | Observación |", "|---|---|---|---|"]
    for e in a["eslabones"]:
        lineas.append(f"| {e['carta']} | {e['copias']} | {e['maximo']} | {'; '.join(e['notas']) or '—'} |")
    if a["sugerencias"]:
        lineas += ["", "| Sugerencia | Tipo | Coste | En el mazo | Por qué |", "|---|---|---|---|---|"]
        for s in a["sugerencias"]:
            lineas.append(f"| {s['carta']} | {s['tipo']} | {s['coste']} | {s['enMazo']}/{s['maximo']} "
                          f"| {'; '.join(s['motivos'])} |")
    return "\n".join(lineas)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.sinergias")
    ap.add_argument("mazo")
    ap.add_argument("--refrescar", action="store_true", help="vuelve a bajar el catálogo de cartas")
    ap.add_argument("--sin-catalogo", action="store_true", help="solo el análisis del mazo, sin sugerencias")
    ap.add_argument("--validar", action="store_true", help="prueba las sugerencias contra el meta")
    args = ap.parse_args(argv)
    from .auditoria import _cargar
    from .datos import cargar_ban_list, exigir_validos

    mazo = _cargar([args.mazo], True)[0]
    ban = cargar_ban_list(mazo.formato, usar_cache=True)
    exigir_validos(mazo, ban=ban)
    docs = None if args.sin_catalogo else documentos(args.refrescar)
    a = analizar(mazo, ban, docs)
    texto = informe_md(a)
    print(texto)
    carpeta = CACHE / "sinergias"
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / f"{mazo.id}.md").write_text(texto + "\n", encoding="utf-8")
    if args.validar and a["sugerencias"]:
        r = validar(mazo, a["sugerencias"], docs, ban)
        print(f"\nWinrate base contra el meta: {r['winrateBase'] * 100:.1f}%")
        for c in r["confirmadas"]:
            print(f"  {c['etiqueta']}: {c['dif'] * 100:+.1f} pts (IC95 {c['ic95'][0] * 100:+.1f} a "
                  f"{c['ic95'][1] * 100:+.1f}){'  ← mejora con confianza' if c['ic95'][0] > 0 else ''}")
        (carpeta / f"{mazo.id}_validacion.json").write_text(
            json.dumps({**r, "confirmadas": [{k: v for k, v in c.items() if k != "cartas"} for c in r["confirmadas"]]},
                       ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
