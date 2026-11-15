"""Reglas compartidas por cartas que estaban pendientes de programación."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Jugada, Partida


ORO = Carta("oro", "Oro", Tipo.ORO, 0, 0, "", "")
ALIADO = Carta("aliado", "Aliado", Tipo.ALIADO, 0, 1, "", "")


def partida():
    return Partida(([ORO] * 20 + [ALIADO] * 30, [ORO] * 20 + [ALIADO] * 30),
                   (Heuristico(1), Heuristico(2)), seed=7)


def poner(p, carta, jugador, zona):
    inst = p._instancia(carta, jugador, Zona.MAZO)
    p.j(jugador).mazo.append(inst)
    p._mover(inst, zona)
    return inst


def test_desterrar_tope_como_costo_exige_cantidad_exacta():
    h = {"cuando": "activada", "costo": {"desterrarTopeMazo": 2},
         "accion": "buscar", "objetivo": {"quien": "propio", "zona": "cementerio"}}
    p = partida()
    fuente = poner(p, Carta("nido", "Nido", Tipo.TOTEM, 0, 0, "", "", (h,), True), 0, Zona.APOYO)
    p.j(0).mazo = p.j(0).mazo[:1]
    assert not hab.puede_pagar_costo(p, 0, fuente, h)
    assert not hab.pagar_costo(p, 0, fuente, h)
    assert not p.j(0).destierro
    p.j(0).mazo.append(p._instancia(ORO, 0, Zona.MAZO))
    p.j(0).mazo.append(p._instancia(ORO, 0, Zona.MAZO))
    primeras = list(p.j(0).mazo[:2])
    assert hab.pagar_costo(p, 0, fuente, h)
    assert p.j(0).destierro == primeras


def test_solo_una_copia_en_juego_tambien_rige_para_totem():
    p = partida()
    carta = Carta("sidhe", "Tótem Sidhe", Tipo.TOTEM, 0, 0, "",
                  "Sólo puedes tener un Tótem Sidhe en juego.", (), True)
    poner(p, carta, 0, Zona.APOYO)
    copia = poner(p, carta, 0, Zona.MANO)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not hab.requisito_para_jugar(p, 0, copia)
    assert not any(j.carta is copia for j in p.jugadas_legales(0, "vigilia"))


def test_permiso_de_templo_juega_aliado_del_cementerio_pagando():
    p = partida()
    h = {"cuando": "activada", "fase": "vigilia", "accion": "jugarDesde",
         "modo": "pagando", "objetivo": {"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"]}}
    fuente = poner(p, Carta("templo", "Templo Sombrío", Tipo.TOTEM, 0, 0, "", "", (h,), True),
                   0, Zona.APOYO)
    aliado = poner(p, ALIADO, 0, Zona.CEMENTERIO)
    p.e.activo, p.e.fase = 0, "vigilia"
    hab.resolver(p, 0, fuente, h)
    assert aliado.zona == Zona.DEFENSA


def test_condicion_controla_nombre_consulta_la_mesa_actual():
    p = partida()
    h = {"condicion": {"tipo": "controla_nombre", "nombre": "Cuchulain"}}
    assert not hab.condicion_ok(p, 0, h)
    aliado = poner(p, Carta("cu", "Cuchulain", Tipo.ALIADO, 1, 2, "", ""), 0, Zona.DEFENSA)
    assert hab.condicion_ok(p, 0, h)
    assert not hab.condicion_ok(p, 1, h)
    p._mover(aliado, Zona.CEMENTERIO)
    assert not hab.condicion_ok(p, 0, h)


def test_permiso_desde_cementerio_respeta_carta_requerida():
    p = partida()
    h = {"cuando": "al_jugar", "accion": "jugarDesde", "modo": "pagando",
         "objetivo": {"quien": "esta_carta", "zona": "cementerio"},
         "condicion": {"tipo": "controla_nombre", "nombre": "Cuchulain"}}
    arma = Carta("espada", "Espada", Tipo.ARMA, 0, 0, "", "", (h,), True)
    poner(p, arma, 0, Zona.CEMENTERIO)
    poner(p, ALIADO, 0, Zona.DEFENSA)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not hab.jugadas_desde_otra_zona(p, 0)
    poner(p, Carta("cu", "Cuchulain", Tipo.ALIADO, 0, 2, "", ""), 0, Zona.DEFENSA)
    assert len(hab.jugadas_desde_otra_zona(p, 0)) == 2  # un portador válido por cada Aliado


def test_tomar_fondo_pone_las_dos_ultimas_en_mano():
    p = partida()
    fuente = poner(p, Carta("templo", "Templo", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.APOYO)
    ultimas = list(p.j(0).mazo[-2:])
    hab.resolver(p, 0, fuente, {"accion": "tomarFondo", "cantidad": 2})
    assert p.j(0).mano[-2:] == ultimas
    assert all(x not in p.j(0).mazo for x in ultimas)


def test_condicion_aliado_destruido_incluye_costos_y_no_destierro():
    p = partida()
    condicion = {"condicion": {"tipo": "aliados_destruidos_turno", "valor": 1}}
    fuente = poner(p, Carta("paso", "Paso", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.APOYO)
    aliado = poner(p, ALIADO, 0, Zona.DEFENSA)
    assert not hab.condicion_ok(p, 0, condicion)
    p.desterrar(aliado)
    assert not hab.condicion_ok(p, 0, condicion)
    poner(p, ALIADO, 0, Zona.DEFENSA)
    assert hab.pagar_costo(p, 0, fuente, {"costo": {"destruirAliados": 1}})
    assert hab.condicion_ok(p, 0, condicion)


def test_talisman_con_dos_opciones_basta_una_legal():
    p = partida()
    poner(p, ALIADO, 1, Zona.DEFENSA)
    opciones = (
        {"cuando": "al_jugar", "grupoElegir": "elegir", "accion": "destruir",
         "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Tótem"]}},
        {"cuando": "al_jugar", "grupoElegir": "elegir", "accion": "destruir",
         "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]}},
    )
    talisman = poner(p, Carta("elige", "Elige", Tipo.TALISMAN, 0, 0, "", "", opciones, True),
                    0, Zona.MANO)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert hab.talisman_jugable(p, 0, talisman, "vigilia")


def test_destruir_dos_aliados_exige_dos_objetivos():
    p = partida()
    h = {"cuando": "al_jugar", "accion": "destruir", "cantidad": 2,
         "cantidadExacta": True,
         "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]}}
    talisman = poner(p, Carta("plaga", "Plaga", Tipo.TALISMAN, 0, 0, "", "", (h,), True),
                    0, Zona.MANO)
    primero = poner(p, ALIADO, 1, Zona.DEFENSA)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not hab.talisman_jugable(p, 0, talisman, "vigilia")
    segundo = poner(p, ALIADO, 1, Zona.DEFENSA)
    assert hab.talisman_jugable(p, 0, talisman, "vigilia")
    p._mover(talisman, Zona.CEMENTERIO)
    hab.resolver(p, 0, talisman, h)
    assert primero.zona == segundo.zona == Zona.CEMENTERIO


def test_fiesta_elige_un_cementerio_con_dos_cartas_y_roba_si_hay_otra():
    p = partida()
    luego = [{"relacion": "si_se_cumplio", "accion": "robar", "cantidad": 2,
              "objetivo": {"quien": "propio"},
              "condicion": {"tipo": "carta_cementerio_arquetipo", "arquetipo": "Fiesta"}}]
    opciones = tuple(
        {"cuando": "al_jugar", "grupoElegir": "fiesta", "accion": "desterrar",
         "cantidad": 2, "cantidadExacta": True,
         "objetivo": {"quien": quien, "zona": "cementerio"}, "luego": luego}
        for quien in ("propio", "oponente")
    )
    carta = Carta("fiesta", "Fiesta de Sangre", Tipo.TALISMAN, 0, 0, "", "", opciones, True)
    fuente = poner(p, carta, 0, Zona.MANO)
    poner(p, Carta("otra", "Fiesta del Sol", Tipo.TALISMAN, 0, 0, "", ""), 0, Zona.CEMENTERIO)
    poner(p, ALIADO, 1, Zona.CEMENTERIO)
    poner(p, ALIADO, 1, Zona.CEMENTERIO)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert hab.talisman_jugable(p, 0, fuente, "vigilia")
    mano_antes = len(p.j(0).mano)
    hab.disparar(p, fuente, "al_jugar")
    assert len(p.j(1).destierro) == 2
    assert len(p.j(0).mano) == mano_antes + 2


def test_robar_hasta_ocho_cuenta_cada_mano_por_separado():
    p = partida()
    fuente = poner(p, Carta("energia", "Energía", Tipo.TALISMAN, 0, 0, "", ""),
                   0, Zona.CEMENTERIO)
    p.robar(0, 3, inicial=True)
    p.robar(1, 6, inicial=True)
    hab.resolver(p, 0, fuente, {"accion": "robarHasta", "valor": 8, "objetivo": {"quien": "ambos"}})
    assert len(p.j(0).mano) == len(p.j(1).mano) == 8


def test_coste_maximo_por_totems_propios():
    p = partida()
    fuente = poner(p, ALIADO, 0, Zona.DEFENSA)
    objetivo = {"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"],
                "coste": {"op": "<=", "segun": "totems_propios"}}
    barato = poner(p, Carta("b", "Barato", Tipo.ALIADO, 1, 1, "", ""), 1, Zona.DEFENSA)
    caro = poner(p, Carta("c", "Caro", Tipo.ALIADO, 2, 2, "", ""), 1, Zona.DEFENSA)
    h = {"accion": "desterrar", "objetivo": objetivo}
    assert not hab.candidatos_validos(p, 0, fuente, h)
    poner(p, Carta("t", "Tótem", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.APOYO)
    assert hab.candidatos_validos(p, 0, fuente, h) == [barato]
    poner(p, Carta("t", "Tótem", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.APOYO)
    assert hab.candidatos_validos(p, 0, fuente, h) == [barato, caro]


def test_desterrar_oro_de_reserva_es_costo_real():
    p = partida()
    fuente = poner(p, ALIADO, 0, Zona.DEFENSA)
    h = {"costo": {"desterrarOroReserva": 1}}
    reserva = list(p.j(0).reserva)
    assert hab.pagar_costo(p, 0, fuente, h)
    assert reserva[0].zona == Zona.DESTIERRO
    assert not hab.puede_pagar_costo(p, 0, fuente, h)


def test_generar_oro_segun_fuerza_del_aliado_sacrificado():
    p = partida()
    fuente = poner(p, Carta("alquimico", "Alquímico", Tipo.TOTEM, 0, 0, "", ""),
                   0, Zona.APOYO)
    aliado = poner(p, Carta("fuerte", "Fuerte", Tipo.ALIADO, 0, 4, "", ""), 0, Zona.DEFENSA)
    h = {"costo": {"destruirAliados": 1}, "accion": "generarOro",
         "cantidadSegun": "fuerza_costo"}
    assert hab.pagar_costo(p, 0, fuente, h)
    hab.resolver(p, 0, fuente, h)
    assert aliado.zona == Zona.CEMENTERIO
    assert p.j(0).oros_virtuales == 4


def test_bono_por_totems_propios_de_coste_minimo():
    p = partida()
    h = {"cuando": "continua", "accion": "modificarFuerza", "valor": 1,
         "valorPorCada": "totem_propio_coste_min", "porCadaCosteMin": 2,
         "objetivo": {"quien": "esta_carta"}}
    aliado = poner(p, Carta("twosret", "Twosret", Tipo.ALIADO, 2, 2, "", "", (h,), True),
                   0, Zona.DEFENSA)
    poner(p, Carta("barato", "Barato", Tipo.TOTEM, 1, 0, "", ""), 0, Zona.APOYO)
    poner(p, Carta("caro", "Caro", Tipo.TOTEM, 2, 0, "", ""), 0, Zona.APOYO)
    poner(p, Carta("rival", "Rival", Tipo.TOTEM, 4, 0, "", ""), 1, Zona.APOYO)
    assert hab.fuerza(p, aliado) == 3


def test_inmunidad_de_arma_solo_protege_a_su_portador():
    p = partida()
    portador = poner(p, ALIADO, 0, Zona.DEFENSA)
    otro = poner(p, ALIADO, 0, Zona.DEFENSA)
    h = {"cuando": "continua", "accion": "inmunidad", "protegePortador": True,
         "protege": {"tipos": ["Aliado"]}, "objetivo": {"quien": "oponente"}}
    arma = p._instancia(Carta("yelmo", "Yelmo", Tipo.ARMA, 0, 0, "", "", (h,), True),
                       0, Zona.PORTADA)
    arma.portador = portador.uid
    p.e.portadas.append(arma)
    rival = poner(p, ALIADO, 1, Zona.DEFENSA)
    assert hab.inmune(p, portador, rival)
    assert not hab.inmune(p, otro, rival)


def test_cantidad_copias_en_cementerio_y_aliados_de_fuerza_minima():
    p = partida()
    fuente = poner(p, ALIADO, 0, Zona.DEFENSA)
    poner(p, Carta("r", "Revivir a Osiris", Tipo.TALISMAN, 0, 0, "", ""), 0, Zona.CEMENTERIO)
    poner(p, Carta("r", "Revivir a Osiris", Tipo.TALISMAN, 0, 0, "", ""), 0, Zona.CEMENTERIO)
    assert hab.cantidad(p, 0, {"cantidadSegun": "cartas_cementerio_nombre",
                              "contarNombre": "Revivir a Osiris"}, []) == 2
    poner(p, Carta("f", "Fuerte", Tipo.ALIADO, 0, 3, "", ""), 0, Zona.DEFENSA)
    assert not hab.condicion_ok(p, 0, {"condicion": {"tipo": "aliados_fuerza_min", "fuerzaMin": 3, "valor": 2}})
    poner(p, Carta("g", "Otro", Tipo.ALIADO, 0, 4, "", ""), 0, Zona.DEFENSA)
    assert hab.condicion_ok(p, 0, {"condicion": {"tipo": "aliados_fuerza_min", "fuerzaMin": 3, "valor": 2}})


def test_arma_identifica_solo_al_bloqueador_de_su_portador():
    p = partida()
    portador = poner(p, ALIADO, 0, Zona.ATAQUE)
    bloqueador = poner(p, ALIADO, 1, Zona.DEFENSA)
    arma = p._instancia(Carta("pesh", "Pesh", Tipo.ARMA, 0, 0, "", ""), 0, Zona.PORTADA)
    arma.portador = portador.uid
    p.e.portadas.append(arma)
    h = {"accion": "destruir", "objetivo": {"quien": "bloqueador_portador", "tipos": ["Aliado"]}}
    assert not hab.candidatos_validos(p, 0, arma, h)
    p.bloqueos[portador.uid] = bloqueador
    assert hab.candidatos_validos(p, 0, arma, h) == [bloqueador]


def test_descartar_dispara_habilidad_y_jugar_talisman_no():
    p = partida()
    h = {"cuando": "al_descartarse", "accion": "robar", "cantidad": 1,
         "objetivo": {"quien": "propio"}}
    carta = Carta("sidhe", "Sidhe", Tipo.ALIADO, 0, 1, "", "", (h,), True)
    inst = poner(p, carta, 0, Zona.MANO)
    p.descartar(inst)
    assert inst.zona == Zona.CEMENTERIO
    assert p.descartadas_turno == [1, 0]
    assert len(p.j(0).mano) == 1
    talisman = poner(p, Carta("tal", "Talismán", Tipo.TALISMAN, 0, 0, "", "", (h,), True),
                    0, Zona.MANO)
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, Jugada("jugar", talisman))
    assert p.descartadas_turno == [1, 0]


def test_condiciones_de_descarte_y_cartas_sidhe_en_juego():
    p = partida()
    descarto = {"condicion": {"tipo": "descarto_este_turno", "valor": 1}}
    sidhe = {"condicion": {"tipo": "cartas_arquetipo_en_juego", "arquetipo": "Sidhe", "valor": 2}}
    assert not hab.condicion_ok(p, 0, descarto)
    poner(p, Carta("s1", "Sidhe Guerrero", Tipo.ALIADO, 0, 1, "", ""), 0, Zona.DEFENSA)
    poner(p, Carta("s2", "Tótem Sidhe", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.APOYO)
    assert hab.condicion_ok(p, 0, sidhe)
    mano = poner(p, ALIADO, 0, Zona.MANO)
    p.descartar(mano)
    assert hab.condicion_ok(p, 0, descarto)


def test_efecto_opcional_en_fase_final_respeta_decision():
    p = partida()
    fuente = poner(p, Carta("r", "Rómulo y Remo", Tipo.TALISMAN, 0, 0, "", ""),
                   0, Zona.CEMENTERIO)
    h = {"accion": "generarOro", "valor": 2,
         "luego": [{"momento": "fase_final", "accion": "robar", "cantidad": 1,
                    "objetivo": {"quien": "propio"}, "opcional": True}]}
    hab.resolver(p, 0, fuente, h)
    assert len(p.pendientes_final) == 1
    class Rechaza(Heuristico):
        def usar_opcional(self, *args, **kwargs):
            return False
    p.jugadores = (Rechaza(1), Heuristico(2))
    p.e.fase = "final"
    hab.resolver_pendientes_final(p)
    assert len(p.j(0).mano) == 0
    assert p.j(0).oros_virtuales == 2


def test_saltar_agrupacion_deja_aliados_y_oros_en_sus_zonas():
    p = partida()
    aliado = poner(p, ALIADO, 0, Zona.ATAQUE)
    aliado.listo = False
    oro = p.j(0).reserva[0]
    p._mover(oro, Zona.PAGADO)
    h = {"cuando": "continua", "accion": "restriccion", "modo": "saltar_agrupacion",
         "objetivo": {"quien": "ambos"}}
    poner(p, Carta("j", "Jerusalén", Tipo.TOTEM, 0, 0, "", "", (h,), True), 1, Zona.APOYO)
    p.e.activo = 0
    p._vigilia = lambda _i: None
    p._batalla = lambda _i: None
    p._finalizar_turno = lambda _i: None
    p._turno()
    assert aliado.zona == Zona.ATAQUE
    assert oro.zona == Zona.PAGADO
    assert not aliado.listo


def test_destruir_todo_excepto_la_fuente():
    p = partida()
    h = {"cuando": "al_jugar", "accion": "destruir",
         "objetivo": {"quien": "ambos", "zona": "en_juego", "seleccion": "todos",
                      "excluirFuente": True}}
    fuente = poner(p, Carta("eolo", "Eolo", Tipo.ALIADO, 0, 3, "", "", (h,), True),
                   0, Zona.DEFENSA)
    otro = poner(p, ALIADO, 0, Zona.DEFENSA)
    rival = poner(p, ALIADO, 1, Zona.DEFENSA)
    hab.resolver(p, 0, fuente, h)
    assert fuente.zona == Zona.DEFENSA
    assert otro.zona == rival.zona == Zona.CEMENTERIO


def test_control_temporal_y_mover_a_defensa_termina_al_salir_fuente():
    p = partida()
    h = {"cuando": "al_jugar", "accion": "ganarControl", "duracion": "mientras_en_juego",
         "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"], "costeMax": 1},
         "luego": [{"relacion": "si_se_cumplio", "accion": "mover", "zonaDestino": "linea_defensa",
                    "objetivo": {"referencia": "afectadas", "quien": "propio"}}]}
    fuente = poner(p, Carta("neferura", "Neferura", Tipo.ALIADO, 0, 2, "", "", (h,), True),
                   0, Zona.DEFENSA)
    rival = poner(p, Carta("rival", "Rival", Tipo.ALIADO, 1, 1, "", ""), 1, Zona.ATAQUE)
    hab.resolver(p, 0, fuente, h)
    assert rival.controlador == 0 and rival.zona == Zona.DEFENSA
    p._mover(fuente, Zona.CEMENTERIO)
    hab.revisar_controles(p)
    assert rival.controlador == 1


def test_cambiar_oro_pagado_por_otro_del_cementerio():
    p = partida()
    pagado = p.j(0).reserva[0]
    p._mover(pagado, Zona.PAGADO)
    recuperado = poner(p, ORO, 0, Zona.CEMENTERIO)
    h = {"cuando": "al_jugar", "accion": "mover", "zonaDestino": "cementerio",
         "condicion": {"tipo": "oros_cementerio", "valor": 1},
         "objetivo": {"quien": "propio", "zona": "oro_pagado", "tipos": ["Oro"]},
         "luego": [{"relacion": "si_se_cumplio", "accion": "mover",
                    "zonaDestino": "reserva_oro",
                    "objetivo": {"quien": "propio", "zona": "cementerio", "tipos": ["Oro"],
                                 "referencia": "no_afectadas"}}]}
    fuente = poner(p, Carta("z", "Zenodoto", Tipo.ALIADO, 0, 2, "", "", (h,), True),
                   0, Zona.DEFENSA)
    hab.resolver(p, 0, fuente, h)
    assert pagado.zona == Zona.CEMENTERIO
    assert recuperado.zona == Zona.RESERVA


def test_arma_adicional_da_un_solo_espacio_extra():
    p = partida()
    portador = poner(p, ALIADO, 0, Zona.DEFENSA)
    extra = p._instancia(Carta("extra", "Extra", Tipo.ARMA, 0, 0, "", "",
                              ({"accion": "armaAdicional"},), True), 0, Zona.PORTADA)
    extra.portador = portador.uid
    p.e.portadas.append(extra)
    normal = p._instancia(Carta("normal", "Normal", Tipo.ARMA, 0, 0, "", ""), 0, Zona.MANO)
    assert hab.portador_valido(p, normal, portador)
    normal.zona, normal.portador = Zona.PORTADA, portador.uid
    p.e.portadas.append(normal)
    tercero = p._instancia(Carta("tercero", "Tercero", Tipo.ARMA, 0, 0, "", ""), 0, Zona.MANO)
    assert not hab.portador_valido(p, tercero, portador)


def test_fuerza_del_portador_queda_registrada_antes_de_desterrar_arma():
    p = partida()
    portador = poner(p, ALIADO, 0, Zona.DEFENSA)
    arma = p._instancia(Carta("espada", "Espada", Tipo.ARMA, 0, 0, "", "",
                             ({"cuando": "continua", "accion": "modificarFuerza", "valor": 1,
                               "objetivo": {"quien": "esta_carta"}},), True), 0, Zona.PORTADA)
    arma.portador = portador.uid
    p.e.portadas.append(arma)
    h = {"costo": {"desterrarEstaCarta": True}, "accion": "botar",
         "cantidadSegun": "fuerza_costo", "objetivo": {"quien": "oponente"}}
    assert hab.pagar_costo(p, 0, arma, h)
    assert arma.zona == Zona.DESTIERRO
    assert hab.cantidad(p, 0, h, []) == 2


def test_propiedad_de_arma_condicionada_por_raza_del_portador():
    p = partida()
    dragon = poner(p, Carta("d", "Dragón", Tipo.ALIADO, 0, 2, "Dragón", ""), 0, Zona.DEFENSA)
    h = {"cuando": "continua", "accion": "imbloqueable", "portadorRaza": "Dragón"}
    arma = p._instancia(Carta("espada", "Espada", Tipo.ARMA, 0, 0, "", "", (h,), True),
                       0, Zona.PORTADA)
    arma.portador = dragon.uid
    p.e.portadas.append(arma)
    assert hab.tiene_prop(p, dragon, "imbloqueable")
    dragon.raza_temporal = "Caballero"
    assert not hab.tiene_prop(p, dragon, "imbloqueable")


def test_barajar_como_maximo_una_carta_de_cada_tipo():
    p = partida()
    fuente = poner(p, Carta("funeral", "Funeral", Tipo.TALISMAN, 0, 0, "", ""), 0, Zona.MANO)
    poner(p, ALIADO, 0, Zona.CEMENTERIO)
    poner(p, ALIADO, 0, Zona.CEMENTERIO)
    poner(p, ORO, 0, Zona.CEMENTERIO)
    poner(p, Carta("t", "Tótem", Tipo.TOTEM, 0, 0, "", ""), 0, Zona.CEMENTERIO)
    antes = len(p.j(0).mazo)
    hab.resolver(p, 0, fuente, {"accion": "barajarTipos"})
    assert len(p.j(0).mazo) == antes + 3
    assert sum(x.tipo == Tipo.ALIADO for x in p.j(0).cementerio) == 1


def test_mirar_dos_de_mano_envia_una_al_fondo():
    p = partida()
    fuente = poner(p, ALIADO, 0, Zona.DEFENSA)
    poner(p, ALIADO, 1, Zona.MANO)
    poner(p, ORO, 1, Zona.MANO)
    antes = len(p.j(1).mazo)
    hab.resolver(p, 0, fuente, {"accion": "mirarManoAzar", "cantidad": 2})
    assert len(p.j(1).mano) == 1
    assert len(p.j(1).mazo) == antes + 1


def test_sinach_pone_oro_del_tope_en_mano_y_bota_otras_cartas():
    p = partida()
    fuente = poner(p, ALIADO, 0, Zona.DEFENSA)
    oro = p._instancia(ORO, 0, Zona.MAZO)
    p.j(0).mazo.insert(0, oro)
    hab.resolver(p, 0, fuente, {"accion": "botarOroAMano"})
    assert oro.zona == Zona.MANO
    aliado = p._instancia(ALIADO, 0, Zona.MAZO)
    p.j(0).mazo.insert(0, aliado)
    hab.resolver(p, 0, fuente, {"accion": "botarOroAMano"})
    assert aliado.zona == Zona.CEMENTERIO


def test_joyero_toma_oro_rival_a_su_reserva_permanentemente():
    p = partida()
    oro_rival = p.j(1).reserva[0]
    h = {"accion": "ganarControl", "duracion": "permanente",
         "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Oro"]},
         "luego": [{"relacion": "si_se_cumplio", "accion": "mover", "zonaDestino": "reserva_oro",
                    "objetivo": {"referencia": "afectadas", "quien": "propio"}}]}
    fuente = poner(p, Carta("joyero", "Joyero", Tipo.TALISMAN, 0, 0, "", ""), 0, Zona.MANO)
    hab.resolver(p, 0, fuente, h)
    assert oro_rival.controlador == 0 and oro_rival.zona == Zona.RESERVA
    hab.revisar_controles(p)
    assert oro_rival.controlador == 0
