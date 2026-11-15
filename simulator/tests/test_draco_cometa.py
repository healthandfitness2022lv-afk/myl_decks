"""Draco Cometa (programado por el agente) y Desleal."""

import json
from pathlib import Path

from myl_sim import habilidades as hab
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.worker import db

import pytest

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, partida
from test_reportes_partida import YO


@pytest.fixture(scope="module")
def cartas():
    try:
        docs = {i: db().collection("cards").document(i).get().to_dict()
                for i in ("draco_cometa", "espada_sagrada_desleal")}
    except Exception:  # sin conexión
        pytest.skip("sin acceso a Firestore")
    out = {i: carta_desde_doc(i, d) for i, d in docs.items() if d}
    faraon = Path(__file__).resolve().parents[1] / "cache" / "mazo_pVmJzkf7GLl5bW3AwWht.json"
    for c in json.loads(faraon.read_text(encoding="utf-8"))["cartas"]:
        if c["nombre"] == "Ramsés II":
            out["ramses_ii"] = carta_desde_doc(c["id"], c)
    return out


def test_draco_cometa_inmoviliza_mientras_este_en_juego(cartas):
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    draco = en_defensa(p, 1, cartas["draco_cometa"])
    assert hab.tiene_prop(p, draco, "furia")
    victima = en_defensa(p, 0, aliado("Pili", 2, 3, [{"accion": "robar", "cuando": "activada"}]))
    h = draco.habilidades[1]
    ok, afectadas = hab._resolver_efecto(p, 1, draco, h)
    hab.aplicar_luego(p, 1, draco, h, ok, afectadas)
    assert victima.sin_habilidad_hasta == "mientras_en_juego"
    assert hab.tiene_estado(p, victima, "no_puede_atacar") and hab.tiene_estado(p, victima, "no_puede_bloquear")
    hab.expirar(p, "hasta_fase_final")
    hab.refrescar_perdidas(p)
    assert victima.sin_habilidad_hasta == "mientras_en_juego"  # sigue mientras Draco esté
    p.destruir(draco)
    hab.refrescar_perdidas(p)
    assert victima.sin_habilidad_hasta is None
    assert not hab.tiene_estado(p, victima, "no_puede_atacar")


def test_draco_cometa_elige_a_ramses_ii(cartas):
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    draco = en_defensa(p, 1, cartas["draco_cometa"])
    ramses = en_defensa(p, 0, cartas["ramses_ii"])
    otro = en_defensa(p, 0, aliado("Guerrero", 2, 3))
    assert YO.elegir_objetivos(p, 1, [otro, ramses], 1, draco.habilidades[1]) == [ramses]


def test_draco_cometa_solo_con_dragones(cartas):
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    draco = en_defensa(p, 1, cartas["draco_cometa"])
    assert hab.condicion_ok(p, 1, draco.habilidades[1])
    en_defensa(p, 1, aliado("Caballero", 2, 2))
    assert not hab.condicion_ok(p, 1, draco.habilidades[1])


def test_desleal_destierra(cartas):
    p = partida()
    p.j(1).oros_virtuales = 3
    desleal = en_zona(p, 1, cartas["espada_sagrada_desleal"], Zona.MANO)
    victima = en_defensa(p, 0, aliado("Pili", 2, 3))
    hab._resolver_efecto(p, 1, desleal, desleal.habilidades[0])
    assert victima.zona == Zona.DESTIERRO
