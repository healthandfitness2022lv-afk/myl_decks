"""Funciones nuevas para programar los mazos Druida y Héroe (tanda A)."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Tipo, Zona

from test_acciones_v3b import en_zona
from test_motor import AtacaTodo, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import jugar, oro


def _druida(nombre="Tadg el Druida", fuerza=2):
    return aliado(nombre, 2, fuerza, raza="Defensor")


# ── Arquetipo: "Aliado Druida" va en el nombre, no en la raza ───────────────
def test_arquetipo_por_nombre():
    p = partida()
    d = en_defensa(p, 0, _druida())
    otro = en_defensa(p, 0, aliado("Pwyll", 3, 2, raza="Defensor"))
    assert hab.coincide(p, d, {"arquetipo": "Druida"}) and not hab.coincide(p, otro, {"arquetipo": "Druida"})
    assert hab.condicion_ok(p, 0, {"condicion": {"tipo": "aliados_arquetipo", "op": ">=", "valor": 1, "arquetipo": "Druida"}})


def test_condiciones_nuevas():
    p = partida()
    en_defensa(p, 0, aliado("A", 2, 2, raza="Héroe"))
    en_defensa(p, 0, aliado("B", 2, 2, raza="Héroe"))
    en_defensa(p, 1, aliado("C", 2, 2))
    ok = lambda c: hab.condicion_ok(p, 0, {"condicion": c})  # noqa: E731
    assert ok({"tipo": "aliados_no_raza", "op": "==", "valor": 0, "raza": "Héroe"})  # todos Héroe
    assert ok({"tipo": "aliados_misma_raza", "op": ">=", "valor": 2})
    assert not ok({"tipo": "aliados_vs_oponente", "op": "<", "valor": 0})  # 2 contra 1
    en_zona(p, 0, _druida(), Zona.MANO)
    assert ok({"tipo": "mano_arquetipo", "op": ">=", "valor": 1, "arquetipo": "Druida"})
    en_zona(p, 0, aliado("Faraón en mano", 2, 2, raza="Faraón"), Zona.MANO)
    assert ok({"tipo": "mano_raza", "op": ">=", "valor": 1, "raza": "Faraón"})
    en_defensa(p, 0, aliado("Ajeno", 2, 2, raza="Defensor"))
    assert not ok({"tipo": "aliados_no_raza", "op": "==", "valor": 0, "raza": "Héroe"})


# ── "Tus demás Aliados" / "que no sea Amergin" ──────────────────────────────
def test_excluir_esta_carta():
    julio = aliado("Julio Cesar", 4, 2, [
        h("modificarFuerza", cuando="continua", valor=1, objetivo={"quien": "propio", "tipos": ["Aliado"],
                                                                     "seleccion": "todos", "excluirEstaCarta": True}),
        h("otorgarPropiedad", cuando="continua", modo="imbloqueable",
          objetivo={"quien": "propio", "tipos": ["Aliado"], "seleccion": "todos", "excluirEstaCarta": True}),
    ])
    p = partida()
    j = en_defensa(p, 0, julio)
    otro = en_defensa(p, 0, aliado("Otro", 2, 2))
    assert hab.fuerza(p, otro) == 3 and hab.fuerza(p, j) == 2
    assert hab.tiene_prop(p, otro, "imbloqueable") and not hab.tiene_prop(p, j, "imbloqueable")


def test_mayor_fuerza():
    p = partida()
    f = en_defensa(p, 0, aliado("Fergus", 2, 1))
    en_defensa(p, 1, aliado("Chico", 2, 2))
    grande = en_defensa(p, 1, aliado("Grande", 2, 5))
    hh = h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "seleccion": "mayor_fuerza"})
    assert hab.candidatos_validos(p, 0, f, hh) == [grande]


def test_coste_segun_aliados_de_una_raza():
    p = partida()
    g = en_defensa(p, 0, aliado("Ganimedes", 2, 2, raza="Héroe"))
    en_defensa(p, 0, aliado("Héroe 2", 2, 2, raza="Héroe"))
    barato = en_defensa(p, 1, aliado("Barato", 2, 2))
    caro = en_defensa(p, 1, aliado("Caro", 3, 2))
    hh = h("destruir", objetivo={"quien": "oponente", "coste": {"op": "<=", "segun": "aliados_raza", "raza": "Héroe"}})
    assert hab.candidatos_validos(p, 0, g, hh) == [barato]  # 2 Héroes → coste ≤ 2
    assert caro.en_juego


def test_restriccion_de_desterrar_solo_oros():
    carmix = oro("Carmix", [h("restriccion", cuando="continua", modo="desterrar",
                              zonaActivacion="reserva_oro", objetivo={"quien": "ambos", "tipos": ["Oro"]})])
    p = partida()
    en_zona(p, 0, carmix, Zona.RESERVA)
    o = en_zona(p, 1, oro("Oro rival", []), Zona.RESERVA)
    a = en_defensa(p, 1, aliado("Aliado rival", 2, 2))
    f = en_defensa(p, 0, aliado("Fuente", 2, 2))
    hh = h("desterrar", objetivo={"quien": "oponente", "zona": "en_juego"})
    cands = hab.candidatos_validos(p, 0, f, hh)
    assert a in cands and o not in cands


def test_por_cada_aliado_de_un_arquetipo():
    maldito = aliado("Druida Maldito", 3, 3, [h(
        "modificarFuerza", valor=-1, valorPorCada="aliado_arquetipo", porCadaArquetipo="Druida",
        duracion="permanente", objetivo={"quien": "oponente", "tipos": ["Aliado"], "seleccion": "todos"})],
        raza="Defensor")
    p = partida()
    en_defensa(p, 0, _druida())
    rival = en_defensa(p, 1, aliado("Rival", 2, 5))
    jugar(p, 0, maldito)
    assert hab.fuerza(p, rival) == 3  # dos Druidas (Tadg y el Maldito)


# ── Costos nuevos ───────────────────────────────────────────────────────────
def test_costo_barajar_esta_carta_y_mover_a_ataque():
    p = partida()
    trono = en_zona(p, 0, oro("Trono Dorado", []), Zona.RESERVA)
    hh = h("robar", cuando="activada", costo={"barajarEstaCarta": True})
    mazo = len(p.j(0).mazo)
    assert hab.pagar_costo(p, 0, trono, hh) and trono.zona == Zona.MAZO and len(p.j(0).mazo) == mazo + 1
    achall = en_defensa(p, 0, aliado("Achall", 2, 2))
    hm = h("robar", cuando="activada", costo={"moverEstaCartaAtaque": True})
    assert hab.pagar_costo(p, 0, achall, hm) and achall.zona == Zona.ATAQUE
    assert not hab.puede_pagar_costo(p, 0, achall, hm)  # ya no está en Defensa


def test_costo_oros_segun_coste_del_objetivo():
    p = partida()
    f = en_zona(p, 0, oro("Ceangal An Fhanaigh", []), Zona.RESERVA)
    p.j(0).oros_virtuales = 3 - p.j(0).oro_disponible  # 3 Oros en total
    caro = en_defensa(p, 1, aliado("Caro", 5, 2))
    barato = en_defensa(p, 1, aliado("Barato", 3, 2))
    hh = h("destruir", costo={"orosSegun": "coste_objetivo"}, objetivo={"quien": "oponente", "tipos": ["Aliado"]})
    assert hab.candidatos_validos(p, 0, f, hh) == [barato]
    hab.resolver(p, 0, f, hh)
    assert not barato.en_juego and caro.en_juego and p.j(0).oro_disponible == 0


def test_limite_compartido_entre_habilidades():
    p = partida()
    c = en_defensa(p, 0, aliado("Cathbadh", 2, 4))
    mas = h("modificarFuerza", cuando="activada", limitePorTurno=1, grupoLimite="cathbadh")
    menos = h("modificarFuerza", cuando="activada", limitePorTurno=1, grupoLimite="cathbadh")
    hab.sumar_uso(p, 0, c, mas, 0)
    assert hab.usos(p, 0, c, menos, 1) == 1  # ya usó la otra


def test_condicion_esta_carta_ataco():
    p = partida()
    dario = en_defensa(p, 0, aliado("Dario III", 3, 4))
    p.ctx_fuente_habilidad = dario
    assert not hab.condicion_ok(p, 0, {"condicion": {"tipo": "esta_carta_ataco"}})
    p.ataco_este_turno.add(dario.uid)
    assert hab.condicion_ok(p, 0, {"condicion": {"tipo": "esta_carta_ataco"}})


def test_mostrar_carta_de_la_mano_con_filtro_generico():
    p = partida()
    fuente = en_defensa(p, 0, aliado("Roxana", 2, 2))
    faraon = en_zona(p, 0, aliado("Ay", 2, 3, raza="Faraón"), Zona.MANO)
    en_zona(p, 0, aliado("Ajeno", 2, 2, raza="Guerrero"), Zona.MANO)
    hh = h("mostrar", objetivo={"quien": "propio", "zona": "mano", "tipos": ["Aliado"], "raza": "Faraón"})
    hab.resolver(p, 0, fuente, hh)
    assert getattr(faraon, "revelada", False) and faraon.zona == Zona.MANO


# ── "Luego": si no se cumplió / si la afectada es Druida ───────────────────
def test_luego_si_afectada_cumple_y_si_no_se_cumplio():
    p = partida()
    f = en_defensa(p, 0, aliado("Druida Sanador", 3, 2, raza="Defensor"))
    d = en_zona(p, 0, _druida(), Zona.CEMENTERIO)
    for _ in range(2):
        en_zona(p, 0, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    hh = h("buscar", zonaDestino="mano", objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"],
                                                    "arquetipo": "Druida"},
           luego=[{"accion": "barajar", "relacion": "si_afectada_cumple", "filtroAfectada": {"arquetipo": "Druida"},
                   "cantidad": 2, "objetivo": {"quien": "propio", "zona": "cementerio"}}])
    cem = len(p.j(0).cementerio)
    hab.resolver(p, 0, f, hh)
    assert d.zona == Zona.MANO and len(p.j(0).cementerio) == cem - 3
    # Si no se cumplió: Idmon manda al Cementerio lo que no es Héroe.
    hn = h("buscar", zonaDestino="mano", objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"],
                                                    "raza": "Nada"},
           luego=[{"accion": "robar", "relacion": "si_no_se_cumplio", "cantidad": 1, "objetivo": {"quien": "propio"}}])
    mano = len(p.j(0).mano)
    hab.resolver(p, 0, f, hn)
    assert len(p.j(0).mano) == mano + 1


# ── Berserk: no puede atacar en tu próximo turno ────────────────────────────
def test_duracion_proximo_turno():
    p = partida()
    afectado = en_defensa(p, 0, aliado("Berserker", 2, 2))
    hh = h("restringirCombate", modo="no_puede_atacar", duracion="proximo_turno",
           objetivo={"quien": "esta_carta"})
    p.e.turno = 5
    hab.resolver(p, 0, afectado, hh)
    assert not hab.tiene_estado(p, afectado, "no_puede_atacar")  # este turno ataca
    p.e.turno = 7
    assert hab.tiene_estado(p, afectado, "no_puede_atacar")  # su próximo turno no
    hab.expirar(p, "hasta_fase_final")
    assert not hab.tiene_estado(p, afectado, "no_puede_atacar")


def test_gaitas_agrupa_este_oro():
    p = partida()
    g = en_zona(p, 0, oro("Gaitas", []), Zona.PAGADO)
    hab.resolver(p, 0, g, h("agrupar", objetivo={"quien": "esta_carta"}))
    assert g.zona == Zona.RESERVA


def test_pwyll_impide_declarar_ataque():
    pwyll = aliado("Pwyll", 3, 2, [h("restriccion", cuando="continua", modo="declarar_ataque",
                                     objetivo={"quien": "ambos"})])
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    p.e.activo = 0
    a = en_defensa(p, 0, aliado("A", 2, 5))
    a.listo = True
    en_defensa(p, 1, pwyll)
    m = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == m and a.zona == Zona.DEFENSA


def test_coliseo_roba_por_cada_atacante():
    from myl_sim.modelo import Carta
    c = Carta("Coliseo", "Coliseo", Tipo.TOTEM, 3, 0, "", "", (h("robar", cuando="propio_ataca",
                                                                  cantidadSegun="num_atacantes", objetivo={"quien": "propio"}),), True)
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    p.e.activo = 0
    for k in range(2):
        a = en_defensa(p, 0, aliado(f"A{k}", 2, 2))
        a.listo = True
    en_zona(p, 0, c, Zona.APOYO)
    mano = len(p.j(0).mano)
    p._batalla(0)
    assert len(p.j(0).mano) == mano + 2


def test_orfeo_nombra_al_activar():
    class Nombra(Heuristico):
        def elegir_carta(self, p, yo, nombres):
            return "Objetivo"

    orfeo = aliado("Orfeo", 3, 3, [h("desterrar", cuando="activada", limitePorTurno=1,
                                     objetivo={"quien": "oponente", "zona": "mazo", "nombrarCarta": True})])
    p = partida(jugadores=(Nombra(1), Heuristico(2)))
    o = en_defensa(p, 0, orfeo)
    blanco = en_zona(p, 1, aliado("Objetivo", 2, 2), Zona.MAZO)
    hab._intentar(p, 0, o, o.habilidades[0])
    assert blanco.zona == Zona.DESTIERRO


# ── Berserk duplica la fuerza con todas las bonificaciones (combo de 48) ────
def test_berserk_duplica_con_bonificaciones():
    from myl_sim.modelo import Carta
    p = partida()
    p.e.turno = 3
    tadg = en_defensa(p, 0, aliado("Tadg el Druida", 2, 4, raza="Defensor"))
    carro = Carta("Carro Celta", "Carro Celta", Tipo.ARMA, 0, 0, "", "", (
        h("modificarFuerza", cuando="continua", valor=4, objetivo={"quien": "esta_carta"}),), True)
    from myl_sim.motor import Jugada
    p.ejecutar_jugada(0, Jugada("jugar_gratis", en_zona(p, 0, carro, Zona.MANO), portador=tadg))
    cloch = h("modificarFuerza", valor=2, duracion="permanente", objetivo={"quien": "esta_carta"})
    berserk = h("modificarFuerza", modoFuerza="duplicar", duracion="hasta_fase_final", objetivo={"quien": "esta_carta"})
    for x in (cloch, cloch, berserk, berserk):
        hab.resolver(p, 0, tadg, x)
    assert hab.fuerza(p, tadg) == 48  # (4 + 4 + 2 + 2) × 2 × 2


# ══ Tanda B: mirar y repartir, cambiar raza, Oro que se vuelve Aliado ═══════
def _mazo_tope(p, cartas):
    """Pone estas cartas arriba del Mazo del jugador 0, en este orden."""
    inst = [en_zona(p, 0, c, Zona.MAZO) for c in cartas]
    for x in inst:
        p.j(0).mazo.remove(x)
    p.j(0).mazo[:0] = inst
    return inst


def test_tadg_toma_oro_o_druida_y_el_resto_al_fondo():
    p = partida()
    f = en_defensa(p, 0, _druida())
    talis, oro_c, druida, otro = _mazo_tope(p, [talisman("T", 2, []), oro("Oro bueno", [h("robar", cuando="activada")]),
                                                  _druida("Druida Sanador", 2), aliado("Guerrero", 3, 3)])
    hh = h("mirarTope", cantidad=4, valor=1, zonaDestino="mano", restoA="mazo_fondo",
           objetivo={"quien": "propio", "tipos": ["Oro", "Aliado"], "arquetipo": "Druida", "filtroSoloAliados": True})
    hab.resolver(p, 0, f, hh)
    tomada = [x for x in (oro_c, druida) if x.zona == Zona.MANO]
    assert len(tomada) == 1 and otro.zona == Zona.MAZO and talis.zona == Zona.MAZO
    assert p.j(0).mazo[-3:] == [x for x in (talis, oro_c, druida, otro) if x not in tomada]


def test_la_odisea_reparte_mano_cementerio_destierro():
    p = partida()
    f = en_zona(p, 0, oro("La Odisea", []), Zona.RESERVA)
    a, b, c = _mazo_tope(p, [aliado("Grande", 5, 5), aliado("Medio", 3, 3), aliado("Chico", 1, 1)])
    hab.resolver(p, 0, f, h("mirarTope", cantidad=3, repartir=["mano", "cementerio", "destierro"]))
    assert a.zona == Zona.MANO and b.zona == Zona.CEMENTERIO and c.zona == Zona.DESTIERRO


def test_pegaso_deja_arriba_o_abajo():
    p = partida()
    f = en_zona(p, 0, talisman("Nacimiento De Pegaso", 1, []), Zona.MANO)
    malas = _mazo_tope(p, [oro("Oro 1", []), oro("Oro 2", [])])
    hab.resolver(p, 0, f, h("mirarTope", cantidad=2, valor=0, restoA="elegir_tope_fondo"))
    assert p.j(0).mazo[-2:] == malas  # cartas flojas: al fondo


def test_idmon_juega_un_heroe_o_lo_manda_al_cementerio():
    p = partida()
    p.j(0).oros_virtuales = 5
    f = en_defensa(p, 0, aliado("Idmon el Adivino", 3, 1, raza="Héroe"))
    hh = h("mirarTope", cantidad=1, valor=1, zonaDestino="en_juego", restoA="cementerio",
           objetivo={"quien": "propio", "tipos": ["Aliado"], "raza": "Héroe"})
    (heroe,) = _mazo_tope(p, [aliado("Héroe", 3, 3, raza="Héroe")])
    hab.resolver(p, 0, f, hh)
    assert heroe.en_juego
    (otro,) = _mazo_tope(p, [aliado("Otro", 3, 3, raza="Bestia")])
    hab.resolver(p, 0, f, hh)
    assert otro.zona == Zona.CEMENTERIO


def test_alejandro_cambia_la_raza_del_robado():
    p = partida()
    f = en_defensa(p, 0, aliado("Alejandro Magno", 4, 3, raza="Héroe"))
    rival = en_defensa(p, 1, aliado("Rival", 3, 3, raza="Bestia"))
    hh = h("ganarControl", duracion="permanente", objetivo={"quien": "oponente", "tipos": ["Aliado"]},
           luego=[{"accion": "cambiarRaza", "razaNueva": "Héroe", "relacion": "si_se_cumplio",
                   "objetivo": {"quien": "propio", "seleccion": "todos", "referencia": "afectadas"}}])
    hab.resolver(p, 0, f, hh)
    assert rival.controlador == 0 and rival.raza == "Héroe"
    assert hab.condicion_ok(p, 0, {"condicion": {"tipo": "aliados_raza", "op": ">=", "valor": 2, "raza": "Héroe"}})


def test_ave_de_hera_se_vuelve_aliado_hasta_la_fase_final():
    p = partida()
    ave = en_zona(p, 0, oro("Ave de Hera", []), Zona.RESERVA)
    hab.resolver(p, 0, ave, h("convertirEnAliado", valor=3, duracion="hasta_fase_final"))
    assert ave.tipo == Tipo.ALIADO and ave in p.j(0).aliados and hab.fuerza(p, ave) == 3 and ave.listo
    hab.expirar(p, "hasta_fase_final")
    assert ave.tipo == Tipo.ORO and ave.zona == Zona.RESERVA
