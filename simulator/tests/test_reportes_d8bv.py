"""Reportes de la partida Faraón guerrero vs Dragón
(simulations/d8bVmrleX92q9c6HZvU2, seed 59018). Un test por arreglo, con las
cartas tal como están programadas en los mazos (simulator/cache)."""

import json
from pathlib import Path

import pytest

from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, partida
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


def _castillo(p, i, n):
    del p.j(i).mazo[n:]


# ── #1: dos atacantes contra un bloqueador y castillo de 3: se ataca ────────
def test_ataca_con_todos_si_no_alcanza_a_bloquear():
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    ramses = en_defensa(p, 0, C("Ramses IX"))
    escorpion = en_defensa(p, 0, C("Guerrero Escorpión"))
    en_defensa(p, 1, C("Dragón Nival"))
    _castillo(p, 1, 3)
    assert sorted(c.nombre for c in YO.elegir_atacantes(p, 0, [ramses, escorpion])) == ["Guerrero Escorpión", "Ramses IX"]


# ── #2: no cambia a Ramsés IX por Dragón Nival si atacando gana ─────────────
def test_no_bloquea_con_el_que_remata():
    p = partida()
    p.e.activo = 1
    ramses = en_defensa(p, 0, C("Ramses IX"))
    nival = en_defensa(p, 1, C("Dragón Nival"))
    _castillo(p, 1, 4)
    assert YO.elegir_bloqueos(p, 0, [nival], [ramses]) == {}
    del p.j(1).mazo[:]
    for _ in range(20):
        en_zona(p, 1, aliado("Relleno", 1, 1), Zona.MAZO)
    assert YO.elegir_bloqueos(p, 0, [nival], [ramses]) == {nival.uid: ramses}  # sin remate, el cambio parejo sigue


# ── #3: Mercaderes no se vuelve bloqueador contra Ramsés II ─────────────────
def test_mercaderes_no_contra_ramses_ii():
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    en_zona(p, 1, C("Codex Arturicus"), Zona.RESERVA)
    p.atacantes = [en_defensa(p, 0, C("Ramsés II"))]
    assert not J._bloquearia_con(p, 1, 3)
    p.atacantes = [en_defensa(p, 0, C("Guerrero Bereber"))]
    assert J._bloquearia_con(p, 1, 3)  # a uno de 2 lo mata


# ── #4: Gaspar baraja 2 Aliados Dragón; la carta suelta no es un Aliado ─────
def test_gaspar_prefiere_dos_dragones():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    gaspar = en_defensa(p, 1, C("Gaspar"))
    una, dos = gaspar.habilidades
    kill = en_zona(p, 1, C("Killgharrah"), Zona.CEMENTERIO)
    codex = en_zona(p, 1, C("Codex Arturicus"), Zona.CEMENTERIO)
    assert not J._otra_opcion_mejor(p, 1, gaspar, una)  # un solo Dragón: vale la de 1 carta
    p.ctx_fuente_habilidad = gaspar
    assert YO.elegir_objetivos(p, 1, [kill, codex], 1, una) == [codex]
    en_zona(p, 1, C("Draig Ifanc"), Zona.CEMENTERIO)
    assert J._otra_opcion_mejor(p, 1, gaspar, una)
    assert not J._otra_opcion_mejor(p, 1, gaspar, dos)


# ── #1b: Ramsés IX solo: el rival bota 1 sí o sí y 2 más si cae Oro/Aliado ──
def test_ramses_ix_ataca_si_lo_que_bota_gana():
    from myl_sim import habilidades as hab
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    ramses = en_defensa(p, 0, C("Ramses IX"))
    en_defensa(p, 1, aliado("Muralla", 4, 5))  # lo bloquea y lo mata: igual bota
    del p.j(1).mazo[:]
    for _ in range(3):
        en_zona(p, 1, aliado("Dragón", 2, 2), Zona.MAZO)
    assert J._bota_letal_al_atacar(p, 0, ramses)
    assert [c.nombre for c in YO.elegir_atacantes(p, 0, [ramses])] == ["Ramses IX"]
    # Con 4 en el castillo no alcanza: 1 + 2.
    en_zona(p, 1, aliado("Dragón", 2, 2), Zona.MAZO)
    assert not J._bota_letal_al_atacar(p, 0, ramses)
    assert hab.fuerza(p, ramses) == 3


# ── #3b: Mercaderes con Corona de Arturo y otro Aliado: indestructible ──────
def test_mercaderes_con_corona_de_arturo():
    from myl_sim import habilidades as hab
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    p.atacantes = [en_defensa(p, 0, aliado("Coloso", 5, 5))]
    merc = en_zona(p, 1, C("Mercaderes"), Zona.RESERVA)
    en_defensa(p, 1, C("Gaspar"))
    assert not J._bloquearia_con(p, 1, 3)  # sin Corona no muere bien contra 5
    en_zona(p, 1, C("Corona de Arturo"), Zona.RESERVA)
    assert J._bloquearia_con(p, 1, 3)
    ok, _ = hab._resolver_efecto(p, 1, merc, merc.habilidades[0])
    assert ok and hab.tiene_prop(p, merc, "indestructible")  # sigue siendo un Oro


# ── Mercaderes vuelve a la zona de Oro de la que salió ──────────────────────
@pytest.mark.parametrize("zona", [Zona.PAGADO, Zona.RESERVA])
def test_mercaderes_vuelve_a_su_zona(zona):
    from myl_sim import habilidades as hab
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    merc = en_zona(p, 1, C("Mercaderes"), zona)
    ok, _ = hab._resolver_efecto(p, 1, merc, merc.habilidades[0])
    assert ok and merc.zona == Zona.DEFENSA
    hab.expirar(p, "hasta_fase_final")
    assert merc.zona == zona and merc.tipo == merc.carta.tipo
