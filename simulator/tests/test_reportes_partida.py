"""Reportes del dueño sobre la partida narrada Faraón Djoser vs Sacerdote
(simulations/oTugLAckS8wKSQzLqAi8, seed 73287). Un test por arreglo."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona

from test_acciones_v3b import en_zona
from test_motor import aliado, en_defensa, h, partida, talisman


def _luz_del_saber():
    return talisman("Luz del Saber", 1, [h(
        "jugarDesde", talismanVaA="destierro", modo="pagando",
        objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado", "Arma", "Talismán", "Tótem"]},
    )])


def _relampago():
    return talisman("Relámpago Arcano", 1, [h(
        "redirigir", cuando="oponente_juega", objetivo={"quien": "propio", "zona": "en_juego"},
        luego=[{"accion": "botar", "relacion": "si_se_cumplio", "cantidadSegun": "coste_afectada",
                "objetivo": {"quien": "oponente"}}],
    )])


# ── #90: Relámpago Arcano no se juega en la Vigilia propia ──────────────────
def test_talisman_de_respuesta_no_se_juega_en_vigilia():
    p = partida()
    r = en_zona(p, 0, _relampago(), Zona.MANO)
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.carta is r for o in p.jugadas_legales(0, "vigilia"))


def test_luz_del_saber_no_juega_un_talisman_de_respuesta():
    p = partida()
    en_zona(p, 0, _relampago(), Zona.CEMENTERIO)
    luz = en_zona(p, 0, _luz_del_saber(), Zona.MANO)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert hab._candidatos_jugar(p, 0, luz, luz.habilidades[0]) == []


# ── #133: Ptolomeo II previene el efecto continuo de Takelot ────────────────
def test_ptolomeo_ii_previene_la_carta_nombrada_por_takelot():
    from test_motor import ORO
    from test_notas_cartas import jugar

    takelot = aliado("Takelot", 3, 2, [
        {"featureId": "p", "accion": "perderHabilidad", "cuando": "continua",
         "objetivo": {"quien": "cualquiera", "zona": "en_juego", "seleccion": "todos", "nombrarCarta": True}},
    ])
    ptolomeo = aliado("Ptolomeo II", 3, 2, [h(
        "prevenir", cuando="activada", modo="afectada", costo={"botar": 3}, costoAlternativo={"oros": 1},
        objetivo={"quien": "propio", "zona": "en_juego"},
    )])
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}
    estrella = aliado("Estrella", 4, 4, [imb])
    p = partida(cartas_b=[ORO] * 17 + [estrella] * 32)
    en_defensa(p, 1, ptolomeo)
    e1 = en_defensa(p, 1, estrella)
    p.j(1).oros_virtuales = 1
    t = jugar(p, 0, takelot)
    assert t.nombrado_carta == "Estrella"
    assert hab.tiene_prop(p, e1, "imbloqueable")  # Ptolomeo II la protegió
    # Se decide una sola vez: no vuelve a preguntar ni a pagar.
    llamadas = []
    original = hab.prevenir_afectar
    hab.prevenir_afectar = lambda *a: llamadas.append(a) or original(*a)
    try:
        hab.refrescar_perdidas(p)
    finally:
        hab.prevenir_afectar = original
    assert llamadas == [] and hab.tiene_prop(p, e1, "imbloqueable")


# ── #128: Werin busca al salir; si no hay Talismanes, la narración lo dice ──
def test_werin_busca_al_salir_y_narra_si_no_hay():
    werin = aliado("Werin el Poseído", 2, 3, [h(
        "buscar", cuando="al_salir_del_juego", zonaDestino="mano",
        objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]},
    )])
    p = partida()
    p.e.log = []
    w = en_defensa(p, 0, werin)
    assert not any(x.tipo == Tipo.TALISMAN for x in p.j(0).mazo)
    p.destruir(w, combate=True)
    assert any("Werin el Poseído: buscar → no hay cartas válidas" in x for x in p.e.log)
    # Con un Talismán en el mazo, lo sube a la mano.
    p2 = partida()
    t = en_zona(p2, 0, talisman("Rayo", 1, [h("destruir")]), Zona.MAZO)
    w2 = en_defensa(p2, 0, werin)
    p2.destruir(w2, combate=True)
    assert t.zona == Zona.MANO


# ══ Decisiones de la máquina ════════════════════════════════════════════════
from myl_sim.motor import Jugada  # noqa: E402
from test_motor import ORO  # noqa: E402
from test_notas_cartas import arma, oro  # noqa: E402

YO = Heuristico(1)


def _vale(p, jugada):
    return YO._vale_la_pena(p, 0, jugada)


def _activar(inst, k=0):
    return Jugada("activar", inst, habilidad=k)


def _pili():
    return aliado("Pili", 3, 2, [h("subirMano", objetivo={"quien": "propio", "zona": "cementerio",
                                                           "tipos": ["Aliado", "Talismán"]})])


# ── #1: mulligan si no hay nada útil en el turno 1 ─────────────────────────
def test_mulligan_sin_jugada_util_en_turno_1():
    p = partida()
    p.j(0).mano = [en_zona(p, 0, c, Zona.MANO) for c in (
        ORO, ORO, ORO, _luz_del_saber(), _pili(), arma("Mandoble", 3, []),
        talisman("Flechas", 2, [h("botar", fase="declaracion_ataque")]), ORO)]
    assert not YO.quedarse_mano(p, 0)
    p.j(0).mano[3] = en_zona(p, 0, aliado("Kawit", 2, 2), Zona.MANO)
    assert YO.quedarse_mano(p, 0)


# ── #3 / #89: Luz del Saber solo si hay algo que jugar y alcanzan los Oros ──
def test_luz_del_saber_solo_con_objetivo_pagable():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    luz = en_zona(p, 0, _luz_del_saber(), Zona.MANO)
    p.j(0).oros_virtuales = 3
    assert not _vale(p, Jugada("jugar", luz))  # Cementerio vacío
    en_zona(p, 0, aliado("Caro", 4, 4), Zona.CEMENTERIO)
    assert not _vale(p, Jugada("jugar", luz))  # 1 + 4 > 4 Oros
    en_zona(p, 0, aliado("Barato", 2, 2), Zona.CEMENTERIO)
    assert _vale(p, Jugada("jugar", luz))


# ── #11: Pili se guarda si no hay nada que subir ────────────────────────────
def test_aliado_debil_sin_objetivo_se_guarda():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    pili = en_zona(p, 0, _pili(), Zona.MANO)
    p.j(0).oros_virtuales = 3
    assert not _vale(p, Jugada("jugar", pili))
    caido = en_zona(p, 0, aliado("Caído", 2, 2), Zona.CEMENTERIO)
    assert _vale(p, Jugada("jugar", pili))
    p.j(0).cementerio.remove(caido)
    p.j(0).mazo = p.j(0).mazo[:10]  # castillo en peligro: se juega igual
    assert _vale(p, Jugada("jugar", pili))


# ── #13: Jeroglíficos no sacrifica el Oro fuera de combate ──────────────────
def test_sacrificar_oro_segun_el_impacto_en_la_partida():
    """Jeroglíficos no depende del coste sino del impacto: el dueño lo define
    como "muy situacional"."""
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    # Ay empata con mi atacante: sin sacarlo no pasa nada (el exceso de un
    # bloqueo pasa igual, así que con uno más débil casi no cambia).
    ay = en_defensa(p, 1, aliado("Ay", 2, 3))
    assert not _vale(p, _activar(j, 1))  # fuera de combate, sin impacto
    atacante = en_defensa(p, 0, aliado("Atacante", 2, 3))
    p.atacantes, p.bloqueos = [atacante], {atacante.uid: ay}
    assert not _vale(p, _activar(j, 1))  # dejar pasar 3 al comienzo no vale un Oro
    p.j(1).mazo = p.j(1).mazo[:12]
    assert _vale(p, _activar(j, 1))  # con su castillo bajo, esos 3 sí pesan
    p.atacantes, p.bloqueos = [], {}
    ramses = en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    assert not _vale(p, _activar(j, 1))  # caro, pero sin impacto ahora
    hab._cambiar_control(p, ramses, 0)
    hab._cambiar_control(p, ramses, 1)
    ramses.dueno = 0  # era mío y me lo robaron
    assert _vale(p, _activar(j, 1))


# ── #40: Nuh guarda la jugada gratis para el Mandoble ──────────────────────
def _nuh():
    return aliado("Nuh", 3, 2, [h("jugarDesde", cuando="activada", fase="vigilia", turno="propio",
                                  modo="sin_pagar", limitePorTurno=1,
                                  objetivo={"quien": "propio", "zonas": ["mazo", "cementerio"], "tipos": ["Arma"]})])


def test_nuh_espera_al_arma_cara():
    escudo = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano", opcional=True,
                                             objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida(cartas_a=[ORO] * 17 + [aliado("Soldado", 1, 1)] * 32)
    p.e.activo, p.e.fase = 0, "vigilia"
    nuh = en_defensa(p, 0, _nuh())
    en_zona(p, 0, escudo, Zona.CEMENTERIO)
    assert _vale(p, _activar(nuh))  # no hay nada mejor que esperar
    mandoble = en_zona(p, 0, arma("Mandoble De Seth", 3, []), Zona.MANO)
    assert not _vale(p, _activar(nuh))  # mejor barajar el Mandoble y jugarlo gratis
    resto = p.j(0).mazo[10:]
    p.j(0).mazo = p.j(0).mazo[:10]
    assert _vale(p, _activar(nuh))  # castillo en peligro: el Escudo recupera
    p.j(0).mazo += resto
    p._mover(mandoble, Zona.MAZO)
    assert _vale(p, _activar(nuh))  # el Mandoble ya está al alcance


# ── #35 / #135: no barajar ni buscar lo que se juega desde el Cementerio ────
def _qer_her():
    return aliado("Qer-Her", 3, 2, [h("jugarDesde", cuando="activada", fase="vigilia", turno="propio",
                                      modo="sin_pagar", costo={"oros": 3},
                                      objetivo={"quien": "esta_carta", "zona": "cementerio"})])


def test_no_baraja_ni_busca_lo_que_se_juega_desde_el_cementerio():
    p = partida()
    qer = en_zona(p, 0, _qer_her(), Zona.CEMENTERIO)
    otro = en_zona(p, 0, aliado("Soldado", 1, 1), Zona.CEMENTERIO)
    barajar = h("barajar", objetivo={"quien": "propio", "zona": "cementerio"})
    assert YO.elegir_objetivos(p, 0, [qer, otro], 1, barajar) == [otro]
    rito = oro("Rito de Aton", [h("buscar", cuando="activada", zonaDestino="mano",
                                  costo={"desterrarEstaCarta": True, "descartar": 1},
                                  objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"],
                                            "coste": {"op": ">=", "valor": 3}})])
    r = en_zona(p, 0, rito, Zona.RESERVA)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not YO._objetivo_util(p, 0, r, r.habilidades[0])  # solo estaba Qer-Her
    en_zona(p, 0, aliado("Grande", 4, 4), Zona.CEMENTERIO)
    assert YO._objetivo_util(p, 0, r, r.habilidades[0])


# ── #57: Qadesh solo si conviene ────────────────────────────────────────────
def test_destruccion_masiva_solo_si_conviene():
    qadesh = talisman("Qadesh", 5, [h("destruir", objetivo={"quien": "cualquiera", "zona": "en_juego",
                                                           "tipos": ["Aliado"], "seleccion": "todos"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    q = en_zona(p, 0, qadesh, Zona.MANO)
    p.j(0).oros_virtuales = 5
    p.j(0).mano = [q]
    en_defensa(p, 0, aliado("Nuh", 3, 2))
    en_defensa(p, 0, aliado("Pili", 3, 2))
    for n in ("Djoser", "Ptolomeo III", "Montuhopet II"):
        en_defensa(p, 1, aliado(n, 3, 3))
    assert not _vale(p, Jugada("jugar", q))  # como en el reporte: sin Aliados en mano
    en_zona(p, 0, aliado("Refuerzo", 2, 2), Zona.MANO)
    assert _vale(p, Jugada("jugar", q))


# ── #58: Nudo de Isis solo si su restricción me afecta ──────────────────────
def test_quitar_restriccion_solo_si_me_afecta():
    from test_notas_cartas import _nudo
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    k = next(i for i, x in enumerate(nudo.habilidades) if x.get("accion") == "perderHabilidad")
    p.j(0).oros_virtuales = 2
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])
    en_zona(p, 0, aliado("Ib-Mut", 1, 1, [h("barajar", objetivo={"quien": "propio", "zona": "cementerio"})]),
            Zona.MANO)
    assert YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])


# ── #104: Ramsés II no repite lo que ya tiene ──────────────────────────────
def test_no_activa_una_propiedad_que_ya_tiene():
    ramses = aliado("Ramsés II", 4, 6, [h(
        "otorgarPropiedad", cuando="activada", fase="vigilia", turno="propio", modo="indestructible",
        duracion="hasta_vigilia", costo={"descartar": 1}, costoAlternativo={"oros": 1}, objetivo={"quien": "esta_carta"},
        luego=[{"accion": "otorgarPropiedad", "relacion": "si_se_cumplio", "modo": "indesterrable",
                "duracion": "hasta_vigilia", "objetivo": {"referencia": "afectadas"}}])])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    r = en_defensa(p, 0, ramses)
    p.j(0).oros_virtuales = 3
    assert _vale(p, _activar(r))
    p.ejecutar_jugada(0, _activar(r))
    assert not _vale(p, _activar(r))


# ── #152: Toro Apis solo en combate ─────────────────────────────────────────
def test_bajar_fuerza_solo_en_combate():
    toro = oro("Toro Apis", [h("modificarFuerza", cuando="activada", valor=-1, modoFuerza="sumar",
                               costo={"pagarEstaCarta": True}, zonaActivacion="reserva_oro",
                               objetivo={"quien": "oponente", "zona": "en_juego"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    t = en_zona(p, 0, toro, Zona.RESERVA)
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    assert not YO._objetivo_util(p, 0, t, t.habilidades[0])
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    mio = en_defensa(p, 0, aliado("Takelot", 3, 3))
    p.atacantes, p.bloqueos = [werin], {werin.uid: mio}
    assert YO._objetivo_util(p, 0, t, t.habilidades[0])  # Werin pelea contra Takelot


def test_luz_del_saber_no_se_evalua_a_si_misma():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    en_zona(p, 0, _luz_del_saber(), Zona.CEMENTERIO)
    luz = en_zona(p, 0, _luz_del_saber(), Zona.MANO)
    assert not _vale(p, Jugada("jugar", luz))  # sin recursión infinita


# ══ 2ª partida (simulations/5l070nNbA7GeW2SUBnjK) ═══════════════════════════
def _demoledor():
    return aliado("Demoledor de Amon", 4, 4, [
        {"featureId": "f", "accion": "furia", "cuando": "continua"},
        h("obligarBloqueo", cuando="al_atacar", fase="declaracion_ataque", turno="propio", opcional=True,
          objetivo={"quien": "oponente", "zona": "en_juego"},
          luego=[{"accion": "perderHabilidad", "relacion": "si_se_cumplio", "duracion": "hasta_fase_final",
                  "objetivo": {"referencia": "afectadas"}},
                 {"accion": "modificarFuerza", "relacion": "siempre", "valor": -1, "modoFuerza": "sumar",
                  "duracion": "hasta_fase_final", "objetivo": {"referencia": "afectadas"}}]),
    ])


# ── #74: dos Demoledores no obligan al mismo Aliado ─────────────────────────
def test_dos_demoledores_no_obligan_al_mismo_bloqueador():
    from test_motor import AtacaTodo
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    d1 = en_defensa(p, 0, _demoledor())
    d2 = en_defensa(p, 0, _demoledor())
    ay = en_defensa(p, 1, aliado("Ay", 2, 3))
    m = len(p.j(1).mazo)
    p.e.activo = 0
    p._batalla(0)
    assert list(p.bloqueo_forzado.values()).count(ay) <= 1
    # Uno lo bloquea Ay (3 − 1 = 2: pasan 2), el otro entra completo (4).
    assert m - len(p.j(1).mazo) == 6 and d1.en_juego and d2.en_juego


# ── #48: el −1 del Demoledor se aplica aunque el bloqueador no pierda su
#    habilidad (Ptolomeo III protegido), con el 2º "luego" en "Siempre" ───────
def test_demoledor_resta_1_aunque_no_pierda_habilidad():
    from test_motor import AtacaTodo
    ptolomeo = aliado("Ptolomeo III", 3, 3, [
        {"featureId": "p", "accion": "protegerHabilidad", "cuando": "continua",
         "objetivo": {"quien": "esta_carta"}},
    ], raza="Faraón")
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    en_defensa(p, 0, _demoledor())
    en_defensa(p, 0, aliado("Werin", 2, 3))
    en_defensa(p, 1, ptolomeo)
    m = len(p.j(1).mazo)
    p.e.activo = 0
    p._batalla(0)
    assert m - len(p.j(1).mazo) == 5  # Werin 3 + (4 − 2)


# ── #44: Kawit ataca si el único bloqueador queda obligado por el Demoledor ─
def test_ataca_si_el_bloqueador_queda_obligado():
    p = partida()
    d = en_defensa(p, 0, _demoledor())
    kawit = en_defensa(p, 0, aliado("Kawit", 2, 2))
    en_defensa(p, 1, aliado("Ptolomeo III", 3, 3))
    assert {x.uid for x in YO.elegir_atacantes(p, 0, [d, kawit])} == {d.uid, kawit.uid}


# ── #54 / #82: Nephre-Ka antes que Ay cuando puede sacar al Demoledor ──────
def test_prefiere_el_aliado_que_saca_una_amenaza():
    nephre = aliado("Nephre-Ka", 2, 2, [h(
        "destruir", opcional=True, costo={"desterrarCementerioSegun": "coste_objetivo"},
        objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    n = en_zona(p, 0, nephre, Zona.MANO)
    ay = en_zona(p, 0, aliado("Ay", 2, 3), Zona.MANO)
    en_defensa(p, 1, _demoledor())
    assert YO._puntaje(p, 0, Jugada("jugar", ay)) > YO._puntaje(p, 0, Jugada("jugar", n))  # Cementerio vacío
    for k in range(4):
        en_zona(p, 0, aliado(f"Caído {k}", 1, 1), Zona.CEMENTERIO)
    assert YO._puntaje(p, 0, Jugada("jugar", n)) > YO._puntaje(p, 0, Jugada("jugar", ay))


# ── #83: Ay no destierra a Cleopatra VII para robar ─────────────────────────
def test_no_sacrifica_un_aliado_valioso_para_robar():
    ay = aliado("Ay", 2, 3, [h("robar", cuando="activada", fase="vigilia", turno="propio", cantidad=2,
                               costo={"desterrarAliados": 1}, objetivo={"quien": "propio"})])
    cleo = aliado("Cleopatra VII", 4, 3, [h("perderHabilidad", duracion="mientras_en_juego",
                                            objetivo={"quien": "cualquiera", "tipos": ["Aliado"],
                                                      "seleccion": "todos", "nombrarRaza": True})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    a = en_defensa(p, 0, ay)
    c = en_defensa(p, 0, cleo)
    assert not _vale(p, _activar(a))
    p._mover(c, Zona.CEMENTERIO)
    en_defensa(p, 0, aliado("Soldado", 1, 1))
    assert _vale(p, _activar(a))


# ── Errores vistos al regenerar la 2ª partida ───────────────────────────────
def test_la_batalla_anterior_no_queda_pegada_al_turno_siguiente():
    p = partida()
    atacante = en_defensa(p, 0, aliado("Atacante", 2, 3))
    p.atacantes, p.bloqueos = [atacante], {}
    p.e.activo = 1
    p.e.turno = 2
    vistos = []
    p._vigilia = lambda a: vistos.append(list(p.atacantes))
    p._batalla = lambda a: None
    p._turno()
    assert vistos == [[]]  # en la Vigilia siguiente ya no hay combate


def _montuhopet():
    return aliado("Montuhopet II", 1, 3, [h("subirMano", objetivo={"quien": "propio", "zona": "en_juego",
                                                                   "tipos": ["Aliado"]})])


def test_montuhopet_no_se_sube_a_si_mismo_y_rejuega_lo_util():
    from test_notas_cartas import jugar
    nephre = aliado("Nephre-Ka", 2, 2, [h(
        "destruir", opcional=True, objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    ramses = en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    p.e.activo, p.e.fase = 0, "vigilia"
    m = en_zona(p, 0, _montuhopet(), Zona.MANO)
    p.j(0).oros_virtuales = 3
    assert not _vale(p, Jugada("jugar", m))  # subiría a Ramsés II: no gana nada
    n = en_defensa(p, 0, nephre)
    en_defensa(p, 1, aliado("Demoledor", 4, 4))
    assert _vale(p, Jugada("jugar", m))
    p.j(0).mano.remove(m)
    jugado = jugar(p, 0, _montuhopet())
    assert n.zona == Zona.MANO and ramses.en_juego and jugado.en_juego


def test_el_costo_de_desterrar_un_aliado_se_narra():
    ay = aliado("Ay", 2, 3, [h("robar", cuando="activada", fase="vigilia", turno="propio", cantidad=2,
                               costo={"desterrarAliados": 1}, objetivo={"quien": "propio"})])
    p = partida()
    p.e.log = []
    p.e.activo, p.e.fase = 0, "vigilia"
    a = en_defensa(p, 0, ay)
    en_defensa(p, 0, aliado("Soldado", 1, 1))
    p.ejecutar_jugada(0, _activar(a))
    assert any("destierra Soldado para pagar Ay" in x for x in p.e.log)


def test_obligar_a_bloquear_solo_elige_aliados_en_defensa():
    p = partida()
    d = en_defensa(p, 0, _demoledor())
    en_zona(p, 1, oro("Toro Apis", []), Zona.RESERVA)
    ay = en_defensa(p, 1, aliado("Ay", 2, 3))
    assert hab.candidatos_validos(p, 0, d, d.habilidades[1]) == [ay]


def test_montuhopet_no_devuelve_un_aliado_util_ni_en_peligro():
    p = partida()
    en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    p.e.activo, p.e.fase = 0, "vigilia"
    m = en_zona(p, 0, _montuhopet(), Zona.MANO)
    p.j(0).oros_virtuales = 3
    p.j(0).mazo = p.j(0).mazo[:8]
    assert not _vale(p, Jugada("jugar", m))


# ══ 3ª partida (simulations/AUh2ZLBV3xrO7Zo1Af9R) ═══════════════════════════
def _amyrteos():
    return aliado("Amyrteos", 2, 1, [h("ponerEnJuego", cuando="al_salir_del_juego", zonaDestino="reserva_oro",
                                       objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]})])


# ── #18: Jeroglíficos no se gasta para evitar 1 de daño ─────────────────────
def test_no_sacrifica_oro_por_un_atacante_debil_ni_elige_a_quien_no_pelea():
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    amy = en_defensa(p, 1, _amyrteos())
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3))
    p.atacantes, p.bloqueos = [amy], {}
    assert not _vale(p, _activar(j, 1))  # Amyrteos hace 1: no vale un Oro
    ramses = en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    p.atacantes = [amy, ramses]
    assert _vale(p, _activar(j, 1))
    elegido = YO.elegir_objetivos(p, 0, [amy, jentakus, ramses], 1, j.habilidades[1])
    assert elegido == [ramses]


# ── #46: Amyrteos ataca aunque muera: al morir acelera un Oro ───────────────
def test_ataca_con_el_que_gana_al_morir():
    p = partida()
    amy = en_defensa(p, 0, _amyrteos())
    en_defensa(p, 1, aliado("Muro", 3, 4))
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [amy])] == [amy.uid]


# ── #90: guardar 3 Oros para Flechas de Lava si el rival amenaza ────────────
def test_reserva_oros_para_el_talisman_defensivo():
    flechas = talisman("Flechas de Lava", 3, [h(
        "cancelarAtaque", fase="declaracion_ataque", turno="oponente", modo="todo_el_ataque",
        objetivo={"quien": "propio", "zona": "en_juego"})])
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", zonaActivacion="reserva_oro",
                                    costo={"desterrarCementerio": 1, "pagarEstaCarta": True},
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    e = en_zona(p, 0, escarabeo, Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)  # 3 Oros: inicial + Escarabeo + este
    en_zona(p, 0, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    en_zona(p, 1, aliado("Neferite I", 2, 2), Zona.CEMENTERIO)
    en_zona(p, 0, flechas, Zona.MANO)
    en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    activar = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is e)
    assert YO.elegir_jugada(p, 0, [activar, Jugada("pasar")]).tipo == "pasar"


# ── Mulligan escalonado: no bajar a 5 cartas ────────────────────────────────
def test_mulligan_mas_flexible_con_7_y_se_queda_con_6():
    p = partida()
    p.j(0).mano = [en_zona(p, 0, c, Zona.MANO) for c in (
        ORO, ORO, _pili(), arma("Mandoble", 3, []), ORO, ORO, ORO)]
    assert YO.quedarse_mano(p, 0)  # 7 cartas: Pili (coste 3) alcanza
    p.j(0).mano = p.j(0).mano[:6]
    p.j(0).mano[2] = en_zona(p, 0, ORO, Zona.MANO)
    assert YO.quedarse_mano(p, 0)  # con 6 se queda


def test_no_bloquea_a_amyrteos_salvo_que_este_apurado():
    p = partida()
    amy = en_defensa(p, 1, _amyrteos())
    muro = en_defensa(p, 0, aliado("Muro", 3, 4))
    assert YO.elegir_bloqueos(p, 0, [amy], [muro]) == {}
    p.j(0).mazo = p.j(0).mazo[:3]  # 1 de daño lo deja al borde: ahora sí bloquea
    assert YO.elegir_bloqueos(p, 0, [amy], [muro]) == {amy.uid: muro}


# ══ 4ª partida (simulations/jp6OiMUiH1eiUeUEtUP7) ═══════════════════════════
def _werin():
    return aliado("Werin el Poseído", 2, 3, [h(
        "buscar", cuando="al_salir_del_juego", zonaDestino="mano",
        objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]},
    )], raza="Sacerdote")


# ── #91: Werin subido a la mano igual busca su Talismán ─────────────────────
def test_werin_devuelto_a_la_mano_busca_igual():
    p = partida()
    t = en_zona(p, 0, talisman("Mercado Egipcio", 5, [h("botar")]), Zona.MAZO)
    w = en_defensa(p, 0, _werin())
    p.sale_del_juego(w, Zona.MANO)
    assert t.zona == Zona.MANO


# ── #157: con Cleopatra VII en juego, el que entra llega sin habilidad ──────
def test_cleopatra_afecta_a_los_que_entran_despues():
    from test_notas_cartas import jugar

    class NombraSacerdote(Heuristico):
        def elegir_raza(self, p, yo, razas, h):
            return "Sacerdote"

    cleo = aliado("Cleopatra VII", 4, 3, [h(
        "perderHabilidad", duracion="mientras_en_juego",
        objetivo={"quien": "cualquiera", "zona": "en_juego", "tipos": ["Aliado"], "seleccion": "todos",
                  "nombrarRaza": True})], raza="Faraón")
    demoledor = aliado("Demoledor de Amon", 4, 4, [{"featureId": "f", "accion": "furia", "cuando": "continua"}],
                       raza="Sacerdote")
    p = partida(jugadores=(NombraSacerdote(1), Heuristico(2)))
    jugar(p, 0, cleo)
    d = jugar(p, 1, demoledor)
    assert not hab.tiene_prop(p, d, "furia")


# ── #15 / #71: Nudo de Isis solo si voy a barajar este turno ────────────────
def test_nudo_solo_si_barajo_este_turno():
    from test_notas_cartas import _nudo
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    k = next(i for i, x in enumerate(nudo.habilidades) if x.get("accion") == "perderHabilidad")
    ib_mut = oro("Ib-Mut", [h("barajar", objetivo={"quien": "ambos", "zona": "cementerio"})])
    en_zona(p, 0, ib_mut, Zona.MAZO)  # en el mazo no cuenta
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])
    en_zona(p, 0, ib_mut, Zona.MANO)
    p.j(0).oro_jugado = True  # ya jugó su Oro: Ib-Mut no entra este turno
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])
    p.j(0).oro_jugado = False
    assert YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])


# ── #99: Adiós Belleza no se gasta en un Oro que solo se activa en combate ──
def test_no_quita_habilidad_a_un_oro_fuera_de_combate():
    adios = talisman("Adiós Belleza", 1, [h("perderHabilidad", objetivo={
        "quien": "cualquiera", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem", "Oro"]})])
    papiros = oro("Papiros de Lahun", [h("botar", cuando="activada", fase="guerra_talismanes", cantidad=3,
                                         costo={"oros": 1, "desterrarEstaCarta": True}, zonaActivacion="reserva_oro",
                                         objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    en_zona(p, 1, papiros, Zona.RESERVA)
    a = en_zona(p, 0, adios, Zona.MANO)
    p.j(0).oros_virtuales = 2
    assert not _vale(p, Jugada("jugar", a))


# ── #43 / #134: Montuhopet sube a Amyrteos para acelerar un Oro ─────────────
def test_montuhopet_rebota_amyrteos_y_se_prefiere():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    amy = en_defensa(p, 0, _amyrteos())
    m = en_zona(p, 0, _montuhopet(), Zona.MANO)
    djoser = en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    assert _vale(p, Jugada("jugar", m))
    assert YO._puntaje(p, 0, Jugada("jugar", m)) > YO._puntaje(p, 0, Jugada("jugar", djoser))
    assert YO.elegir_objetivos(p, 0, [amy], 1, m.habilidades[0]) == [amy]


# ── #124: no atacar contra un bloqueador que se arma desde el Cementerio ────
def test_considera_el_arma_que_el_rival_juega_desde_el_cementerio():
    escudo = arma("Escudo Miliciano", 3, [
        h("modificarFuerza", cuando="continua", valor=3, objetivo={"quien": "esta_carta"}),
        h("jugarDesde", cuando="activada", fase="declaracion_ataque", turno="oponente", modo="sin_pagar",
          costo={"oros": 2}, zonaActivacion="cementerio", objetivo={"quien": "esta_carta", "zona": "mazo"}),
    ])
    p = partida()
    werin = en_defensa(p, 0, aliado("Werin", 2, 5))
    en_defensa(p, 1, aliado("Djoser", 3, 3))
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [werin])] == [werin.uid]
    en_zona(p, 1, escudo, Zona.CEMENTERIO)
    p.j(1).oros_virtuales = 2
    assert YO.elegir_atacantes(p, 0, [werin]) == []


# ── #155: si una jugada gana la partida, se hace ────────────────────────────
def test_juega_lo_que_gana_la_partida():
    papiros = oro("Papiros de Lahun", [h("botar", cuando="activada", fase="guerra_talismanes", cantidad=3,
                                         costo={"oros": 1, "desterrarEstaCarta": True}, zonaActivacion="reserva_oro",
                                         objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    pap = en_zona(p, 0, papiros, Zona.RESERVA)
    p.j(0).oros_virtuales = 1
    p.j(1).mazo = p.j(1).mazo[:3]
    jugadas = p.jugadas_legales(0, "guerra_talismanes")
    elegida = YO.elegir_jugada(p, 0, jugadas)
    assert elegida.tipo == "activar" and elegida.carta is pap


# ── Papiros de Lahun con fase "Cualquiera": tu Vigilia o la Guerra ──────────
def test_papiros_en_vigilia_propia_o_en_guerra():
    papiros = oro("Papiros de Lahun", [h("botar", cuando="activada", fase="cualquiera", cantidad=3,
                                         costo={"oros": 1, "desterrarEstaCarta": True}, zonaActivacion="reserva_oro",
                                         objetivo={"quien": "oponente"})])
    p = partida()
    pap = en_zona(p, 0, papiros, Zona.RESERVA)
    p.j(0).oros_virtuales = 1

    def puede(fase, activo):
        p.e.activo, p.e.fase = activo, fase
        return any(o.tipo == "activar" and o.carta is pap for o in p.jugadas_legales(0, fase))

    assert puede("vigilia", 0)  # su propia Vigilia
    assert puede("guerra_talismanes", 0) and puede("guerra_talismanes", 1)  # Guerra de cualquiera
    assert not puede("declaracion_bloqueo", 1)
    p.j(1).mazo = p.j(1).mazo[:3]
    p.e.activo, p.e.fase = 0, "vigilia"
    assert YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia")).carta is pap  # y gana con él


# ══ 5ª partida (simulations/tTdKtAJDv6QfiQ2zdIh3) ═══════════════════════════
def _haquika():
    return aliado("Haquika", 3, 2, [h("ganarControl", duracion="mientras_en_juego",
                                      objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])


def _akhet():
    return Carta("Akhet", "Akhet", Tipo.TOTEM, 3, 0, "", "x", (
        h("mover", zonaDestino="mazo_fondo",
          objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"]}),
    ), True)


def _djedefhor():
    return aliado("Djedefhor", 3, 3, [h("robar", cantidad=2, objetivo={"quien": "propio"})])


# ── #74: Ib-Mut ya en la Reserva no justifica pagar el Nudo ────────────────
def test_nudo_no_cuenta_ib_mut_que_ya_esta_en_juego():
    from test_notas_cartas import _nudo
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    k = next(i for i, x in enumerate(nudo.habilidades) if x.get("accion") == "perderHabilidad")
    en_zona(p, 0, oro("Ib-Mut", [h("barajar", objetivo={"quien": "ambos", "zona": "cementerio"})]), Zona.RESERVA)
    p.j(0).oros_virtuales = 2
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])


# ── #37: Luz del Saber trae a Akhet y saca a Ramsés (mejor que el Ritón) ────
def test_luz_del_saber_vale_lo_que_trae():
    riton = oro("Riton Aqueménida", [h("buscar", cuando="activada", zonaDestino="mano",
                                       costo={"oros": 2, "fondoMazoEstaCarta": True}, zonaActivacion="reserva_oro",
                                       objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Tótem", "Arma"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    luz = en_zona(p, 0, _luz_del_saber(), Zona.MANO)
    r = en_zona(p, 0, riton, Zona.RESERVA)
    en_zona(p, 0, _akhet(), Zona.CEMENTERIO)
    en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    jugadas = p.jugadas_legales(0, "vigilia")
    assert any(o.carta is r for o in jugadas)
    assert YO.elegir_jugada(p, 0, jugadas).carta is luz


# ── #64 / #77: Luz del Saber trae a Haquika (roba a Djoser) y no a Djedefhor ─
def test_luz_del_saber_elige_lo_que_mas_rinde():
    mercado = talisman("Mercado Egipcio", 5, [h("botar", cantidadSegun="oros_que_controla",
                                               objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    luz = en_zona(p, 0, _luz_del_saber(), Zona.MANO)
    m = en_zona(p, 0, mercado, Zona.MANO)
    haquika = en_zona(p, 0, _haquika(), Zona.CEMENTERIO)
    djed = en_zona(p, 0, _djedefhor(), Zona.CEMENTERIO)
    en_defensa(p, 1, aliado("Djoser", 3, 6))
    assert YO._puntaje(p, 0, Jugada("jugar", luz)) > YO._puntaje(p, 0, Jugada("jugar", m))
    assert YO.elegir_objetivos(p, 0, [djed, haquika], 1, luz.habilidades[0]) == [haquika]


# ── Métricas en vivo de las simulaciones de N partidas ──────────────────────
def test_resumen_curva_mulligan_dado_y_rondas():
    from myl_sim.datos import Mazo
    from myl_sim.simulacion import simular
    from test_motor import mazo_basico

    def mazo(x):
        return Mazo(x, x, "racial", "", mazo_basico(), [])

    vistos = []
    r = simular(mazo("A"), mazo("B"), 20, seed=3,
                progreso=lambda k, parcial: vistos.append((k, parcial)))
    assert [k for k, _ in vistos] == list(range(1, 21))
    final = vistos[-1][1]()
    assert final["jugadas"] == 20 and len(final["resultados"]) == 20
    assert final["ladoA"]["ganaDado"] + final["ladoB"]["ganaDado"] == 20
    assert 0 <= final["ladoA"]["fallaCurva"] <= final["ladoA"]["evaluadasCurva"] <= 20
    assert r["rondasPromedio"] == final["rondasPromedio"] > 0
    # Las rondas cuentan turnos completos (los dos jugaron).
    assert r["turnos"]["max"] <= 100


# ══ 6ª partida (simulations/gg1cgKY3lTyZ8rjaWlgK) ═══════════════════════════
def _toro():
    return oro("Toro Apis", [h("modificarFuerza", cuando="activada", valor=-1, modoFuerza="sumar",
                               costo={"pagarEstaCarta": True}, zonaActivacion="reserva_oro",
                               objetivo={"quien": "oponente", "zona": "en_juego"})])


def _papiros():
    return oro("Papiros de Lahun", [h("botar", cuando="activada", fase="guerra_talismanes", cantidad=3,
                                      costo={"oros": 1, "desterrarEstaCarta": True}, zonaActivacion="reserva_oro",
                                      objetivo={"quien": "oponente"})])


# ── #122: el −1 instantáneo de Toro Apis dura solo ese turno ────────────────
def test_fuerza_instantanea_dura_hasta_el_final_del_turno():
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    t = en_zona(p, 0, _toro(), Zona.RESERVA)
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    p.ejecutar_jugada(0, _activar(t))
    assert hab.fuerza(p, werin) == 2
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, werin) == 3  # no se arrastra a los turnos siguientes


# ── #150: Papiros no se paga a sí mismo ─────────────────────────────────────
def test_oro_que_se_destierra_no_paga_su_propio_costo():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    p.j(0).reserva.clear()
    pap = en_zona(p, 0, _papiros(), Zona.RESERVA)
    assert not any(o.carta is pap for o in p.jugadas_legales(0, "guerra_talismanes"))
    en_zona(p, 0, ORO, Zona.RESERVA)
    assert any(o.carta is pap for o in p.jugadas_legales(0, "guerra_talismanes"))
    m = len(p.j(1).mazo)
    p.ejecutar_jugada(0, _activar(pap))
    assert pap.zona == Zona.DESTIERRO and m - len(p.j(1).mazo) == 3
    assert len(p.j(0).pagado) == 1  # pagó con el otro Oro


# ── #127: Haquika indestructible no es objetivo de Djoser ───────────────────
def test_indestructible_no_es_objetivo_de_destruir():
    p = partida()
    haquika = en_defensa(p, 1, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible",
                                                          "cuando": "continua"}]))
    otro = en_defensa(p, 1, aliado("Kawit", 2, 2))
    fuente = en_defensa(p, 0, aliado("Djoser", 3, 3))
    destruir = h("destruir", objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})
    assert hab.candidatos_validos(p, 0, fuente, destruir) == [otro]
    assert haquika.en_juego


# ── #64: Toro Apis al que ataca, no al Kawit que se quedó defendiendo ───────
def test_en_combate_baja_la_fuerza_del_atacante():
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    t = en_zona(p, 0, _toro(), Zona.RESERVA)
    defiende = en_defensa(p, 1, aliado("Kawit", 2, 2))
    ataca = en_defensa(p, 1, aliado("Kawit", 2, 2))
    p.atacantes, p.bloqueos = [ataca], {}
    assert YO.elegir_objetivos(p, 0, [defiende, ataca], 1, t.habilidades[0]) == [ataca]


# ── #94: el Mandoble a quien puede atacar este turno ────────────────────────
def test_arma_a_un_aliado_que_puede_atacar():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    recien = en_defensa(p, 0, aliado("Werin", 2, 3), listo=False)
    listo = en_defensa(p, 0, aliado("Haquika", 3, 2))
    mandoble = en_zona(p, 0, arma("Mandoble De Seth", 3, []), Zona.MANO)
    assert _vale(p, Jugada("jugar", mandoble, portador=listo))
    assert not _vale(p, Jugada("jugar", mandoble, portador=recien))


# ── #90: Biblioteca Eterna con Oros de sobra ────────────────────────────────
def test_destierra_un_oro_para_robar_si_sobran_oros():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"desterrarEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    b = en_zona(p, 0, biblioteca, Zona.RESERVA)
    p.j(0).mano.clear()
    assert not _vale(p, _activar(b))  # con 2 Oros no sobra nada
    for _ in range(5):
        en_zona(p, 0, ORO, Zona.RESERVA)
    assert _vale(p, _activar(b))


# ── #131: rematar con Jinetes de Fuego + Papiros de Lahun ───────────────────
def test_remata_sumando_lo_que_bota_este_turno():
    jinetes = talisman("Jinetes de Fuego", 2, [h("botar", cantidad=3, objetivo={"quien": "oponente"})])
    pap = _papiros()
    pap.habilidades[0]["fase"] = "cualquiera"
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    j = en_zona(p, 0, jinetes, Zona.MANO)
    en_zona(p, 0, pap, Zona.RESERVA)
    for _ in range(3):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(1).mazo = p.j(1).mazo[:5]
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert _botar_de_jugada(p, elegida) == 3
    p.ejecutar_jugada(0, elegida)
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert elegida.carta is j or elegida.tipo == "activar"
    from myl_sim.motor import FinPartida
    try:
        p.ejecutar_jugada(0, elegida)
    except FinPartida:
        pass
    assert p.e.terminada and p.e.ganador == 0


def _botar_de_jugada(p, j):
    from myl_sim.jugadores import _botar_de
    return _botar_de(p, 0, j)


# ── Jinetes de Fuego tal como lo guarda el editor ("Al jugarse", Cementerio) ─
def _jinetes_editor():
    return talisman("Jinetes de Fuego", 2, [
        h("botar", cantidad=3, objetivo={"quien": "oponente"}),
        h("jugarDesde", modo="pagando", talismanVaA="destierro",
          objetivo={"quien": "esta_carta", "zona": "cementerio"}),
    ])


def test_jinetes_se_juega_desde_el_cementerio_y_queda_desterrado():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    j = en_zona(p, 0, _jinetes_editor(), Zona.CEMENTERIO)
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is j)
    m = len(p.j(1).mazo)
    p.ejecutar_jugada(0, jugada)
    assert m - len(p.j(1).mazo) == 3 and j.zona == Zona.DESTIERRO


def test_jinetes_desde_la_mano_no_se_vuelve_a_jugar_a_si_mismo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    j = en_zona(p, 0, _jinetes_editor(), Zona.MANO)
    m = len(p.j(1).mazo)
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is j))
    assert m - len(p.j(1).mazo) == 3  # bota una sola vez


def test_jinetes_con_zona_mano_no_se_juega_desde_el_cementerio():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    viejo = _jinetes_editor()
    viejo.habilidades[1]["objetivo"]["zona"] = "mano"  # como quedó guardado antes
    j = en_zona(p, 0, viejo, Zona.CEMENTERIO)
    assert not any(o.carta is j for o in p.jugadas_legales(0, "vigilia"))


# ══ 7ª partida (simulations/FcbBzCJDCJxds5rBJkq8) ═══════════════════════════
# ── #23/#25: Escudo Celestial no baraja al portador ni a un Oro pagado ──────
def test_escudo_celestial_solo_baraja_del_cementerio():
    p = partida()
    werin = en_defensa(p, 0, aliado("Werin", 2, 3))
    rito = en_zona(p, 0, oro("Rito de Aton", []), Zona.PAGADO)
    akhet = en_zona(p, 0, _akhet(), Zona.CEMENTERIO)
    barajar = h("barajar", opcional=True, cantidadSegun="dano_hecho",
                objetivo={"quien": "propio", "zonas": ["en_juego", "cementerio"]})
    assert YO.elegir_objetivos(p, 0, [werin, akhet, rito], 3, barajar) == [akhet]


# ── #18: guardar Akhet si el rival buscó a Ramsés II ────────────────────────
def test_guarda_la_remocion_para_la_amenaza_revelada():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    akhet = en_zona(p, 0, _akhet(), Zona.MANO)
    djed = en_zona(p, 0, _djedefhor(), Zona.MANO)
    en_defensa(p, 1, aliado("Jentakus I", 3, 3))
    assert YO._puntaje(p, 0, Jugada("jugar", akhet)) > YO._puntaje(p, 0, Jugada("jugar", djed))
    ramses = en_zona(p, 1, aliado("Ramsés II", 4, 6), Zona.MANO)
    ramses.revelada = True  # lo buscó con Jentakus I
    assert YO._puntaje(p, 0, Jugada("jugar", djed)) > YO._puntaje(p, 0, Jugada("jugar", akhet))


# ══ 8ª partida (simulations/WDjIrm8BqlhYd2dtajCp) ═══════════════════════════
def _ay():
    return aliado("Ay", 2, 3, [h("robar", cuando="activada", fase="vigilia", turno="propio", cantidad=2,
                                 costo={"desterrarAliados": 1}, objetivo={"quien": "propio"})])


# ── #13: con Ay en mesa, Amyrteos antes que Jentakus ────────────────────────
def test_amyrteos_con_ay_en_mesa():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    amy = en_zona(p, 0, _amyrteos(), Zona.MANO)
    jentakus = en_zona(p, 0, aliado("Jentakus I", 3, 3), Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", jentakus)) > YO._puntaje(p, 0, Jugada("jugar", amy))
    en_defensa(p, 0, _ay())
    assert YO._puntaje(p, 0, Jugada("jugar", amy)) > YO._puntaje(p, 0, Jugada("jugar", jentakus))


# ── #38: Jeroglíficos recupera a Ramsés II robado por Haquika ───────────────
def test_subir_a_la_mano_recupera_lo_robado():
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    ramses = en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    hab._cambiar_control(p, ramses, 1)  # Haquika se lo robó
    djed = en_defensa(p, 1, _djedefhor())
    p.atacantes, p.bloqueos = [djed], {}
    subir = h("subirMano", objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})
    assert YO.elegir_objetivos(p, 0, [djed, ramses], 1, subir) == [ramses]


# ── #39: un bloqueador sin atacante ya no está en combate ───────────────────
def test_bloqueador_sin_atacante_no_esta_en_combate():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    t = en_zona(p, 0, _toro(), Zona.RESERVA)
    djed = en_defensa(p, 0, _djedefhor())
    ay = en_defensa(p, 1, aliado("Ay", 2, 3))
    p.atacantes, p.bloqueos = [djed], {djed.uid: ay}
    assert YO._objetivo_util(p, 0, t, t.habilidades[0])
    p._mover(djed, Zona.MANO)  # Jeroglíficos lo devolvió
    assert not YO._objetivo_util(p, 0, t, t.habilidades[0])


# ── #48: bloquear con Haquika indestructible ────────────────────────────────
def test_bloquea_con_un_indestructible():
    p = partida()
    haquika = en_defensa(p, 0, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible",
                                                          "cuando": "continua"}]))
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3))
    assert YO.elegir_bloqueos(p, 0, [jentakus], [haquika]) == {jentakus.uid: haquika}


def test_no_recupera_una_carta_robada_debil_con_jeroglificos():
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    amy = en_defensa(p, 0, _amyrteos())
    hab._cambiar_control(p, amy, 1)  # el rival le robó un Amyrteos
    atacante = en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    p.atacantes, p.bloqueos = [atacante], {}
    # Vale el Oro por el atacante (fuerza 6), no por recuperar a Amyrteos.
    assert _vale(p, _activar(j, 1))
    assert YO.elegir_objetivos(p, 0, [amy, atacante], 1, j.habilidades[1]) == [atacante]
    # Solo con Amyrteos de objetivo, no gasta el Oro.
    p.atacantes = []
    p._mover(atacante, Zona.CEMENTERIO)
    assert not _vale(p, _activar(j, 1))


# ══ 9ª partida (simulations/Lgle3MPGSIMC970ADGFW) ═══════════════════════════
# ── #27: no gastar Jeroglíficos en 3 de daño temprano ni en Werin ───────────
def test_no_sacrifica_oro_por_poco_dano_ni_por_quien_gana_al_salir():
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    kawit = en_defensa(p, 1, aliado("Kawit", 2, 3))
    p.atacantes, p.bloqueos = [kawit], {}
    assert not _vale(p, _activar(j, 1))  # 3 de daño con el castillo lleno
    p.j(0).mazo = p.j(0).mazo[:12]
    assert _vale(p, _activar(j, 1))  # con el castillo bajo, sí
    werin = en_defensa(p, 1, _werin())
    p.atacantes = [werin]
    assert not _vale(p, _activar(j, 1))  # Werin se buscaría un Talismán


# ── #33: Corona Faraónica necesita otro Faraón antes del que entra ──────────
def test_corona_no_cuenta_al_aliado_que_entra():
    from test_notas_cartas import jugar
    corona = oro("Corona Faraónica", [h(
        "restringirCombate", cuando="propia_entra", modo="puede_atacar_este_turno", opcional=True,
        costo={"botar": 1}, disparoTipos=["Aliado"],
        condicion={"tipo": "aliados_raza", "raza": "Faraón", "op": ">=", "valor": 1},
        objetivo={"quien": "disparadora", "zona": "en_juego"})])
    p = partida()
    en_zona(p, 0, corona, Zona.RESERVA)
    jentakus = jugar(p, 0, aliado("Jentakus I", 3, 3, raza="Faraón"))
    assert not jentakus.listo  # no había otro Faraón antes
    otro = jugar(p, 0, aliado("Djoser", 3, 3, raza="Faraón"))
    assert otro.listo  # Jentakus ya estaba


# ── #43: Escudo Celestial se guarda hasta que haga falta barajar ────────────
def test_escudo_celestial_se_guarda():
    escudo = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano", opcional=True,
                                             cantidadSegun="dano_hecho",
                                             objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    djed = en_defensa(p, 0, _djedefhor())
    e = en_zona(p, 0, escudo, Zona.MANO)
    assert not _vale(p, Jugada("jugar", e, portador=djed))
    p.j(0).mazo = p.j(0).mazo[:12]
    assert _vale(p, Jugada("jugar", e, portador=djed))


# ── #47: Corona no se gasta en Ramsés II, que ya tiene Furia ────────────────
def test_puede_atacar_no_se_da_a_quien_tiene_furia():
    p = partida()
    ramses = en_defensa(p, 0, aliado("Ramsés II", 4, 6, [{"featureId": "f", "accion": "furia", "cuando": "continua"}]))
    corona = en_zona(p, 0, oro("Corona Faraónica", []), Zona.RESERVA)
    h_corona = h("restringirCombate", cuando="propia_entra", modo="puede_atacar_este_turno",
                 objetivo={"quien": "disparadora", "zona": "en_juego"})
    p.ctx_disparadora = ramses
    assert not YO._objetivo_util(p, 0, corona, h_corona)
    p.ctx_disparadora = en_defensa(p, 0, aliado("Jentakus I", 3, 3))
    assert YO._objetivo_util(p, 0, corona, h_corona)


# ── #49: bloquear a Jentakus contando el −1 de Toro Apis, y aplicárselo ─────
def test_bloquea_contando_el_toro_y_se_lo_aplica_al_bloqueado():
    p = partida()
    t = en_zona(p, 0, _toro(), Zona.RESERVA)
    djed = en_defensa(p, 0, _djedefhor())
    ramses = en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3))
    assert YO.elegir_bloqueos(p, 0, [ramses, jentakus], [djed]) == {jentakus.uid: djed}
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    p.atacantes, p.bloqueos = [ramses, jentakus], {jentakus.uid: djed}
    assert YO.elegir_objetivos(p, 0, [ramses, jentakus], 1, t.habilidades[0]) == [jentakus]


# ── #55: guardar Oros para Abismo si el rival buscó a Ramsés II ────────────
def test_guarda_oros_para_anular_la_amenaza_revelada():
    abismo = talisman("Abismo", 2, [h("anular", cuando="oponente_juega")])
    mercado = talisman("Mercado Egipcio", 5, [h("botar", cantidadSegun="oros_que_controla",
                                               objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    en_zona(p, 0, abismo, Zona.MANO)
    m = en_zona(p, 0, mercado, Zona.MANO)
    jugadas = [Jugada("jugar", m), Jugada("pasar")]
    assert YO.elegir_jugada(p, 0, jugadas).carta is m
    ramses = en_zona(p, 1, aliado("Ramsés II", 4, 6), Zona.MANO)
    ramses.revelada = True
    assert YO.elegir_jugada(p, 0, jugadas).tipo == "pasar"


# ── #85: en peligro, el Rito de Aton recupera Flechas de Lava ───────────────
def test_en_peligro_recupera_el_talisman_defensivo():
    rito = oro("Rito de Aton", [h("buscar", cuando="activada", zonaDestino="mano",
                                  costo={"desterrarEstaCarta": True, "descartar": 1}, zonaActivacion="reserva_oro",
                                  objetivo={"quien": "propio", "zona": "cementerio",
                                            "tipos": ["Aliado", "Talismán"], "coste": {"op": ">=", "valor": 3}})])
    flechas = talisman("Flechas de Lava", 3, [h("cancelarAtaque", fase="declaracion_ataque", turno="oponente",
                                                objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    r = en_zona(p, 0, rito, Zona.RESERVA)
    f = en_zona(p, 0, flechas, Zona.CEMENTERIO)
    takelot = en_zona(p, 0, aliado("Takelot", 3, 2), Zona.CEMENTERIO)
    en_zona(p, 0, aliado("Kawit", 2, 2), Zona.MANO)
    p.j(0).mazo = p.j(0).mazo[:7]
    en_defensa(p, 1, aliado("Ramsés II", 4, 9))
    assert _vale(p, _activar(r))
    assert YO._puntaje(p, 0, _activar(r)) >= 30
    assert YO.elegir_objetivos(p, 0, [takelot, f], 1, r.habilidades[0]) == [f]


def test_nudo_no_cuenta_un_escudo_celestial_guardado_en_la_mano():
    from test_notas_cartas import _nudo
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    k = next(i for i, x in enumerate(nudo.habilidades) if x.get("accion") == "perderHabilidad")
    p.j(0).oros_virtuales = 2
    en_zona(p, 0, arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano",
                                                  objetivo={"quien": "propio", "zona": "cementerio"})]), Zona.MANO)
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])


# ══ 10ª partida (simulations/AAWlk8K6Sy6cKIWQVhx9) ══════════════════════════
def _corona_h():
    return h("restringirCombate", cuando="propia_entra", modo="puede_atacar_este_turno",
             objetivo={"quien": "disparadora", "zona": "en_juego"})


# ── #33: Corona no se gasta en Ay, que es Guardián ──────────────────────────
def test_corona_no_en_un_guardian():
    p = partida()
    corona = en_zona(p, 0, oro("Corona Faraónica", []), Zona.RESERVA)
    ay = en_defensa(p, 0, aliado("Ay", 2, 3, [{"featureId": "g", "accion": "guardian", "cuando": "continua"}]))
    p.ctx_disparadora = ay
    assert not YO._objetivo_util(p, 0, corona, _corona_h())


# ── #128: ni en el Aliado que se va a desterrar con Ay ──────────────────────
def test_corona_no_en_el_que_se_sacrifica():
    p = partida()
    corona = en_zona(p, 0, oro("Corona Faraónica", []), Zona.RESERVA)
    en_defensa(p, 0, _ay())
    nephre = en_defensa(p, 0, aliado("Nephre-Ka", 2, 2))
    p.ctx_disparadora = nephre
    assert not YO._objetivo_util(p, 0, corona, _corona_h())


# ── #39: el Demoledor obliga a Ay, no a Jentakus ────────────────────────────
def test_demoledor_obliga_al_que_tiene_habilidades_reutilizables():
    p = partida()
    d = en_defensa(p, 0, _demoledor())
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3, [h("buscar", zonaDestino="mano",
                                                                objetivo={"quien": "propio", "zona": "mazo"})]))
    ay = en_defensa(p, 1, _ay())
    assert YO.elegir_objetivos(p, 0, [jentakus, ay], 1, d.habilidades[1]) == [ay]


# ── #67: Jentakus no ataca contra Haquika indestructible + Toro Apis ────────
def test_no_ataca_para_morir_contra_un_indestructible():
    p = partida()
    jentakus = en_defensa(p, 0, aliado("Jentakus I", 3, 3))
    en_defensa(p, 1, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible", "cuando": "continua"}]))
    en_zona(p, 1, _toro(), Zona.RESERVA)
    assert YO.elegir_atacantes(p, 0, [jentakus]) == []


# ── #113: el Demoledor no ataca si el bloqueador que obliga lo mata ─────────
def test_demoledor_no_ataca_si_pierde_la_pelea_que_fuerza():
    p = partida()
    d = en_defensa(p, 0, _demoledor())
    haquika = en_defensa(p, 0, aliado("Haquika", 3, 2))
    en_defensa(p, 1, aliado("Ay", 2, 6))
    assert YO.elegir_atacantes(p, 0, [d, haquika]) == []


# ── #120: Ataúd +1 a Ay, que ya le ganaba al Demoledor, no ──────────────────
def test_mas_fuerza_solo_si_cambia_quien_muere():
    ataud = oro("Ataúd de Ramses", [h("modificarFuerza", cuando="activada", valor=1, duracion="hasta_fase_final",
                                      costo={"destruirEstaCarta": True}, zonaActivacion="reserva_oro",
                                      objetivo={"quien": "propio", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    a = en_zona(p, 0, ataud, Zona.RESERVA)
    ay = en_defensa(p, 0, aliado("Ay", 2, 5))
    dem = en_defensa(p, 1, aliado("Demoledor", 4, 4))
    p.atacantes, p.bloqueos = [dem], {dem.uid: ay}
    assert not YO._objetivo_util(p, 0, a, a.habilidades[0])  # 5 > 4: ya gana
    ay.mods.clear()
    p.bloqueos = {dem.uid: en_defensa(p, 0, aliado("Kawit", 2, 4))}
    assert YO._objetivo_util(p, 0, a, a.habilidades[0])  # 4 vs 4 → con +1 sobrevive


# ── #87: Werin busca un Talismán que bote ───────────────────────────────────
def test_werin_busca_un_talisman_que_bote():
    p = partida()
    qadesh = en_zona(p, 0, talisman("Qadesh", 5, [h("destruir", objetivo={"quien": "cualquiera", "seleccion": "todos"})]), Zona.MAZO)
    jinetes = en_zona(p, 0, talisman("Jinetes de Fuego", 2, [h("botar", cantidad=3, objetivo={"quien": "oponente"})]), Zona.MAZO)
    buscar = h("buscar", cuando="al_salir_del_juego", zonaDestino="mano",
               objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]})
    assert YO.elegir_objetivos(p, 0, [qadesh, jinetes], 1, buscar) == [jinetes]


# ── #89: Montuhopet no se juega sin un Aliado propio que subir ──────────────
def test_montuhopet_sin_aliados_se_guarda():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    m = en_zona(p, 0, _montuhopet(), Zona.MANO)
    assert not _vale(p, Jugada("jugar", m))


# ── #136: con Mandoble + Papiros gana: no paga el Ib-Mut y remata ───────────
def test_remate_con_mandoble_en_un_aliado_listo():
    mandoble = arma("Mandoble De Seth", 3, [h("botar", cuando="al_atacar", cantidad=3,
                                               objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    haquika = en_defensa(p, 0, aliado("Haquika", 3, 2))
    m = en_zona(p, 0, mandoble, Zona.MANO)
    en_zona(p, 0, _papiros(), Zona.RESERVA)
    for _ in range(4):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(1).mazo = p.j(1).mazo[:5]
    ib_mut = oro("Ib-Mut", [])
    pagar = {"accion": "robar", "costo": {"pagarEstaCarta": True}, "opcional": True, "objetivo": {"quien": "propio"}}
    assert not YO.usar_opcional(p, 0, en_zona(p, 0, ib_mut, Zona.RESERVA), pagar)
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert elegida.carta is m and elegida.portador is haquika
    p.ejecutar_jugada(0, elegida)
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [haquika])] == [haquika.uid]


# ── #166: no atacar con Haquikas que solo serán bloqueadas; Quemar los Templos
def test_no_ataca_si_todos_seran_bloqueados_y_quema_las_armas():
    p = partida()
    h1 = en_defensa(p, 0, aliado("Haquika", 3, 2))
    h2 = en_defensa(p, 0, aliado("Haquika", 3, 2))
    en_defensa(p, 1, aliado("Ay", 2, 6))
    en_defensa(p, 1, aliado("Cleopatra VII", 4, 3))
    p.j(1).mazo = p.j(1).mazo[:7]
    assert YO.elegir_atacantes(p, 0, [h1, h2]) == []
    quemar = talisman("Quemar los Templos", 4, [h("desterrar", objetivo={
        "quien": "cualquiera", "zona": "en_juego", "tipos": ["Arma", "Tótem"], "seleccion": "todos"})])
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    q = en_zona(p, 0, quemar, Zona.MANO)
    ay = p.j(1).defensa[0]
    escudo = p._instancia(arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                                          objetivo={"quien": "esta_carta"})]), 1, Zona.MANO)
    p.j(1).mano.append(escudo)
    p.j(1).oros_virtuales = 3
    p.e.activo = 1
    p.ejecutar_jugada(1, Jugada("jugar", escudo, portador=ay))
    p.e.activo = 0
    assert _vale(p, Jugada("jugar", q))


def test_montuhopet_no_se_puede_jugar_sin_otro_aliado_propio():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    m = en_zona(p, 0, _montuhopet(), Zona.MANO)
    assert not any(o.carta is m for o in p.jugadas_legales(0, "vigilia"))  # regla, no decisión
    en_defensa(p, 0, _amyrteos())
    assert any(o.carta is m for o in p.jugadas_legales(0, "vigilia"))


# ══ 11ª partida (simulations/z208nq5yQlSvX7PUFdP6) ══════════════════════════
# ── #68: el "encarecer" del Demoledor no rige en el Cementerio ──────────────
def test_recargo_solo_en_juego():
    p = partida()
    dem = en_zona(p, 1, _demoledor_con_encarecer(), Zona.CEMENTERIO)
    gg = en_zona(p, 0, talisman("Gran Guardian", 2, []), Zona.MANO)
    assert hab.recargo(p, dem, gg) == 0
    p._mover(dem, Zona.DEFENSA)
    assert hab.recargo(p, dem, gg) == 2


def _demoledor_con_encarecer():
    return aliado("Demoledor de Amon", 4, 4, [h("encarecer", cuando="continua", valor=2,
                                                 objetivo={"quien": "oponente", "tipos": ["Talismán"]})])


# ── #55: renovar la protección de un Ramsés robado ─────────────────────────
def test_renueva_la_proteccion_que_puso_el_dueno_anterior():
    ramses = aliado("Ramsés II", 4, 6, [h(
        "otorgarPropiedad", cuando="activada", fase="vigilia", turno="propio", modo="indestructible",
        duracion="hasta_vigilia", costo={"oros": 1}, objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    r = en_defensa(p, 1, ramses)
    p.j(1).oros_virtuales = 1
    p.ejecutar_jugada(1, _activar(r))  # Faraón lo protege
    hab._cambiar_control(p, r, 0)  # Haquika se lo roba
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 1
    assert _vale(p, _activar(r))  # la de Faraón vence en su Vigilia
    p.ejecutar_jugada(0, _activar(r))
    assert not _vale(p, _activar(r))  # ahora sí es mía


# ── #121: no atacar contra Flechas de Lava a la vista, salvo poder anularla ─
def test_no_ataca_contra_un_cancelador_revelado():
    flechas = talisman("Flechas de Lava", 3, [h("cancelarAtaque", fase="declaracion_ataque", turno="oponente",
                                                objetivo={"quien": "propio"})])
    p = partida()
    werin = en_defensa(p, 0, aliado("Werin", 2, 3))
    f = en_zona(p, 1, flechas, Zona.MANO)
    f.revelada = True
    p.j(1).oros_virtuales = 3
    assert YO.elegir_atacantes(p, 0, [werin]) == []
    gg = talisman("Gran Guardian", 2, [h("anular", cuando="oponente_juega",
                                         objetivo={"quien": "oponente", "coste": {"op": "<=", "valor": 3}})])
    en_zona(p, 0, gg, Zona.MANO)
    p.j(0).oros_virtuales = 2
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [werin])] == [werin.uid]


# ══ 12ª partida (simulations/SaJ7Wf3ID9r04O5SZzFB) ══════════════════════════
# ── #26: con Amyrteos en mesa, Ay antes que Jentakus ────────────────────────
def test_ay_con_amyrteos_en_mesa():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    en_defensa(p, 0, _amyrteos())
    ay = en_zona(p, 0, _ay(), Zona.MANO)
    jentakus = en_zona(p, 0, aliado("Jentakus I", 3, 3), Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", ay)) > YO._puntaje(p, 0, Jugada("jugar", jentakus))


# ── #41: Jeroglíficos no se gasta en el Demoledor para salvar a Jentakus ────
def test_no_sacrifica_oro_por_un_coste_4_comun():
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    dem = en_defensa(p, 1, aliado("Demoledor de Amon", 4, 4))
    jentakus = en_defensa(p, 0, aliado("Jentakus I", 3, 2))
    p.atacantes, p.bloqueos = [dem], {dem.uid: jentakus}
    assert not _vale(p, _activar(j, 1))


# ── #78: bloquear a Werin si voy muy atrás o mi bloqueador recupera ─────────
def test_bloquea_al_que_gana_al_morir_si_voy_atras():
    p = partida()
    werin = en_defensa(p, 1, _werin())
    ay = en_defensa(p, 0, aliado("Ay", 2, 6))
    assert YO.elegir_bloqueos(p, 0, [werin], [ay]) == {}
    p.j(0).mazo = p.j(0).mazo[:16]  # 16 contra 39: muy atrás
    assert YO.elegir_bloqueos(p, 0, [werin], [ay]) == {werin.uid: ay}


# ── #111: el Escudo Celestial en juego no justifica el Nudo si no ataco ─────
def test_nudo_no_si_no_voy_a_atacar():
    from test_notas_cartas import _nudo
    flechas = talisman("Flechas de Lava", 3, [h("cancelarAtaque", fase="declaracion_ataque", turno="oponente",
                                                objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    k = next(i for i, x in enumerate(nudo.habilidades) if x.get("accion") == "perderHabilidad")
    p.j(0).oros_virtuales = 2
    werin = en_defensa(p, 0, aliado("Werin", 2, 3))
    escudo = p._instancia(arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano",
                                                          objetivo={"quien": "propio", "zona": "cementerio"})]),
                          0, Zona.MANO)
    p.j(0).mano.append(escudo)
    p.ejecutar_jugada(0, Jugada("jugar_gratis", escudo, portador=werin))
    assert YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])  # va a atacar y barajar
    f = en_zona(p, 1, flechas, Zona.MANO)
    f.revelada = True
    p.j(1).oros_virtuales = 3
    assert not YO._objetivo_util(p, 0, nudo, nudo.habilidades[k])


# ── #122: Ramsés II gana lo bloqueen o no ───────────────────────────────────
def test_juega_y_ataca_con_ramses_si_es_letal():
    ramses = aliado("Ramsés II", 4, 6, [
        {"featureId": "f", "accion": "furia", "cuando": "continua"},
        h("botar", cuando="al_ser_bloqueado", opcional=True, cantidadSegun="fuerza_esta_carta",
          objetivo={"quien": "oponente"}),
    ])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    r = en_zona(p, 0, ramses, Zona.MANO)
    en_zona(p, 0, aliado("Ptolomeo III", 3, 3), Zona.MANO)
    for _ in range(3):
        en_defensa(p, 1, aliado("Muro", 3, 6))
    p.j(1).mazo = p.j(1).mazo[:6]
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert elegida.carta is r
    p.ejecutar_jugada(0, elegida)
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [r])] == [r.uid]


# ── #126: el Rito de Aton busca Mercado Egipcio si gana ─────────────────────
def test_busca_lo_que_gana_antes_que_lo_defensivo():
    flechas = talisman("Flechas de Lava", 3, [h("cancelarAtaque", fase="declaracion_ataque", turno="oponente",
                                                objetivo={"quien": "propio"})])
    mercado = talisman("Mercado Egipcio", 5, [h("botar", cantidadSegun="oros_que_controla",
                                               objetivo={"quien": "oponente"})])
    p = partida()
    f = en_zona(p, 0, flechas, Zona.CEMENTERIO)
    m = en_zona(p, 0, mercado, Zona.CEMENTERIO)
    for _ in range(5):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(0).mazo = p.j(0).mazo[:6]
    for _ in range(2):
        en_defensa(p, 1, aliado("Ramsés", 4, 6))
    p.j(1).mazo = p.j(1).mazo[:1]
    buscar = h("buscar", cuando="activada", zonaDestino="mano",
               objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Talismán"]})
    assert YO.elegir_objetivos(p, 0, [f, m], 1, buscar) == [m]


# ══ Tanda de 3 partidas (8WS7AGcV…, SNmW0Pve…, tsMOIgzU…) ═══════════════════
def _nephre():
    return aliado("Nephre-Ka", 2, 2, [h("destruir", opcional=True,
                                        costo={"desterrarCementerioSegun": "coste_objetivo"},
                                        objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])


# ── #79: con el ataque cancelado, el Mandoble no bota ───────────────────────
def test_ataque_cancelado_no_dispara_al_atacar():
    from test_motor import AtacaTodo
    mandoble = arma("Mandoble De Seth", 3, [h("botar", cuando="al_atacar", cantidad=3, objetivo={"quien": "oponente"})])
    flechas = talisman("Flechas de Lava", 3, [h("cancelarAtaque", fase="declaracion_ataque", turno="oponente",
                                                modo="todo_el_ataque", objetivo={"quien": "propio"})])
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    jentakus = en_defensa(p, 0, aliado("Jentakus I", 3, 3))
    m = p._instancia(mandoble, 0, Zona.MANO)
    p.j(0).mano.append(m)
    p.j(0).oros_virtuales = 3
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, Jugada("jugar", m, portador=jentakus))
    en_zona(p, 1, flechas, Zona.MANO)
    p.j(1).oros_virtuales = 3
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == antes  # no botó: el ataque se canceló


# ── #45: no se redirige lo que no afecta cartas en juego ────────────────────
def test_no_se_redirige_un_efecto_sobre_el_cementerio():
    p = partida()
    rel = talisman("Relámpago Arcano", 1, [h("redirigir", cuando="oponente_juega",
                                             objetivo={"quien": "propio", "zona": "en_juego"})])
    en_zona(p, 1, rel, Zona.MANO)
    p.j(1).oros_virtuales = 1
    muerto = en_zona(p, 1, aliado("Ramsés II", 4, 6), Zona.CEMENTERIO)
    fuente = en_zona(p, 0, talisman("Gran Guardian", 2, []), Zona.DESTIERRO)
    h_destierro = h("desterrar", objetivo={"quien": "oponente", "zona": "cementerio"})
    assert hab.ventana_redireccion(p, 0, fuente, h_destierro, [muerto]) == [muerto]


# ── #137: Bennu no se juega a sí misma desde el Cementerio ──────────────────
def test_bennu_no_se_elige_a_si_misma():
    bennu = aliado("Bennu", 3, 2, [h("jugarDesde", cuando="activada", fase="vigilia", turno="propio",
                                     modo="sin_pagar", costo={"destruirEstaCarta": True},
                                     objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"],
                                               "raza": "Sacerdote", "coste": {"op": "<=", "valor": 3}})],
                   raza="Sacerdote")
    p = partida()
    b = en_defensa(p, 0, bennu)
    p._mover(b, Zona.CEMENTERIO)
    assert hab._candidatos_jugar(p, 0, b, b.habilidades[0]) == []
    otro = en_zona(p, 0, aliado("Kawit", 2, 2, raza="Sacerdote"), Zona.CEMENTERIO)
    assert hab._candidatos_jugar(p, 0, b, b.habilidades[0]) == [otro]


# ── #195: "no puede atacar" solo a Aliados ──────────────────────────────────
def test_restringir_combate_solo_aliados():
    p = partida()
    fuente = en_defensa(p, 0, aliado("Werin", 2, 3))
    en_zona(p, 1, oro("Escarabeo", []), Zona.RESERVA)
    ay = en_defensa(p, 1, aliado("Ay", 2, 3))
    restringe = h("restringirCombate", modo="no_puede_atacar", objetivo={"quien": "oponente", "zona": "en_juego"})
    assert hab.candidatos_validos(p, 0, fuente, restringe) == [ay]


# ── #2: 3 Oros con Akhet, Haquika y Nuh es para quedarse ────────────────────
def test_mano_con_tres_oros_y_cartas_para_bajar_se_queda():
    p = partida()
    p.j(0).mano = [en_zona(p, 0, c, Zona.MANO) for c in (
        ORO, ORO, ORO, _akhet(), _haquika(), _nuh(), arma("Lanza De Osiris", 3, []),
        talisman("Quemar los Templos", 4, []))]
    assert YO.quedarse_mano(p, 0)


# ── #11: Nephre-Ka sin Cementerio para pagar se guarda ──────────────────────
def test_nephre_ka_sin_cementerio_se_guarda():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    n = en_zona(p, 0, _nephre(), Zona.MANO)
    en_defensa(p, 0, aliado("Werin", 2, 3))  # ya tengo mesa
    en_defensa(p, 1, aliado("Kawit", 2, 2))
    assert not _vale(p, Jugada("jugar", n))
    for k in range(2):
        en_zona(p, 0, aliado(f"Caído {k}", 1, 1), Zona.CEMENTERIO)
    assert _vale(p, Jugada("jugar", n))


# ── #24: la Lanza de Ramsés no va en Ay (Guardián) ──────────────────────────
def test_arma_de_ataque_no_va_en_un_guardian():
    lanza = arma("Lanza de Ramsés", 1, [
        h("modificarFuerza", cuando="continua", valor=1, objetivo={"quien": "esta_carta"}),
        h("barajar", cuando="al_hacer_dano", objetivo={"quien": "propio", "zona": "cementerio"}),
    ])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 1
    ay = en_defensa(p, 0, aliado("Ay", 2, 3, [{"featureId": "g", "accion": "guardian", "cuando": "continua"}]))
    l = en_zona(p, 0, lanza, Zona.MANO)
    assert not _vale(p, Jugada("jugar", l, portador=ay))


# ── #55: no sacar a un Aliado rival ya neutralizado ─────────────────────────
def test_no_saca_a_un_aliado_neutralizado():
    qer = aliado("Qer-Her", 3, 2, [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                     objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    q = en_defensa(p, 0, qer)
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3))
    for modo in ("no_puede_atacar", "no_puede_bloquear"):
        jentakus.estados.append({"modo": modo, "duracion": "permanente", "fuente": 0, "turno": 1, "creador": 0})
    assert not YO._objetivo_util(p, 0, q, q.habilidades[0])


# ── #69: el Demoledor ataca si no hay bloqueadores ──────────────────────────
def test_demoledor_ataca_sin_bloqueadores():
    p = partida()
    d = en_defensa(p, 0, _demoledor())
    assert [x.uid for x in YO.elegir_atacantes(p, 0, [d])] == [d.uid]


# ── #91: no bloquear a Ramsés II (bloquearlo hace botar su fuerza) ──────────
def test_no_bloquea_a_ramses():
    ramses = aliado("Ramsés II", 4, 6, [
        {"featureId": "i", "accion": "indestructible", "cuando": "continua"},
        h("botar", cuando="al_ser_bloqueado", opcional=True, cantidadSegun="fuerza_esta_carta",
          objetivo={"quien": "oponente"}),
    ])
    p = partida()
    r = en_defensa(p, 1, ramses)
    haquika = en_defensa(p, 0, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible",
                                                          "cuando": "continua"}]))
    assert YO.elegir_bloqueos(p, 0, [r], [haquika]) == {}


# ── #34: no gastar Jeroglíficos si el intercambio es parejo ─────────────────
def test_no_rescata_un_intercambio_parejo():
    from test_notas_cartas import _jeroglificos
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    j = en_zona(p, 0, _jeroglificos(), Zona.RESERVA)
    djoser = en_defensa(p, 1, aliado("Djoser", 3, 3))
    djed = en_defensa(p, 0, _djedefhor())
    p.atacantes, p.bloqueos = [djoser], {djoser.uid: djed}
    assert not _vale(p, _activar(j, 1))


# ── #73: Haquika roba lo que más aporta (Nephre-Ka con su Lanza) ────────────
def test_haquika_roba_lo_que_mas_aporta():
    lanza = arma("Lanza de Ramsés", 1, [h("barajar", cuando="al_hacer_dano",
                                          objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    jentakus = en_defensa(p, 1, aliado("Jentakus I", 3, 3, [h("buscar", zonaDestino="mano",
                                                                objetivo={"quien": "propio", "zona": "mazo"})]))
    nephre = en_defensa(p, 1, aliado("Nephre-Ka", 2, 3))
    l = p._instancia(lanza, 1, Zona.MANO)
    p.j(1).mano.append(l)
    p.j(1).oros_virtuales = 1
    p.e.activo, p.e.fase = 1, "vigilia"
    p.ejecutar_jugada(1, Jugada("jugar", l, portador=nephre))
    robar = h("ganarControl", objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})
    assert YO.elegir_objetivos(p, 0, [jentakus, nephre], 1, robar) == [nephre]


# ── #80: Neferite I cuenta lo que destierra al activarla ────────────────────
def test_neferite_vale_por_lo_que_destierra():
    neferite = aliado("Neferite I", 3, 2, [h("desterrar", cuando="activada", fase="vigilia", turno="propio",
                                             costo={"desterrarCementerioSegun": "coste_objetivo"},
                                             objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    n = en_zona(p, 0, neferite, Zona.MANO)
    djoser = en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    for k in range(4):
        en_zona(p, 0, aliado(f"Caído {k}", 1, 1), Zona.CEMENTERIO)
    en_defensa(p, 1, _demoledor())
    assert YO._puntaje(p, 0, Jugada("jugar", n)) > YO._puntaje(p, 0, Jugada("jugar", djoser))


# ── #29: no jugar a Ramsés contra un Abismo a la vista ──────────────────────
def test_no_juega_contra_un_anulador_a_la_vista():
    abismo = Carta("Abismo", "Abismo", Tipo.TOTEM, 2, 0, "", "x", (
        h("anular", cuando="activada", costo={"destruirEstaCarta": True},
          objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]}),), True)
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 4
    r = en_zona(p, 0, _ramses_completo(), Zona.MANO)
    assert _vale(p, Jugada("jugar", r))
    a = en_zona(p, 1, abismo, Zona.APOYO)
    assert _vale(p, Jugada("jugar", r))  # #115: sola en la mano, se juega igual
    carnada = en_zona(p, 0, aliado("Jentakus I", 3, 6), Zona.MANO)  # importante, pero menos
    assert not _vale(p, Jugada("jugar", r))  # primero la carnada, que gasta el Abismo
    assert _vale(p, Jugada("jugar", carnada))


# ── #19: Jentakus busca lo que arma combo con la mesa ───────────────────────
def test_jentakus_busca_ay_si_tengo_amyrteos():
    p = partida()
    en_defensa(p, 0, _amyrteos())
    ramses = en_zona(p, 0, aliado("Ramsés II", 4, 6), Zona.MAZO)
    ay = en_zona(p, 0, _ay(), Zona.MAZO)
    buscar = h("buscar", zonaDestino="mano", objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"]})
    assert YO.elegir_objetivos(p, 0, [ramses, ay], 1, buscar) == [ay]


# ── #80: Escudo Miliciano en Djoser para frenar al Demoledor ────────────────
def test_arma_que_vuelve_al_portador_un_bloqueador_que_mata():
    escudo = arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                            objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    djoser = en_defensa(p, 0, aliado("Djoser", 3, 3))
    e = en_zona(p, 0, escudo, Zona.MANO)
    otro = en_zona(p, 0, aliado("Jentakus I", 3, 3), Zona.MANO)
    con = Jugada("jugar", e, portador=djoser)
    assert YO._puntaje(p, 0, Jugada("jugar", otro)) > YO._puntaje(p, 0, con) - 1  # sin amenaza, parejo
    en_defensa(p, 1, _demoledor())  # fuerza 4: Djoser (3) solo no lo frena; con +3, sí
    assert YO._puntaje(p, 0, con) > YO._puntaje(p, 0, Jugada("jugar", otro))


def test_nephre_ka_sin_efecto_se_juega_para_hacer_mesa_o_para_ay():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    n = en_zona(p, 0, _nephre(), Zona.MANO)
    en_defensa(p, 0, aliado("Kawit", 2, 2))  # ya tengo mesa
    rival = en_defensa(p, 1, aliado("Werin", 2, 3))
    assert not _vale(p, Jugada("jugar", n))
    p._mover(p.j(0).aliados[0], Zona.CEMENTERIO)
    p.j(0).cementerio.clear()
    assert _vale(p, Jugada("jugar", n))  # sin mesa y el rival con Aliados
    en_defensa(p, 0, aliado("Kawit", 2, 2))
    assert not _vale(p, Jugada("jugar", n))
    en_zona(p, 0, _ay(), Zona.MANO)
    assert _vale(p, Jugada("jugar", n))  # para desterrarlo con Ay y robar


# ══ Decisiones situacionales (aclaraciones del dueño) ══════════════════════
def _ramses_completo():
    return aliado("Ramsés II", 4, 6, [
        {"featureId": "f", "accion": "furia", "cuando": "continua"},
        h("botar", cuando="al_ser_bloqueado", opcional=True, cantidadSegun="fuerza_esta_carta",
          objetivo={"quien": "oponente"}),
    ], raza="Faraón")


def test_bloquea_a_ramses_si_tiene_tocador():
    tocador = oro("Tocador", [h("botar", cuando="al_botar_por_oponente", cantidadSegun="botadas",
                                objetivo={"quien": "oponente"})])
    p = partida()
    r = en_defensa(p, 1, _ramses_completo())
    haquika = en_defensa(p, 0, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible",
                                                          "cuando": "continua"}]))
    assert YO.elegir_bloqueos(p, 0, [r], [haquika]) == {}
    en_zona(p, 0, tocador, Zona.RESERVA)
    # Con el castillo rival lleno, botarle 6 no lo deja a tiro: no bloquea.
    assert YO.elegir_bloqueos(p, 0, [r], [haquika]) == {}
    p.j(1).mazo = p.j(1).mazo[:14]  # 14 − 6 = 8: con 2 de ataque + lo que bota, a tiro en 2 turnos
    for _ in range(2):
        en_defensa(p, 0, aliado("Kawit", 2, 2))
    assert YO.elegir_bloqueos(p, 0, [r], [haquika]) == {r.uid: haquika}


def test_anula_por_importancia_no_por_coste():
    abismo = talisman("Abismo", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    djed = _djedefhor()  # coste 3, roba 2
    p = partida()
    j = en_zona(p, 0, djed, Zona.DEFENSA)
    opciones = [(en_zona(p, 1, abismo, Zona.MANO), abismo.habilidades[0])]
    while len(p.j(0).mano) < 6:
        en_zona(p, 0, ORO, Zona.MANO)
    assert YO.anular(p, 1, j, opciones) is None  # con mano llena, robar 2 no es tanto
    p.j(0).mano.clear()
    assert YO.anular(p, 1, j, opciones) == 0  # con poca mano, negarle cartas sí
    ramses = en_zona(p, 0, _ramses_completo(), Zona.DEFENSA)
    assert YO.anular(p, 1, ramses, opciones) == 0
    soldado = en_zona(p, 0, aliado("Soldado", 3, 2), Zona.DEFENSA)
    assert YO.anular(p, 1, soldado, opciones) is None  # coste 3 pero sin importancia


def test_jentakus_busca_segun_el_plan():
    ptolomeo = aliado("Ptolomeo II", 3, 2, [h("prevenir", cuando="activada", modo="afectada",
                                              objetivo={"quien": "propio"})], raza="Faraón")
    djoser = aliado("Djoser", 3, 3, [h("modificarFuerza", cuando="continua", valor=2, valorPorCada="arma_portada",
                                       objetivo={"quien": "esta_carta"})], raza="Faraón")
    buscar = h("buscar", zonaDestino="mano", objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"]})
    p = partida()
    r = en_zona(p, 0, _ramses_completo(), Zona.MAZO)
    pt = en_zona(p, 0, ptolomeo, Zona.MAZO)
    dj = en_zona(p, 0, djoser, Zona.MAZO)
    cands = [r, pt, dj]
    assert YO.elegir_objetivos(p, 0, cands, 1, buscar) == [r]  # agresivo: Ramsés
    for _ in range(2):
        en_defensa(p, 1, aliado("Muro", 3, 5))
    assert YO.elegir_objetivos(p, 0, cands, 1, buscar) == [pt]  # me superan: control con Ptolomeo II
    p.j(1).defensa.clear()
    for _ in range(2):
        en_zona(p, 0, arma("Lanza", 1, []), Zona.MANO)
    assert YO.elegir_objetivos(p, 0, cands, 1, buscar) == [dj]  # con Armas: Djoser


# ══ Partida pQTJhm3zbkRLPh2CWJvS ════════════════════════════════════════════
def _resplandor():
    return talisman("Resplandor de Heka", 2, [h(
        "perderHabilidad", cuando="oponente_juega", objetivo={"quien": "oponente", "zona": "en_juego"},
        luego=[{"accion": "robar", "relacion": "si_se_cumplio", "momento": "fase_final", "cantidad": 1,
                "objetivo": {"quien": "propio", "zona": "mazo", "seleccion": "todos", "referencia": "copias"}}],
    )])


# ── #57: Resplandor de Heka frena a Haquika antes de que robe ───────────────
def test_resplandor_responde_antes_del_al_entrar():
    from test_notas_cartas import jugar
    p = partida()
    nephre = en_defensa(p, 1, aliado("Nephre-Ka", 2, 5))
    r = en_zona(p, 1, _resplandor(), Zona.MANO)
    p.j(1).oros_virtuales = 2
    haquika = jugar(p, 0, _haquika())
    assert nephre.controlador == 1  # no se lo robaron
    assert r.zona == Zona.CEMENTERIO and haquika.sin_habilidad_hasta is not None
    assert len(p.pendientes_final) == 1  # roba en la Fase Final


# ── #82: también contra Djedefhor (robar 2) si el rival tiene poca mano ─────
def test_resplandor_contra_djedefhor_con_poca_mano():
    from test_notas_cartas import jugar
    p = partida()
    r = en_zona(p, 1, _resplandor(), Zona.MANO)
    p.j(1).oros_virtuales = 2
    p.j(0).mano.clear()
    mano = len(p.j(0).mano)
    jugar(p, 0, _djedefhor())
    assert r.zona != Zona.MANO and len(p.j(0).mano) == mano  # no robó


# ── #51: guardar los Oros de Resplandor en vez de una jugada floja ──────────
def test_guarda_oros_para_resplandor():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2  # 3 Oros: Nephre-Ka (2) dejaría 1, no alcanza Resplandor (2)
    en_zona(p, 0, _resplandor(), Zona.MANO)
    n = en_zona(p, 0, _nephre(), Zona.MANO)
    en_defensa(p, 1, aliado("Pili", 3, 2))  # sin Cementerio: Nephre-Ka entraría sin efecto
    jugadas = [Jugada("jugar", n), Jugada("pasar")]
    assert YO.elegir_jugada(p, 0, jugadas).tipo == "pasar"


# ── #22: Akhet no saca a Amyrteos ───────────────────────────────────────────
def test_akhet_no_saca_a_amyrteos():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    a = en_zona(p, 0, _akhet(), Zona.MANO)
    en_defensa(p, 1, _amyrteos())
    assert not _vale(p, Jugada("jugar", a))
    en_defensa(p, 1, aliado("Nephre-Ka", 2, 2))  # #35: ya usó su habilidad, no vale un Akhet
    assert not _vale(p, Jugada("jugar", a))
    en_defensa(p, 1, _ay())  # roba cada turno: sí
    assert _vale(p, Jugada("jugar", a))


# ── #121: Akhet saca al portador y se lleva el Arma ─────────────────────────
def test_akhet_saca_al_portador_con_su_arma():
    escudo = arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                            objetivo={"quien": "esta_carta"})])
    p = partida()
    montu = en_defensa(p, 1, aliado("Montuhopet II", 1, 3))
    e = p._instancia(escudo, 1, Zona.MANO)
    p.j(1).mano.append(e)
    p.j(1).oros_virtuales = 3
    p.e.activo, p.e.fase = 1, "vigilia"
    p.ejecutar_jugada(1, Jugada("jugar", e, portador=montu))
    mover = h("mover", zonaDestino="mazo_fondo",
              objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"]})
    assert YO.elegir_objetivos(p, 0, [e, montu], 1, mover) == [montu]


# ── #64: Biblioteca Eterna con 5 Oros y la mano corta ───────────────────────
def test_biblioteca_con_mano_corta():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"desterrarEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    b = en_zona(p, 0, biblioteca, Zona.RESERVA)
    for _ in range(3):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(0).mano = [en_zona(p, 0, aliado(f"Carta {k}", 3, 3), Zona.MANO) for k in range(7)]
    assert not _vale(p, _activar(b))  # 5 Oros y mano llena
    p.j(0).mano = p.j(0).mano[:4]
    assert not _vale(p, _activar(b))  # mano corta, pero primero juego lo que tengo
    p.j(0).mano = [en_zona(p, 0, aliado(f"Cara {k}", 9, 9), Zona.MANO) for k in range(4)]
    assert _vale(p, _activar(b))  # mano corta, nada que jugar ni Oro: robar


# ── #137: rematar con 2 Papiros + Montuhopet sin bloqueadores ───────────────
def test_remata_con_papiros_y_combate_sin_bloqueadores():
    pap = _papiros()
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    en_defensa(p, 0, aliado("Montuhopet II", 1, 3))
    a = en_zona(p, 0, pap, Zona.RESERVA)
    en_zona(p, 0, _papiros(), Zona.RESERVA)
    for _ in range(3):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(1).mazo = p.j(1).mazo[:9]
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "guerra_talismanes"))
    assert elegida.tipo == "activar" and elegida.carta.nombre == "Papiros de Lahun"


def test_qer_her_no_se_destruye_por_un_objetivo_flojo():
    qer = aliado("Qer-Her", 3, 2, [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                     objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    q = en_defensa(p, 0, qer)
    amy = en_defensa(p, 1, _amyrteos())
    p.atacantes, p.bloqueos = [amy], {}
    assert not YO._objetivo_util(p, 0, q, q.habilidades[0])  # le daría un Oro al rival
    ramses = en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    p.atacantes = [ramses]
    assert YO._objetivo_util(p, 0, q, q.habilidades[0])  # evitar 6 de daño sí


def test_no_quita_la_habilidad_que_ya_se_uso_al_entrar():
    adios = talisman("Adiós Belleza", 1, [h("perderHabilidad", objetivo={"quien": "cualquiera", "zona": "en_juego"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    a = en_zona(p, 0, adios, Zona.MANO)
    p.j(0).oros_virtuales = 1
    en_defensa(p, 1, aliado("Kawit", 2, 2, [h("buscar", zonaDestino="mano",
                                              objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]})]))
    assert not _vale(p, Jugada("jugar", a))
    en_defensa(p, 1, _ay())
    assert not _vale(p, Jugada("jugar", a))  # #87: solo se activa pagando; mejor guardarla
    en_defensa(p, 1, _demoledor())
    assert _vale(p, Jugada("jugar", a))  # obliga a bloquear cada vez que ataca


def test_importancia_por_impacto_en_mesa_no_por_coste():
    abismo = talisman("Abismo", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    p = partida()
    en_defensa(p, 1, aliado("Ramsés II", 4, 6))
    opciones = [(en_zona(p, 1, abismo, Zona.MANO), abismo.habilidades[0])]
    while len(p.j(0).mano) < 6:
        en_zona(p, 0, ORO, Zona.MANO)
    barata = en_zona(p, 0, aliado("Ladrona", 1, 1, [h("ganarControl", duracion="mientras_en_juego",
                                                       objetivo={"quien": "oponente", "tipos": ["Aliado"]})]),
                     Zona.DEFENSA)
    cara = en_zona(p, 0, aliado("Coloso de adorno", 6, 2), Zona.DEFENSA)
    assert YO.anular(p, 1, barata, opciones) == 0  # coste 1, pero me roba a Ramsés
    assert YO.anular(p, 1, cara, opciones) is None  # coste 6, pero no cambia la mesa


def test_haquika_sin_habilidad_no_devuelve_el_aliado_robado():
    from test_notas_cartas import jugar
    p = partida()
    nephre = en_defensa(p, 1, aliado("Nephre-Ka", 2, 5))
    haquika = jugar(p, 0, _haquika())
    assert nephre.controlador == 0  # lo robó
    # Después le quitan la habilidad a Haquika (Cleopatra, Takelot, un Talismán…).
    silencio = talisman("Silencio", 1, [h("perderHabilidad", objetivo={"quien": "disparadora"})])
    s_inst = en_zona(p, 1, silencio, Zona.MANO)
    p.ctx_disparadora = haquika
    hab.resolver(p, 1, s_inst, silencio.habilidades[0])
    p.ctx_disparadora = None
    assert haquika.sin_habilidad_hasta is not None
    assert nephre.controlador == 0  # #102: lo robado no vuelve por perder la habilidad


# ══ Partida U2VmaDlk89UQ8CjNd1cb ════════════════════════════════════════════
# ── #8: al comienzo, Resplandor contra Kawit (acelera un Oro y roba) ────────
def test_responde_a_kawit_al_comienzo():
    kawit = aliado("Kawit", 2, 2, [h("buscar", zonaDestino="mano",
                                     objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]},
                                     luego=[{"accion": "robar", "relacion": "si_se_cumplio", "cantidad": 1,
                                             "objetivo": {"quien": "propio"}}])])
    p = partida()
    k = en_zona(p, 0, kawit, Zona.DEFENSA)
    opciones = [(en_zona(p, 1, _resplandor(), Zona.MANO), _resplandor().habilidades[0])]
    assert YO.responder(p, 1, k, opciones) == 0  # con 1 Oro en juego, acelerar uno pesa
    for _ in range(5):
        en_zona(p, 0, ORO, Zona.RESERVA)
    for _ in range(6):
        en_zona(p, 0, aliado("Carta", 2, 2), Zona.MANO)
    assert YO.responder(p, 1, k, opciones) is None  # ya con 6 Oros y mano llena, no tanto


# ── #71: la Biblioteca Eterna antes que las demás jugadas ───────────────────
def test_resplandor_prioriza_entrada_y_guarda_respuesta_para_haquika():
    """# último reporte: no se gasta contra Werin y queda para Haquika."""
    p = partida()
    resplandor = _resplandor()
    opciones = [(en_zona(p, 1, resplandor, Zona.MANO), resplandor.habilidades[0])]

    # Werin solo aporta al salir: silenciarlo al entrar no cambia esta jugada.
    werin = en_defensa(p, 0, aliado(
        "Werin el Poseído", 2, 3,
        [h("buscar", cuando="al_salir_del_juego", objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]})],
    ))
    assert YO.responder(p, 1, werin, opciones) is None

    # Haquika sí toma de inmediato el mejor Aliado rival; ahí Resplandor vale.
    en_defensa(p, 1, aliado("Nephre-Ka", 2, 5))
    haquika = en_defensa(p, 0, _haquika())
    assert YO.responder(p, 1, haquika, opciones) == 0


