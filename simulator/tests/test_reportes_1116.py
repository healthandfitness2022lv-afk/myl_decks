"""Reportes desde la simulación Sombra Agro vs Caballero Plaga (yI09, 14-11):
simulación eTOU (Desafiante Control vs Desafiante Plaga), duda 1GfZ (Piedra
Roseta) y desafío 2PE6 (Amkh). Usan las cartas reales del catálogo local."""

import pytest

from myl_sim import busqueda_vigilia
from myl_sim import habilidades as hab
from myl_sim.datos import CACHE, carta_desde_doc
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import en_defensa, partida

if not (CACHE / "catalogo.json").exists():
    pytest.skip("sin catálogo local (python -m myl_sim.sinergias <mazo> --refrescar)", allow_module_level=True)

from myl_sim.sinergias import documentos  # noqa: E402

_DOCS = documentos()
_CARTAS = {}


def C(nombre):
    if nombre not in _CARTAS:
        cid, doc = next((k, d) for k, d in _DOCS.items() if d.get("nombre") == nombre)
        _CARTAS[nombre] = carta_desde_doc(cid, doc)
    return _CARTAS[nombre]


YO = Heuristico(1)


def test_caturix_baraja_tambien_oros_del_cementerio():
    """eTOU T14: «Oros y/o Aliados de raza Desafiante»: la raza filtra solo a los Aliados."""
    p = partida()
    for n in ("Aine", "Salmon del Saber", "Conand"):
        en_zona(p, 0, C(n), Zona.CEMENTERIO)
    caturix = en_defensa(p, 0, C("Caturix"))
    nombres = {x.nombre for x in hab.candidatos_validos(p, 0, caturix, C("Caturix").habilidades[0])}
    assert nombres == {"Aine", "Salmon del Saber"}  # Conand es Sombra


def test_desafiar_a_arturo_no_se_baraja_a_si_mismo():
    """yI09 T3: el Talismán va al Cementerio recién al terminar de resolverse."""
    p = partida()
    desafiar = en_zona(p, 0, C("Desafiar A Arturo"), Zona.CEMENTERIO)
    en_zona(p, 0, C("Aine"), Zona.CEMENTERIO)
    luego = C("Desafiar A Arturo").habilidades[0]["luego"][0]
    assert [x.nombre for x in hab.candidatos(p, 0, desafiar, luego)] == ["Aine"]


def test_piedra_roseta_se_activa_ya_pagada():
    """Duda 1GfZ: «tengo 2 Sacerdotes, debería poder activar la Roseta»."""
    p = partida()
    for n in ("Haquika", "Nuh"):
        en_defensa(p, 0, C(n))
    roseta = en_zona(p, 0, C("Piedra Roseta"), Zona.PAGADO)
    en_zona(p, 0, C("Aine"), Zona.MANO)
    p.e.fase, p.e.activo = "vigilia", 0
    assert hab.activable(p, 0, roseta, roseta.habilidades[0], 0, "vigilia")


def test_amkh_no_previene_una_destruccion():
    """Desafío 2PE6: Amkh solo previene que la carta sea barajada o puesta en el Mazo."""
    p = partida()
    en_zona(p, 1, C("Amkh"), Zona.RESERVA)
    nuh = en_defensa(p, 1, C("Nuh"))
    assert p.destruir(nuh, combate=True)
    assert nuh.zona == Zona.CEMENTERIO


def test_salmon_del_saber_va_al_atacante_que_me_hace_dano():
    """eTOU T17: iba a un Bodb Derg que no atacaba; el Caturix bloqueado pasaba 3."""
    p = partida()
    caturix = en_defensa(p, 1, C("Caturix"))
    quieto = en_defensa(p, 1, C("Bodb Derg"))
    mio = en_defensa(p, 0, C("Rhiannon"))
    p.atacantes, p.bloqueos = [caturix], {caturix.uid: mio}
    h = C("Salmon del Saber").habilidades[1]
    assert YO.elegir_objetivos(p, 0, [quieto, caturix], 1, h) == [caturix]


def test_oillipheist_destierra_lo_que_mas_le_sirve_al_rival():
    """yI09 T9: entre Sir Dinadan, Espada Larga (roba 2) y Caballeros, la Espada."""
    p = partida()
    vistas = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Sir Dinadan", "Espada Larga", "Caballeros")]
    h = {**C("Oillipheist").habilidades[1], "accion": "mirarTope"}
    assert YO.elegir_objetivos(p, 0, vistas, 1, h)[0].nombre == "Espada Larga"


def test_magia_amatista_destierra_la_copia_del_que_esta_en_juego():
    """eTOU T8: desterró a Nuada del Mazo y no a Bodb Derg, que además destruía el de la mesa."""
    p = partida()
    en_defensa(p, 1, C("Bodb Derg"))
    del_mazo = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Nuada Brazo de Plata", "Bodb Derg")]
    h = C("Magia Amatista").habilidades[0]
    assert YO.elegir_objetivos(p, 0, del_mazo, 1, h)[0].nombre == "Bodb Derg"


def test_martillo_pesado_antes_que_otra_tutatis():
    """eTOU T17: con 3 Oros, el Martillo (saca un bloqueador) en el Caturix que ataca."""
    p = partida()
    for n in ("Caturix", "Caturix", "Bodb Derg"):
        en_defensa(p, 1, C(n))
    en_defensa(p, 1, C("Tutatis"), listo=False)
    for n in ("Caturix", "Bodb Derg"):
        en_defensa(p, 0, C(n))
    for n in ("Tutatis", "Martillo Pesado", "Red de Plata"):
        en_zona(p, 1, C(n), Zona.MANO)
    for n in ("Linaje Celta", "Joya Amatista", "Clochafarmore"):
        en_zona(p, 1, C(n), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 1
    p.j(1).oro_jugado = True
    j = YO.elegir_jugada(p, 1, p.jugadas_legales(1, "vigilia"))
    assert j.carta.nombre == "Martillo Pesado" and j.portador.nombre == "Caturix"


def test_la_ia_buena_simula_a_quien_destruye_el_martillo():
    """yI09 T9: el Martillo destruye «una carta en juego» (quien=cualquiera):
    la búsqueda compara las del rival en vez de dejarlo a la regla."""
    p = partida()
    portador = en_defensa(p, 0, C("Abhartach"))
    for n in ("Saladino", "Sir Erec", "Melchor"):
        en_defensa(p, 1, C(n))
    martillo = en_zona(p, 0, C("Martillo Pesado"), Zona.MANO)
    for n in ("Linaje Celta", "Joya Amatista", "Clochafarmore"):
        en_zona(p, 0, C(n), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 0
    j = next(x for x in p.jugadas_legales(0, "vigilia") if x.carta is martillo and x.portador is portador)
    objetivos = busqueda_vigilia._objetivos_en_juego(p, 0, j, 4)
    assert {t.nombre for t in objetivos} == {"Saladino", "Sir Erec", "Melchor"}
