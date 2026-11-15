"""Funciones del lote 2 de programación (mazos restantes) y Vínculo del Aullido."""

from myl_sim import habilidades as hab
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, h, partida, talisman
from test_notas_cartas import oro
from test_reportes_partida import YO


def _vinculo():
    return oro("Vinculo del Aullido", [h("robar", opcional=True, cantidad=2, costo={"pagarEstaCarta": True, "oros": 1},
                                         objetivo={"quien": "propio"},
                                         luego=[{"accion": "descartar", "relacion": "si_se_cumplio", "cantidad": 1,
                                                 "objetivo": {"quien": "propio"}}])])


def test_vinculo_se_juega_y_activa_en_el_turno_1():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).mano.clear()
    v = en_zona(p, 0, _vinculo(), Zona.MANO)
    en_zona(p, 0, oro("Corona", [h("robar", cuando="activada", objetivo={"quien": "propio"})]), Zona.MANO)
    for i in range(6):
        en_zona(p, 0, aliado(f"A{i}", 2, 2), Zona.MANO)
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert elegida.tipo == "oro" and elegida.carta is v
    assert YO.usar_opcional(p, 0, v, v.habilidades[0])


def test_voluntad_de_caballero_mira_en_la_fase_final_si_peleo():
    voluntad = talisman("Voluntad", 1, [h("modificarFuerza", valor=3, duracion="hasta_fase_final",
                                          objetivo={"quien": "propio", "tipos": ["Aliado"]},
                                          luego=[{"accion": "modificarFuerza", "relacion": "si_afectada_cumple",
                                                  "filtroAfectada": {"combate": True}, "momento": "fase_final",
                                                  "valor": 1, "duracion": "permanente",
                                                  "objetivo": {"quien": "propio", "seleccion": "todos",
                                                               "referencia": "afectadas"}}])])
    p = partida()
    a = en_defensa(p, 0, aliado("Caballero", 2, 2))
    t = p._instancia(voluntad, 0, Zona.MANO)
    hab.resolver(p, 0, t, t.habilidades[0])
    assert hab.fuerza(p, a) == 5 and p.pendientes_final
    p.ataco_este_turno.add(a.uid)
    hab.expirar(p, "hasta_fase_final")
    hab.resolver_pendientes_final(p)
    assert hab.fuerza(p, a) == 3  # 2 + 1 permanente
    b = en_defensa(p, 0, aliado("Quieto", 2, 2))
    hab.resolver(p, 0, t, {**t.habilidades[0], "objetivo": {"quien": "propio", "tipos": ["Aliado"], "seleccion": "todos"}})
    hab.expirar(p, "hasta_fase_final")
    p.ataco_este_turno.clear()
    hab.resolver_pendientes_final(p)
    assert hab.fuerza(p, b) == 2  # no peleó: no gana nada


def test_apophis_no_reacciona_a_oros():
    apophis = aliado("Apophis", 5, 4, [h("botar", cuando="oponente_juega", cantidad=3, objetivo={"quien": "oponente"},
                                         disparoTipos=["Aliado", "Arma", "Tótem", "Talismán"])])
    p = partida()
    en_defensa(p, 0, apophis)
    antes = len(p.j(1).mazo)
    o = en_zona(p, 1, oro("Oro", []), Zona.RESERVA)
    hab._reacciones_oponente(p, o)
    assert len(p.j(1).mazo) == antes
    a = en_defensa(p, 1, aliado("Soldado", 1, 1))
    hab._reacciones_oponente(p, a)
    assert antes - len(p.j(1).mazo) == 3


def test_flidais_cancela_desde_la_mesa():
    flidais = aliado("Flidais", 2, 3, [h("cancelarHabilidad", cuando="activada", costo={"barajarEstaCarta": True},
                                         objetivo={"quien": "oponente", "tipos": ["Aliado", "Arma", "Tótem"]})])
    djoser = aliado("Djoser", 3, 3, [h("destruir", cuando="propia_entra", disparoTipos=["Arma"],
                                       objetivo={"quien": "oponente", "tipos": ["Aliado"]})])
    p = partida()
    d = en_defensa(p, 0, djoser)
    f = en_defensa(p, 1, flidais)
    mio = en_defensa(p, 1, aliado("Valioso", 4, 4))
    hab._intentar(p, 0, d, d.habilidades[0])
    assert mio.en_juego and f.zona == Zona.MAZO
