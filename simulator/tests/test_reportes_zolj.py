"""Reportes de la repetición Faraón guerrero vs Dragón
(simulations/ZOlJafNXj5dPbmWmfCGy, seed 59018). Un test por arreglo, con las
cartas tal como están programadas en los mazos (simulator/cache)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida
from test_reportes_partida import YO

CACHE = Path(__file__).resolve().parents[1] / "cache"
_CARTAS = {}
for _f in ("mazo_pVmJzkf7GLl5bW3AwWht.json", "mazo_MrS4zt3yCdpPkAr2zsaE.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _CARTAS[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _CARTAS.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))

pytestmark = pytest.mark.skipif(len(_CARTAS) < 10, reason="faltan los mazos en simulator/cache")


def C(nombre):
    return _CARTAS[nombre]


def _log(p):
    return "\n".join(p.e.log or [])


# ── #1: Látigo y Bastón no muestra un Guerrero si no hay nada que barajar ───
def test_latigo_no_muestra_sin_cementerio():
    p = partida()
    latigo = en_zona(p, 0, C("Látigo y Bastón"), Zona.RESERVA)
    en_zona(p, 0, C("Guerrero Bereber"), Zona.MANO)
    mostrar = latigo.habilidades[0]
    assert not YO.usar_opcional(p, 0, latigo, mostrar)
    en_zona(p, 0, C("Forma de Lince"), Zona.CEMENTERIO)
    assert YO.usar_opcional(p, 0, latigo, mostrar)


# ── #2: la Corona es el Oro principal: se baja antes que Látigo ────────────
def test_corona_antes_que_latigo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    en_defensa(p, 0, C("Guerrero Bereber"))
    en_zona(p, 0, ORO, Zona.RESERVA)
    corona = en_zona(p, 0, C("Corona Faraónica"), Zona.MANO)
    latigo = en_zona(p, 0, C("Látigo y Bastón"), Zona.MANO)
    en_zona(p, 0, C("Ramses IX"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 0, [Jugada("oro", latigo), Jugada("oro", corona), Jugada("pasar")])
    assert elegida.carta is corona


# ── #3 / #8: el robo de un efecto en la Fase Final dice de dónde viene ──────
def test_robo_en_fase_final_nombra_la_carta():
    p = partida(log=True)
    p.e.activo, p.e.fase = 0, "final"
    escorpion = en_defensa(p, 0, C("Guerrero Escorpión"))
    hab._resolver_efecto(p, 0, escorpion, escorpion.habilidades[2])
    assert "Guerrero Escorpión: J0 roba" in _log(p)
    assert "finaliza" not in _log(p)


# ── #4: Ramsés IX dice qué cayó para botar 2 más ───────────────────────────
def test_ramses_ix_narra_lo_que_cayo():
    p = partida(log=True)
    p.e.activo = 0
    ramses = en_defensa(p, 0, C("Ramses IX"))
    milano = en_zona(p, 1, aliado("Milano Rojo", 2, 2, raza="Dragón"), Zona.MAZO)
    p.j(1).mazo.remove(milano)
    p.j(1).mazo.insert(0, milano)
    h = ramses.habilidades[0]
    cumplido, afectadas = hab._resolver_efecto(p, 0, ramses, h)
    hab.aplicar_luego(p, 0, ramses, h, cumplido, afectadas)
    assert "Milano Rojo (Aliado)" in _log(p) and "Ramses IX: cayó" in _log(p)


# ── #5: Dragones solo se juega desde la mano ───────────────────────────────
def test_draig_ifanc_no_busca_dragones():
    assert C("Dragones").solo_desde_mano and not C("Carnwennan").solo_desde_mano
    p = partida()
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.CEMENTERIO)
    for c in list(p.j(1).mazo):
        p.j(1).mazo.remove(c)
    en_zona(p, 1, C("Dragones"), Zona.MAZO)
    buscar = draig.habilidades[1]
    assert hab._resolver_efecto(p, 1, draig, buscar) == (False, []) or not any(
        c.nombre == "Dragones" for c in p.j(1).reserva
    )
    carn = en_zona(p, 1, C("Carnwennan"), Zona.MAZO)
    hab._resolver_efecto(p, 1, draig, buscar)
    assert carn in p.j(1).reserva and not any(c.nombre == "Dragones" for c in p.j(1).reserva)


# ── #6 / #7: Carnwennan a Ptolomeo II antes del Dragón de Magma; nunca a ────
#    Ramsés IX ni a Guerrero Escorpión en mi turno
def _dragon_con_carnwennan(p, oros):
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(oros):
        en_zona(p, 1, ORO, Zona.RESERVA)
    return en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)


def test_carnwennan_a_ptolomeo_antes_del_magma():
    p = partida()
    carn = _dragon_con_carnwennan(p, 4)
    magma = en_zona(p, 1, C("Dragón de Magma"), Zona.MANO)
    ptolomeo = en_defensa(p, 0, C("Ptolomeo II"))
    en_defensa(p, 0, C("Ramses IX"))
    h = carn.habilidades[0]
    assert J._objetivos_perder_habilidad(p, 1, carn, h) == [ptolomeo]
    activar = Jugada("activar", carn, habilidad=0)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", magma), activar, Jugada("pasar")])
    assert elegida is activar


def test_carnwennan_no_sirve_contra_ramses_ni_escorpion():
    p = partida()
    carn = _dragon_con_carnwennan(p, 1)
    en_defensa(p, 0, C("Ramses IX"))
    en_defensa(p, 0, C("Guerrero Escorpión"))
    assert J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0]) == []


# ── Contra agro, Draig Ifanc se trae el Codex Arturicus ────────────────────
def test_draig_ifanc_trae_codex_contra_agro():
    p = partida()
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.CEMENTERIO)
    for c in list(p.j(1).mazo):
        p.j(1).mazo.remove(c)
    for n in ("Corona de Arturo", "Codex Arturicus", "Milano Rojo"):
        en_zona(p, 1, C(n), Zona.MAZO)
    for n in ("Guerrero Bereber", "Ramses IX", "Guerrero Escorpión"):
        en_defensa(p, 0, C(n))
    hab._resolver_efecto(p, 1, draig, draig.habilidades[1])
    assert [c.nombre for c in p.j(1).reserva if c.nombre != "Oro inicial"] == ["Codex Arturicus"]
