"""Acciones del catálogo unificado (casos dados por el dueño)."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona

from test_motor import (
    AtacaTodo,
    BloqueaFijo,
    ORO,
    aliado,
    en_defensa,
    h,
    jugar_talisman,
    partida,
    talisman,
)


def prop(accion):
    return {"featureId": accion, "accion": accion, "cuando": "continua"}


def en_zona(p, i, carta, zona):
    inst = p._instancia(carta, i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    p._mover(inst, zona)
    return inst


# ── Propiedades ───────────────────────────────────────────────────────────────
def test_guardian_no_ataca():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    g = en_defensa(p, 0, aliado("Muro", 2, 5, [prop("guardian")]))
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert g.zona == Zona.DEFENSA and len(p.j(1).mazo) == antes


def test_retador_obliga_a_bloquear():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))  # el rival no bloquearía
    en_defensa(p, 0, aliado("Retador", 2, 4, [prop("retador")]))
    victima = en_defensa(p, 1, aliado("Peón", 1, 1))
    p._batalla(0)
    assert victima.zona == Zona.CEMENTERIO


def test_errante_solo_una_copia():
    errante = aliado("Viajero", 1, 1, [prop("errante")])
    p = partida()
    vieja = en_defensa(p, 0, errante)
    nueva = p._instancia(errante, 0, Zona.MANO)
    p.j(0).mano.append(nueva)
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    # Con una copia en juego, la segunda no se puede jugar (MUh4: Killgharrah).
    assert not any(o.carta is nueva for o in p.jugadas_legales(0, "vigilia"))
    assert vieja.en_juego


# ── Restringir combate / cancelar ataque ──────────────────────────────────────
def test_restringir_combate_no_puede_bloquear():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Atk": "Blk"})))
    en_defensa(p, 0, aliado("Atk", 2, 3))
    blk = en_defensa(p, 1, aliado("Blk", 2, 5))
    blk.estados.append({"modo": "no_puede_bloquear", "duracion": "hasta_fase_final"})
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 3  # no pudo bloquear


def test_cancelar_todo_el_ataque_como_flechas_de_lava():
    flechas = talisman("Flechas de Lava", 1, [h("cancelarAtaque", fase="guerra_talismanes", modo="todo_el_ataque")])

    class Defensor(BloqueaFijo):
        def elegir_jugada(self, p, yo, jugadas):
            return next((j for j in jugadas if j.carta is not None and j.carta.nombre == "Flechas de Lava"), jugadas[-1])

    p = partida(jugadores=(AtacaTodo(1), Defensor({})))
    atk = en_defensa(p, 0, aliado("Atk", 2, 4))
    inst = p._instancia(flechas, 1, Zona.MANO)
    p.j(1).mano.append(inst)
    p.j(1).oros_virtuales = 3
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == antes
    assert atk.zona == Zona.DEFENSA


# ── Reducir daño desde el Cementerio (druida) ────────────────────────────────
def test_reducir_dano_a_cero_desterrando_desde_cementerio():
    druida = aliado(
        "Druida", 2, 1,
        [h("reducirDano", cuando="activada", fase="asignacion_dano", modo="dano_a_cero",
           zonaActivacion="cementerio", costo={"desterrarEstaCarta": True}, opcional=True)],
    )
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    en_defensa(p, 0, aliado("Atk", 2, 5))
    d = en_zona(p, 1, druida, Zona.CEMENTERIO)
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == antes
    assert d.zona == Zona.DESTIERRO


def test_aliado_sin_dano_este_turno():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    atk = en_defensa(p, 0, aliado("Atk", 2, 5))
    atk.estados.append({"modo": "aliado_sin_dano", "duracion": "hasta_fase_final"})
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == antes


# ── Control, mover, desterrar del tope ───────────────────────────────────────
def test_ganar_control_hasta_fase_final():
    p = partida()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    jugar_talisman(p, 0, talisman("Encantar", 2, [h(
        "ganarControl", duracion="hasta_fase_final",
        objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego", "coste": {"op": "<=", "valor": 3}},
    )]))
    assert rival.controlador == 0 and rival in p.j(0).defensa
    p.e.fase = "final"
    hab.revisar_controles(p)
    assert rival.controlador == 1 and rival in p.j(1).defensa


def test_mover_al_fondo_del_mazo():
    p = partida()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    jugar_talisman(p, 0, talisman("Remolino", 1, [h(
        "mover", zonaDestino="mazo_fondo",
        objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"},
    )]))
    assert p.j(1).mazo[-1] is rival


def test_desterrar_del_tope():
    p = partida()
    tope = p.j(1).mazo[:3]
    jugar_talisman(p, 0, talisman("Olvido", 1, [h(
        "desterrar", cantidad=3, objetivo={"quien": "oponente", "zona": "mazo", "seleccion": "tope"},
    )]))
    assert all(x.zona == Zona.DESTIERRO for x in tope)


# ── Oro, restricciones, inmunidad ─────────────────────────────────────────────
def test_oro_generado_solo_para_aliados_de_una_raza():
    p = partida()
    jugar_talisman(p, 0, talisman("Ofrenda", 0, [h("generarOro", valor=3, soloParaRaza="Sombra")]))
    p.j(0).oros_virtuales = 0
    sombra = p._instancia(aliado("Vampiro", 3, 3, raza="Sombra"), 0, Zona.MANO)
    otro = p._instancia(aliado("Caballero", 3, 3, raza="Caballero"), 0, Zona.MANO)
    p.j(0).reserva.clear()
    assert p.puede_pagar(0, sombra)
    assert not p.puede_pagar(0, otro)


def test_restriccion_no_se_puede_barajar_como_nudo_de_isis():
    nudo = Carta("Nudo", "Nudo de Isis", Tipo.ORO, 0, 0, "", "x", (h(
        "restriccion", cuando="continua", modo="barajar", zonaActivacion="reserva_oro", objetivo={"quien": "ambos"},
    ),), True)
    p = partida()
    en_zona(p, 1, nudo, Zona.RESERVA)
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    t = talisman("Torbellino", 1, [h("barajar", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})])
    inst = p._instancia(t, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).oros_virtuales = 3
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.carta is inst for o in p.jugadas_legales(0, "vigilia"))
    assert rival.en_juego


def test_inmunidad_a_talismanes_oponentes():
    inmune = aliado("Dendera", 4, 3, [{"featureId": "i", "accion": "inmunidad", "cuando": "continua", "objetivo": {"quien": "oponente", "tipos": ["Talismán"]}}])
    p = partida()
    d = en_defensa(p, 1, inmune)
    otro = en_defensa(p, 1, aliado("Otro", 1, 1))
    jugar_talisman(p, 0, talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego", "seleccion": "todos"})]))
    assert d.en_juego and otro.zona == Zona.CEMENTERIO


# ── Jugar desde otra zona, fuerza base, agrupar ──────────────────────────────
def test_invocador_juega_aliado_de_la_mano_sin_pagar():
    invocador = aliado("Invocador", 2, 1, [h(
        "jugarDesde", modo="sin_pagar",
        objetivo={"quien": "propio", "tipos": ["Aliado"], "zona": "mano", "coste": {"op": "<=", "valor": 4}},
    )])
    p = partida()
    gratis = p._instancia(aliado("Gigante", 4, 4), 0, Zona.MANO)
    p.j(0).mano.append(gratis)
    inv = p._instancia(invocador, 0, Zona.MANO)
    p.j(0).mano.append(inv)
    p.j(0).reserva.clear()
    p.j(0).oros_virtuales = 2
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is inv)
    p.ejecutar_jugada(0, jugada)
    assert gratis.zona == Zona.DEFENSA
    assert p.j(0).oros_virtuales == 0


def test_exhumar_se_juega_desde_el_cementerio():
    exhumar = aliado("Espectro", 2, 2, [{"featureId": "e", "accion": "jugarDesde", "cuando": "continua", "modo": "pagando", "objetivo": {"quien": "esta_carta"}}])
    p = partida()
    e = en_zona(p, 0, exhumar, Zona.CEMENTERIO)
    p.j(0).oros_virtuales = 2
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is e)
    p.ejecutar_jugada(0, jugada)
    assert e.zona == Zona.DEFENSA


def test_cancelar_bonificaciones_vuelve_a_fuerza_impresa():
    p = partida()
    a = en_defensa(p, 1, aliado("A", 2, 2))
    a.mods.append(hab.ModFuerza("sumar", 3, "permanente", 0))
    jugar_talisman(p, 0, talisman("Desencanto", 1, [h(
        "modificarFuerza", modoFuerza="base", duracion="hasta_fase_final",
        objetivo={"quien": "oponente", "zona": "en_juego"},
    )]))
    assert hab.fuerza(p, a) == 2


def test_agrupar_oros_del_oponente():
    p = partida()
    oro = en_zona(p, 1, ORO, Zona.PAGADO)
    jugar_talisman(p, 0, talisman("Gaitas", 0, [h("agrupar", modo="oros", objetivo={"quien": "oponente"})]))
    assert oro.zona == Zona.RESERVA


def test_no_agrupar_deja_los_oros_pagados():
    p = partida()
    oro = en_zona(p, 0, ORO, Zona.PAGADO)
    p.j(0).no_agrupar = "oros"
    p.e.activo = 0
    p.j(0).mano.clear()  # sin cartas: el turno solo agrupa
    p._turno()
    assert oro.zona == Zona.PAGADO


# ── Forma de Lince: efecto diferido si el afectado hizo daño ─────────────────
def _lince():
    return talisman("Forma de Lince", 1, [h(
        "modificarFuerza", valor=3, duracion="hasta_fase_final",
        objetivo={"quien": "propio", "zona": "en_juego", "seleccion": "elige"},
        luego=[{
            "accion": "robar", "relacion": "si_afectada_hizo_dano", "momento": "fase_final",
            "cantidad": 1, "objetivo": {"quien": "propio"},
        }],
    )])


def test_forma_de_lince_roba_si_el_aliado_hizo_dano():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    atk = en_defensa(p, 0, aliado("Gato", 2, 2))
    jugar_talisman(p, 0, _lince())
    assert hab.fuerza(p, atk) == 5
    p._batalla(0)
    mano = len(p.j(0).mano)
    p.e.fase = "final"
    hab.resolver_pendientes_final(p)
    assert len(p.j(0).mano) == mano + 1


def test_forma_de_lince_no_roba_si_fue_bloqueado_y_no_hizo_dano():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Gato": "Muro"})))
    en_defensa(p, 0, aliado("Gato", 2, 2))
    en_defensa(p, 1, aliado("Muro", 5, 9))
    jugar_talisman(p, 0, _lince())
    p._batalla(0)
    mano = len(p.j(0).mano)
    hab.resolver_pendientes_final(p)
    assert len(p.j(0).mano) == mano


# ── Oros que se usan pagándolos (Toro Apis) ──────────────────────────────────
def _toro_apis():
    return Carta("toro", "Toro Apis", Tipo.ORO, 0, 0, "", "x", (
        prop("indestructible"),
        h("modificarFuerza", cuando="activada", fase="cualquiera", valor=-1, duracion="hasta_fase_final",
          zonaActivacion="reserva_oro", costo={"pagarEstaCarta": True},
          objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"}),
    ), True)


def test_toro_apis_se_paga_para_quitar_fuerza():
    p = partida()
    toro = en_zona(p, 0, _toro_apis(), Zona.RESERVA)
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is toro)
    p.ejecutar_jugada(0, jugada)
    assert toro.zona == Zona.PAGADO
    assert hab.fuerza(p, rival) == 2
    # Ya pagado: no se puede volver a usar este turno.
    assert not any(o.tipo == "activar" and o.carta is toro for o in p.jugadas_legales(0, "vigilia"))


def test_talisman_no_queda_en_juego():
    p = partida()
    t = jugar_talisman(p, 0, talisman("Saber", 1, [h("robar", cantidad=1, objetivo={"quien": "propio"})]))
    assert t.zona == Zona.CEMENTERIO and not t.en_juego
    assert t not in p.e.instancias_en_juego()


# ── Werin el Poseído ─────────────────────────────────────────────────────────
def _werin():
    return aliado("Werin el Poseído", 2, 3, [
        {"featureId": "gen_inm", "accion": "inmunidad", "cuando": "continua",
         "objetivo": {"quien": "oponente", "tipos": ["Aliado"]}},
        h("buscar", cuando="al_salir_del_juego", opcional=True, zonaDestino="mano",
          objetivo={"quien": "propio", "tipos": ["Talismán"], "zona": "mazo"}),
    ], raza="Sacerdote")


def test_werin_inmune_a_habilidades_de_aliados_oponentes():
    asesino = aliado("Asesino", 3, 2, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego", "seleccion": "todos"})])
    debilitador = aliado("Sombra", 3, 2, [h("modificarFuerza", cuando="continua", valor=-2, duracion="mientras_en_juego", objetivo={"quien": "oponente", "zona": "en_juego"})])
    p = partida()
    werin = en_defensa(p, 1, _werin())
    otro = en_defensa(p, 1, aliado("Otro", 2, 3))
    en_defensa(p, 0, debilitador)
    assert hab.fuerza(p, werin) == 3 and hab.fuerza(p, otro) == 1
    a = en_defensa(p, 0, asesino)
    hab.resolver(p, 0, a, asesino.habilidades[0])
    assert werin.en_juego and otro.zona == Zona.CEMENTERIO
    # Un Talismán sí lo afecta.
    jugar_talisman(p, 0, talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})]))
    assert werin.zona == Zona.CEMENTERIO


def test_werin_al_salir_busca_un_talisman():
    p = partida()
    t = p._instancia(talisman("Buscado", 1, []), 1, Zona.MAZO)
    p.j(1).mazo.append(t)
    werin = en_defensa(p, 1, _werin())
    p.destruir(werin)
    assert t.zona == Zona.MANO


# ── Propiedades con condición ─────────────────────────────────────────────────
def test_no_anulable_solo_con_dos_aliados():
    no_anulable = {"featureId": "n", "accion": "noAnulable", "cuando": "continua",
                   "condicion": {"tipo": "aliados_propios", "op": ">=", "valor": 2}}
    carta = talisman("Plegaria", 1, [no_anulable, h("robar", cantidad=1, objetivo={"quien": "propio"})])
    anula = talisman("Contra", 1, [h("anular", cuando="oponente_juega", objetivo={"tipos": ["Talismán"]})])

    def jugar_con(n_aliados):
        p = partida()
        for k in range(n_aliados):
            en_defensa(p, 0, aliado(f"A{k}", 1, 1))
        c = p._instancia(anula, 1, Zona.MANO)
        p.j(1).mano.append(c)
        p.j(1).oros_virtuales = 3
        return hab.tiene_prop(p, p._instancia(carta, 0, Zona.MANO), "noAnulable")

    assert not jugar_con(1)
    assert jugar_con(2)


def test_imbloqueable_solo_en_tu_turno():
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua", "turno": "propio"}
    p = partida()
    x = en_defensa(p, 0, aliado("Escurridizo", 2, 2, [imb]))
    p.e.activo = 0
    assert hab.tiene_prop(p, x, "imbloqueable")
    p.e.activo = 1
    assert not hab.tiene_prop(p, x, "imbloqueable")
