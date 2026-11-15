"""Reportes de la partida Faraón guerrero vs Dragón
(simulations/MUh41mkXYK8KpXIFcaIk, seed 74639; sin los pasos 52 y 96).
Un test por arreglo, con las cartas tal como están programadas en los mazos."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import aliado, ORO, en_defensa, partida
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


def _AIRE():
    # Dragón de Aire salió del mazo Dragón (lo reemplazaron Alquimista y Cruzada).
    return _CARTAS.get("Dragón de Aire") or aliado("Dragón de Aire", 4, 4, raza="Dragón")


def C(nombre):
    return _CARTAS[nombre]


# ── #1 (paso 51): Ramsés II descarta a Nephre-Ka, no la Forma de Lince ──────
def test_ramses_ii_descarta_nephre_ka():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(0).reserva[:]  # sin Oros: paga descartando
    ramses = en_defensa(p, 0, C("Ramsés II"))
    for n in ("Nephre-Ka", "Jinetes de Fuego", "Forma de Lince"):
        en_zona(p, 0, C(n), Zona.MANO)
    h = ramses.habilidades[1]
    assert hab.pagar_costo(p, 0, ramses, h)
    assert [c.nombre for c in p.j(0).cementerio] == ["Nephre-Ka"]


# ── #2 (paso 95): con el castillo crítico, Cathach antes que Dragón de Aire ─
def test_cathach_con_castillo_critico():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    del p.j(1).mazo[5:]
    for n in ("Killgharrah", "Dragón Nival", "Gaspar", "Vouivre"):
        en_zona(p, 1, C(n), Zona.CEMENTERIO)
    cathach = en_zona(p, 1, C("Cathach"), Zona.MANO)
    aire = en_zona(p, 1, _AIRE(), Zona.MANO)
    assert YO._puntaje(p, 1, Jugada("jugar", cathach)) > YO._puntaje(p, 1, Jugada("jugar", aire))


# ── #3 (paso 124): con un Killgharrah en mesa no se juega otro ──────────────
def test_no_segundo_killgharrah():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(6):
        en_zona(p, 1, ORO, Zona.RESERVA)
    en_defensa(p, 1, C("Killgharrah"))
    otro = en_zona(p, 1, C("Killgharrah"), Zona.MANO)
    assert not any(j.carta is otro for j in p.jugadas_legales(1, "vigilia"))


# ── #4 (paso 118): Ramsés IX se paga con Látigo y Bastón, no con el Nudo ────
def test_no_paga_con_el_nudo_de_isis():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(0).reserva[:]
    nudo = en_zona(p, 0, C("Nudo De Isis"), Zona.RESERVA)
    for n in ("Látigo y Bastón", "Látigo y Bastón", "Escarabeo"):
        en_zona(p, 0, C(n), Zona.RESERVA)
    ramses = en_zona(p, 0, C("Ramses IX"), Zona.MANO)
    p._pagar_oro(0, 2, carta=ramses)
    assert nudo.zona == Zona.RESERVA
    assert sorted(c.nombre for c in p.j(0).pagado) == ["Látigo y Bastón", "Látigo y Bastón"]


# ── Ajustes UUOX: Cruz Templaria y Vouivre ──────────────────────────────────
def test_cruz_no_para_un_aliado_que_ya_no_hace_nada():
    from myl_sim import jugadores as J
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    cruz = en_zona(p, 1, C("Cruz Templaria"), Zona.RESERVA)
    en_defensa(p, 0, C("Nephre-Ka"))  # fuerza 2, ya usó lo de "al entrar"
    assert not YO._vale_la_pena(p, 1, Jugada("activar", cruz, habilidad=0))
    assert J._amenaza_en_mesa(p, en_defensa(p, 0, C("Ramsés II")))


def test_vouivre_se_juega_por_el_combo():
    from myl_sim import jugadores as J
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(5):
        en_zona(p, 1, ORO, Zona.RESERVA)
    vouivre = en_zona(p, 1, C("Vouivre"), Zona.MANO)
    en_zona(p, 1, C("Gaspar"), Zona.MANO)
    en_zona(p, 1, C("Cathach"), Zona.MANO)
    en_defensa(p, 0, C("Ramsés II"))
    en_defensa(p, 0, C("Nephre-Ka"))
    assert J._sacrificio_sin_combo(p, 1, vouivre)  # no tengo a quién barajar
    en_defensa(p, 1, C("Cultistas del Dragón"))
    assert not J._sacrificio_sin_combo(p, 1, vouivre)  # Cultistas por Ramsés II y Nephre-Ka


def test_vouivre_con_barrida_es_prioridad_sobre_amenaza_cara():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(5):
        en_zona(p, 1, ORO, Zona.RESERVA)
    vouivre = en_zona(p, 1, C("Vouivre"), Zona.MANO)
    killgharrah = en_zona(p, 1, C("Killgharrah"), Zona.MANO)
    en_defensa(p, 1, C("Draig Ifanc"))
    en_defensa(p, 0, C("Ramsés II"))
    en_defensa(p, 0, C("Nephre-Ka"))
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", vouivre), Jugada("jugar", killgharrah), Jugada("pasar")])
    assert elegida.carta is vouivre


def test_paga_el_nudo_si_voy_a_barajar():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(0).reserva[:]
    nudo = en_zona(p, 0, C("Nudo De Isis"), Zona.RESERVA)
    for n in ("Látigo y Bastón", "Látigo y Bastón", "Escarabeo"):
        en_zona(p, 0, C(n), Zona.RESERVA)
    en_defensa(p, 0, C("Gaspar"))  # baraja del Cementerio en mi Vigilia: el Nudo me estorba
    ramses = en_zona(p, 0, C("Ramses IX"), Zona.MANO)
    p._pagar_oro(0, 2, carta=ramses)
    assert nudo.zona == Zona.PAGADO
