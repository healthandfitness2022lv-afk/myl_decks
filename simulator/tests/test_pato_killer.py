"""Artabano el Guerrero, Guerrero de Guardia y Xerxes el Grande (Pato Killer
top 32, notable_decks/YEXidMgF2kBoqNYOMmWP), con las cartas del caché."""

import json
from pathlib import Path

import pytest

from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida
from test_reportes_partida import YO

CACHE = Path(__file__).resolve().parents[1] / "cache"
_C = {}
for _f in ("mazo_YEXidMgF2kBoqNYOMmWP.json", "mazo_PQQzjvNznnYBs4VA3nz5.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _C[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _C.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))


def K(nombre):
    if nombre not in _C:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _C[nombre]


def _vigilia(p, oros):
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    for _ in range(oros):
        en_zona(p, 0, ORO, Zona.RESERVA)


def test_artabano_destruye_hasta_el_coste_de_sus_guerreros():
    p = partida()
    _vigilia(p, 4)
    en_defensa(p, 0, K("Guerrero Bereber"))
    mel = en_defensa(p, 1, K("Melisende"))
    arturo = en_defensa(p, 1, K("Rey Arturo Pendragón"))
    art = en_zona(p, 0, K("Artabano el Guerrero"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", art))
    assert mel not in p.j(1).aliados and arturo in p.j(1).aliados


def test_artabano_quita_la_habilidad_antes_indestructible_no_lo_salva():
    p = partida()
    _vigilia(p, 4)
    en_defensa(p, 0, K("Guerrero Bereber"))
    duro = en_defensa(p, 1, aliado("Muro", 2, 2, [{"accion": "indestructible", "cuando": "continua"}]))
    art = en_zona(p, 0, K("Artabano el Guerrero"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", art))
    assert duro not in p.j(1).aliados


def test_guerrero_de_guardia_ataca_con_otro_guerrero_y_quita_habilidad():
    p = partida()
    _vigilia(p, 3)
    en_defensa(p, 0, K("Guerrero Bereber"))
    mel = en_defensa(p, 1, K("Melisende"))
    g = en_zona(p, 0, K("Guerrero de Guardia"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", g))
    assert g.listo and mel.sin_habilidad_hasta == "hasta_fase_final"


def test_guerrero_de_guardia_sin_otro_guerrero_no_ataca():
    p = partida()
    _vigilia(p, 3)
    en_defensa(p, 1, K("Melisende"))
    g = en_zona(p, 0, K("Guerrero de Guardia"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", g))
    assert not g.listo


def test_xerxes_ataca_y_trae_un_aliado_que_ataca_ya():
    p = partida()
    _vigilia(p, 4)
    del p.j(0).mazo[:]
    for n in ("Guerrero Medjay", "Kamose el Guerrero", "Guerrero Bereber", "Ramsés II"):
        en_zona(p, 0, K(n), Zona.MAZO)
    x = en_zona(p, 0, K("Xerxes el Grande"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", x))
    nombres = [a.nombre for a in p.j(0).aliados]
    assert x.listo and "Guerrero Bereber" in nombres and "Ramsés II" not in nombres


def test_artabano_al_final_si_los_guerreros_lo_dejan_llegar_mas_lejos():
    p = partida()
    _vigilia(p, 5)
    en_defensa(p, 1, K("Rey Arturo Pendragón"))  # coste 4
    en_defensa(p, 0, K("Guerrero Medjay"))
    art = en_zona(p, 0, K("Artabano el Guerrero"), Zona.MANO)
    ber = en_zona(p, 0, K("Guerrero Bereber"), Zona.MANO)
    # Ahora: Medjay + Artabano = 2 (no alcanza a Arturo). Con Bereber primero: 3... y con
    # Kamose, 4: el orden importa cuando el siguiente Guerrero abre un objetivo mejor.
    en_defensa(p, 1, K("Melisende"))
    en_defensa(p, 1, aliado("Sir de 3", 3, 6, []))
    elegida = YO.elegir_jugada(p, 0, [Jugada("jugar", art), Jugada("jugar", ber), Jugada("pasar")])
    assert elegida.carta is ber
