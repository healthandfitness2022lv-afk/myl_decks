"""Reportes de la partida Faraón Djoser vs Sacerdote
(simulations/0VzQQOqN80Uodubbm6H2, seed 14682). Un test por arreglo."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import _bonus_carnada
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import arma, oro
from test_reportes_partida import YO, _activar, _ay, _djoser, _haquika, _kawit, _nuh, _vale


def _abismo():
    return Carta("Abismo", "Abismo", Tipo.TOTEM, 2, 0, "", "x", (
        h("anular", cuando="activada", costo={"destruirEstaCarta": True},
          objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"}),
    ), True)


def _opciones_abismo(p):
    a = en_zona(p, 1, _abismo(), Zona.APOYO)
    return [(a, a.habilidades[0])]


def _lanza_osiris_h():
    return h("restringirCombate", modo="no_puede_atacar", duracion="permanente",
             objetivo={"quien": "oponente", "tipos": ["Aliado"]},
             luego=[{"accion": "restringirCombate", "modo": "no_puede_bloquear", "relacion": "siempre",
                     "objetivo": {"quien": "oponente", "seleccion": "todos", "referencia": "afectadas"}}])


def _guardian():
    return {"featureId": "g", "accion": "guardian", "cuando": "continua"}


# ── #1: Ay no destierra un Aliado para robar si no necesito cartas ───────
def test_ay_no_roba_si_no_hace_falta():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    a = en_defensa(p, 0, _ay())
    en_defensa(p, 0, aliado("Soldado", 1, 1))
    p.j(0).mano.clear()
    p.j(0).oros_virtuales = 3
    assert _vale(p, _activar(a))  # sin mano: sí hace falta
    for c in (aliado("Roxana de Bactria", 2, 2), aliado("Dario III", 3, 4), ORO):
        en_zona(p, 0, c, Zona.MANO)
    assert not _vale(p, _activar(a))  # tengo qué jugar: el destierro sobra


# ── #2: el Abismo no deja pasar a Nuh ni a Haquika ──────────────────────────
def test_abismo_anula_nuh_y_haquika():
    p = partida()
    opciones = _opciones_abismo(p)
    nuh = en_zona(p, 0, _nuh(), Zona.DEFENSA)
    haq = en_zona(p, 0, _haquika(), Zona.DEFENSA)
    while len(p.j(0).mano) < 8:
        en_zona(p, 0, ORO, Zona.MANO)
    assert YO.anular(p, 1, nuh, opciones) == 0
    assert YO.anular(p, 1, haq, opciones) == 0


# ── #10: Kawit se anula si el rival anda corto ──────────────────────────────
def test_abismo_anula_kawit_si_el_rival_anda_corto():
    p = partida()
    opciones = _opciones_abismo(p)
    k = en_zona(p, 0, _kawit(), Zona.DEFENSA)
    p.e.activo = 0
    p.j(0).mano.clear()
    for _ in range(3):
        en_zona(p, 0, ORO, Zona.MANO)
    assert YO.anular(p, 1, k, opciones) == 0  # 3 cartas en mano
    while len(p.j(0).mano) < 5:
        en_zona(p, 0, ORO, Zona.MANO)
    assert YO.anular(p, 1, k, opciones) == 0  # no bajó Oro este turno: no tiene en la mano


# ── #3 / #7 / #12: a quién le pone la Lanza de Osiris ───────────────────────
def test_lanza_de_osiris_a_quien_mas_le_quita():
    p = partida()
    lanza = _lanza_osiris_h()
    ay = en_defensa(p, 1, aliado("Ay", 2, 3, [_guardian()]))
    rox = en_defensa(p, 1, aliado("Roxana de Bactria", 2, 2))
    assert YO.elegir_objetivos(p, 0, [rox, ay], 1, lanza) == [ay]  # #3: Ay es el que bloquea
    rox.estados += [{"modo": "no_puede_atacar", "duracion": "permanente", "turno": 0},
                    {"modo": "no_puede_bloquear", "duracion": "permanente", "turno": 0}]
    assert YO.elegir_objetivos(p, 0, [rox, ay], 1, lanza) == [ay]  # #7: Roxana ya no hace nada
    djoser = en_defensa(p, 1, aliado("Djoser", 3, 3, [h("sinLimiteArmas", cuando="continua")]))
    cleo = en_defensa(p, 1, aliado("Cleopatra VII", 4, 3))
    assert YO.elegir_objetivos(p, 0, [cleo, djoser], 1, lanza) == [djoser]  # #12: pega más con Armas


# ── #4: Akhet al portador (o a Nuh), nunca al Arma sola ─────────────────────
def test_akhet_no_saca_el_arma_sola_y_prefiere_a_nuh():
    lanza = arma("Lanza De Osiris", 3, [h("modificarFuerza", cuando="continua", valor=2,
                                          objetivo={"quien": "esta_carta"})])
    p = partida()
    pili = en_defensa(p, 1, aliado("Pili", 3, 2))
    nuh = en_defensa(p, 1, _nuh())
    en_zona(p, 1, arma("Mandoble De Seth", 3, []), Zona.MAZO)  # Nuh tiene qué traer
    la = p._instancia(lanza, 1, Zona.MANO)
    p.j(1).mano.append(la)
    p.j(1).oros_virtuales = 3
    p.e.activo, p.e.fase = 1, "vigilia"
    p.ejecutar_jugada(1, Jugada("jugar", la, portador=pili))
    mover = h("mover", zonaDestino="mazo_fondo",
              objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"]})
    p.e.activo = 0
    assert YO.elegir_objetivos(p, 0, [la, pili, nuh], 1, mover) == [nuh]
    assert YO.elegir_objetivos(p, 0, [la, pili], 1, mover) == [pili]


# ── #5: Piedra Roseta no baraja Quemar los Templos con Abismo y Akhet a tiro ─
def test_quemar_los_templos_vale_si_hay_totems_rivales():
    quemar = talisman("Quemar los Templos", 4, [h("desterrar", objetivo={
        "quien": "cualquiera", "zona": "en_juego", "tipos": ["Arma", "Tótem"]})])
    p = partida()
    q = en_zona(p, 1, quemar, Zona.MANO)
    p.j(1).oros_virtuales = 5
    sin = YO._valor_descarte(p, 1, q)
    en_zona(p, 0, _abismo(), Zona.APOYO)
    assert YO._valor_descarte(p, 1, q) > sin


# ── #6: con el Abismo rival en la mesa, primero un Aliado barato ────────────
def test_carnada_contra_abismo():
    p = partida()
    barato = en_zona(p, 0, aliado("Werin", 2, 2), Zona.MANO)
    assert _bonus_carnada(p, 0, Jugada("jugar", barato)) == 0
    en_zona(p, 1, _abismo(), Zona.APOYO)
    assert _bonus_carnada(p, 0, Jugada("jugar", barato)) > 0
    nuh = en_zona(p, 0, _nuh(), Zona.MANO)
    assert _bonus_carnada(p, 0, Jugada("jugar", nuh)) == 0  # Nuh lo anularía igual


# ── #8: no manda a Nuh contra Ay con el Escudo Miliciano en su Cementerio ───
def test_ataque_con_todos_mira_el_escudo_del_cementerio():
    escudo = arma("Escudo Miliciano", 3, [
        h("modificarFuerza", cuando="continua", valor=3, objetivo={"quien": "esta_carta"}),
        h("jugarDesde", cuando="activada", fase="declaracion_ataque", modo="sin_pagar", costo={"oros": 2},
          zonaActivacion="cementerio", objetivo={"quien": "esta_carta"}),
    ])
    p = partida()
    kawit = en_defensa(p, 1, aliado("Kawit", 2, 2))
    pili = en_defensa(p, 1, aliado("Pili", 3, 2))
    nuh = en_defensa(p, 1, aliado("Nuh", 3, 4, [h("jugarDesde", cuando="activada", fase="vigilia",
                                                   objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Arma"]})]))
    en_defensa(p, 0, aliado("Ay", 2, 3, [_guardian()]))
    en_zona(p, 0, escudo, Zona.CEMENTERIO)
    p.j(0).oros_virtuales = 2
    atacan = YO.elegir_atacantes(p, 1, [kawit, pili, nuh])
    assert nuh not in atacan


# ── #9: Jeroglíficos no sube a un atacante de 4 con el castillo sano ────────
def test_jeroglificos_no_se_gasta_en_un_golpe_de_4():
    jero = oro("Jeroglificos", [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                  objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, jero, Zona.RESERVA)
    nuh = en_defensa(p, 1, aliado("Nuh", 3, 4))
    p.atacantes, p.bloqueos = [nuh], {}
    assert len(p.j(0).mazo) > 20
    assert not _vale(p, _activar(j))


# ── #3: qué Arma trae Nuh ───────────────────────────────────────────────────
def test_nuh_trae_mandoble_o_escudo_segun_el_castillo():
    mandoble = arma("Mandoble De Seth", 3, [h("botar", cuando="al_atacar", cantidad=3, objetivo={"quien": "oponente"})])
    escudo = arma("Escudo Celestial", 3, [h("barajar", cuando="al_hacer_dano", cantidad=2,
                                            objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    m = en_zona(p, 0, mandoble, Zona.MAZO)
    e = en_zona(p, 0, escudo, Zona.MAZO)
    jugar = h("jugarDesde", modo="sin_pagar", objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Arma"]})
    assert YO.elegir_objetivos(p, 0, [e, m], 1, jugar) == [m]
    del p.j(0).mazo[10:]
    if m not in p.j(0).mazo:
        p.j(0).mazo += [m, e]
    assert YO.elegir_objetivos(p, 0, [e, m], 1, jugar) == [e]


# ── #15: por ganar, Djoser destruye a un bloqueador ─────────────────────────
def test_djoser_saca_un_bloqueador_si_esta_por_ganar():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    d = en_defensa(p, 0, _djoser())
    d.mods  # noqa: B018
    en_defensa(p, 0, aliado("Dario III", 3, 4))
    atacante = en_zona(p, 1, aliado("Kawit con Lanza", 2, 4), Zona.ATAQUE)
    bloq = en_defensa(p, 1, aliado("Nuh", 3, 2))
    del p.j(1).mazo[5:]
    destruir = d.habilidades[0]
    assert YO.elegir_objetivos(p, 0, [atacante, bloq], 1, destruir) == [bloq]


# ── #11: el Escudo Miliciano va a Djoser y antes que otro Ay ────────────────
def test_escudo_en_djoser_antes_que_ay():
    from myl_sim.jugadores import _bono_por_arma

    djoser = aliado("Djoser", 3, 3, [h("modificarFuerza", cuando="continua", valor=2, valorPorCada="arma_portada",
                                       objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    d = en_defensa(p, 0, djoser)
    dario = en_defensa(p, 0, aliado("Dario III", 3, 4))
    escudo = en_zona(p, 0, arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                                           objetivo={"quien": "esta_carta"})]), Zona.MANO)
    assert _bono_por_arma(d) == 2
    assert _vale(p, Jugada("jugar", escudo, portador=d))
    assert not _vale(p, Jugada("jugar", escudo, portador=dario))


# ── #14: Dario III (Furia e Imbloqueable) cuenta como daño seguro al rematar ─
def test_remate_cuenta_al_aliado_imbloqueable_con_furia():
    from myl_sim.jugadores import _remate

    dario = aliado("Dario III", 3, 4, [{"featureId": "f", "accion": "furia", "cuando": "continua"},
                                       {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    d = en_zona(p, 0, dario, Zona.MANO)
    p.j(0).oros_virtuales = 3
    del p.j(1).mazo[4:]
    j = Jugada("jugar", d)
    assert _remate(p, 0, [j, Jugada("pasar", None)]) == j


# ── Akhet es situacional: la Haquika que me controla un Aliado importante ──
def test_akhet_prefiere_la_haquika_que_me_roba_un_aliado():
    from test_reportes_partida import _haquika_con

    mover = h("mover", zonaDestino="mazo_fondo",
              objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"]})
    p = partida()
    nuh = en_defensa(p, 1, _nuh())
    en_zona(p, 1, arma("Mandoble De Seth", 3, []), Zona.MAZO)
    ramses = en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    haq = _haquika_con(p, ramses)
    assert YO.elegir_objetivos(p, 0, [nuh, haq], 1, mover) == [haq]
