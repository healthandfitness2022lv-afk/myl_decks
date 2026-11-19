"""Reportes del tablero pendientes al 2026-11-19: IQVB (Sir Agravain), dmwP
(Marmita Druida, Tadg el Druida, Magia Amatista) y gYcs (Damarchus en la
Guerra de Talismanes). Cartas reales del catálogo local."""

import pytest

from myl_sim.datos import CACHE, carta_desde_doc
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, partida
from test_notas_cartas import jugar
from test_tanda_guerrero_dragon_titan import SiempreUsa

if not (CACHE / "catalogo.json").exists():
    pytest.skip("sin catálogo local", allow_module_level=True)

from myl_sim.sinergias import documentos  # noqa: E402

_DOCS = documentos()


def C(nombre):
    cid, doc = next((k, d) for k, d in _DOCS.items() if d.get("nombre") == nombre)
    return carta_desde_doc(cid, doc)


def _p():
    return partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))


def test_sir_agravain_solo_no_roba():
    """IQVB T2: «si controlas otro Aliado Caballero»; estaba solo y robó 2."""
    p = _p()
    jugar(p, 0, C("Sir Agravain"))
    assert len(p.j(0).mano) == 0
    p = _p()
    en_defensa(p, 0, aliado("Otro", 2, 2, raza="Caballero"))
    jugar(p, 0, C("Sir Agravain"))
    assert len(p.j(0).mano) == 1  # roba 2 y descarta 1


def test_magia_amatista_sin_copia_en_juego_no_roba():
    """dmwP T11: desterró del Mazo rival sin copia en juego y dejaba robar."""
    p = _p()
    en_zona(p, 1, aliado("Solo en el mazo", 2, 2), Zona.MAZO)
    mano = len(p.j(0).mano)
    jugar(p, 0, C("Magia Amatista"))
    assert len(p.j(0).mano) == mano


def test_magia_amatista_con_copia_destruye_y_roba():
    p = _p()
    gemelo = aliado("Gemelo", 4, 4)
    copia = en_defensa(p, 1, gemelo)
    en_zona(p, 1, gemelo, Zona.MAZO)  # la IA destierra la que tiene copia en juego
    jugar(p, 0, C("Magia Amatista"))
    assert copia.zona == Zona.CEMENTERIO and len(p.j(0).mano) == 1


def test_marmita_druida_muestra_un_druida_para_robar():
    """dmwP T1: «puedes mostrar una carta Druida de tu Mano para robar»."""
    from myl_sim import habilidades as hab

    p = _p()
    hab.disparar(p, en_zona(p, 0, C("Marmita Druida"), Zona.RESERVA), "al_jugar")
    assert len(p.j(0).mano) == 0  # sin Druida en la mano, no roba
    p = _p()
    druida = en_zona(p, 0, C("Tadg el Druida"), Zona.MANO)
    hab.disparar(p, en_zona(p, 0, C("Marmita Druida"), Zona.RESERVA), "al_jugar")
    assert druida.revelada and len(p.j(0).mano) == 2


def test_tadg_muestra_la_carta_que_toma():
    """dmwP T3: solo puede tomar un Oro o un Aliado Druida: la muestra."""
    p = _p()
    tomada = en_zona(p, 0, C("Tadg el Druida"), Zona.MAZO)
    p.j(0).mazo.remove(tomada)
    p.j(0).mazo.insert(0, tomada)  # en el tope
    jugar(p, 0, C("Tadg el Druida"))
    assert tomada.zona == Zona.MANO and tomada.revelada


def test_damarchus_se_activa_en_la_guerra_de_talismanes():
    """gYcs T7: «debo poder activar el Damarchus en guerra»."""
    p = _p()
    d = en_defensa(p, 0, C("Damarchus"))
    p.e.fase = "guerra_talismanes"
    assert any(o.tipo == "activar" and o.carta is d for o in p.jugadas_legales(0, "guerra_talismanes"))
