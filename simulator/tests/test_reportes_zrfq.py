"""Reportes de la partida Faraón guerrero vs Dragón
(simulations/ZrfqvGljolCLkXNOf5o6, seed 59018). Un test por arreglo, con las
cartas tal como están programadas en los mazos (simulator/cache)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida
from test_reportes_partida import YO, _activar, _vale

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


# ── #1: Aton busca la Corona Faraónica ──────────────────────────────────────
def test_aton_busca_la_corona():
    p = partida()
    aton = en_zona(p, 0, C("Aton"), Zona.MANO)
    cands = [en_zona(p, 0, C(n), Zona.MAZO) for n in ("Jeroglificos", "Nudo De Isis", "Corona Faraónica")]
    buscar = next(h for h in aton.habilidades if h.get("accion") == "buscar")
    assert YO.elegir_objetivos(p, 0, cands, 1, buscar)[0].nombre == "Corona Faraónica"


# ── #2: con exceso de mano, Dragón descarta a Lady Calvaur ──────────────────
def test_descarta_lady_calvaur():
    p = partida()
    mano = [en_zona(p, 1, C(n), Zona.MANO) for n in ("Fe Sin Limite", "Lady Calvaur", "Dragón de Magma", "Draig Ifanc")]
    assert YO.elegir_descartes(p, 1, mano, 1)[0].nombre == "Lady Calvaur"


# ── #3: Forma de Lince se guarda para la Guerra de Talismanes ───────────────
def test_forma_de_lince_no_en_la_vigilia():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    b = en_defensa(p, 0, C("Guerrero Bereber"))
    f = en_zona(p, 0, C("Forma de Lince"), Zona.MANO)
    p.j(0).oros_virtuales = 3
    assert not _vale(p, Jugada("jugar", f))
    p.e.fase = "guerra_talismanes"
    p._mover(b, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [b], {}
    assert _vale(p, Jugada("jugar", f))  # atacante libre: más daño y roba la copia


# ── #4: la narración dice qué carta del Mazo miró ───────────────────────────
def test_latigo_narra_la_carta_mirada():
    p = partida(log=True)
    p.e.activo, p.e.fase = 0, "final"
    lat = en_zona(p, 0, C("Látigo y Bastón"), Zona.RESERVA)
    en_defensa(p, 0, C("Guerrero Bereber"))
    h = next(x for x in lat.habilidades if x.get("accion") == "mirarTope")
    hab.resolver(p, 0, lat, h)
    assert any("mira la primera carta del Mazo de J0" in linea for linea in p.e.log)


# ── #5: el +1 al atacar de Bereber cuenta para atacar ───────────────────────
def test_bereber_ataca_contra_un_bloqueador_de_2():
    p = partida()
    b = en_defensa(p, 0, C("Guerrero Bereber"))
    en_defensa(p, 1, C("Draig Ifanc"))
    assert b in YO.elegir_atacantes(p, 0, [b])


# ── #8: el Merodeador no le da fuerza a quien no ataca este turno ───────────
def test_merodeador_no_sube_al_que_no_ataca():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    mero = en_defensa(p, 0, C("Merodeador de las arenas"), listo=False)
    medjay = en_defensa(p, 0, C("Guerrero Medjay"), listo=False)
    en_zona(p, 0, ORO, Zona.CEMENTERIO)
    k = next(i for i, h in enumerate(mero.habilidades) if h.get("accion") == "modificarFuerza")
    assert not _vale(p, _activar(mero, k))  # nadie ataca este turno
    medjay.listo = True
    assert not _vale(p, _activar(mero, k))  # #3 EZMt: en la Vigilia no; se espera a ver los bloqueos
    p.e.fase = "guerra_talismanes"
    p._mover(medjay, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [medjay], {}
    assert _vale(p, _activar(mero, k))


# ── #6: Draig Ifanc se queda bloqueando contra varios atacantes ─────────────
def test_draig_ifanc_se_queda_en_casa():
    p = partida()
    d = en_defensa(p, 1, C("Draig Ifanc"))
    en_defensa(p, 0, C("Guerrero Bereber"))
    en_defensa(p, 0, C("Merodeador de las arenas"))
    assert d not in YO.elegir_atacantes(p, 1, [d])


# ── #7: Vouivre baraja a Draig Ifanc para barajar 2 Aliados rivales ─────────
def test_vouivre_baraja_draig_y_dos_rivales():
    p = partida()
    v = en_zona(p, 1, C("Vouivre"), Zona.DEFENSA)
    d = en_defensa(p, 1, C("Draig Ifanc"))
    for n in ("Nephre-Ka", "Guerrero Bereber", "Merodeador de las arenas"):
        en_defensa(p, 0, C(n) if n in _CARTAS else aliado(n, 2, 2))
    h = next(x for x in v.habilidades if x.get("cuando") == "al_jugar")
    p.ctx_fuente_habilidad = v
    assert YO.usar_opcional(p, 1, v, h)
    assert YO.elegir_objetivos(p, 1, hab.candidatos_validos(p, 1, v, h), 1, h) == [d]


# ── #9: Draig Ifanc rampea su Oro aunque el castillo esté corto ─────────────
def test_draig_rampea_con_castillo_corto():
    p = partida()
    d = en_defensa(p, 1, C("Draig Ifanc"))
    del p.j(1).mazo[7:]
    en_zona(p, 1, ORO, Zona.MAZO)
    en_defensa(p, 0, C("Guerrero Medjay"))
    h = next(x for x in d.habilidades if x.get("cuando") == "al_salir_del_juego")
    assert YO.usar_opcional(p, 1, d, h)


# ── #10: Cultistas del Dragón se activa al tiro ─────────────────────────────
def test_cultistas_se_activan():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    cul = en_defensa(p, 1, C("Cultistas del Dragón"))
    for _ in range(3):
        en_zona(p, 0, aliado("Ramsés II", 4, 6), Zona.MANO)
    assert YO._vale_la_pena(p, 1, _activar(cul, 0))