def test_guarda_gran_guardian_si_resplandor_corta_a_kawit():
    """# última partida: la anulación no debe impedir la ventana de Resplandor."""
    p = partida()
    kawit = en_defensa(p, 0, _kawit())
    gran = talisman("Gran Guardian", 2, [h(
        "anular", cuando="oponente_juega", objetivo={"quien": "oponente"},
    )])
    en_zona(p, 1, gran, Zona.MANO)
    en_zona(p, 1, _resplandor(), Zona.MANO)
    p.j(1).oros_virtuales = 2

    # La anulación se guarda y Kawit llega a la ventana de respuesta.
    assert not hab.ventana_anulacion(p, 0, kawit)
    hab.ventana_respuesta(p, kawit)
    assert any(x.carta is gran for x in p.j(1).mano)
    assert kawit.sin_habilidad_hasta is not None


def test_biblioteca_primero_en_la_vigilia():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"desterrarEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    b = en_zona(p, 0, biblioteca, Zona.RESERVA)
    for _ in range(4):
        en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert elegida.tipo == "activar" and elegida.carta is b


# ── #81 / #97: bloquear con Amyrteos ────────────────────────────────────────
def test_bloquea_con_amyrteos():
    p = partida()
    amy = en_defensa(p, 0, _amyrteos())
    kawit = en_defensa(p, 1, aliado("Kawit", 2, 2))
    assert YO.elegir_bloqueos(p, 0, [kawit], [amy]) == {kawit.uid: amy}


