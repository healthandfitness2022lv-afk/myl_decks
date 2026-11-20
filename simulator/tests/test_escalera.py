"""Escalera del modo Entrenamiento: rating de cada rival y carga de su mazo."""

import pytest

from myl_sim import datos, escalera
from myl_sim.datos import Mazo
from myl_sim.modelo import Carta, Tipo


def _informe():
    return {"meta": "prueba", "ranking": [
        {"id": "fuerte", "raza": "Faraón", "perfil": "Agro", "indice": 80, "score": 0.65},
        {"id": "parejo", "raza": "Faraón", "perfil": "Agro", "indice": 70, "score": 0.50},
        {"id": "debil", "raza": "Dragón", "perfil": "Control", "indice": 20, "score": 0.35},
    ]}


def test_elo_de_cada_nivel_sale_de_la_arena():
    ranking = {"ranking": [
        {"motor": "nivel1@v1115", "elo": 1034, "partidas": 480},
        {"motor": "nivel2@v1115", "elo": 1236, "partidas": 480},
        {"motor": "heuristico#aaa", "elo": 1508, "partidas": 1200},
        {"motor": "heuristico@v1115b", "elo": 1504, "partidas": 7360},  # la más medida
        {"motor": "busqueda_vigilia#bbb", "elo": 1616, "partidas": 720},
    ]}
    elos = escalera.elo_niveles(ranking)
    assert elos[1] == 1034 and elos[2] == 1236 and elos[4] == 1504 and elos[5] == 1616
    assert elos[3] == escalera.ELO_POR_DEFECTO[3]  # sin medir: valor por defecto
    assert escalera.elo_niveles(None) == escalera.ELO_POR_DEFECTO
    # Nunca un nivel más alto por debajo del anterior.
    raro = escalera.elo_niveles({"ranking": [{"motor": "nivel2", "elo": 900, "partidas": 10}]})
    assert raro[2] > raro[1]


def test_ajuste_por_fuerza_del_mazo():
    assert escalera.ajuste_mazo(0.5) == 0
    assert escalera.ajuste_mazo(0.64) == 100  # 64% de victorias ≈ +100 Elo
    assert escalera.ajuste_mazo(0.36) == -100
    assert escalera.ajuste_mazo(0.99) == escalera.TOPE_MAZO
    assert escalera.ajuste_mazo(0.0) == -escalera.TOPE_MAZO


def test_escalera_ordenada_y_con_nombres_sin_dueño():
    e = escalera.generar(_informe())
    r = e["rivales"]
    assert len(r) == 15 and [x["rating"] for x in r] == sorted(x["rating"] for x in r)
    assert {x["nombre"] for x in r} == {"Faraón Agro", "Faraón Agro II", "Dragón Control"}
    por_id = {x["id"]: x for x in r}
    assert por_id["parejo|4"]["rating"] == escalera.ELO_POR_DEFECTO[4]
    assert por_id["fuerte|4"]["rating"] > por_id["parejo|4"]["rating"] > por_id["debil|4"]["rating"]
    assert por_id["fuerte|5"]["rating"] > por_id["fuerte|1"]["rating"]
    assert por_id["fuerte|5"]["deck"] == "fuerte"
    assert e["ratingInicial"] == r[0]["rating"] + 100


def test_el_worker_carga_el_mazo_rival_desde_el_cache(tmp_path, monkeypatch):
    monkeypatch.setattr(escalera, "CARPETA", tmp_path)
    oro = Carta(id="oro", nombre="Oro", tipo=Tipo.ORO, coste=0, fuerza=0, raza="", texto="", revisada=True)
    mazos = [Mazo(id=i, nombre=i, formato="racial", raza="X", cartas=[oro] * 3, faltantes=[])
             for i in ("fuerte", "otro")]
    e = escalera.generar(_informe())
    assert escalera.guardar_mazos(mazos, e) == 1  # "otro" no está en la escalera
    m = datos.cargar_mazo("cualquier_uid", "escalera:fuerte")
    assert m.id == "fuerte" and len(m.cartas) == 3
    with pytest.raises(ValueError):
        datos.cargar_mazo("uid", "escalera:parejo")  # sin lista guardada
    with pytest.raises(ValueError):
        datos.cargar_mazo("uid", "escalera:../secreto")
    assert "Faraón Agro" in escalera.escalera_md(e)
