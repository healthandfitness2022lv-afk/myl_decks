"""Reportes de Héctor del 2026-11-18 (desafío SkkvVn)."""

from myl_sim import habilidades as hab
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, h, partida
from test_notas_cartas import oro
from test_tanda_guerrero_dragon_titan import SiempreUsa

CINTURON = oro("Cinturón De Lady Ann", [h("restriccion", cuando="continua", modo="desterrar_cementerio",
                                          zonaActivacion="reserva_oro", objetivo={"quien": "ambos"})])
DESTERRAR = h("desterrar", cuando="al_hacer_dano", opcional=True, cantidad=2,
              objetivo={"quien": "cualquiera", "zona": "cementerio"})


def test_milano_negro_dice_por_que_no_destierra():
    """#1: «no le desterré con Milano Negro»: había un Cinturón de Lady Ann en
    la Reserva (impide desterrar de los Cementerios) y la mesa no lo decía."""
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)), log=True)
    milano = en_defensa(p, 0, aliado("Milano Negro", 2, 2, [DESTERRAR]))
    victima = en_zona(p, 1, aliado("En el Cementerio", 2, 2), Zona.CEMENTERIO)
    en_zona(p, 1, CINTURON, Zona.RESERVA)
    hab.disparar(p, milano, "al_hacer_dano")
    assert victima.zona == Zona.CEMENTERIO
    assert any("✗ Milano Negro: no se puede desterrar del Cementerio: lo impide Cinturón De Lady Ann (J1)" in x
               for x in p.e.log)


def test_sin_restriccion_destierra_y_no_avisa():
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)), log=True)
    milano = en_defensa(p, 0, aliado("Milano Negro", 2, 2, [DESTERRAR]))
    victima = en_zona(p, 1, aliado("En el Cementerio", 2, 2), Zona.CEMENTERIO)
    hab.disparar(p, milano, "al_hacer_dano")
    assert victima.zona == Zona.DESTIERRO and not any("✗" in x for x in p.e.log)
    # Sin cartas en los Cementerios y sin restricción: nada que explicar.
    hab.disparar(p, milano, "al_hacer_dano")
    assert not any("✗" in x for x in p.e.log)


def test_la_mano_inicial_dice_quien_empieza():
    """#0: «no sé si voy primero o no, ¿cómo decidir bien la mano?»"""
    from myl_sim.desafio import HumanoRemoto

    class Mudo(HumanoRemoto):
        def __init__(self):  # sin Firestore: solo captura lo que se pregunta
            self.titulos = []

        def _pedir(self, tipo, opciones, config):
            self.titulos.append(config["titulo"])
            return "quedarse"

    humano = Mudo()
    p = partida(jugadores=(humano, SiempreUsa(2)), inicial=None)
    assert humano.quedarse_mano(p, 0)
    a, b = p.dados[-1]
    esperado = "Empiezas tú" if p.inicial == 0 else "Empieza el rival"
    assert humano.titulos == [f"{esperado} (dado: tú {a}, rival {b}). ¿Te quedas esta mano?"]