# ── #87: Adiós Belleza en combate, al Haquika indestructible que bloquea ────
def test_adios_belleza_en_combate_al_indestructible():
    adios = talisman("Adiós Belleza", 1, [h("perderHabilidad", objetivo={"quien": "cualquiera", "zona": "en_juego"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    a = en_zona(p, 0, adios, Zona.MANO)
    p.j(0).oros_virtuales = 1
    mio = en_defensa(p, 0, aliado("Amyrteos con Escudo", 2, 4))
    haquika = en_defensa(p, 1, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible",
                                                          "cuando": "continua"}]))
    p.atacantes, p.bloqueos = [mio], {mio.uid: haquika}
    assert YO._objetivo_util(p, 0, a, a.habilidades[0])


# ── #120: Ramsés paga 1 Oro en vez de descartar con la mano corta ───────────
def test_ramses_paga_oro_con_la_mano_corta():
    ramses = aliado("Ramsés II", 4, 6, [h(
        "otorgarPropiedad", cuando="activada", fase="vigilia", turno="propio", modo="indestructible",
        duracion="hasta_vigilia", costo={"descartar": 1}, costoAlternativo={"oros": 1},
        objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    r = en_defensa(p, 0, ramses)
    p.j(0).mano = [en_zona(p, 0, aliado("Regresa el Dios", 1, 1), Zona.MANO)]
    p.j(0).oros_virtuales = 1
    p.ejecutar_jugada(0, _activar(r))
    assert len(p.j(0).mano) == 1  # no descartó: pagó el Oro


# ── #129: Amyrteos trae Papiros si el rival está corto ──────────────────────
def test_amyrteos_trae_un_oro_que_bota_si_el_rival_esta_corto():
    p = partida()
    gf = en_zona(p, 0, oro("Grandes Faraones", [h("botar", cuando="activada", cantidad=1,
                                                  objetivo={"quien": "ambos"})]), Zona.MAZO)
    pap = en_zona(p, 0, _papiros(), Zona.MAZO)
    poner = h("ponerEnJuego", cuando="al_salir_del_juego", zonaDestino="reserva_oro",
              objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]})
    p.j(1).mazo = p.j(1).mazo[:8]
    assert YO.elegir_objetivos(p, 0, [gf, pap], 1, poner) == [pap]


def test_cambiar_fuerza_solo_a_aliados():
    p = partida()
    t = en_zona(p, 0, _toro(), Zona.RESERVA)
    abismo = en_zona(p, 1, Carta("Abismo", "Abismo", Tipo.TOTEM, 2, 0, "", "x", (), True), Zona.APOYO)
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    assert hab.candidatos_validos(p, 0, t, t.habilidades[0]) == [werin]


def test_haquika_sin_habilidad_al_salir_no_devuelve_el_aliado():
    from test_notas_cartas import jugar
    p = partida()
    nephre = en_defensa(p, 1, aliado("Nephre-Ka", 2, 5))
    haquika = jugar(p, 0, _haquika())
    assert nephre.controlador == 0
    # Con su habilidad: al salir devuelve lo robado.
    otra = en_defensa(p, 1, aliado("Kawit", 2, 2))
    h2 = jugar(p, 0, _haquika())
    if otra.controlador == 0:
        p.destruir(h2)
        assert otra.controlador == 1
    # Sin habilidad (Cleopatra de forma continua) y destruida: no devuelve.
    haquika.sin_habilidad_hasta = "continua"
    p.destruir(haquika)
    hab.revisar_controles(p)
    assert nephre.controlador == 0


# ══ Partida k22vqTLbpYdvV8UAxzMc ════════════════════════════════════════════
def _kawit():
    return aliado("Kawit", 2, 2, [h("buscar", zonaDestino="mano",
                                    objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]},
                                    luego=[{"accion": "robar", "relacion": "si_se_cumplio", "cantidad": 1,
                                            "objetivo": {"quien": "propio"}}])])


