"""Auditoría de cartas 2026-11-13: texto impreso vs habilidades (datos._corregir)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Tipo, Zona

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida

CACHE = Path(__file__).resolve().parents[1] / "cache"
_CARTAS = {}
for _f in sorted(CACHE.glob("mazo_*.json")):
    for _c in json.loads(_f.read_text(encoding="utf-8"))["cartas"]:
        _CARTAS.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))


def C(nombre):
    if nombre not in _CARTAS:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _CARTAS[nombre]


def test_rito_de_aton_no_es_errante_y_se_activa_una_vez_por_turno():
    rito = C("Rito de Aton")
    assert not any(h.get("accion") == "errante" for h in rito.habilidades)
    h = next(h for h in rito.habilidades if h.get("accion") == "buscar")
    assert h["limitePorTurno"] == 1 and h["limitePorNombre"]
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    en_zona(p, 0, rito, Zona.RESERVA)
    otro = en_zona(p, 0, rito, Zona.MANO)
    p.j(0).oro_jugado = False
    assert any(j.tipo == "oro" and j.carta is otro for j in p.jugadas_legales(0, "vigilia"))


def test_toro_apis_es_indestructible():
    p = partida()
    toro = en_zona(p, 0, C("Toro Apis"), Zona.RESERVA)
    assert not p.destruir(toro)
    assert toro.zona == Zona.RESERVA


def test_qadesh_se_puede_anular_pagando_5():
    q = C("Qadesh")
    assert any(h.get("modo") == "anulable_pagando" and h.get("valor") == 5 for h in q.habilidades)


def test_amkh_previene_que_barajen_mi_aliado():
    p = partida()
    amkh = en_zona(p, 0, C("Amkh"), Zona.RESERVA)
    mio = en_defensa(p, 0, aliado("Grande", 4, 4))
    efecto = {"accion": "barajar", "objetivo": {"quien": "oponente", "tipos": ["Aliado"]}}
    assert hab.prevenir_afectar(p, mio, 1, efecto)
    assert amkh.zona == Zona.CEMENTERIO


def test_amkh_no_previene_destruir():
    p = partida()
    en_zona(p, 0, C("Amkh"), Zona.RESERVA)
    mio = en_defensa(p, 0, aliado("Grande", 4, 4))
    assert not hab.prevenir_afectar(p, mio, 1, {"accion": "destruir"})


def test_tebas_no_se_baja_si_frena_mis_ataques():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    en_defensa(p, 0, aliado("Mio", 4, 4))
    en_defensa(p, 1, aliado("Suyo", 2, 2))
    tebas = en_zona(p, 0, C("Tebas"), Zona.MANO)
    assert J._veto_ataque_me_perjudica(p, 0, tebas)
    en_defensa(p, 1, aliado("Suyo grande", 5, 6))
    assert not J._veto_ataque_me_perjudica(p, 0, tebas)


def test_carmix_impide_desterrar_oros_como_costo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    en_zona(p, 0, C("Carmix"), Zona.RESERVA)
    b = en_zona(p, 0, C("Biblioteca Eterna"), Zona.RESERVA)
    assert not any(j.tipo == "activar" and j.carta is b for j in p.jugadas_legales(0, "vigilia"))


def test_soteira_solo_en_combate():
    p = partida()
    s = en_zona(p, 0, C("Soteira"), Zona.RESERVA)
    a = en_defensa(p, 0, aliado("x", 3, 3))
    assert p.destruir(a)
    assert s.zona == Zona.RESERVA


def test_grandes_faraones_limite_por_nombre_y_raza():
    h = C("Grandes Faraones").habilidades[0]
    assert h["limitePorNombre"]
    assert h["luego"][0]["condicion"] == {"tipo": "aliados_raza", "raza": "Faraón", "valor": 0, "op": "=="}


def test_corona_faraonica_solo_desde_la_reserva():
    assert all(h.get("zonaActivacion") == "reserva_oro" for h in C("Corona Faraónica").habilidades
               if h.get("cuando") == "propia_entra")


def test_quemar_los_templos_baraja_del_cementerio():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    for _ in range(6):
        en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 1, C("Tebas"), Zona.APOYO)
    en_zona(p, 0, C("Akhet"), Zona.APOYO)
    for k in range(3):
        en_zona(p, 0, aliado(f"m{k}", 1, 1), Zona.CEMENTERIO)
    q = en_zona(p, 0, C("Quemar los Templos"), Zona.MANO)
    n0 = len(p.j(0).mazo)
    p.ejecutar_jugada(0, Jugada("jugar", q))
    assert len(p.j(0).mazo) - n0 == 2


# ── Menores y sin programar (2026-11-13, 2ª tanda) ──────────────────────────
def test_sin_programar_ahora_programadas():
    for n in ("Wep Renpet", "Antorcha Olímpica", "Mochuelo", "Glas Gaibhenenn", "Aguila Imperial",
              "Vino De La Eternidad"):
        c = C(n)
        assert c.programada and c.habilidades, n


def test_aguila_imperial_quita_habilidad_a_fuerza_1():
    p = partida()
    en_zona(p, 0, C("Aguila Imperial"), Zona.RESERVA)
    a = en_defensa(p, 1, aliado("uno", 1, 1, [{"accion": "furia", "cuando": "continua"}]))
    b = en_defensa(p, 1, aliado("dos", 2, 2, [{"accion": "furia", "cuando": "continua"}]))
    hab.refrescar_perdidas(p)
    assert a.sin_habilidad_hasta is not None and b.sin_habilidad_hasta is None


def test_herrero_se_destruye_si_pierde_la_habilidad():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    her = en_zona(p, 0, C("Herrero"), Zona.RESERVA)
    fn = en_zona(p, 1, C("Figuras Negras"), Zona.RESERVA)
    j = next(j for j in p.jugadas_legales(1, "vigilia") if j.tipo == "activar" and j.carta is fn)
    p.ejecutar_jugada(1, j)
    assert her.zona == Zona.CEMENTERIO


def test_antorcha_olimpica_necesita_dos_heroes():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    an = en_zona(p, 0, C("Antorcha Olímpica"), Zona.RESERVA)
    en_zona(p, 1, C("Tebas"), Zona.APOYO)
    assert not any(j.tipo == "activar" and j.carta is an for j in p.jugadas_legales(0, "vigilia"))
    en_defensa(p, 0, aliado("h1", 1, 1, raza="Héroe"))
    en_defensa(p, 0, aliado("h2", 1, 1, raza="Héroe"))
    assert any(j.tipo == "activar" and j.carta is an for j in p.jugadas_legales(0, "vigilia"))


def test_milano_negro_toma_la_raza_de_mis_aliados():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    for _ in range(2):
        en_zona(p, 0, ORO, Zona.RESERVA)
    mn = en_zona(p, 0, C("Milano Negro"), Zona.RESERVA)
    en_defensa(p, 0, aliado("s", 1, 1, raza="Sacerdote"))
    j = next(j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "activar" and j.carta is mn)
    p.ejecutar_jugada(0, j)
    assert mn.raza == "Sacerdote"


def test_djedefhor_baraja_solo_con_sacerdotes():
    h = next(h for h in C("Djedefhor").habilidades if h.get("cuando") == "al_salir_del_juego")
    assert h["condicion"]["raza"] == "Sacerdote"


def test_carmix_se_paga_primero_si_me_estorba():
    p = partida()
    carmix = en_zona(p, 0, C("Carmix"), Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 0, C("Salmon del Saber"), Zona.RESERVA)
    p._pagar_oro(0, 1)
    assert carmix.zona == Zona.PAGADO


def test_carmix_se_guarda_si_frena_al_rival():
    p = partida()
    carmix = en_zona(p, 0, C("Carmix"), Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 1, C("Biblioteca Eterna"), Zona.RESERVA)
    p._pagar_oro(0, 1)
    assert carmix.zona == Zona.RESERVA
