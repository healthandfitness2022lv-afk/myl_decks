"""Reportes de la partida Titán Minotauro vs Djoser - Guerrero
(simulations/ZiXUJSPxFyUWhz55ArRq, seed 11465). Un test por arreglo."""

from myl_sim import habilidades as hab
from myl_sim.modelo import Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, h, partida, talisman
from test_reportes_partida import YO


def _siete():
    return talisman("Siete contra Tebas", 2, [h(
        "cancelarHabilidad", cuando="habilidad_oponente",
        objetivo={"quien": "oponente", "tipos": ["Aliado", "Arma", "Tótem"]},
        luego=[{"accion": "robar", "relacion": "siempre", "cantidad": 1, "objetivo": {"quien": "propio"}}],
    )])


# ── #2: Siete contra Tebas cancela la habilidad que se dispara ──────────────
def test_siete_contra_tebas_cancela_el_destruir_de_djoser():
    djoser = aliado("Djoser", 3, 3, [h("destruir", cuando="propia_entra", disparoTipos=["Arma"],
                                       objetivo={"quien": "oponente", "tipos": ["Aliado"]})])
    p = partida()
    d = en_defensa(p, 0, djoser)
    mio = en_defensa(p, 1, aliado("Minotauro de Cartago", 3, 3))
    s = en_zona(p, 1, _siete(), Zona.MANO)
    p.j(1).oros_virtuales = 2
    mano = len(p.j(1).mano)
    hab._intentar(p, 0, d, d.habilidades[0])
    assert mio.en_juego  # no se resolvió
    assert s.zona == Zona.CEMENTERIO and len(p.j(1).mano) == mano  # jugó el Talismán y robó 1
    assert d.sin_habilidad_hasta is None  # Djoser conserva su habilidad


def test_siete_contra_tebas_no_se_juega_en_la_vigilia():
    p = partida()
    s = en_zona(p, 1, _siete(), Zona.MANO)
    assert not hab.talisman_jugable(p, 1, s, "vigilia")


# ── #3: Kamose no se previene a sí mismo ───────────────────────────────────
def test_kamose_no_se_previene_a_si_mismo():
    kamose = aliado("Kamose el Guerrero", 2, 3, [h(
        "prevenir", cuando="al_salir_del_juego", modo="destruir_desterrar", opcional=True,
        costo={"barajarEstaCarta": True},
        objetivo={"quien": "propio", "tipos": ["Aliado"], "arquetipo": "Guerrero", "excluirEstaCarta": True})])
    p = partida()
    k = en_defensa(p, 0, kamose)
    otro = en_defensa(p, 0, aliado("Guerrero Bereber", 2, 2))
    assert not hab.prevenir(p, k, combate=True)
    assert k.en_juego
    from test_tanda_guerrero_dragon_titan import SiempreUsa
    p2 = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))
    k2 = en_defensa(p2, 0, kamose)
    b2 = en_defensa(p2, 0, aliado("Guerrero Bereber", 2, 2))
    assert hab.prevenir(p2, b2, combate=True) and k2.zona == Zona.MAZO  # sí salva a otro Guerrero
    assert otro.en_juego


# ── #1: el único bloqueador que gana se queda defendiendo ──────────────────
def test_ultimo_defensor_no_ataca():
    p = partida()
    bereber = en_defensa(p, 0, aliado("Guerrero Bereber", 2, 5))
    for n, f in (("Minotauro de Cartago", 3), ("Minotauro de Creta", 2), ("Temis", 2)):
        en_defensa(p, 1, aliado(n, 2, f))
    assert bereber not in YO.elegir_atacantes(p, 0, [bereber])
    en_defensa(p, 0, aliado("Guerrero Medjay", 2, 3))
    assert not __import__("myl_sim.jugadores", fromlist=["x"])._ultimo_defensor(p, 0, bereber)  # ya no es el único