# ── #35: Kawit antes que un Akhet sin buen objetivo ─────────────────────────
def test_kawit_antes_que_akhet_sin_objetivo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    a = en_zona(p, 0, _akhet(), Zona.MANO)
    k = en_zona(p, 0, _kawit(), Zona.MANO)
    en_defensa(p, 1, aliado("Nephre-Ka", 2, 2))
    en_defensa(p, 1, _amyrteos())
    elegida = YO.elegir_jugada(p, 0, [Jugada("jugar", a), Jugada("jugar", k), Jugada("pasar")])
    assert elegida.carta is k


# ── #40: con la mano corta, jugar la Biblioteca Eterna ──────────────────────
def test_juega_la_biblioteca_con_la_mano_corta():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"desterrarEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", costo={"pagarEstaCarta": True},
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).mano.clear()
    b = en_zona(p, 0, biblioteca, Zona.MANO)
    e = en_zona(p, 0, escarabeo, Zona.MANO)
    en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    assert YO.elegir_jugada(p, 0, [Jugada("oro", e), Jugada("oro", b)]).carta is b


# ── #93: Abismo anula a Cleopatra VII ───────────────────────────────────────
def test_anula_a_cleopatra():
    cleo = aliado("Cleopatra VII", 4, 3, [h("perderHabilidad", duracion="mientras_en_juego",
                                            objetivo={"quien": "cualquiera", "tipos": ["Aliado"],
                                                      "seleccion": "todos", "nombrarRaza": True})])
    abismo = talisman("Abismo", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    p = partida()
    en_defensa(p, 1, _djedefhor())
    en_defensa(p, 1, _kawit())
    c = en_zona(p, 0, cleo, Zona.DEFENSA)
    opciones = [(en_zona(p, 1, abismo, Zona.MANO), abismo.habilidades[0])]
    assert YO.anular(p, 1, c, opciones) == 0


# ── #139: rematar con 2 Papiros + Jinetes del Cementerio + combate ──────────
def test_remata_con_papiros_jinetes_y_combate():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    cleo = en_defensa(p, 0, aliado("Cleopatra VII", 4, 6))
    takelot = en_defensa(p, 1, aliado("Takelot", 3, 1))
    p.atacantes, p.bloqueos = [cleo], {cleo.uid: takelot}
    for _ in range(2):
        en_zona(p, 0, _papiros(), Zona.RESERVA)
    for _ in range(3):
        en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 0, _jinetes_editor(), Zona.CEMENTERIO)
    p.j(1).mazo = p.j(1).mazo[:10]
    from myl_sim.jugadores import _botar_posible
    assert _botar_posible(p, 0) >= 10  # 3 + 3 + 3 + 5 de combate
    elegida = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "guerra_talismanes"))
    assert elegida.tipo != "pasar"


