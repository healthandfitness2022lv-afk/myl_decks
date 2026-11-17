"""Auditoría 2026-11-15: ataques letales que la IA dejaba pasar."""

from myl_sim.modelo import Carta, Tipo, Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, partida
from test_reportes_partida import YO

NO_BLOQUEABLE_POR_FUERZA = {
    "accion": "restringirCombate", "modo": "no_bloqueable_por_fuerza", "valor": 3, "cuando": "continua",
    "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": ["Aliado"], "quien": "esta_carta"},
}
BAJAR_FUERZA = {
    "accion": "modificarFuerza", "valor": -1, "cuando": "activada", "fase": "cualquiera", "turno": "cualquiera",
    "costo": {"pagarEstaCarta": True}, "zonaActivacion": "reserva_oro", "cantidad": 1,
    "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": [], "quien": "oponente"},
}
TORO = Carta("toro", "Toro Apis", Tipo.ORO, 0, 0, "", "x", (BAJAR_FUERZA,), True)


def _castillo(p, lado, cartas):
    del p.j(lado).mazo[cartas:]


def test_melisende_cierra_aunque_el_rival_tenga_bloqueadores_grandes():
    """Caballero Armas T21: Melisende (1) contra castillo 1. A Melisende no la
    bloquean Aliados de fuerza 3 o más: los dos de fuerza 5 no la frenan."""
    p = partida()
    melisende = en_defensa(p, 0, aliado("Melisende", 2, 1, (NO_BLOQUEABLE_POR_FUERZA,)))
    en_defensa(p, 1, aliado("Minotauro Colosal", 5, 5))
    en_defensa(p, 1, aliado("Cronos", 5, 5))
    _castillo(p, 1, 1)
    assert YO.elegir_atacantes(p, 0, [melisende]) == [melisende]


def test_un_bloqueador_chico_si_la_frena():
    p = partida()
    melisende = en_defensa(p, 0, aliado("Melisende", 2, 1, (NO_BLOQUEABLE_POR_FUERZA,)))
    en_defensa(p, 1, aliado("Escudero", 1, 2))
    _castillo(p, 1, 1)
    from myl_sim import jugadores as J

    assert J._letal_conjunto(p, 0, [melisende], p.j(1).defensa, 0, 1) == []


def test_un_toro_apis_rebaja_a_un_solo_atacante():
    """Sacer Premier T15: dos Werin (3 + 3) contra castillo 5 y un Toro Apis
    rival. El Toro baja a uno: 3 + 2 = 5, letal."""
    from myl_sim import jugadores as J

    p = partida()
    werin = [en_defensa(p, 0, aliado("Werin", 3, 3)) for _ in range(2)]
    en_zona(p, 1, TORO, Zona.RESERVA)
    assert J._rebaja_disponible(p, 1) == 1 and J._rebaja_total(p, 1) == 1
    assert J._letal_conjunto(p, 0, werin, [], 1, 5) == werin
    assert J._letal_conjunto(p, 0, werin, [], 1, 6) == []
    en_zona(p, 1, TORO, Zona.RESERVA)  # con dos Toros sí bajan a los dos
    assert J._rebaja_total(p, 1) == 2 and J._letal_conjunto(p, 0, werin, [], 1, 5) == []


def test_con_una_carta_de_castillo_ataca_el_letal():
    p = partida()
    werin = [en_defensa(p, 0, aliado("Werin", 3, 3)) for _ in range(2)]
    _castillo(p, 0, 1)
    _castillo(p, 1, 5)
    assert sorted(a.uid for a in YO.elegir_atacantes(p, 0, werin)) == sorted(a.uid for a in werin)
