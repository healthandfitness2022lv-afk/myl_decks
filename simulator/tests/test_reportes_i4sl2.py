"""Reportes I4Sl2 (Sacer Totem vs Titanes) y hkp2r (vs Sombra Agro)."""

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida
from test_reportes_partida import YO

ILIADA = Carta("iliada", "La Ilíada", Tipo.ORO, 0, 0, "", "x", ({
    "accion": "modificarFuerza", "duracion": "hasta_fase_final", "valor": 2, "cuando": "activada",
    "limitePorTurno": 1, "modoFuerza": "sumar", "costo": {"botar": 1}, "zonaActivacion": "reserva_o_pagado",
    "objetivo": {"raza": "Titán", "seleccion": "elige", "zona": "en_juego", "tipos": ["Aliado"], "quien": "propio"}},),
    True)


def test_no_ataca_si_la_iliada_del_rival_gana_el_combate():
    p = partida()
    p.e.activo = 0
    kawit = en_defensa(p, 0, aliado("Kawit", 2, 3, raza="Sacerdote"))
    en_defensa(p, 1, aliado("Temis", 2, 2, raza="Titán"))
    en_zona(p, 1, ILIADA, Zona.RESERVA)
    assert J._refuerzo_activable(p, 1, p.j(1).defensa) == 2
    assert kawit not in YO.elegir_atacantes(p, 0, [kawit])


def test_iliada_en_un_atacante_bloqueado_suma_el_exceso_al_castillo():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    lion = en_defensa(p, 0, aliado("Liontari", 5, 5, raza="Titán"))
    haq = en_defensa(p, 1, aliado("Haquika", 3, 2, [{"accion": "indestructible", "cuando": "continua"}]))
    p._mover(lion, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [lion], {lion.uid: haq}
    il = en_zona(p, 0, ILIADA, Zona.RESERVA)
    assert J._fuerza_temporal_conviene(p, 0, il, il.habilidades[0])


def test_badbury_no_baraja_lo_propio_si_no_hay_objetivo_rival():
    p = partida()
    corff = en_defensa(p, 0, aliado("Corff", 3, 3))
    h = {"accion": "barajar", "opcional": True, "cantidad": 1, "cuando": "al_jugar",
         "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"],
                      "quien": "cualquiera"}}
    badbury = en_zona(p, 0, Carta("badbury", "Anillos de Badbury", Tipo.TOTEM, 3, 0, "", "x", (h,), True), Zona.APOYO)
    assert all(c.controlador == 0 for c in hab.candidatos_validos(p, 0, badbury, h))
    assert not YO.usar_opcional(p, 0, badbury, h)
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    assert rival in hab.candidatos_validos(p, 0, badbury, h)


def test_desterrar_del_cementerio_rival_prioriza_lo_que_recicla():
    p = partida()
    reciclable = Carta("homu", "Homunculus", Tipo.TALISMAN, 1, 0, "", "x", ({
        "accion": "barajar", "cuando": "activada", "zonaActivacion": "cementerio",
        "objetivo": {"quien": "esta_carta"}},), True)
    luz = en_zona(p, 1, Carta("luz", "Luz de Prometeo", Tipo.TALISMAN, 3, 0, "", "x", (), True), Zona.CEMENTERIO)
    homu = en_zona(p, 1, reciclable, Zona.CEMENTERIO)
    h = {"accion": "desterrar", "objetivo": {"zona": "cementerio", "quien": "oponente"}}
    assert YO.elegir_objetivos(p, 0, [luz, homu], 1, h) == [homu]