def test_cleopatra_se_anula_salvo_que_venga_algo_peor_a_la_vista():
    cleo = aliado("Cleopatra VII", 4, 3, [h("perderHabilidad", duracion="mientras_en_juego",
                                            objetivo={"quien": "cualquiera", "tipos": ["Aliado"],
                                                      "seleccion": "todos", "nombrarRaza": True})])
    abismo = talisman("Abismo", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    p = partida()
    c = en_zona(p, 0, cleo, Zona.DEFENSA)
    en_zona(p, 1, aliado("Rival", 2, 2, raza="Faraón"), Zona.MAZO)  # hay una raza que le conviene nombrar
    opciones = [(en_zona(p, 1, abismo, Zona.MANO), abismo.habilidades[0])]
    assert YO.anular(p, 1, c, opciones) == 0  # aunque mi mesa esté vacía
    ladrona = en_zona(p, 0, aliado("Ladrona", 1, 1, [h("ganarControl", duracion="mientras_en_juego",
                                                      objetivo={"quien": "oponente", "tipos": ["Aliado"]})]), Zona.MANO)
    ladrona.revelada = True
    for _ in range(3):
        en_defensa(p, 1, aliado("Ramsés II", 4, 6, [h("botar", cuando="al_ser_bloqueado", objetivo={"quien": "oponente"})]))
    assert YO.anular(p, 1, c, opciones) is None  # se guarda para lo que viene, que es peor


def test_con_cleopatra_el_demoledor_no_ataca_al_entrar():
    from test_notas_cartas import jugar

    class NombraSacerdote(Heuristico):
        def elegir_raza(self, p, yo, razas, h):
            return "Sacerdote"

    cleo = aliado("Cleopatra VII", 4, 3, [h(
        "perderHabilidad", duracion="mientras_en_juego",
        objetivo={"quien": "cualquiera", "zona": "en_juego", "tipos": ["Aliado"], "seleccion": "todos",
                  "nombrarRaza": True})], raza="Faraón")
    demoledor = aliado("Demoledor de Amon", 4, 4, [{"featureId": "f", "accion": "furia", "cuando": "continua"}],
                       raza="Sacerdote")
    p = partida(jugadores=(NombraSacerdote(1), Heuristico(2)))
    jugar(p, 0, cleo)
    d = jugar(p, 1, demoledor)
    assert not d.listo  # sin Furia: no ataca el turno que entra


def test_ptolomeo_iii_antes_que_los_demas_faraones():
    ptolomeo = aliado("Ptolomeo III", 3, 3, [
        h("botar", cuando="propia_entra", disparoTipos=["Aliado"], disparoRaza="Faraón", cantidad=1,
          objetivo={"quien": "oponente"}),
        h("botar", cuando="propia_sale", disparoTipos=["Aliado"], disparoRaza="Faraón", cantidad=1,
          objetivo={"quien": "oponente"}),
    ], raza="Faraón")
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    pt = en_zona(p, 0, ptolomeo, Zona.MANO)
    nephre = en_zona(p, 0, aliado("Nephre-Ka", 2, 2, raza="Faraón"), Zona.MANO)
    montu = en_zona(p, 0, aliado("Montuhopet II", 1, 3, raza="Faraón"), Zona.MANO)
    jugadas = [Jugada("jugar", x) for x in (nephre, montu, pt)]
    assert YO.elegir_jugada(p, 0, jugadas).carta is pt


# ══ Partida fLvHGd4Lc49OGErBh6ZB ════════════════════════════════════════════
def _cleopatra():
    return aliado("Cleopatra VII", 4, 3, [h(
        "perderHabilidad", duracion="mientras_en_juego",
        objetivo={"quien": "cualquiera", "zona": "en_juego", "tipos": ["Aliado"], "seleccion": "todos",
                  "nombrarRaza": True})], raza="Faraón")


class _NombraSacerdote(Heuristico):
    def elegir_raza(self, p, yo, razas, h):
        return "Sacerdote"


# ── #107: muerta Cleopatra, Djedefhor recupera su habilidad ─────────────────
def test_muerta_cleopatra_vuelven_las_habilidades():
    from test_notas_cartas import jugar
    djed = aliado("Djedefhor", 3, 3, [h("barajar", cuando="al_salir_del_juego", opcional=True,
                                        objetivo={"quien": "propio", "zona": "cementerio"})], raza="Sacerdote")
    p = partida(jugadores=(_NombraSacerdote(1), Heuristico(2)))
    d = en_defensa(p, 1, djed)
    c = jugar(p, 0, _cleopatra())
    assert d.sin_habilidad_hasta is not None
    p.destruir(c)
    assert d.sin_habilidad_hasta is None


# ── #63: Akhet a Cleopatra antes que Mercado Egipcio ────────────────────────
def test_akhet_a_cleopatra():
    from test_notas_cartas import jugar
    mercado = talisman("Mercado Egipcio", 5, [h("botar", cantidadSegun="oros_que_controla",
                                               objetivo={"quien": "oponente"})])
    p = partida(jugadores=(Heuristico(1), _NombraSacerdote(2)))
    en_defensa(p, 0, aliado("Haquika", 3, 2, raza="Sacerdote"))
    en_defensa(p, 0, aliado("Nephre-Ka", 2, 2, raza="Sacerdote"))
    jugar(p, 1, _cleopatra())
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    a = en_zona(p, 0, _akhet(), Zona.MANO)
    m = en_zona(p, 0, mercado, Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", a)) > YO._puntaje(p, 0, Jugada("jugar", m))


# ── #100: Montuhopet sube a Amyrteos antes que a Nephre-Ka ──────────────────
def test_montuhopet_prefiere_amyrteos():
    p = partida()
    amy = en_defensa(p, 0, _amyrteos())
    nephre = en_defensa(p, 0, _nephre())
    en_defensa(p, 1, _djedefhor())
    for k in range(3):
        en_zona(p, 0, aliado(f"Caído {k}", 1, 1), Zona.CEMENTERIO)
    m = en_zona(p, 0, _montuhopet(), Zona.DEFENSA)
    assert YO.elegir_objetivos(p, 0, [amy, nephre], 1, m.habilidades[0]) == [amy]


# ── #103: Cleopatra no ataca para cambiarse por Djedefhor ───────────────────
def test_cleopatra_no_se_cambia_por_djedefhor():
    p = partida()
    cleo = en_defensa(p, 0, _cleopatra())
    en_defensa(p, 1, _djedefhor())
    assert YO.elegir_atacantes(p, 0, [cleo]) == []


# ── #135: con 2 atacantes de sobra, atacar con todos ────────────────────────
def test_ataca_con_todos_si_sobran_atacantes():
    p = partida()
    mios = [en_defensa(p, 0, aliado(n, 2, f)) for n, f in (("Haquika", 2), ("Pili", 2), ("Djedefhor", 3), ("Demoledor", 4))]
    en_defensa(p, 1, aliado("Montuhopet II", 1, 6))
    assert len(YO.elegir_atacantes(p, 0, mios)) == 4


# ── #103 / #116: el atacante también juega en la Declaración de Ataque ──────
def test_el_atacante_juega_en_la_declaracion_de_ataque():
    escudo = arma("Escudo Miliciano", 3, [
        h("modificarFuerza", cuando="continua", valor=3, objetivo={"quien": "esta_carta"}),
        h("jugarDesde", cuando="activada", fase="declaracion_ataque", turno="cualquiera", modo="sin_pagar",
          costo={"oros": 2}, zonaActivacion="cementerio", objetivo={"quien": "esta_carta", "zona": "cementerio"}),
    ])
    p = partida()
    p.e.activo = 0
    atacante = en_defensa(p, 0, aliado("Cleopatra VII", 4, 3))
    e = en_zona(p, 0, escudo, Zona.CEMENTERIO)
    p.j(0).oros_virtuales = 2
    p.atacantes = [atacante]
    p.e.fase = "declaracion_ataque"
    assert any(o.carta is e for o in p.jugadas_legales(0, "declaracion_ataque"))


def test_resplandor_se_guarda_para_haquika_no_para_werin():
    p = partida()
    en_defensa(p, 1, aliado("Nephre-Ka", 2, 2))
    opciones = [(en_zona(p, 1, _resplandor(), Zona.MANO), _resplandor().habilidades[0])]
    while len(p.j(0).mano) < 5:
        en_zona(p, 0, ORO, Zona.MANO)
    werin = en_zona(p, 0, _werin(), Zona.DEFENSA)
    assert YO.responder(p, 1, werin, opciones) is None  # su habilidad útil es al salir: no vale
    haquika = en_zona(p, 0, _haquika(), Zona.DEFENSA)
    assert YO.responder(p, 1, haquika, opciones) == 0  # me roba un Aliado: sí


# ══ Partida yVzdThstf34roFnBJD0n ════════════════════════════════════════════
# ── T3: para armar mesa, Amyrteos antes que Nephre-Ka sin objetivo ─────────
def test_nephre_sin_objetivo_se_guarda_si_hay_otro_aliado():
    from myl_sim.jugadores import _aliado_conviene
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    en_defensa(p, 1, aliado("Kawit", 2, 2))
    n = en_zona(p, 0, _nephre(), Zona.MANO)
    assert _aliado_conviene(p, 0, n)  # solo, arma mesa igual
    en_zona(p, 0, _amyrteos(), Zona.MANO)
    assert not _aliado_conviene(p, 0, n)  # con Amyrteos en la mano, se guarda


# ── T8: Piedra Roseta no baraja el Akhet que saca a Cleopatra ───────────────
def test_roseta_no_baraja_el_akhet_con_buen_objetivo():
    p = partida()
    p.j(0).oros_virtuales = 3
    en_defensa(p, 1, _cleopatra())
    a = en_zona(p, 0, _akhet(), Zona.MANO)
    lanza = en_zona(p, 0, Carta("Lanza", "Lanza", Tipo.ARMA, 2, 0, "", "x", (), True), Zona.MANO)
    pili = en_zona(p, 0, aliado("Pili", 3, 2), Zona.MANO)
    assert YO.elegir_descartes(p, 0, [a, lanza, pili], 1) == [lanza]


# ── T12: Escudo Miliciano en el turno rival va al que bloquea ───────────────
def test_escudo_en_turno_rival_va_al_bloqueador():
    escudo = Carta("Escudo Miliciano", "Escudo", Tipo.ARMA, 3, 0, "", "x", (
        h("modificarFuerza", cuando="continua", valor=3, objetivo={"quien": "esta_carta"}),
    ), True)
    p = partida()
    p.e.activo = 1
    nephre = en_defensa(p, 0, aliado("Nephre-Ka", 2, 2))
    ptolomeo = en_zona(p, 0, aliado("Ptolomeo II", 3, 2), Zona.ATAQUE)
    p.atacantes = [en_defensa(p, 1, aliado("Werin", 2, 3))]
    e = en_zona(p, 0, escudo, Zona.CEMENTERIO)
    assert YO.elegir_portador(p, 0, e, [nephre, ptolomeo]) is nephre


# ── T12: Ptolomeo II no paga por un Aliado que muere igual en el combate ────
def test_ptolomeo_no_previene_si_muere_en_combate():
    ptolomeo = aliado("Ptolomeo II", 3, 2, [h("prevenir", cuando="activada", modo="afectada", costo={"botar": 3},
                                              objetivo={"quien": "propio", "zona": "en_juego"})])
    p = partida()
    p.e.activo = 1
    s = en_defensa(p, 0, ptolomeo)
    nephre = en_defensa(p, 0, aliado("Nephre-Ka", 2, 2))
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    p.atacantes, p.bloqueos = [werin], {werin.uid: nephre}
    efecto = {"accion": "subirMano", "objetivo": {"quien": "oponente"}}
    assert not YO.prevenir_conviene(p, 0, s, s.habilidades[0], nephre, efecto)


# ── Piedra Roseta es opcional: sin una carta que sobre, no se activa ────────
def test_roseta_solo_si_sobra_una_carta():
    roseta = oro("Piedra Roseta", [h("robar", cuando="activada", fase="vigilia", turno="propio", cantidad=1,
                                     limitePorTurno=1, costo={"barajarMano": 1}, objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).mano.clear()
    p.j(0).oros_virtuales = 3
    r = en_zona(p, 0, roseta, Zona.RESERVA)
    en_defensa(p, 1, _cleopatra())
    en_zona(p, 0, _akhet(), Zona.MANO)
    en_zona(p, 0, aliado("Pili", 3, 2), Zona.MANO)
    assert not YO._vale_la_pena(p, 0, Jugada("activar", r, habilidad=0))
    en_zona(p, 0, Carta("Lanza", "Lanza", Tipo.ARMA, 2, 0, "", "x", (), True), Zona.MANO)
    assert YO._vale_la_pena(p, 0, Jugada("activar", r, habilidad=0))


# ══ Partida lmdyS9c58FxzgDWcUzo6 ════════════════════════════════════════════
def _ptolomeo2():
    return aliado("Ptolomeo II", 3, 2, [h("prevenir", cuando="activada", modo="afectada", costo={"botar": 3},
                                          objetivo={"quien": "propio", "zona": "en_juego"})])


# ── T12: Ptolomeo II no bloquea (se cuida a toda costa) ─────────────────────
def test_ptolomeo_no_bloquea():
    p = partida()
    p.e.activo = 1
    pt = en_defensa(p, 0, _ptolomeo2())
    amy = en_defensa(p, 1, _amyrteos())
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    bloqueos = YO.elegir_bloqueos(p, 0, [amy, werin], [pt])
    assert pt not in bloqueos.values()


# ── T13: Ptolomeo II vuelve a la mesa antes que el Escudo Miliciano ─────────
def test_ptolomeo_se_juega_antes_que_el_escudo():
    escudo = arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                            objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    m = en_defensa(p, 0, aliado("Montuhopet II", 1, 3))
    en_defensa(p, 1, aliado("Werin", 2, 3))
    pt = en_zona(p, 0, _ptolomeo2(), Zona.MANO)
    e = en_zona(p, 0, escudo, Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", pt)) > YO._puntaje(p, 0, Jugada("jugar", e, portador=m))


# ── T14: Qer-Her saca al bloqueador en la Vigilia, no en la Guerra ──────────
def test_qer_her_saca_al_bloqueador_en_vigilia():
    qer = aliado("Qer-Her", 3, 2, [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                     objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    escudo = arma("Escudo Miliciano", 3, [h("modificarFuerza", cuando="continua", valor=3,
                                            objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    q = en_defensa(p, 0, qer)
    en_defensa(p, 0, aliado("Werin", 2, 3))
    m = en_defensa(p, 1, aliado("Montuhopet II", 1, 3))
    e = en_zona(p, 1, escudo, Zona.MANO)
    p.ejecutar_jugada(1, Jugada("jugar_gratis", e, portador=m))
    assert YO._vale_la_pena(p, 0, Jugada("activar", q, habilidad=0))


# ── T18: Haquika roba a Neferite I (y con ella destierra a Djoser) ──────────
def test_haquika_roba_la_remocion_activable():
    neferite = aliado("Neferite I", 3, 2, [h("desterrar", cuando="activada", fase="vigilia", turno="propio",
                                             limitePorTurno=1, costo={"desterrarCementerioSegun": "coste_objetivo"},
                                             objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    p = partida()
    for k in range(5):
        en_zona(p, 0, aliado(f"Caído {k}", 1, 1), Zona.CEMENTERIO)
    djoser = en_defensa(p, 1, aliado("Djoser", 3, 3))
    n = en_defensa(p, 1, neferite)
    haq = {"accion": "ganarControl", "objetivo": {"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]}}
    assert YO.elegir_objetivos(p, 0, [djoser, n], 1, haq) == [n]


# ── El candado Ptolomeo II + Neferite I + Cleopatra VII se cuida ────────────
def test_cleopatra_y_neferite_son_piezas_clave():
    from myl_sim.jugadores import _pieza_clave
    neferite = aliado("Neferite I", 3, 2, [h("desterrar", cuando="activada", limitePorTurno=1,
                                             costo={"desterrarCementerioSegun": "coste_objetivo"},
                                             objetivo={"quien": "oponente", "zona": "en_juego"})])
    p = partida()
    p.e.activo = 1
    cleo = en_defensa(p, 0, _cleopatra())
    assert _pieza_clave(cleo) and _pieza_clave(en_defensa(p, 0, neferite))
    assert not _pieza_clave(en_defensa(p, 0, _nephre()))
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    assert cleo not in YO.elegir_bloqueos(p, 0, [werin], [cleo]).values()  # 3 vs 3: no se cambia


# ══ Partida NSCk1q62BuWie9PEbjsr ════════════════════════════════════════════
def _jinetes():
    return talisman("Jinetes de Fuego", 2, [
        h("botar", cantidad=3, objetivo={"quien": "oponente"}),
        h("jugarDesde", modo="pagando", talismanVaA="destierro",
          objetivo={"quien": "esta_carta", "zona": "cementerio"}),
    ])


# ── T16: Jinetes de la mano va al Cementerio y se juega otra vez ────────────
def test_jinetes_de_la_mano_va_al_cementerio_y_cuenta_doble():
    from myl_sim.jugadores import _botar_posible
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oros_virtuales = 4
    j = en_zona(p, 1, _jinetes(), Zona.MANO)
    assert _botar_posible(p, 1) >= 6
    p.ejecutar_jugada(1, Jugada("jugar", j))
    assert j.zona == Zona.CEMENTERIO
    desde = [o for o in p.jugadas_legales(1, "vigilia") if o.carta is j]
    assert desde
    p.ejecutar_jugada(1, desde[0])
    assert j.zona == Zona.DESTIERRO


# ── T14: para el Escudo Miliciano se paga el Nudo de Isis (y así baraja) ────
def test_paga_con_el_nudo_de_isis_para_poder_barajar():
    nudo = oro("Nudo De Isis", [h("restriccion", cuando="continua", modo="barajar_cementerio",
                                  objetivo={"quien": "ambos"})])
    escudo = arma("Escudo Miliciano", 3, [
        h("barajar", cuando="al_bloquear", cantidad=2, objetivo={"quien": "propio", "zona": "cementerio"}),
    ])
    p = partida()
    n = en_zona(p, 0, nudo, Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)
    e = en_zona(p, 0, escudo, Zona.CEMENTERIO)
    p._pagar_oro(0, 2, por=e)
    assert n.zona == Zona.PAGADO
    assert not hab.prohibido(p, "barajar_cementerio", 0)


# ══ Partida jbqPGjNzLRnFfuhc3Uom ════════════════════════════════════════════
# ── T15: Grandes Faraones (botamos los dos) no se usa con el castillo corto ─
def test_grandes_faraones_no_con_pocas_cartas():
    gf = oro("Grandes Faraones", [h("botar", cuando="activada", cantidad=1, limitePorTurno=1,
                                    zonaActivacion="reserva_oro", costo={"pagarEstaCarta": True},
                                    objetivo={"quien": "ambos"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    g = en_zona(p, 0, gf, Zona.RESERVA)
    p.j(0).mazo = p.j(0).mazo[:7]
    p.j(1).mazo = p.j(1).mazo[:19]
    assert not YO._vale_la_pena(p, 0, Jugada("activar", g, habilidad=0))
    p.j(1).mazo = p.j(1).mazo[:1]
    assert YO._vale_la_pena(p, 0, Jugada("activar", g, habilidad=0))  # lo deja fuera


# ── T14: Ptolomeo II previene pagando 1 Oro, no botando 3 ───────────────────
def test_ptolomeo_prefiere_pagar_un_oro():
    pt = aliado("Ptolomeo II", 3, 2, [h("prevenir", cuando="activada", modo="afectada", costo={"botar": 3},
                                        costoAlternativo={"oros": 1}, objetivo={"quien": "propio"})])
    p = partida()
    s = en_defensa(p, 0, pt)
    p.j(0).oros_virtuales = 1
    assert YO.preferir_alternativo(p, 0, s, s.habilidades[0])


# ── Qer-Her: "Jugar desde otra zona" activada con la zona en el objetivo ────
def test_qer_her_se_activa_desde_el_cementerio():
    qer = aliado("Qer-Her", 3, 2, [h("jugarDesde", cuando="activada", fase="vigilia", turno="propio",
                                     modo="sin_pagar", costo={"oros": 3},
                                     objetivo={"quien": "esta_carta", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    q = en_zona(p, 0, qer, Zona.CEMENTERIO)
    js = [o for o in p.jugadas_legales(0, "vigilia") if o.carta is q]
    assert js
    p.ejecutar_jugada(0, js[0])
    assert q.zona == Zona.DEFENSA


# ══ Partida tOy7PG20RZe38s4fjK6n ════════════════════════════════════════════
# ── T12: con Ptolomeo II listo para prevenir, el Gran Guardián se guarda ────
def test_no_anula_el_akhet_si_ptolomeo_previene():
    pt = aliado("Ptolomeo II", 3, 2, [h("prevenir", cuando="activada", modo="afectada", costo={"botar": 3},
                                        costoAlternativo={"oros": 1}, objetivo={"quien": "propio", "zona": "en_juego"})])
    guardian = talisman("Gran Guardian", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo = 1
    en_defensa(p, 0, aliado("Nephre-Ka", 2, 2))
    a = en_zona(p, 1, _akhet(), Zona.DEFENSA)
    opciones = [(en_zona(p, 0, guardian, Zona.MANO), guardian.habilidades[0])]
    en_defensa(p, 0, pt)
    assert YO.anular(p, 0, a, opciones) is None


# ── T13: Jeroglíficos no saca a un bloqueador que muere igual ───────────────
def test_no_saca_al_bloqueador_que_muere_igual():
    from myl_sim.jugadores import _impacto_quitar
    p = partida()
    p.e.activo = 0
    nephre = en_defensa(p, 0, aliado("Nephre-Ka", 2, 5))
    werin = en_defensa(p, 1, aliado("Werin", 2, 3))
    p.atacantes, p.bloqueos = [nephre], {nephre.uid: werin}
    assert _impacto_quitar(p, 0, werin) < 3  # muere igual: no vale un Oro


# ── 1000 partidas: con el castillo rival vacío no hay remate (se caía) ──────
def test_remate_sin_castillo_rival_no_falla():
    from myl_sim.jugadores import _remate
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    p.j(1).mazo.clear()
    assert _remate(p, 0, [Jugada("pasar")]) is None


# ══ Partida 5sElFUD7P7R1XhAvea5D ════════════════════════════════════════════
def _miliciano():
    return arma("Escudo Miliciano", 3, [
        h("modificarFuerza", cuando="continua", valor=3, objetivo={"quien": "esta_carta"}),
        h("jugarDesde", cuando="activada", fase="declaracion_ataque", turno="oponente", modo="sin_pagar",
          costo={"oros": 2}, zonaActivacion="cementerio", objetivo={"quien": "esta_carta", "zona": "mazo"}),
    ])


# ── T11: Nacer de la Muerte juega un Aliado del Mazo Castillo oponente ──────
def test_nacer_de_la_muerte_juega_del_mazo_rival():
    nacer = talisman("Nacer De La Muerte", 5, [h("jugarDesde", modo="sin_pagar",
                                                 objetivo={"quien": "oponente", "zona": "mazo", "tipos": ["Aliado"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    n = en_zona(p, 0, nacer, Zona.MANO)
    cands = hab._candidatos_jugar(p, 0, n, n.habilidades[0])
    assert cands and all(c.dueno == 1 for c in cands)


# ── T8 / T12: Ramsés II descarta el Escudo Miliciano (vuelve del Cementerio) ─
def test_ramses_descarta_el_escudo_miliciano():
    ramses = aliado("Ramsés II", 4, 6, [h("otorgarPropiedad", cuando="activada", modo="indestructible",
                                          costo={"descartar": 1}, costoAlternativo={"oros": 1},
                                          objetivo={"quien": "esta_carta"})])
    p = partida()
    r = en_defensa(p, 0, ramses)
    p.j(0).mano.clear()
    p.j(0).oros_virtuales = 2
    m = en_zona(p, 0, _miliciano(), Zona.MANO)
    celeste = en_zona(p, 0, arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano",
                                                           objetivo={"quien": "propio", "zona": "cementerio"})]), Zona.MANO)
    assert not YO.preferir_alternativo(p, 0, r, r.habilidades[0])  # descarta en vez de pagar
    assert YO.elegir_descartes(p, 0, [celeste, m], 1) == [m]


# ── T5: Qer-Her no cuenta como atacante (se destruye para usarse) ───────────
def test_qer_her_no_se_cuenta_como_atacante():
    from myl_sim.jugadores import _impacto_bloqueador
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    q = en_defensa(p, 0, aliado("Qer-Her", 3, 2))
    t = en_defensa(p, 1, aliado("Ptolomeo III", 3, 3))
    assert _impacto_bloqueador(p, 0, t, q) == 0


# ── T8: Ramsés II indestructible ataca aunque haya un bloqueador más fuerte ─
def test_indestructible_ataca():
    p = partida()
    p.e.activo = 0
    r = en_defensa(p, 0, aliado("Ramsés II", 4, 6, [h("botar", cuando="al_ser_bloqueado", opcional=True,
                                                     cantidadSegun="fuerza_esta_carta",
                                                     objetivo={"quien": "oponente"})]))
    r.listo = True
    r.estados.append({"modo": "prop:indestructible"})  # lo activó este turno
    en_defensa(p, 1, aliado("Demoledor", 4, 7))
    assert hab.tiene_prop(p, r, "indestructible")
    assert YO.elegir_atacantes(p, 0, [r]) == [r]


# ── Jinetes no se descarta (de la mano se juega 2 veces); ni con Escarabeo ──
def test_descarte_gratis_ni_jinetes_ni_con_escarabeo():
    from myl_sim.jugadores import _descarte_gratis
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", costo={"pagarEstaCarta": True},
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    p = partida()
    m = en_zona(p, 0, _miliciano(), Zona.MANO)
    j = en_zona(p, 0, _jinetes(), Zona.MANO)
    assert _descarte_gratis(p, 0, m)
    assert not _descarte_gratis(p, 0, j)
    en_zona(p, 1, escarabeo, Zona.RESERVA)
    assert not _descarte_gratis(p, 0, m)  # me lo destierran del Cementerio


# ══ Partida weGAPhuIWKvndboVUZ5I ════════════════════════════════════════════
# ── T10: con Qer-Her a la vista, ni Indestructible ni Escudo para Ramsés ────
def test_no_invierte_en_ramses_con_qer_her_a_la_vista():
    qer = aliado("Qer-Her", 3, 2, [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                     objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])
    ramses = aliado("Ramsés II", 4, 6, [h("otorgarPropiedad", cuando="activada", modo="indestructible",
                                          costo={"descartar": 1}, costoAlternativo={"oros": 1},
                                          objetivo={"quien": "esta_carta"})])
    celeste = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano",
                                             objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    r = en_defensa(p, 0, ramses)
    r.listo = True
    e = en_zona(p, 0, celeste, Zona.MANO)
    assert YO._vale_la_pena(p, 0, Jugada("activar", r, habilidad=0))
    en_defensa(p, 1, qer)
    assert not YO._vale_la_pena(p, 0, Jugada("activar", r, habilidad=0))
    assert not YO._vale_la_pena(p, 0, Jugada("jugar", e, portador=r))


# ══ Partida xk9C0QKBYqZ16NLrXntH ════════════════════════════════════════════
def _djoser():
    return aliado("Djoser", 3, 3, [h("destruir", cuando="propia_entra", disparoTipos=["Arma"], limitePorTurno=1,
                                     objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])


# ── T10: Escudo Celestial en juego con Djoser: destruye al Demoledor ────────
def test_djoser_hace_valer_cualquier_arma():
    celeste = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano",
                                             objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    d = en_defensa(p, 0, _djoser())
    en_defensa(p, 1, aliado("Demoledor de Amon", 4, 6))
    en_defensa(p, 1, aliado("Qer-Her", 3, 2, [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                                 objetivo={"quien": "oponente", "tipos": ["Aliado"]})]))
    e = en_zona(p, 0, celeste, Zona.MANO)
    assert YO._vale_la_pena(p, 0, Jugada("jugar", e, portador=d))


# ── T11: el Demoledor quita la habilidad antes de la ventana del defensor ───
def test_demoledor_resuelve_al_declarar_el_ataque():
    from test_motor import AtacaTodo
    demoledor = aliado("Demoledor de Amon", 4, 6, [h("obligarBloqueo", cuando="al_atacar", fase="declaracion_ataque",
                                                     turno="propio", objetivo={"quien": "oponente", "zona": "en_juego"},
                                                     luego=[{"accion": "perderHabilidad", "relacion": "si_se_cumplio",
                                                             "duracion": "hasta_fase_final",
                                                             "objetivo": {"quien": "oponente", "referencia": "afectadas"}}])])
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    p.e.activo = 0
    dm = en_defensa(p, 0, demoledor)
    dm.listo = True
    d = en_defensa(p, 1, _djoser())
    vistos = []
    orig = p._ventana_declaracion_ataque
    p._ventana_declaracion_ataque = lambda defensor, **kw: (vistos.append(d.sin_habilidad_hasta), orig(defensor, **kw))
    p._batalla(0)
    assert len(vistos) == 2 and vistos[1] is not None  # Djoser ya sin habilidad al abrir la ventana


# ── T12: combo Amyrteos + Montuhopet II antes que otro Aliado ───────────────
def test_amyrteos_primero_si_esta_montuhopet():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    amy = en_zona(p, 0, _amyrteos(), Zona.MANO)
    dj = en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    en_zona(p, 0, _montuhopet(), Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", amy)) > YO._puntaje(p, 0, Jugada("jugar", dj))


# ══ Partida cD56Ah7ajh4zhl4YoGan ════════════════════════════════════════════
# ── T13: Quemar los Templos le saca las Armas a Djoser (antes que Qer-Her) ──
def test_quemar_los_templos_contra_djoser_armado():
    quemar = talisman("Quemar los Templos", 4, [h("desterrar", objetivo={"quien": "cualquiera", "zona": "en_juego",
                                                                         "tipos": ["Arma", "Tótem"], "seleccion": "todos"},
                                                  luego=[{"accion": "barajar", "relacion": "si_se_cumplio",
                                                          "cantidadSegun": "num_afectadas",
                                                          "objetivo": {"quien": "propio", "zona": "mazo"}}])])
    qer = aliado("Qer-Her", 3, 2, [
        h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
          objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]}),
        h("jugarDesde", cuando="activada", fase="vigilia", turno="propio", modo="sin_pagar", costo={"oros": 3},
          objetivo={"quien": "esta_carta", "zona": "cementerio"}),
    ])
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oros_virtuales = 4
    d = en_defensa(p, 0, _djoser())
    for a in (_miliciano(), arma("Escudo Celestial", 0, [])):
        x = en_zona(p, 0, a, Zona.MANO)
        p.ejecutar_jugada(0, Jugada("jugar_gratis", x, portador=d))
    q = en_zona(p, 1, quemar, Zona.MANO)
    qh = en_zona(p, 1, qer, Zona.CEMENTERIO)
    yo = Heuristico(1)
    assert yo._puntaje(p, 1, Jugada("jugar", q)) > yo._puntaje(p, 1, Jugada("activar", qh, habilidad=1))


# ══ Partida tFD3S15MFMIy6RUvr16z ════════════════════════════════════════════
# ── Cleopatra no nombra la raza de sus propios Aliados ──────────────────────
def test_cleopatra_no_nombra_la_raza_propia():
    p = partida()
    for k in range(3):
        en_defensa(p, 0, aliado(f"Faraón {k}", 2, 2, raza="Faraón"))
    en_defensa(p, 1, aliado("Faraón rival", 2, 2, raza="Faraón"))
    en_defensa(p, 1, aliado("Sacerdote rival", 2, 2, raza="Sacerdote"))
    assert YO.elegir_raza(p, 0, ["Faraón", "Sacerdote"], {}) == "Sacerdote"


# ── Si toda raza presente la daña más a ella, nombra una que no está ────────
def test_cleopatra_nombra_otra_raza_si_todas_la_danan():
    from myl_sim import habilidades as hab
    p = partida()
    en_defensa(p, 0, aliado("Haquika", 3, 2, raza="Sacerdote"))
    en_defensa(p, 1, aliado("Djoser", 3, 3, raza="Faraón"))
    assert YO.elegir_raza(p, 0, ["Sacerdote", hab.OTRA_RAZA], {}) == hab.OTRA_RAZA


# ── Nacer de la Muerte: sin raza útil que nombrar, Cleopatra no es candado ──
def test_cleopatra_sin_raza_util_no_suma_candado():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    en_defensa(p, 0, aliado("Haquika", 3, 2, raza="Sacerdote"))
    en_defensa(p, 1, aliado("Djoser", 3, 3, raza="Faraón"))
    cleo = _cleopatra()
    cleo.habilidades[0]["objetivo"]["excluirRazas"] = ["Faraón"]
    c = en_zona(p, 0, cleo, Zona.MANO)
    r = en_zona(p, 0, aliado("Ramsés II", 4, 4, raza="Faraón"), Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", r)) > YO._puntaje(p, 0, Jugada("jugar", c))


# ══ Partida hvRcpW8SuKs0zarNsjcP ════════════════════════════════════════════
def _mandoble_seth():
    return arma("Mandoble De Seth", 3, [
        h("botar", cuando="al_atacar", fase="declaracion_ataque", turno="propio", cantidad=3,
          objetivo={"quien": "oponente"}),
        h("modificarFuerza", cuando="continua", valor=1, objetivo={"quien": "esta_carta"}),
    ])


def _flechas():
    return talisman("Flechas de Lava", 3, [h(
        "cancelarAtaque", fase="declaracion_ataque", turno="oponente", modo="todo_el_ataque",
        objetivo={"quien": "propio"})])


# ── Kawit busca la Piedra Roseta antes que el Rito de Aton ──────────────────
def test_kawit_busca_piedra_roseta():
    roseta = oro("Piedra Roseta", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                     costo={"barajarMano": 1}, objetivo={"quien": "propio"})])
    rito = oro("Rito de Aton", [h("errante", cuando="continua"),
                                h("buscar", cuando="activada", zonaDestino="mano",
                                  costo={"descartar": 1, "desterrarEstaCarta": True},
                                  objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    k = en_zona(p, 0, _kawit(), Zona.DEFENSA)
    cands = [en_zona(p, 0, rito, Zona.MAZO), en_zona(p, 0, roseta, Zona.MAZO)]
    assert YO.elegir_objetivos(p, 0, cands, 1, k.habilidades[0])[0].nombre == "Piedra Roseta"


# ── Nuh le pone el Arma al Aliado que ataca este turno ──────────────────────
def test_nuh_arma_al_que_ataca():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    kawit = en_defensa(p, 0, _kawit())
    kawit.listo = True
    nuh = en_defensa(p, 0, _nuh())
    nuh.listo = False  # recién entra
    m = en_zona(p, 0, _mandoble_seth(), Zona.MAZO)
    assert YO.elegir_portador(p, 0, m, [nuh, kawit]) is kawit


# ── Resplandor de Heka le quita a Nuh su Arma gratis de cada turno ──────────
def test_resplandor_contra_nuh():
    p = partida()
    r = en_zona(p, 1, _resplandor(), Zona.MANO)
    nuh = en_defensa(p, 0, _nuh())
    assert YO.responder(p, 1, nuh, [(r, r.habilidades[0])]) == 0


# ── Con la mesa vacía, juega a Ay aunque tenga Flechas y Resplandor ─────────
def test_mesa_vacia_juega_aliado_antes_que_reservar():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    en_zona(p, 0, _flechas(), Zona.MANO)
    en_zona(p, 0, _resplandor(), Zona.MANO)
    ay = en_zona(p, 0, _ay(), Zona.MANO)
    for n, f in (("Nuh", 3), ("Kawit", 2)):
        en_defensa(p, 1, aliado(n, 3, f))
    elegida = YO.elegir_jugada(p, 0, [Jugada("jugar", ay), Jugada("pasar")])
    assert elegida.carta is ay


# ── Flechas de Lava cancela antes de que el Mandoble bote 3 ─────────────────
def test_flechas_cancela_antes_del_mandoble():
    from test_motor import AtacaTodo

    class UsaFlechas(Heuristico):
        def elegir_jugada(self, p, yo, opciones):
            return next((o for o in opciones if o.carta is not None and o.carta.nombre == "Flechas de Lava"),
                        next(o for o in opciones if o.tipo == "pasar"))

    p = partida(jugadores=(AtacaTodo(1), UsaFlechas(2)))
    p.e.activo = 0
    atk = en_defensa(p, 0, aliado("Kawit", 2, 2))
    atk.listo = True
    p.ejecutar_jugada(0, Jugada("jugar_gratis", en_zona(p, 0, _mandoble_seth(), Zona.MANO), portador=atk))
    en_zona(p, 1, _flechas(), Zona.MANO)
    p.j(1).oros_virtuales = 3
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert p.ataque_cancelado
    assert len(p.j(1).mazo) == antes  # el Mandoble no botó


# ══ Partida 3fvzLbFvoQ2bGIC4qSCe ════════════════════════════════════════════
# ── No robar con la Biblioteca Eterna si deja el castillo sin cartas ────────
def test_biblioteca_no_roba_con_el_castillo_corto():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"destruirEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    b = en_zona(p, 0, biblioteca, Zona.RESERVA)
    for _ in range(5):
        en_zona(p, 0, ORO, Zona.RESERVA)
    p.j(0).mano = []
    assert _vale(p, _activar(b))  # castillo sano: cambia el Oro por 2 cartas
    p.j(0).mazo = p.j(0).mazo[:4]
    assert not _vale(p, _activar(b))


# ── Grandes Faraones y Nudo de Isis no botan el propio castillo ─────────────
def test_no_se_bota_el_propio_castillo():
    grandes = oro("Grandes Faraones", [h("botar", cuando="activada", costo={"pagarEstaCarta": True},
                                         objetivo={"quien": "ambos"}, cantidad=1,
                                         luego=[{"accion": "botar", "relacion": "si_se_cumplio", "cantidad": 1,
                                                 "objetivo": {"quien": "propio"}}])])
    nudo = oro("Nudo De Isis", [h("perderHabilidad", cuando="activada", costo={"oros": 2},
                                  costoAlternativo={"botar": 3}, objetivo={"quien": "esta_carta"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    g = en_zona(p, 0, grandes, Zona.RESERVA)
    n = en_zona(p, 0, nudo, Zona.RESERVA)
    p.j(1).mazo = p.j(1).mazo[:1]  # el rival queda fuera con 1
    assert _vale(p, _activar(g))
    p.j(0).mazo = p.j(0).mazo[:2]  # pero yo boto 2: pierdo yo
    assert not _vale(p, _activar(g))
    p.j(0).mazo = p.j(0).mazo[:3]
    assert not _vale(p, _activar(n))  # sin 2 Oros, botar 3 con 3 cartas


def test_remate_no_usa_grandes_faraones_si_me_bota_a_mi():
    from myl_sim import jugadores as J
    grandes = oro("Grandes Faraones", [h("botar", cuando="activada", costo={"pagarEstaCarta": True},
                                         objetivo={"quien": "ambos"}, cantidad=1)])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    g = en_zona(p, 0, grandes, Zona.RESERVA)
    p.j(1).mazo = p.j(1).mazo[:1]
    jugadas = [_activar(g), Jugada("pasar")]
    assert J._remate(p, 0, jugadas) is jugadas[0]
    p.j(0).mazo = p.j(0).mazo[:1]
    assert J._remate(p, 0, jugadas) is None


# ══ Desafío 92LI2l565sS3IYM95QYT (tú contra la IA) ══════════════════════════
def _adios():
    return talisman("Adiós Belleza", 1, [h("perderHabilidad", objetivo={
        "quien": "cualquiera", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem", "Oro"]})])


def _jeroglificos():
    return oro("Jeroglificos", [h("subirMano", cuando="activada", costo={"destruirEstaCarta": True},
                                  objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})])


# ── T7: Adiós Belleza no se gasta en la Inmunidad de Werin ni en Neferite ───
def test_adios_belleza_no_se_gasta_sin_motivo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 1
    a = en_zona(p, 0, _adios(), Zona.MANO)
    en_defensa(p, 1, aliado("Werin el Poseído", 2, 3, [h("inmunidad", cuando="continua",
                                                         objetivo={"quien": "esta_carta"})]))
    en_defensa(p, 1, aliado("Neferite I", 3, 2, [h("desterrar", cuando="activada", fase="vigilia",
                                                    objetivo={"quien": "oponente", "zona": "en_juego"})]))
    assert not YO._objetivo_util(p, 0, a, a.habilidades[0])


# ── T7: Ramsés descarta el Escudo Miliciano, no Papiros de Lahun ────────────
def test_ramses_descarta_miliciano_antes_que_papiros():
    p = partida()
    for _ in range(5):
        en_zona(p, 0, ORO, Zona.PAGADO)  # ya tiene 5 Oros en juego
    m = en_zona(p, 0, _miliciano(), Zona.MANO)
    en_zona(p, 0, _papiros(), Zona.MANO)
    assert YO.elegir_descartes(p, 0, list(p.j(0).mano), 1) == [m]


# ── T13: Adiós Belleza a Jeroglíficos antes de atacar con Ramsés ────────────
def test_adios_belleza_a_jeroglificos_antes_de_atacar():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 1
    a = en_zona(p, 0, _adios(), Zona.MANO)
    r = en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    r.listo = True
    jero = en_zona(p, 1, _jeroglificos(), Zona.RESERVA)
    en_defensa(p, 1, aliado("Kawit", 2, 2, [h("buscar", objetivo={"quien": "propio", "tipos": ["Oro"]})]))
    assert YO._objetivo_util(p, 0, a, a.habilidades[0])
    cands = hab.candidatos_validos(p, 0, a, a.habilidades[0])
    assert YO.elegir_objetivos(p, 0, cands, 1, a.habilidades[0]) == [jero]
    r.listo = False  # si no voy a atacar, se guarda
    assert not YO._objetivo_util(p, 0, a, a.habilidades[0])


# ── T13: pago mi propio Nudo de Isis para que el Escudo Celestial baraje ────
def test_pago_mi_nudo_de_isis_para_barajar():
    nudo = oro("Nudo De Isis", [
        h("restriccion", cuando="continua", modo="barajar_cementerio", objetivo={"quien": "ambos"}),
        h("perderHabilidad", cuando="activada", usaQuien="ambos", costo={"oros": 2},
          objetivo={"quien": "esta_carta"}),
    ])
    celestial = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano", opcional=True,
                                               objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    n = en_zona(p, 0, nudo, Zona.RESERVA)
    r = en_defensa(p, 0, aliado("Ramsés II", 4, 6))
    r.listo = True
    p.ejecutar_jugada(0, Jugada("jugar_gratis", en_zona(p, 0, celestial, Zona.MANO), portador=r))
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is n)
    assert _vale(p, jugada)


# ── Combo: Adiós Belleza a Werin y Nephre-Ka lo destruye sin que busque ─────
def test_adios_belleza_a_werin_y_nephre_ka_lo_saca():
    werin = aliado("Werin el Poseído", 2, 3, [
        h("inmunidad", cuando="continua", objetivo={"quien": "oponente", "tipos": ["Aliado"]}),
        h("buscar", cuando="al_salir_del_juego", zonaDestino="mano",
          objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]}),
    ], raza="Sacerdote")
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    p.j(0).oros_virtuales = 3
    a = en_zona(p, 0, _adios(), Zona.MANO)
    en_zona(p, 0, _nephre(), Zona.MANO)
    for _ in range(3):
        en_zona(p, 0, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    w = en_defensa(p, 1, werin)
    assert YO._objetivo_util(p, 0, a, a.habilidades[0])
    mano_rival = len(p.j(1).mano)
    for _ in range(4):
        j = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
        if j.tipo == "pasar":
            break
        p.ejecutar_jugada(0, j)
    assert not w.en_juego
    assert len(p.j(1).mano) == mano_rival  # sin habilidad, no buscó su Talismán


# ── Combo: Adiós Belleza a Werin y Neferite I lo destierra ──────────────────
def test_adios_belleza_a_werin_y_neferite_lo_destierra():
    werin = aliado("Werin el Poseído", 2, 3, [
        h("inmunidad", cuando="continua", objetivo={"quien": "oponente", "tipos": ["Aliado"]}),
        h("buscar", cuando="al_salir_del_juego", zonaDestino="mano",
          objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Talismán"]}),
    ], raza="Sacerdote")
    neferite = aliado("Neferite I", 3, 2, [h(
        "desterrar", cuando="activada", fase="vigilia", turno="propio",
        costo={"desterrarCementerioSegun": "coste_objetivo"},
        objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    p.j(0).oros_virtuales = 1
    a = en_zona(p, 0, _adios(), Zona.MANO)
    en_defensa(p, 0, neferite)
    for _ in range(3):
        en_zona(p, 0, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    w = en_defensa(p, 1, werin)
    assert YO._objetivo_util(p, 0, a, a.habilidades[0])
    mano_rival = len(p.j(1).mano)
    for _ in range(4):
        j = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
        if j.tipo == "pasar":
            break
        p.ejecutar_jugada(0, j)
    assert w.zona == Zona.DESTIERRO
    assert len(p.j(1).mano) == mano_rival


# ══ Partida aomi9eavAWzvvK312kcH ════════════════════════════════════════════
def _bennu():
    return aliado("Bennu", 3, 2, [h("jugarDesde", cuando="activada", fase="vigilia", turno="propio",
                                    modo="sin_pagar", costo={"destruirEstaCarta": True},
                                    objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"],
                                              "raza": "Sacerdote", "coste": {"valor": 3, "op": "<="}})],
                   raza="Sacerdote")


# ── T5: sin Aliado que traer del Cementerio, Werin antes que Bennu ──────────
def test_werin_antes_que_bennu_sin_aliado_en_cementerio():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    p.j(0).oros_virtuales = 4
    b = en_zona(p, 0, _bennu(), Zona.MANO)
    w = en_zona(p, 0, _werin(), Zona.MANO)
    assert YO.elegir_jugada(p, 0, [Jugada("jugar", b), Jugada("jugar", w), Jugada("pasar")]).carta is w
    en_zona(p, 0, aliado("Haquika", 3, 2, raza="Sacerdote"), Zona.CEMENTERIO)
    assert YO.elegir_jugada(p, 0, [Jugada("jugar", b), Jugada("jugar", w), Jugada("pasar")]).carta is b


# ── T6: perdiendo la mesa, Amyrteos pone un Oro defensivo ───────────────────
def test_perdiendo_la_mesa_pone_oro_defensivo():
    toro = oro("Toro Apis", [h("modificarFuerza", cuando="activada", valor=-1,
                               objetivo={"quien": "oponente", "zona": "en_juego"})])
    p = partida()
    cands = [en_zona(p, 0, _papiros(), Zona.MAZO), en_zona(p, 0, toro, Zona.MAZO)]
    h_poner = {"accion": "ponerEnJuego", "objetivo": {"quien": "propio", "zona": "mazo", "tipos": ["Oro"]}}
    assert YO.elegir_objetivos(p, 0, cands, 1, h_poner)[0].nombre == "Papiros de Lahun"
    for n in ("Nuh", "Kawit", "Werin"):
        en_defensa(p, 1, aliado(n, 3, 3))
    assert YO.elegir_objetivos(p, 0, cands, 1, h_poner)[0].nombre == "Toro Apis"


# ── T10: con Oros de sobra, baja la Biblioteca para cambiarla por 2 cartas ──
def test_baja_biblioteca_con_oros_de_sobra():
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"destruirEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    corona = oro("Corona Faraónica", [h("restringirCombate", cuando="activada", modo="puede_atacar_este_turno",
                                        objetivo={"quien": "propio", "zona": "en_juego"}),
                                      h("modificarFuerza", cuando="activada", valor=1,
                                        objetivo={"quien": "propio", "zona": "en_juego"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    for _ in range(6):
        en_zona(p, 0, ORO, Zona.RESERVA)
    b = en_zona(p, 0, biblioteca, Zona.MANO)
    c = en_zona(p, 0, corona, Zona.MANO)
    en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    en_zona(p, 0, aliado("Djoser", 3, 3), Zona.MANO)
    en_zona(p, 0, _relampago(), Zona.MANO)  # de respuesta: no cuenta como gasto del turno
    elegida = YO.elegir_jugada(p, 0, [Jugada("oro", b), Jugada("oro", c), Jugada("pasar")])
    assert elegida.carta is b


# ── Biblioteca para buscar un Arma, salvo que ya haya una en el Cementerio ──
def test_biblioteca_busca_arma_si_no_hay_en_el_cementerio():
    from myl_sim import jugadores as J
    biblioteca = oro("Biblioteca Eterna", [h("robar", cuando="activada", fase="vigilia", turno="propio",
                                             cantidad=2, costo={"destruirEstaCarta": True},
                                             objetivo={"quien": "propio"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    for _ in range(3):  # 5 Oros en juego con el inicial y la Biblioteca
        en_zona(p, 0, ORO, Zona.RESERVA)
    b = en_zona(p, 0, biblioteca, Zona.RESERVA)
    en_defensa(p, 0, aliado("Djoser", 3, 3))
    p.j(0).mano = []
    en_zona(p, 0, aliado("Jentakus I", 3, 3), Zona.MANO)  # algo que jugar igual
    en_zona(p, 0, _miliciano(), Zona.MAZO)
    h0 = b.habilidades[0]
    assert J._sacrificio_de_oro_conviene(p, 0, b, h0)  # cavar por el Escudo Miliciano
    en_zona(p, 0, _miliciano(), Zona.CEMENTERIO)
    assert not J._sacrificio_de_oro_conviene(p, 0, b, h0)  # ya se juega desde ahí


# ══ Partida zDGKX582b8mRYGZXQ2pF ════════════════════════════════════════════
# ── Mulligan: 1 Oro + Amyrteos + Ay es una mano que se queda ────────────────
def test_se_queda_con_amyrteos_y_ay():
    from myl_sim.modelo import Zona as Z
    p = partida()
    j = p.j(0)
    for c in list(j.mano):
        p._mover(c, Z.MAZO)
    for c in (_flechas(), _miliciano(), _ay(), talisman("Qadesh", 5, []), oro("Biblioteca Eterna", []),
              _amyrteos(), aliado("Neferite I", 3, 2), aliado("Djoser", 3, 3)):
        en_zona(p, 0, c, Z.MANO)
    assert len(j.mano) == 8
    assert YO.quedarse_mano(p, 0)
    j.mano = [c for c in j.mano if c.nombre != "Ay"]
    en_zona(p, 0, aliado("Pili", 3, 2), Z.MANO)  # sin Ay, Amyrteos no acelera
    assert not YO.quedarse_mano(p, 0)


# ── Exceso de mano: un Oro se descarta solo con más de 3 en la mano ─────────
def test_exceso_no_descarta_oro_con_3_en_mano():
    riton = oro("Riton Aqueménida", [])
    p = partida()
    oros = [en_zona(p, 0, riton, Zona.MANO) for _ in range(3)]
    flojo = en_zona(p, 0, talisman("Luz del Saber", 1, []), Zona.MANO)
    assert YO.elegir_descartes(p, 0, list(p.j(0).mano), 1) == [flojo]
    oros.append(en_zona(p, 0, riton, Zona.MANO))
    assert YO.elegir_descartes(p, 0, list(p.j(0).mano), 1)[0] in oros


# ══ Partida LLQmSkOIAM4wb7v84iVG ════════════════════════════════════════════
# ── T20: Riton al fondo (+1), Papiros con Tocador y sin adelgazar con Kawit ─
def test_cierre_con_riton_papiros_y_tocador():
    papiros = lambda: oro("Papiros de Lahun", [h("botar", cuando="activada", cantidad=3,  # noqa: E731
                                                 costo={"oros": 1, "desterrarEstaCarta": True},
                                                 zonaActivacion="reserva_oro", objetivo={"quien": "oponente"})])
    tocador = oro("Tocador", [h("botar", cuando="al_botar_por_oponente", cantidadSegun="cartas_botadas",
                                opcional=True, costo={"destruirEstaCarta": True}, objetivo={"quien": "oponente"})])
    riton = oro("Riton Aqueménida", [h("buscar", cuando="activada", zonaDestino="mano",
                                       costo={"fondoMazoEstaCarta": True, "oros": 2},
                                       objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Tótem", "Arma"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    for c in (papiros(), tocador, riton, ORO, ORO, ORO):
        en_zona(p, 0, c, Zona.RESERVA)
    en_zona(p, 0, arma("Escudo Celestial", 0, []), Zona.CEMENTERIO)
    k = en_zona(p, 0, _kawit(), Zona.MANO)
    p.j(0).mazo = p.j(0).mazo[:4]
    en_zona(p, 1, papiros(), Zona.RESERVA)
    en_zona(p, 1, ORO, Zona.RESERVA)
    ay = en_defensa(p, 1, aliado("Ay", 2, 3, [h("guardian", cuando="continua")]))  # Guardián: no ataca
    ay.listo = True
    p.j(1).mazo = p.j(1).mazo[:6]
    for _ in range(6):
        j = YO.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
        if j.tipo == "pasar":
            break
        p.ejecutar_jugada(0, j)
    assert len(p.j(0).mazo) == 5  # Riton al fondo
    assert len(p.j(1).mazo) == 3  # Papiros: 6 → 3
    assert k in p.j(0).mano  # Kawit no se juega: me dejaba a tiro


def _neferite():
    return aliado("Neferite I", 3, 2, [h("desterrar", cuando="activada", fase="vigilia", turno="propio",
                                         costo={"desterrarCementerioSegun": "coste_objetivo"},
                                         objetivo={"quien": "oponente", "zona": "en_juego",
                                                   "tipos": ["Aliado", "Arma", "Tótem"]})], raza="Faraón")


# ── T5: Resplandor no se gasta en una Neferite sin Cementerio para pagar ────
def test_resplandor_no_a_neferite_sin_cementerio():
    p = partida()
    r = en_zona(p, 1, _resplandor(), Zona.MANO)
    en_defensa(p, 1, aliado("Kawit", 2, 2))
    nef = en_defensa(p, 0, _neferite())
    p.j(0).cementerio.clear()
    assert YO.responder(p, 1, nef, [(r, r.habilidades[0])]) is None
    for _ in range(3):
        en_zona(p, 0, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    assert YO.responder(p, 1, nef, [(r, r.habilidades[0])]) == 0


# ── T5: Ay no destierra a Neferite para robar ───────────────────────────────
def test_ay_no_destierra_a_neferite():
    from myl_sim import jugadores as J
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    ay = en_defensa(p, 0, _ay())
    nef = en_defensa(p, 0, _neferite())
    nef.sin_habilidad_hasta = "permanente"  # Resplandor
    assert not J._sacrificio_de_aliados_conviene(p, 0, ay, ay.habilidades[0])


# ── T8: Escarabeo destierra el Escudo Miliciano del Cementerio rival ────────
def test_escarabeo_al_escudo_miliciano():
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", zonaActivacion="reserva_oro",
                                    costo={"desterrarCementerio": 1, "pagarEstaCarta": True},
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    p = partida()
    e = en_zona(p, 0, escarabeo, Zona.RESERVA)
    escudo = en_zona(p, 1, _miliciano(), Zona.CEMENTERIO)
    otro = en_zona(p, 1, aliado("Ramsés II", 4, 6), Zona.CEMENTERIO)
    assert YO.elegir_objetivos(p, 0, [otro, escudo], 1, e.habilidades[0]) == [escudo]


# ── T12: Demoledor no obliga a bloquear a quien no puede bloquear ───────────
def test_demoledor_no_obliga_al_que_no_puede_bloquear():
    p = partida()
    dj = en_defensa(p, 1, aliado("Djoser", 3, 3))
    p.e.jugadores[1]  # noqa: B018
    dj.estados.append({"modo": "no_puede_bloquear"})
    dem = en_defensa(p, 0, _demoledor())
    hh = next(x for x in dem.habilidades if x.get("accion") == "obligarBloqueo")
    assert dj not in hab.candidatos_validos(p, 0, dem, hh)


# ── T11: Jentakus busca a Ptolomeo II (protege todo) ────────────────────────
def test_jentakus_busca_ptolomeo_ii():
    from myl_sim import jugadores as J
    p = partida()
    p2 = en_zona(p, 0, _ptolomeo2(), Zona.MAZO)
    p3 = en_zona(p, 0, aliado("Ptolomeo III", 3, 3, raza="Faraón"), Zona.MAZO)
    assert J._valor_para_el_plan(p, 0, p2) > J._valor_para_el_plan(p, 0, p3)


# ── T15: bloquear al que baraja al hacer daño (Escudo Celestial) ────────────
def test_bloquea_al_del_escudo_celestial():
    from test_motor import AtacaTodo
    celestial = arma("Escudo Celestial", 0, [h("barajar", cuando="al_hacer_dano", opcional=True,
                                               cantidadSegun="dano_hecho",
                                               objetivo={"quien": "propio", "zona": "cementerio"})])
    p = partida(jugadores=(AtacaTodo(1), Heuristico(2)))
    cleo = en_defensa(p, 0, aliado("Cleopatra VII", 4, 3))
    jent = en_defensa(p, 0, aliado("Jentakus I", 3, 3))
    p.ejecutar_jugada(0, Jugada("jugar_gratis", en_zona(p, 0, celestial, Zona.MANO), portador=jent))
    werin = en_defensa(p, 1, aliado("Werin el Poseído", 2, 3))
    assert YO.elegir_bloqueos(p, 1, [cleo, jent], [werin]).get(jent.uid) is werin


# ── T16: Resplandor de Heka no responde a un Talismán ───────────────────────
def test_resplandor_no_responde_a_talisman():
    p = partida()
    quemar = en_zona(p, 0, talisman("Quemar los Templos", 4, []), Zona.MANO)
    nef = en_defensa(p, 0, _neferite())
    resplandor = _resplandor().habilidades[0]
    assert not hab._responde_a(resplandor, quemar)
    assert hab._responde_a(resplandor, nef)


# ── Neferite se anula (Gran Guardián) y Escarabeo la destierra después ──────
def test_neferite_se_anula_y_escarabeo_la_destierra():
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", zonaActivacion="reserva_oro",
                                    costo={"desterrarCementerio": 1, "pagarEstaCarta": True},
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    guardian = talisman("Gran Guardian", 2, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})])
    p = partida()
    g = en_zona(p, 1, guardian, Zona.MANO)
    p.j(1).oros_virtuales = 2
    en_defensa(p, 1, aliado("Kawit", 2, 2))
    nef = en_defensa(p, 0, _neferite())
    p.j(0).cementerio.clear()
    assert YO.anular(p, 1, nef, [(g, g.habilidades[0])]) == 0  # aunque no tenga Cementerio
    e = en_zona(p, 1, escarabeo, Zona.RESERVA)
    p._mover(nef, Zona.CEMENTERIO)
    otro = en_zona(p, 0, aliado("Djedefhor", 3, 3), Zona.CEMENTERIO)
    assert YO.elegir_objetivos(p, 1, [otro, nef], 1, e.habilidades[0]) == [nef]


# ── Kawit con "puedes": con el castillo a tiro, entra pero no busca ni roba ─
def test_kawit_opcional_no_adelgaza_el_castillo():
    from test_notas_cartas import jugar
    kawit = aliado("Kawit", 2, 2, [h("buscar", opcional=True, zonaDestino="mano",
                                     objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Oro"]},
                                     luego=[{"accion": "robar", "relacion": "si_se_cumplio", "opcional": True,
                                             "cantidad": 1, "objetivo": {"quien": "propio"}}])])
    p = partida()
    p.j(0).mazo = [c for c in p.j(0).mazo if c.tipo == Tipo.ORO][:4]
    ay = en_defensa(p, 1, aliado("Ay", 2, 6))
    ay.listo = True
    jugar(p, 0, kawit)
    assert len(p.j(0).mazo) == 4  # no buscó: con 6 de fuerza rival quedaba a tiro


# ── No botar si eso le paga a Neferite el destierro de mi Haquika ───────────
def test_jinetes_no_alimenta_a_neferite():
    jinetes = talisman("Jinetes de Fuego", 2, [h("botar", cantidad=3, objetivo={"quien": "oponente"})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 2
    j = en_zona(p, 0, jinetes, Zona.MANO)
    en_defensa(p, 0, aliado("Haquika", 3, 2, raza="Sacerdote"))
    en_defensa(p, 1, _neferite())
    p.j(1).cementerio.clear()
    assert not _vale(p, Jugada("jugar", j))  # 0 → 3 en su Cementerio: Neferite alcanza a Haquika
    for _ in range(3):
        en_zona(p, 1, aliado("Caído", 1, 1), Zona.CEMENTERIO)
    assert _vale(p, Jugada("jugar", j))  # ya la alcanzaba: botar no cambia nada


# ══ Partida iQeBPG4J25pk9PMelFel (Sacerdote vs Héroe) ══════════════════════
def _haquika_con(p, robado):
    haq = en_defensa(p, 1, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible", "cuando": "continua"}]))
    robado.controlador = 1
    p.j(0).defensa.remove(robado)
    p.j(1).defensa.append(robado)
    robado.control = {"duracion": "mientras_en_juego", "fuente": haq.uid, "turno": 1, "original": 0}
    return haq


# ── Sacar a Haquika vale también lo que me devuelve ─────────────────────────
def test_sacar_al_ladron_vale_lo_que_devuelve():
    from myl_sim import jugadores as J
    p = partida()
    mio = en_defensa(p, 0, aliado("Teseo de Atenas", 4, 4, raza="Héroe"))
    haq = _haquika_con(p, mio)
    kawit = en_defensa(p, 1, aliado("Kawit", 2, 2))
    assert J._impacto_quitar(p, 0, haq) > J._impacto_quitar(p, 0, kawit) + 3


# ── Ganimedes no destruye mi Constantino robado si hay otro objetivo ────────
def test_no_destruyo_lo_mio_robado():
    p = partida()
    mio = en_defensa(p, 0, aliado("Constantino", 3, 1, raza="Héroe"))
    _haquika_con(p, mio)
    djed = en_defensa(p, 1, aliado("Djedefhor", 3, 3))
    hh = h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"]})
    assert YO.elegir_objetivos(p, 0, [mio, djed], 1, hh) == [djed]


# ── Perseo no se sacrifica para barajar a Kawit ─────────────────────────────
def test_perseo_no_se_gasta_en_kawit():
    from myl_sim import jugadores as J
    perseo = aliado("Perseo", 2, 2, [h("barajar", cuando="activada", fase="vigilia", turno="propio",
                                       costo={"desterrarEstaCarta": True},
                                       objetivo={"quien": "oponente", "tipos": ["Aliado"], "coste": {"op": "<=", "valor": 3}})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    pe = en_defensa(p, 0, perseo)
    en_defensa(p, 1, aliado("Kawit", 2, 2))
    assert not J._remocion_que_se_sacrifica_conviene(p, 0, pe, pe.habilidades[0])
    mio = en_defensa(p, 0, aliado("Constantino", 3, 1, raza="Héroe"))
    _haquika_con(p, mio)
    assert J._remocion_que_se_sacrifica_conviene(p, 0, pe, pe.habilidades[0])


# ── Haquika indestructible no ataca para chocar contra un bloqueador ────────
def test_indestructible_debil_se_queda_defendiendo():
    p = partida()
    haq = en_defensa(p, 0, aliado("Haquika", 3, 2, [{"featureId": "i", "accion": "indestructible", "cuando": "continua"}]))
    haq.listo = True
    en_defensa(p, 1, aliado("Constantino", 3, 3))
    assert YO.elegir_atacantes(p, 0, [haq]) == []


# ── Figuras Negras: Escarabeo (Cementerio) no; Amkh (prevenir) sí ───────────
def test_figuras_negras_a_amkh_y_no_a_escarabeo():
    from myl_sim import jugadores as J
    escarabeo = oro("Escarabeo", [h("desterrar", cuando="activada", zonaActivacion="reserva_oro",
                                    objetivo={"quien": "oponente", "zona": "cementerio"})])
    amkh = oro("Amkh", [h("prevenir", cuando="activada", zonaActivacion="reserva_o_pagado",
                          objetivo={"quien": "oponente", "tipos": ["Aliado", "Arma", "Tótem", "Oro"]})])
    figuras = h("perderHabilidad", cuando="activada", objetivo={"quien": "cualquiera", "tipos": ["Oro"]})
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    f = en_zona(p, 0, oro("Figuras Negras", [figuras]), Zona.RESERVA)
    e = en_zona(p, 1, escarabeo, Zona.RESERVA)
    a = en_zona(p, 1, amkh, Zona.RESERVA)
    en_defensa(p, 0, aliado("Atacante", 3, 3)).listo = True
    assert e not in J._objetivos_perder_habilidad(p, 0, f, figuras)
    p.j(0).oros_virtuales = 3
    en_zona(p, 0, talisman("Focea", 3, [h("mover", zonaDestino="mazo_tope",
                                         objetivo={"quien": "oponente", "tipos": ["Aliado"]})]), Zona.MANO)
    assert a in J._objetivos_perder_habilidad(p, 0, f, figuras)


# ── Focea: con la mano corta, se destruye en la Guerra para robar 2 ─────────
def test_focea_roba_en_la_guerra_tambien_con_mano_amplia():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    robo = h("robar", cuando="activada", fase="guerra_talismanes", cantidad=2, costo={"destruirEstaCarta": True})
    p.j(0).mano = p.j(0).mano[:2]
    assert YO._guerra_conviene(p, 0, [robo])
    for _ in range(4):
        en_zona(p, 0, aliado("Relleno", 1, 1), Zona.MANO)
    assert YO._guerra_conviene(p, 0, [robo])


def test_demoledor_considera_fuerza_que_pierde_bloqueador_al_anularlo():
    p = partida()
    demoledor = en_defensa(p, 0, _demoledor())
    constante = h("modificarFuerza", cuando="continua", valor=2,
                  objetivo={"quien": "propio", "zona": "en_juego", "tipos": ["Aliado"]})
    rival = en_defensa(p, 1, aliado("Constantino", 3, 3, [constante]))
    assert hab.fuerza(p, rival) == 5
    assert demoledor in YO.elegir_atacantes(p, 0, [demoledor])
    assert rival.sin_habilidad_hasta is None


def test_takelot_prefiere_quitar_bonificacion_vigente_a_habilidad_ya_usada():
    p = partida()
    constante = h("modificarFuerza", cuando="continua", valor=2,
                  objetivo={"quien": "propio", "zona": "en_juego", "tipos": ["Aliado"]})
    en_defensa(p, 1, aliado("Constantino", 3, 3, [constante]))
    en_defensa(p, 1, aliado("Otro héroe", 2, 2))
    en_defensa(p, 1, aliado("Ganimedes", 3, 3, [h("destruir", cuando="al_jugar")]))
    assert YO.elegir_carta(p, 0, ["Ganimedes", "Constantino"]) == "Constantino"


def test_restriccion_de_combate_prioriza_amenaza_imbloqueable():
    p = partida()
    julio = en_defensa(p, 1, aliado("Julio", 4, 4))
    minos = en_defensa(p, 1, aliado("Minos", 3, 3, [
        {"accion": "imbloqueable", "cuando": "continua"},
        h("buscar", cuando="al_hacer_dano"),
    ]))
    efecto = h("restringirCombate", modo="no_puede_atacar", objetivo={"quien": "oponente"})
    assert YO.elegir_objetivos(p, 0, [julio, minos], 1, efecto) == [minos]


def test_riton_se_reserva_si_un_aliado_puede_jugar_el_arma_gratis():
    from myl_sim.motor import Jugada

    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    buscar = h("buscar", cuando="activada", zonaDestino="mano",
               costo={"oros": 2, "fondoMazoEstaCarta": True},
               objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Arma"]})
    riton = en_zona(p, 0, oro("Riton", [buscar]), Zona.RESERVA)
    arma = Carta("arma", "Arma", Tipo.ARMA, 2, 0, "", "")
    en_zona(p, 0, arma, Zona.CEMENTERIO)
    recuperar = h("jugarDesde", cuando="activada", modo="sin_pagar", costo={},
                  objetivo={"quien": "propio", "zonas": ["mazo", "cementerio"], "tipos": ["Arma"]})
    nuh = en_zona(p, 0, aliado("Nuh", 3, 2, [recuperar]), Zona.MANO)
    jugada = Jugada("activar", riton, habilidad=0)
    assert not YO._vale_la_pena(p, 0, jugada)
    p._mover(nuh, Zona.CEMENTERIO)
    assert not YO._vale_la_pena(p, 0, jugada)  # todavía no tiene portador
    en_defensa(p, 0, aliado("Portador", 1, 1))
    assert YO._vale_la_pena(p, 0, jugada)


def test_descarte_se_narra_y_puede_ser_carta_anterior_de_la_mano():
    p = partida()
    p.e.log = []
    fuente = en_defensa(p, 0, aliado("Fuente", 1, 1))
    vieja = en_zona(p, 0, aliado("Carta anterior", 0, 0), Zona.MANO)
    en_zona(p, 0, aliado("Carta nueva", 5, 5), Zona.MANO)
    hab._resolver_efecto(p, 0, fuente, h("descartar", cantidad=1, objetivo={"quien": "propio"}))
    assert vieja.zona == Zona.CEMENTERIO
    assert any("descarta Carta anterior" in texto for texto in p.e.log)


def test_demoledor_no_cuenta_dos_veces_al_bloqueador_que_obliga():
    p = partida()
    p.j(1).mazo = p.j(1).mazo[:20]  # ventaja suficiente para activar la agresividad
    demoledor = en_defensa(p, 0, _demoledor())
    kawit = en_defensa(p, 0, aliado("Kawit", 2, 2))
    en_defensa(p, 1, aliado("Constantino", 3, 1, [h("modificarFuerza", cuando="continua", valor=2,
               objetivo={"quien": "propio", "zona": "en_juego", "tipos": ["Aliado"]})]))
    en_defensa(p, 1, aliado("Marco", 2, 4))
    atacantes = YO.elegir_atacantes(p, 0, [demoledor, kawit])
    assert demoledor in atacantes
    assert kawit not in atacantes


def test_descarte_prefiere_copia_duplicada_a_unico_oro():
    p = partida()
    oro_mano = en_zona(p, 0, oro("Trono", [h("desterrar", cuando="activada")]), Zona.MANO)
    carta = aliado("Ganimedes", 2, 2, [h("destruir", cuando="al_jugar")])
    primera = en_zona(p, 0, carta, Zona.MANO)
    en_zona(p, 0, carta, Zona.MANO)
    assert YO.elegir_descartes(p, 0, p.j(0).mano, 1) == [primera]
    assert oro_mano in p.j(0).mano


def test_werin_bloquea_amenaza_con_habilidades_continuas():
    p = partida()
    werin = en_defensa(p, 0, aliado("Werin", 2, 3))
    ganimedes = en_defensa(p, 1, aliado("Ganimedes", 2, 3))
    marco = en_defensa(p, 1, aliado("Marco", 2, 3, [
        h("restriccion", cuando="continua", modo="jugar_tipo"),
        h("modificarFuerza", cuando="continua", valor=1, objetivo={"quien": "propio", "tipos": ["Aliado"], "excluirEstaCarta": True}),
    ]))
    # Igualamos la fuerza sin quitar la habilidad de Marco.
    ganimedes.carta = aliado("Ganimedes", 2, 2)
    assert YO.elegir_bloqueos(p, 0, [ganimedes, marco], [werin]) == {marco.uid: werin}


def test_marco_no_se_expone_a_bloqueo_que_lo_destruye():
    p = partida()
    marco = en_defensa(p, 0, aliado("Marco", 2, 3, [h("restriccion", cuando="continua", modo="jugar_tipo")]))
    en_defensa(p, 1, aliado("Werin", 2, 3))
    assert marco not in YO.elegir_atacantes(p, 0, [marco])


def test_bloqueador_fuerza_cero_no_se_sacrifica_sin_reducir_dano():
    p = partida()
    werin = en_defensa(p, 0, aliado("Werin", 2, 0, [h("buscar", cuando="al_salir_del_juego")]))
    atacante = en_defensa(p, 1, aliado("Marco", 2, 3))
    p.j(0).mazo = p.j(0).mazo[:3]
    assert YO.elegir_bloqueos(p, 0, [atacante], [werin]) == {}


def test_titanes_espera_al_combate_y_funciona_sobre_bloqueador():
    from myl_sim import jugadores as J
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    efecto = h("modificarFuerza", cuando="activada", modoFuerza="fijar", valor=0,
               duracion="hasta_fase_final", objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})
    fuente = en_zona(p, 0, oro("Titanes", [efecto]), Zona.RESERVA)
    atacante = en_defensa(p, 0, aliado("Atacante", 2, 3))
    defensor = en_defensa(p, 1, aliado("Defensor", 2, 3))
    assert not J._fuerza_temporal_conviene(p, 0, fuente, efecto)
    p.atacantes = [atacante]
    p.bloqueos = {atacante.uid: defensor}
    p.e.fase = "guerra_talismanes"
    assert J._fuerza_temporal_conviene(p, 0, fuente, efecto)


def test_riton_no_busca_arma_que_no_puede_jugar_con_mano_llena():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 5
    buscar = h("buscar", cuando="activada", zonaDestino="mano",
               costo={"oros": 2, "fondoMazoEstaCarta": True},
               objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Arma"]})
    riton = en_zona(p, 0, oro("Riton", [buscar]), Zona.RESERVA)
    en_zona(p, 0, arma("Mandoble", 2, []), Zona.CEMENTERIO)
    for i in range(8):
        en_zona(p, 0, aliado(f"Mano {i}", 2, 2), Zona.MANO)
    assert not YO._vale_la_pena(p, 0, Jugada("activar", riton, habilidad=0))


def test_djedefhor_no_se_elige_al_salir():
    p = partida()
    efecto = h("barajar", cuando="al_salir_del_juego", objetivo={"quien": "propio", "zona": "cementerio"})
    djedefhor = en_zona(p, 0, aliado("Djedefhor", 3, 3, [efecto]), Zona.CEMENTERIO)
    otra = en_zona(p, 0, aliado("Otra", 2, 2), Zona.CEMENTERIO)
    assert hab.candidatos_validos(p, 0, djedefhor, efecto) == [otra]


def test_robar_o_devolver_bonificador_considera_fuerza_del_equipo():
    from myl_sim import jugadores as J
    p = partida()
    bonus = h("modificarFuerza", cuando="continua", valor=2,
              objetivo={"quien": "propio", "zona": "en_juego", "tipos": ["Aliado"]})
    constantino = en_defensa(p, 1, aliado("Constantino", 3, 1, [bonus]))
    en_defensa(p, 1, aliado("Otro", 2, 3))
    otro = en_defensa(p, 1, aliado("Sin habilidades", 3, 3))
    assert J._valor_robar(p, 0, constantino) > J._valor_robar(p, 0, otro)
    assert J._impacto_quitar(p, 0, constantino) > J._impacto_quitar(p, 0, otro)


def test_no_quita_restriccion_que_habilitaria_talisman_rival():
    from myl_sim import jugadores as J
    p = partida()
    restriccion = h("restriccion", cuando="continua", modo="jugar_tipo",
                    objetivo={"quien": "ambos", "tipos": ["Talismán"]})
    marco = en_defensa(p, 1, aliado("Marco", 2, 3, [restriccion, h("modificarFuerza", cuando="continua", valor=1)]))
    en_zona(p, 1, talisman("Flechas", 1, [h("cancelarAtaque")]), Zona.MANO)
    efecto = h("perderHabilidad", objetivo={"quien": "oponente"})
    assert not J._objetivos_perder_habilidad(p, 0, None, efecto, objetivos=[marco])


def test_no_busca_talisman_que_restriccion_impide_jugar():
    from myl_sim import jugadores as J
    p = partida()
    restriccion = h("restriccion", cuando="continua", modo="jugar_tipo",
                    objetivo={"quien": "ambos", "tipos": ["Talismán"]})
    en_defensa(p, 1, aliado("Marco", 2, 3, [restriccion]))
    en_zona(p, 0, talisman("Flechas", 3, [h("cancelarAtaque")]), Zona.CEMENTERIO)
    buscar = h("buscar", cuando="activada", zonaDestino="mano", costo={"descartar": 1},
               objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Talismán"]})
    rito = en_zona(p, 0, oro("Rito", [buscar]), Zona.RESERVA)
    assert not J._buscar_conviene(p, 0, rito, buscar)


def test_pili_valora_recuperar_y_jugar_haquika_en_mismo_turno():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 6
    robar = h("ganarControl", cuando="al_jugar", objetivo={"quien": "oponente", "zona": "en_juego", "tipos": ["Aliado"]})
    en_zona(p, 0, aliado("Haquika", 3, 2, [robar]), Zona.CEMENTERIO)
    en_defensa(p, 1, aliado("Constantino", 3, 4))
    recuperar = h("subirMano", cuando="al_jugar", objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"]})
    pili = en_zona(p, 0, aliado("Pili", 3, 2, [recuperar]), Zona.MANO)
    werin = en_zona(p, 0, aliado("Werin", 2, 3), Zona.MANO)
    assert YO._puntaje(p, 0, Jugada("jugar", pili)) > YO._puntaje(p, 0, Jugada("jugar", werin))


def test_escarabeo_no_destierra_carta_util_por_objetivo_inofensivo():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    desterrar = h("desterrar", cuando="activada", costo={"desterrarCementerio": 1, "pagarEstaCarta": True},
                  objetivo={"quien": "oponente", "zona": "cementerio"})
    escarabeo = en_zona(p, 0, oro("Escarabeo", [desterrar]), Zona.RESERVA)
    recuperar = h("jugarDesde", cuando="activada", objetivo={"quien": "esta_carta", "zona": "cementerio"})
    en_zona(p, 0, aliado("Qer-Her", 3, 2, [recuperar]), Zona.CEMENTERIO)
    en_zona(p, 1, oro("Caja", []), Zona.CEMENTERIO)
    assert not YO._vale_la_pena(p, 0, Jugada("activar", escarabeo, habilidad=0))


def test_escarabeo_nunca_gasta_qer_her_como_costo():
    from myl_sim.motor import Jugada
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    efecto = h("desterrar", cuando="activada", costo={"desterrarCementerio": 1, "pagarEstaCarta": True},
               objetivo={"quien": "oponente", "zona": "cementerio"})
    escarabeo = en_zona(p, 0, oro("Escarabeo", [efecto]), Zona.RESERVA)
    qer = en_zona(p, 0, aliado("Qer-Her", 3, 2), Zona.CEMENTERIO)
    jugada = Jugada("activar", escarabeo, habilidad=0)
    assert not YO._vale_la_pena(p, 0, jugada)
    otra = en_zona(p, 0, aliado("Otra", 1, 1), Zona.CEMENTERIO)
    assert YO.elegir_destierro_costo(p, 0, escarabeo, [qer, otra], 1) == [otra]


def test_kawit_valora_asegurar_oro_situacionalmente_con_cuatro_o_cinco():
    from myl_sim.motor import Jugada
    p = partida()
    k = en_zona(p, 0, _kawit(), Zona.MANO)
    for n in (3, 4, 5, 6):
        p.j(0).reserva = p.j(0).reserva[:1]
        for _ in range(n - 1):
            en_zona(p, 0, ORO, Zona.RESERVA)
        con_busqueda = YO._puntaje(p, 0, Jugada("jugar", k))
        oro_mano = en_zona(p, 0, ORO, Zona.MANO)
        sin_busqueda = YO._puntaje(p, 0, Jugada("jugar", k))
        p._mover(oro_mano, Zona.CEMENTERIO)
        diferencia = con_busqueda - sin_busqueda
        assert (diferencia > 3.8) == (n in (4, 5))


# ══ Partida VwDuRAVi7cjRlLkkcCzv (Faraón Djoser vs Sacerdote) ══════════════
# ── Ay no paga un Aliado por cartas si ya tengo todo en la mano ─────────────
def test_ay_no_roba_si_tengo_todos_los_recursos():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    p.j(0).oros_virtuales = 0
    ay = en_defensa(p, 0, _ay())
    en_defensa(p, 0, aliado("Montuhopet II", 1, 1))
    p.j(0).mano = []
    for c in (_akhet(), aliado("A", 3, 3), aliado("B", 3, 3), aliado("C", 3, 3), talisman("Q", 5, []), oro("Oro", [])):
        en_zona(p, 0, c, Zona.MANO)
    assert not _vale(p, _activar(ay))  # aliados y Oro en mano: no hace falta
    p.j(0).mano = p.j(0).mano[:2]
    assert _vale(p, _activar(ay))  # con la mano corta sí roba


# ── Un robo gratis tolera descartar 1 (Kawit), no 2 ─────────────────────────
def test_robo_gratis_tolera_descartar_una_carta():
    from myl_sim import jugadores as J
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    p.j(0).mano = []
    for k in range(6):
        en_zona(p, 0, aliado(f"X{k}", 5, 3), Zona.MANO)  # ninguna se alcanza a jugar
    gratis = h("robar", opcional=True, objetivo={"quien": "propio"})
    assert not J._robo_obliga_a_descartar(p, 0, gratis)
    en_zona(p, 0, aliado("X6", 5, 3), Zona.MANO)
    assert not J._robo_obliga_a_descartar(p, 0, gratis)  # 9 al final: descarta 1
    en_zona(p, 0, aliado("X7", 5, 3), Zona.MANO)
    assert J._robo_obliga_a_descartar(p, 0, gratis)  # descartaría 2


# ── Exceso de mano: se tiran Qadesh y Mercado, no Akhet ni el Arma de Djoser ─
def test_exceso_conserva_akhet_y_el_arma_con_djoser():
    p = partida()
    for _ in range(2):
        en_zona(p, 0, ORO, Zona.RESERVA)  # 3 Oros en juego con el inicial
    en_defensa(p, 0, _djoser())
    lanza = arma("Lanza de Ramsés", 1, [h("restringirCombate", modo="no_puede_atacar",
                                          objetivo={"quien": "oponente", "tipos": ["Aliado"]}),
                                        h("modificarFuerza", cuando="continua", valor=1,
                                          objetivo={"quien": "esta_carta"})])
    qadesh = talisman("Qadesh", 5, [h("destruir", objetivo={"quien": "cualquiera", "tipos": ["Aliado"],
                                                            "seleccion": "todos"})])
    mercado = talisman("Mercado Egipcio", 5, [h("botar", cantidadSegun="oros_que_controla",
                                                objetivo={"quien": "oponente"})])
    p.j(0).mano = []
    for c in (_akhet(), lanza, qadesh, mercado, aliado("Dario", 3, 4), aliado("Roxana", 2, 2)):
        en_zona(p, 0, c, Zona.MANO)
    tiradas = YO.elegir_descartes(p, 0, list(p.j(0).mano), 2)
    assert {c.nombre for c in tiradas} == {"Qadesh", "Mercado Egipcio"}


# ── T13 (Sacerdote vs Héroe): Ritón no se usa si Nuh trae el Arma gratis ────
def test_riton_no_si_nuh_trae_el_arma_gratis():
    riton = oro("Riton Aqueménida", [h("buscar", cuando="activada", zonaDestino="mano",
                                       costo={"fondoMazoEstaCarta": True, "oros": 2},
                                       objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Tótem", "Arma"]})])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 3
    r = en_zona(p, 0, riton, Zona.RESERVA)
    en_defensa(p, 0, aliado("Portador", 2, 2))  # el Arma se podría usar este turno
    en_zona(p, 0, arma("Mandoble De Seth", 3, []), Zona.CEMENTERIO)
    assert _vale(p, _activar(r))
    nuh = en_zona(p, 0, _nuh(), Zona.MANO)
    assert not _vale(p, _activar(r))  # Nuh en la mano
    p._mover(nuh, Zona.DEFENSA)
    assert not _vale(p, _activar(r))  # Nuh ya en mesa


# ── T15: la Lanza de Osiris va al que más amenaza como atacante ─────────────
def test_lanza_al_que_mas_amenaza():
    p = partida()
    lanza = h("restringirCombate", modo="no_puede_atacar", objetivo={"quien": "oponente", "tipos": ["Aliado"]})
    julio = en_defensa(p, 1, aliado("Julio Cesar", 4, 4, [h(
        "modificarFuerza", cuando="continua", valor=1,
        objetivo={"quien": "propio", "tipos": ["Aliado"], "seleccion": "todos", "excluirEstaCarta": True})]))
    minos = en_defensa(p, 1, aliado("Rey Minos", 2, 2, [
        h("buscar", cuando="al_hacer_dano", zonaDestino="mano",
          objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"]}),
        {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}]))
    assert hab.fuerza(p, minos) == 3
    assert YO.elegir_objetivos(p, 0, [julio, minos], 1, lanza) == [minos]
