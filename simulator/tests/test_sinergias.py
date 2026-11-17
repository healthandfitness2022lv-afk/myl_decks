"""Valor de cadena (cartas que se juegan gratis unas a otras) y análisis de sinergias."""

from myl_sim import jugadores, sinergias
from myl_sim.datos import Mazo
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Partida


def _gratis(objetivo):
    return {"accion": "jugarDesde", "modo": "sin_pagar", "cuando": "al_jugar", "cantidad": 1,
            "objetivo": {"seleccion": "elige", "quien": "propio", **objetivo}}


def _c(nombre, tipo, coste, *habilidades, fuerza=2):
    return Carta(id=nombre.lower(), nombre=nombre, tipo=tipo, coste=coste, fuerza=fuerza if tipo == Tipo.ALIADO else 0,
                 raza="Faerie" if tipo == Tipo.ALIADO else "", texto="", revisada=True, habilidades=tuple(habilidades))


# La cadena de Faerie Control, con las habilidades tal como están programadas.
TALIESIN = _c("Taliesin", Tipo.ALIADO, 4, _gratis({"raza": "Faerie", "zona": "mazo", "tipos": ["Aliado"]}))
DAMA = _c("Dama", Tipo.ALIADO, 4, _gratis({"zonas": ["mazo", "cementerio"], "zona": "mazo", "tipos": ["Arma"]}))
ESCUDO = _c("Escudo", Tipo.ARMA, 4, _gratis({"zona": "mazo", "tipos": ["Aliado"], "coste": {"valor": 3, "op": "<="}}))
DAME = _c("Dame", Tipo.ALIADO, 3, _gratis({"zona": "cementerio", "zonas": ["cementerio"], "tipos": ["Aliado"],
                                           "nombres": ["Morgana"]}))
MERLIN = _c("Merlin", Tipo.ALIADO, 3)
MORGANA = _c("Morgana", Tipo.ALIADO, 4)
ORO = _c("Oro", Tipo.ORO, 0)
CARTAS = [TALIESIN] * 2 + [DAMA] + [ESCUDO] * 2 + [DAME] * 3 + [MERLIN] * 3 + [MORGANA] * 3 + [ORO] * 35


def _partida():
    return Partida((CARTAS, CARTAS), (Heuristico(1), Heuristico(2)), inicial=0, seed=1)


def _del_mazo(p, nombre):
    return next(x for x in p.j(0).mazo if x.nombre == nombre)


def _al_cementerio(p, nombre):
    x = _del_mazo(p, nombre)
    p.j(0).mazo.remove(x)
    x.zona = Zona.CEMENTERIO
    p.j(0).cementerio.append(x)


def test_la_cadena_suma_todo_lo_que_arrastra():
    p = _partida()
    _al_cementerio(p, "Morgana")
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Dame")) == 4
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Escudo")) == 3 + 4
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Taliesin")) == 4 + 4 + 3 + 4
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Morgana")) == 0


def test_una_entrada_que_hoy_no_trae_nada_resta():
    p = _partida()  # Cementerio vacío: Dame no tiene a quién revivir
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Dame")) == -jugadores._CASTIGO_ENTRADA_VACIA
    # El Escudo prefiere entonces otro Aliado de coste 3 (Merlin) y guarda la Dame.
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Escudo")) == 3


def test_el_escudo_trae_a_dame_solo_con_morgana_en_el_cementerio():
    yo = Heuristico(1)
    h = ESCUDO.habilidades[0]
    p = _partida()
    candidatos = [_del_mazo(p, "Dame"), _del_mazo(p, "Merlin")]
    assert yo.elegir_objetivos(p, 0, candidatos, 1, h)[0].nombre == "Merlin"
    _al_cementerio(p, "Morgana")
    assert yo.elegir_objetivos(p, 0, candidatos, 1, h)[0].nombre == "Dame"


def test_taliesin_abre_la_cadena_por_la_dama():
    yo = Heuristico(1)
    p = _partida()
    candidatos = [_del_mazo(p, n) for n in ("Morgana", "Merlin", "Dame", "Dama")]
    assert yo.elegir_objetivos(p, 0, candidatos, 1, TALIESIN.habilidades[0])[0].nombre == "Dama"


def test_apagado_no_cambia_nada(monkeypatch):
    monkeypatch.setattr(jugadores, "_VALOR_CADENA", False)
    p = _partida()
    assert jugadores._valor_cadena(p, 0, _del_mazo(p, "Taliesin")) == 0


def test_el_analisis_encuentra_la_cadena_y_sus_eslabones():
    mazo = Mazo(id="m", nombre="Prueba", formato="racial", raza="Faerie", cartas=CARTAS, faltantes=[])
    a = sinergias.analizar(mazo, ban={"dama": 1})
    mejor = a["cadenas"][0]
    assert mejor["carta"] == "Taliesin" and mejor["total"] == 4 + 4 + 4 + 3 + 4
    assert [r["carta"] for r in mejor["ruta"]] == ["Dama", "Escudo", "Dame", "Morgana"]
    assert {x["carta"] for x in a["llaves"]} == {"Taliesin", "Dama"}
    dama = next(e for e in a["eslabones"] if e["carta"] == "Dama")
    assert any("máximo de la Ban List" in n for n in dama["notas"])
    morgana = next(e for e in a["eslabones"] if e["carta"] == "Morgana")
    assert any("Cementerio" in n for n in morgana["notas"])
    assert 0.3 < a["probLlave"]["turno 4"] < 0.7  # 3 llaves en 49 cartas, 11 vistas
