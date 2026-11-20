"""Reportes del tablero sin atender al 2026-11-20 (revisión de los antiguos y
los nuevos NJO9/A3SB). Cartas reales del catálogo local."""

import pytest

from myl_sim import habilidades as hab
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


def test_resplandor_de_heka_quita_la_habilidad_solo_hasta_la_fase_final():
    """NJO9 T13: «entra en juego sin habilidad hasta la Fase Final»."""
    h = next(x for x in C("Resplandor de Heka").habilidades if x.get("accion") == "perderHabilidad")
    assert h["duracion"] == "hasta_fase_final"


def test_guerrero_escorpion_solo_no_roba_en_la_fase_final():
    """lLnW T3 / ffAu T3: «debe tener otro aliado Guerrero más en juego»."""
    p = _p()
    p.e.activo = 0
    escorpion = en_defensa(p, 0, C("Guerrero Escorpión"))
    p.ataco_este_turno.add(escorpion.uid)
    mano = len(p.j(0).mano)
    hab.disparar_inicio_fase(p, "final")
    assert len(p.j(0).mano) == mano
    en_defensa(p, 0, aliado("Guerrero de Prueba", 2, 2, raza="Faraón"))
    hab.disparar_inicio_fase(p, "final")
    assert len(p.j(0).mano) == mano + 1


def test_djedefhor_no_se_baraja_a_si_mismo_al_salir():
    """oXy1 T8: «no puede barajarse a sí mismo cuando va saliendo»."""
    p = _p()
    dj = en_defensa(p, 0, C("Djedefhor"))
    otra = en_zona(p, 0, aliado("Del cementerio", 1, 1), Zona.CEMENTERIO)
    p.destruir(dj)
    assert dj.zona == Zona.CEMENTERIO and otra.zona == Zona.MAZO


def test_crom_dubh_desterrado_no_dispara():
    """5Lcf T3: solo «si este Aliado es destruido»; desterrado no destierra."""
    p = _p()
    crom = en_defensa(p, 0, C("Crom Dubh"))
    tope = en_zona(p, 1, aliado("Tope rival", 1, 1), Zona.MAZO)
    p.desterrar(crom)
    assert tope.zona == Zona.MAZO


def test_epicuro_no_se_sube_a_si_mismo():
    """qZJp T15: «no se puede subir a sí mismo»."""
    p = _p()
    ep = en_defensa(p, 0, C("Epicuro De Samos"))
    h = next(x for x in ep.habilidades if x.get("accion") == "subirMano")
    assert ep not in hab.candidatos_validos(p, 0, ep, h)


def test_focea_deja_al_aliado_en_el_tope():
    """g3hq T5: con armas, el Aliado debe quedar en el tope del mazo."""
    from test_notas_cartas import _cargar, arma as Arma

    p = _p()
    rival = en_defensa(p, 1, aliado("Portador", 3, 3))
    arma, jugada = _cargar(p, 1, Arma("Espada de Prueba", 1, []), rival)
    assert jugada is not None
    p.e.activo = 0
    jugar(p, 0, C("Focea"))
    assert p.j(1).mazo[0] is rival and arma.zona == Zona.MAZO


def test_ya_corregidos_teseo_killgharrah_cleopatra_demoledor():
    """g3hq T7/T15 (Teseo se destruía a sí mismo), lLnW T20 (segundo
    Killgharrah), 9Phx T10 (Cleopatra nombraba Faraón) y oHee T18 (Demoledor
    sin habilidad por Cleopatra atacaba al entrar): ya no ocurren."""
    from myl_sim.jugadores import Heuristico

    p = _p()
    teseo = en_defensa(p, 0, C("Teseo de Atenas"))
    en_defensa(p, 0, aliado("Otro Héroe", 2, 2, raza="Héroe"))
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    h = next(x for x in teseo.habilidades if x.get("accion") == "destruir")
    assert hab.candidatos_validos(p, 0, teseo, h) == [rival]

    p = _p()
    en_defensa(p, 0, C("Killgharrah"))
    segundo = en_zona(p, 0, C("Killgharrah"), Zona.MANO)
    p.j(0).oros_virtuales, p.e.activo, p.e.fase = 10, 0, "vigilia"
    assert not any(o.carta is segundo for o in p.jugadas_legales(0, "vigilia"))

    h = next(x for x in C("Cleopatra VII").habilidades if x.get("accion") == "perderHabilidad")
    assert "Faraón" in h["objetivo"]["excluirRazas"]

    class NombraSacerdote(Heuristico):
        def elegir_raza(self, p, yo, razas, h):
            return "Sacerdote"

    p = partida(jugadores=(Heuristico(1), NombraSacerdote(2)))
    p.e.activo = 1
    jugar(p, 1, C("Cleopatra VII"))
    p.e.activo = 0
    demoledor = jugar(p, 0, C("Demoledor de Amon"))
    assert not hab.tiene_prop(p, demoledor, "furia")


def test_destrucciones_en_masa_en_una_sola_lista():
    """g3hq T11: primero la lista de destruidos y después las activaciones."""
    from myl_sim.motor import _compactar

    out = _compactar(["A es destruido en combate", "A: roba Carta", "B es destruido en combate",
                      "C es destruido en combate"])
    assert out[0] == "Destruidos en combate: A, B, C" and out[1] == "A: roba Carta"
    assert _compactar(["A es destruido en combate"]) == ["A es destruido en combate"]


def test_la_foto_cuenta_los_oros_generados_restringidos():
    """g3hq T10: los Oros de Saladino (solo para ciertas cartas) también se ven."""
    p = _p()
    p.e.log = []
    p.j(0).oros_virtuales = 1
    p.j(0).oros_restringidos.append([2, ["Arma"], "", 0])
    assert p.foto("x")["j"][0]["v"] == 3
