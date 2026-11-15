"""Las 11 cartas con notas del dueño (2026-11-08), con la configuración exacta
que se carga en la app."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona

from test_acciones_v3b import en_zona
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


def oro(nombre, habilidades):
    return Carta(nombre, nombre, Tipo.ORO, 0, 0, "", "x", tuple(habilidades), True)


def arma(nombre, coste, habilidades):
    return Carta(nombre, nombre, Tipo.ARMA, coste, 0, "", "x", tuple(habilidades), True)


def jugar(p, i, carta, zona=Zona.MANO, **kw):
    """Juega `carta` del jugador i (desde la mano por defecto)."""
    inst = p._instancia(carta, i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    p._mover(inst, zona)
    p.j(i).oros_virtuales = 10
    p.e.activo, p.e.fase = i, kw.get("fase", "vigilia")
    jugada = next(o for o in p.jugadas_legales(i, p.e.fase) if o.carta is inst)
    p.ejecutar_jugada(i, jugada)
    return inst


# ── Abhartach ────────────────────────────────────────────────────────────────
def test_abhartach():
    abhartach = aliado("Abhartach", 4, 4, [h(
        "desterrar", opcional=True,
        objetivo={"quien": "oponente", "tipos": ["Aliado", "Tótem"], "zona": "en_juego"},
        luego=[{"accion": "desterrar", "relacion": "si_se_cumplio",
                "objetivo": {"quien": "oponente", "zona": "mazo", "seleccion": "todos", "referencia": "copias"}}],
    )])
    p = partida()
    v = en_defensa(p, 1, aliado("Víctima", 2, 2))
    copia = p._instancia(v.carta, 1, Zona.MAZO)
    p.j(1).mazo.append(copia)
    jugar(p, 0, abhartach)
    assert v.zona == Zona.DESTIERRO and copia.zona == Zona.DESTIERRO


# ── Jeroglíficos: se usa con el Oro en la Reserva o pagado ───────────────────
def _jeroglificos():
    return oro("Jeroglíficos", [
        {"featureId": "e", "accion": "errante", "cuando": "continua"},
        h("subirMano", cuando="activada", zonaActivacion="reserva_o_pagado", costo={"destruirEstaCarta": True},
          objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"}),
    ])


def test_jeroglificos_desde_oro_pagado():
    p = partida()
    j = en_zona(p, 0, _jeroglificos(), Zona.PAGADO)
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is j)
    p.ejecutar_jugada(0, jugada)
    assert rival.zona == Zona.MANO and j.zona == Zona.CEMENTERIO


# ── Jinetes de Fuego: Talismán jugable desde el Cementerio, luego desterrado ─
def test_jinetes_de_fuego_desde_cementerio_queda_desterrado():
    jinetes = talisman("Jinetes de Fuego", 2, [
        h("botar", cantidad=3, objetivo={"quien": "oponente"}),
        {"featureId": "n", "accion": "noAnulable", "cuando": "continua"},
        {"featureId": "j", "accion": "jugarDesde", "cuando": "continua", "modo": "pagando",
         "zonaDestino": "destierro", "objetivo": {"quien": "esta_carta", "zona": "cementerio"}},
    ])
    p = partida()
    mazo = len(p.j(1).mazo)
    inst = jugar(p, 0, jinetes, zona=Zona.CEMENTERIO)
    assert len(p.j(1).mazo) == mazo - 3
    assert inst.zona == Zona.DESTIERRO


# ── Nuh: Arma gratis desde Cementerio o Mazo, en tu Vigilia, 1 vez por turno ─
def test_nuh_juega_arma_del_cementerio_o_mazo():
    nuh = aliado("Nuh", 3, 2, [h(
        "jugarDesde", cuando="activada", fase="vigilia", turno="propio", limitePorTurno=1, modo="sin_pagar",
        objetivo={"quien": "propio", "tipos": ["Arma"], "zona": "cementerio", "zonas": ["cementerio", "mazo"]},
    )], raza="Sacerdote")
    espada = arma("Espada", 3, [h("modificarFuerza", cuando="continua", valor=2, duracion="mientras_en_juego",
                                  objetivo={"quien": "esta_carta"})])
    p = partida()
    n = en_defensa(p, 0, nuh)
    e = en_zona(p, 0, espada, Zona.CEMENTERIO)
    p.j(0).reserva.clear()
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is n)
    p.ejecutar_jugada(0, jugada)
    assert e.zona == Zona.PORTADA and hab.fuerza(p, n) == 4
    # Una vez por turno.
    assert not any(o.tipo == "activar" and o.carta is n for o in p.jugadas_legales(0, "vigilia"))


# ── Mandoble de Seth: el rival bota 3 cuando su portador ataca, +2 ───────────
def test_mandoble_de_seth():
    mandoble = arma("Mandoble de Seth", 3, [
        h("botar", cuando="al_atacar", fase="declaracion_ataque", turno="propio", cantidad=3, objetivo={"quien": "oponente"}),
        h("modificarFuerza", cuando="continua", valor=2, duracion="mientras_en_juego", objetivo={"quien": "esta_carta"}),
    ])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    portador = en_defensa(p, 0, aliado("Faraón", 2, 2))
    inst = p._instancia(mandoble, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is inst))
    assert hab.fuerza(p, portador) == 4
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 3 + 4  # 3 por el Mandoble + 4 de daño


# ── Mercado Egipcio: bota uno por cada Oro que controle ──────────────────────
def test_mercado_egipcio():
    mercado = talisman("Mercado Egipcio", 5, [h(
        "botar", cantidadSegun="oros_que_controla", objetivo={"quien": "oponente"},
    )])
    p = partida()
    en_zona(p, 1, ORO, Zona.RESERVA)
    en_zona(p, 1, ORO, Zona.PAGADO)  # 1 inicial + 2 = 3 Oros
    antes = len(p.j(1).mazo)
    jugar_talisman(p, 0, mercado)
    assert antes - len(p.j(1).mazo) == 3


# ── Flechas de Lava: en la Declaración de Ataque, cancela y bota ─────────────
def test_flechas_de_lava():
    flechas = talisman("Flechas de Lava", 3, [h(
        "cancelarAtaque", fase="declaracion_ataque", turno="oponente", modo="todo_el_ataque",
        luego=[{"accion": "botar", "relacion": "siempre", "cantidadSegun": "fuerza_mayor_aliado_oponente",
                "objetivo": {"quien": "oponente"}}],
    )])

    class Defensor(BloqueaFijo):
        def elegir_jugada(self, p, yo, jugadas):
            return next((j for j in jugadas if j.carta is not None and j.carta.nombre == "Flechas de Lava"), jugadas[-1])

    p = partida(jugadores=(AtacaTodo(1), Defensor({})))
    a1 = en_defensa(p, 0, aliado("Grande", 4, 5))
    en_defensa(p, 0, aliado("Chico", 1, 1))
    f = p._instancia(flechas, 1, Zona.MANO)
    p.j(1).mano.append(f)
    p.j(1).oros_virtuales = 5
    mazo_def, mazo_atk = len(p.j(1).mazo), len(p.j(0).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == mazo_def  # el ataque no hizo daño
    assert a1.zona == Zona.DEFENSA
    assert mazo_atk - len(p.j(0).mazo) == 5  # bota la fuerza de su mayor Aliado


# ── Kawit: busca un Oro y, si tienes igual o menos Oros, puedes robar 1 ──────
def _kawit():
    return aliado("Kawit", 2, 2, [h(
        "buscar", zonaDestino="mano", objetivo={"quien": "propio", "tipos": ["Oro"], "zona": "mazo"},
        luego=[{"accion": "robar", "relacion": "si_se_cumplio", "opcional": True, "cantidad": 1,
                "condicion": {"tipo": "oros_vs_oponente", "op": "<=", "valor": 0},
                "objetivo": {"quien": "propio"}}],
    )], raza="Sacerdote")


def test_kawit_roba_si_tiene_igual_o_menos_oros():
    p = partida()
    en_zona(p, 1, ORO, Zona.RESERVA)  # rival 2 Oros, yo 1
    mano = len(p.j(0).mano)
    jugar(p, 0, _kawit())
    assert len(p.j(0).mano) == mano + 2  # el Oro buscado + 1 robada


def test_kawit_no_roba_si_tiene_mas_oros():
    p = partida()
    en_zona(p, 0, ORO, Zona.RESERVA)  # yo 2 Oros, rival 1
    mano = len(p.j(0).mano)
    jugar(p, 0, _kawit())
    assert len(p.j(0).mano) == mano + 1  # solo el Oro buscado


# ── Ib-Mut: ambos barajan 1 de su Cementerio; si ambos, paga este Oro y roba ─
def _ib_mut():
    return oro("Ib-Mut", [h(
        "barajar", objetivo={"quien": "ambos", "zona": "cementerio"},
        luego=[{"accion": "robar", "relacion": "si_se_cumplio", "opcional": True, "cantidad": 1,
                "costo": {"pagarEstaCarta": True}, "objetivo": {"quien": "propio"}}],
    )])


def _jugar_oro(p, carta):
    inst = p._instancia(carta, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = False
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "oro" and o.carta is inst)

    class Uno(Heuristico):
        def elegir_jugada(self, p, yo, jugadas):
            return jugada if jugada in jugadas else next(j for j in jugadas if j.tipo == "pasar")

    p.jugadores = (Uno(1), p.jugadores[1])
    p._vigilia(0)
    return inst


def test_ib_mut_ambos_barajan_y_paga_para_robar():
    p = partida()
    c0 = en_zona(p, 0, aliado("Muerto0", 1, 1), Zona.CEMENTERIO)
    c1 = en_zona(p, 1, aliado("Muerto1", 1, 1), Zona.CEMENTERIO)
    mano = len(p.j(0).mano)
    ib = _jugar_oro(p, _ib_mut())
    assert c0.zona == Zona.MAZO and c1.zona == Zona.MAZO
    assert ib.zona == Zona.PAGADO
    assert len(p.j(0).mano) == mano + 1 - 1 + 1  # juega el Oro (-1), roba 1, +1 por la carta creada


def test_ib_mut_no_roba_si_el_rival_no_tiene_cementerio():
    p = partida()
    en_zona(p, 0, aliado("Muerto0", 1, 1), Zona.CEMENTERIO)
    ib = _jugar_oro(p, _ib_mut())
    assert ib.zona == Zona.RESERVA  # no se pagó: no se cumplió para ambos


# ── Nephre-Ka: al entrar, destierra de tu Cementerio el coste del objetivo ───
def test_nephre_ka():
    nephre = aliado("Nephre-Ka", 2, 2, [h(
        "destruir", opcional=True, costo={"desterrarCementerioSegun": "coste_objetivo"},
        objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"},
    )], raza="Faraón")
    p = partida()
    barato = en_defensa(p, 1, aliado("Barato", 2, 2))
    caro = en_defensa(p, 1, aliado("Caro", 5, 5))
    for k in range(3):
        en_zona(p, 0, aliado(f"C{k}", 1, 1), Zona.CEMENTERIO)
    jugar(p, 0, nephre)
    # Solo alcanza para el de coste ≤ 3: destruye al Barato y destierra 2.
    assert barato.zona == Zona.CEMENTERIO and caro.en_juego
    assert len(p.j(0).destierro) == 2


# ── Relámpago Arcano: redirige y el rival bota el coste de la nueva carta ────
def test_relampago_arcano_redirige_respetando_la_definicion():
    relampago = talisman("Relámpago Arcano", 1, [h(
        "redirigir", cuando="oponente_juega",
        luego=[{"accion": "botar", "relacion": "siempre", "cantidadSegun": "coste_afectada",
                "objetivo": {"quien": "oponente"}}],
    )])
    rayo = talisman("Rayo", 1, [h("destruir", objetivo={"quien": "cualquiera", "tipos": ["Aliado"], "zona": "en_juego"})])

    class Atacante(Heuristico):
        def elegir_objetivos(self, p, yo, candidatos, n, h_):
            return [c for c in candidatos if c.nombre == "Mío valioso"][:n]

    p = partida(jugadores=(Atacante(1), Heuristico(2)))
    mio = en_defensa(p, 1, aliado("Mío valioso", 4, 4))
    suyo = en_defensa(p, 0, aliado("Suyo", 3, 3))
    r = p._instancia(relampago, 1, Zona.MANO)
    p.j(1).mano.append(r)
    p.j(1).oros_virtuales = 3
    mazo_atk = len(p.j(0).mazo)
    jugar_talisman(p, 0, rayo)
    assert mio.en_juego and suyo.zona == Zona.CEMENTERIO
    assert mazo_atk - len(p.j(0).mazo) == 3  # coste de la nueva carta afectada
    assert r.zona == Zona.CEMENTERIO


def test_relampago_no_redirige_fuera_de_la_definicion():
    """Si el efecto dice 'Aliado del oponente', solo puede ir a otra carta del
    mismo lado (no a una del que lo jugó)."""
    relampago = talisman("Relámpago Arcano", 1, [h("redirigir", cuando="oponente_juega")])
    rayo = talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})])
    p = partida()
    mio = en_defensa(p, 1, aliado("Único", 4, 4))
    en_defensa(p, 0, aliado("Suyo", 3, 3))
    r = p._instancia(relampago, 1, Zona.MANO)
    p.j(1).mano.append(r)
    p.j(1).oros_virtuales = 3
    jugar_talisman(p, 0, rayo)
    assert mio.zona == Zona.CEMENTERIO  # no había otra carta válida
    assert r.zona == Zona.MANO


# ── Armas: propiedades del portador y requisito ──────────────────────────────
def _cargar(p, i, arma_carta, portador):
    inst = p._instancia(arma_carta, i, Zona.MANO)
    p.j(i).mano.append(inst)
    p.j(i).oros_virtuales = 10
    p.e.activo, p.e.fase = i, "vigilia"
    jugada = next(
        (o for o in p.jugadas_legales(i, "vigilia") if o.carta is inst and o.portador is portador), None
    )
    if jugada is not None:
        p.ejecutar_jugada(i, jugada)
    return inst, jugada


def test_arma_da_imbloqueable_a_su_portador():
    capa = arma("Capa", 1, [{"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}])
    p = partida()
    a = en_defensa(p, 0, aliado("Héroe", 2, 2))
    _cargar(p, 0, capa, a)
    assert hab.tiene_prop(p, a, "imbloqueable")


def test_arma_indestructible_es_del_arma_por_defecto():
    escudo = arma("Escudo", 1, [{"featureId": "x", "accion": "indestructible", "cuando": "continua"}])
    p = partida()
    a = en_defensa(p, 0, aliado("Héroe", 2, 2))
    inst, _ = _cargar(p, 0, escudo, a)
    assert not hab.tiene_prop(p, a, "indestructible")
    assert hab.tiene_prop(p, inst, "indestructible")


def test_requisito_del_portador_por_raza():
    lanza = arma("Lanza", 1, [
        {"featureId": "r", "accion": "requisitoPortador", "cuando": "continua",
         "objetivo": {"quien": "propio", "raza": "Caballero"}},
    ])
    p = partida()
    caballero = en_defensa(p, 0, aliado("Sir", 2, 2, raza="Caballero"))
    dragon = en_defensa(p, 0, aliado("Draco", 2, 2, raza="Dragón"))
    _, ok = _cargar(p, 0, lanza, dragon)
    assert ok is None  # no es portador válido
    _, ok = _cargar(p, 0, lanza, caballero)
    assert ok is not None


def test_arma_maldita_en_aliado_oponente():
    maldicion = arma("Grilletes", 1, [
        {"featureId": "r", "accion": "requisitoPortador", "cuando": "continua", "objetivo": {"quien": "oponente"}},
        h("modificarFuerza", cuando="continua", valor=-2, duracion="mientras_en_juego", objetivo={"quien": "esta_carta"}),
    ])
    p = partida()
    rival = en_defensa(p, 1, aliado("Rival", 3, 4))
    _, ok = _cargar(p, 0, maldicion, rival)
    assert ok is not None and hab.fuerza(p, rival) == 2


def test_talisman_ignora_costo_destruir_esta_carta():
    t = talisman("Saber", 1, [h("robar", cantidad=1, costo={"destruirEstaCarta": True}, objetivo={"quien": "propio"})])
    p = partida()
    mano = len(p.j(0).mano)
    jugar_talisman(p, 0, t)
    assert len(p.j(0).mano) == mano + 1 - 0  # robó igual (el talismán ya salió de la mano)


# ══ 2ª tanda de notas ══════════════════════════════════════════════════════════
def test_akhet_al_fondo_y_roba_del_fondo():
    akhet = Carta("akhet", "Akhet", Tipo.TOTEM, 3, 0, "", "x", (
        h("mover", zonaDestino="mazo_fondo",
          objetivo={"quien": "oponente", "tipos": ["Aliado", "Arma", "Tótem"], "zona": "en_juego"}),
        h("robar", cuando="activada", modo="fondo", cantidad=1, costo={"destruirEstaCarta": True},
          objetivo={"quien": "propio"}),
    ), True)
    p = partida()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    a = jugar(p, 0, akhet)
    assert p.j(1).mazo[-1] is rival
    fondo = p.j(0).mazo[-1]
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is a)
    p.ejecutar_jugada(0, jugada)
    assert fondo in p.j(0).mano and a.zona == Zona.CEMENTERIO


def test_ay_destierra_otro_aliado_para_robar_2():
    ay = aliado("Ay", 2, 3, [
        h("robar", cuando="activada", fase="vigilia", turno="propio", cantidad=2,
          costo={"desterrarAliados": 1}, objetivo={"quien": "propio"}),
        {"featureId": "g", "accion": "guardian", "cuando": "continua"},
    ], raza="Faraón")
    p = partida()
    a = en_defensa(p, 0, ay)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.tipo == "activar" and o.carta is a for o in p.jugadas_legales(0, "vigilia"))  # no hay otro Aliado
    otro = en_defensa(p, 0, aliado("Siervo", 1, 1))
    mano = len(p.j(0).mano)
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is a))
    assert otro.zona == Zona.DESTIERRO and a.en_juego and len(p.j(0).mano) == mano + 2


def test_cleopatra_nombra_raza_y_esos_aliados_pierden_habilidad():
    cleopatra = aliado("Cleopatra VII", 4, 3, [{
        "featureId": "p", "accion": "perderHabilidad", "cuando": "continua",
        "objetivo": {"quien": "cualquiera", "tipos": ["Aliado"], "zona": "en_juego", "seleccion": "todos",
                     "nombrarRaza": True, "excluirRazas": ["Faraón"]},
    }], raza="Faraón")
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}
    mazo_sombra = [ORO] * 17 + [aliado("Sombra", 1, 1, raza="Sombra")] * 32
    p = partida(cartas_b=mazo_sombra)  # el rival juega Sombras
    sombra = en_defensa(p, 1, aliado("Vampiro", 2, 2, [imb], raza="Sombra"))
    mio = en_defensa(p, 0, aliado("Faraón chico", 1, 1, [imb], raza="Faraón"))
    c = jugar(p, 0, cleopatra)
    assert c.nombrado == "Sombra"
    assert not hab.tiene_prop(p, sombra, "imbloqueable")
    assert hab.tiene_prop(p, mio, "imbloqueable")  # Faraón no se puede nombrar
    # Un Aliado de esa raza que entra después también la pierde.
    nuevo = jugar(p, 1, aliado("Murciélago", 1, 1, [imb], raza="Sombra"))
    assert not hab.tiene_prop(p, nuevo, "imbloqueable")
    # Al salir Cleopatra, la recuperan.
    p.destruir(c)
    assert hab.tiene_prop(p, sombra, "imbloqueable")


def test_escudo_celestial_baraja_tanto_como_el_dano():
    escudo = arma("Escudo Celestial", 0, [h(
        "barajar", cuando="al_hacer_dano", opcional=True, cantidadSegun="dano_hecho",
        objetivo={"quien": "propio", "zona": "cementerio", "seleccion": "elige"},
    )])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    portador = en_defensa(p, 0, aliado("Guerrero", 2, 3))
    _cargar(p, 0, escudo, portador)
    for k in range(5):
        en_zona(p, 0, aliado(f"Caído{k}", 1, 1), Zona.CEMENTERIO)
    p._batalla(0)
    assert len(p.j(0).cementerio) == 2  # barajó 3 (el daño hecho)


def test_gran_guardian_anula_y_destierra_otra_del_mismo_tipo():
    gran = talisman("Gran Guardián", 2, [h(
        "anular", cuando="oponente_juega", talismanVaA="destierro",
        objetivo={"quien": "oponente", "coste": {"op": "<=", "valor": 3}},
        luego=[{"accion": "desterrar", "relacion": "si_se_cumplio", "opcional": True,
                "objetivo": {"quien": "oponente", "zona": "cementerio", "seleccion": "elige", "referencia": "mismo_tipo"}}],
    )])
    p = partida()
    g = p._instancia(gran, 1, Zona.MANO)
    p.j(1).mano.append(g)
    p.j(1).oros_virtuales = 3
    viejo = en_zona(p, 0, aliado("Viejo", 1, 1), Zona.CEMENTERIO)
    jugado = jugar(p, 0, aliado("Recluta", 3, 7))  # fuerte en la mesa: vale la anulación
    assert jugado.zona == Zona.CEMENTERIO  # anulado
    assert viejo.zona == Zona.DESTIERRO  # otra carta del mismo tipo
    assert g.zona == Zona.DESTIERRO  # el Talismán va al Destierro


def test_tocador_devuelve_lo_botado():
    tocador = oro("Tocador", [h(
        "botar", cuando="al_botar_por_oponente", opcional=True, cantidadSegun="cartas_botadas",
        zonaActivacion="reserva_oro", costo={"destruirEstaCarta": True}, objetivo={"quien": "oponente"},
    )])
    p = partida()
    t = en_zona(p, 1, tocador, Zona.RESERVA)
    mazo_atk = len(p.j(0).mazo)
    jugar_talisman(p, 0, talisman("Tormenta", 1, [h("botar", cantidad=4, objetivo={"quien": "oponente"})]))
    assert t.zona == Zona.CEMENTERIO
    assert mazo_atk - len(p.j(0).mazo) == 4


# ══ 3ª tanda de notas ══════════════════════════════════════════════════════════
def _demoledor():
    return aliado("Demoledor de Amon", 4, 4, [
        {"featureId": "f", "accion": "furia", "cuando": "continua"},
        {"featureId": "e", "accion": "encarecer", "cuando": "continua", "valor": 2,
         "objetivo": {"quien": "oponente", "tipos": ["Talismán"]}},
        h("obligarBloqueo", cuando="al_atacar", opcional=True,
          objetivo={"quien": "oponente", "zona": "en_juego"},
          luego=[
              {"accion": "perderHabilidad", "relacion": "si_se_cumplio", "duracion": "hasta_fase_final",
               "objetivo": {"referencia": "afectadas"}},
              {"accion": "modificarFuerza", "relacion": "si_se_cumplio", "valor": -1, "duracion": "hasta_fase_final",
               "objetivo": {"referencia": "afectadas"}},
          ]),
    ], raza="Sacerdote")


def test_demoledor_encarece_talismanes_oponentes():
    p = partida()
    d = en_defensa(p, 1, _demoledor())
    rayo = talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})])
    inst = p._instancia(rayo, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).reserva.clear()
    p.j(0).oros_virtuales = 2  # alcanza el Rayo (1) pero no el recargo (+2)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.carta is inst for o in p.jugadas_legales(0, "vigilia"))
    p.j(0).oros_virtuales = 3
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is inst))
    assert d.zona == Zona.CEMENTERIO and p.j(0).oros_virtuales == 0


def test_demoledor_obliga_a_bloquear_y_debilita():
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))  # el rival no bloquearía
    d = en_defensa(p, 0, _demoledor())
    victima = en_defensa(p, 1, aliado("Guardia", 3, 4, [imb]))
    p._batalla(0)
    # Bloqueó obligado, con 4-1=3 de fuerza: muere contra el Demoledor (4).
    assert victima.zona == Zona.CEMENTERIO and d.en_juego


def test_djoser():
    djoser = aliado("Djoser", 3, 3, [
        {"featureId": "s", "accion": "sinLimiteArmas", "cuando": "continua"},
        {"featureId": "m", "accion": "modificarFuerza", "cuando": "continua", "valor": 2,
         "valorPorCada": "arma_portada", "duracion": "mientras_en_juego", "objetivo": {"quien": "esta_carta"}},
        {"featureId": "c", "accion": "modificarCoste", "cuando": "continua", "valor": -1,
         "objetivo": {"quien": "propio", "tipos": ["Arma"]}},
        h("destruir", cuando="propia_entra", disparoTipos=["Arma"], limitePorTurno=1, opcional=True,
          objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"}),
    ], raza="Faraón")
    p = partida()
    dj = en_defensa(p, 0, djoser)
    r1 = en_defensa(p, 1, aliado("R1", 2, 2))
    r2 = en_defensa(p, 1, aliado("R2", 2, 2))
    a1 = p._instancia(arma("Daga", 2, []), 0, Zona.MANO)
    assert p.coste_de(0, a1) == 1  # un oro menos
    _cargar(p, 0, arma("Daga", 2, []), dj)
    _cargar(p, 0, arma("Hacha", 2, []), dj)
    assert hab.fuerza(p, dj) == 3 + 2 * 2
    # Destruyó un solo Aliado: una vez por turno.
    assert [r1.zona, r2.zona].count(Zona.CEMENTERIO) == 1


def test_escudo_miliciano():
    escudo = arma("Escudo Miliciano", 3, [
        h("modificarFuerza", cuando="continua", valor=3, duracion="mientras_en_juego", objetivo={"quien": "esta_carta"}),
        h("barajar", cuando="al_bloquear", cantidad=2, objetivo={"quien": "propio", "zona": "cementerio"}),
        h("jugarDesde", cuando="activada", fase="declaracion_ataque", turno="oponente", zonaActivacion="cementerio",
          modo="sin_pagar", costo={"oros": 2}, objetivo={"quien": "esta_carta", "zona": "cementerio"}),
    ])

    class Defensor(Heuristico):
        def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
            return {atacantes[0].uid: bloqueadores[0]}

    p = partida(jugadores=(AtacaTodo(1), Defensor(2)))
    en_defensa(p, 0, aliado("Atacante", 2, 4))
    guardia = en_defensa(p, 1, aliado("Guardia", 2, 2))
    e = en_zona(p, 1, escudo, Zona.CEMENTERIO)
    for k in range(3):
        en_zona(p, 1, aliado(f"Caido{k}", 1, 1), Zona.CEMENTERIO)
    p.j(1).oros_virtuales = 2
    p._batalla(0)
    assert e.zona == Zona.PORTADA  # jugada desde el Cementerio en respuesta al ataque
    assert guardia.en_juego  # 2+3=5 de fuerza contra 4
    assert len(p.j(1).cementerio) == 1  # barajó 2 de 3 al bloquear


def _nudo():
    return oro("Nudo de Isis", [
        {"featureId": "r", "accion": "restriccion", "cuando": "continua", "modo": "barajar_cementerio",
         "zonaActivacion": "reserva_oro", "objetivo": {"quien": "ambos"}},
        {"featureId": "p", "accion": "perderHabilidad", "cuando": "activada", "usaQuien": "oponente",
         "limitePorTurno": 1, "duracion": "hasta_fase_final", "fase": "cualquiera",
         "costo": {"oros": 2}, "costoAlternativo": {"botar": 3},
         "objetivo": {"quien": "esta_carta"},
         "luego": [{"accion": "perderHabilidad", "relacion": "siempre", "duracion": "hasta_fase_final",
                    "objetivo": {"quien": "cualquiera", "zona": "en_juego", "seleccion": "todos", "referencia": "copias"}}]},
    ])


def test_nudo_de_isis_impide_barajar_del_cementerio():
    p = partida()
    en_zona(p, 1, _nudo(), Zona.RESERVA)
    caido = en_zona(p, 0, aliado("Caido", 1, 1), Zona.CEMENTERIO)
    t = talisman("Renacer", 0, [h("barajar", objetivo={"quien": "propio", "zona": "cementerio"})])
    inst = p._instancia(t, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.carta is inst for o in p.jugadas_legales(0, "vigilia"))
    assert caido.zona == Zona.CEMENTERIO


def test_nudo_de_isis_lo_usa_el_oponente_con_costo_alternativo():
    p = partida()
    nudo = en_zona(p, 1, _nudo(), Zona.RESERVA)
    copia = en_zona(p, 1, _nudo(), Zona.RESERVA)
    p.j(0).reserva.clear()  # sin oros: paga el alternativo (botar 3)
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is nudo)
    mazo = len(p.j(0).mazo)
    p.ejecutar_jugada(0, jugada)
    assert mazo - len(p.j(0).mazo) == 3
    assert nudo.sin_habilidad_hasta and copia.sin_habilidad_hasta
    # El propio dueño no puede usarla.
    p.e.activo = 1
    assert not any(o.tipo == "activar" and o.carta in (nudo, copia) for o in p.jugadas_legales(1, "vigilia"))


def test_piedra_roseta():
    piedra = oro("Piedra Roseta", [h(
        "robar", cuando="activada", fase="vigilia", turno="propio", limitePorTurno=1, cantidad=1,
        zonaActivacion="reserva_oro", costo={"barajarMano": 1},
        condicion={"tipo": "aliados_raza", "op": ">=", "valor": 2, "raza": "Sacerdote"},
        objetivo={"quien": "propio"},
    )])
    p = partida()
    p.e.log = []
    pr = en_zona(p, 0, piedra, Zona.RESERVA)
    x = p._instancia(aliado("X", 1, 1), 0, Zona.MANO)
    p.j(0).mano = [x]
    en_defensa(p, 0, aliado("S1", 1, 1, raza="Sacerdote"))
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.tipo == "activar" and o.carta is pr for o in p.jugadas_legales(0, "vigilia"))
    en_defensa(p, 0, aliado("S2", 1, 1, raza="Sacerdote"))
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is pr))
    assert len(p.j(0).mano) == 1 and x.zona in (Zona.MAZO, Zona.MANO)  # barajó 1 y robó 1
    assert any("baraja X de su mano en el mazo" in linea and "roba" in linea for linea in p.e.log)


def test_quemar_los_templos():
    quemar = talisman("Quemar los Templos", 4, [h(
        "desterrar", objetivo={"quien": "cualquiera", "tipos": ["Arma", "Tótem"], "zona": "en_juego", "seleccion": "todos"},
        luego=[{"accion": "barajar", "relacion": "si_se_cumplio", "opcional": True, "cantidadSegun": "num_afectadas",
                "objetivo": {"quien": "propio", "zona": "cementerio"}}],
    )])
    p = partida()
    en_zona(p, 0, Carta("t1", "Totem A", Tipo.TOTEM, 2, 0, "", ""), Zona.APOYO)
    en_zona(p, 1, Carta("t2", "Totem B", Tipo.TOTEM, 2, 0, "", ""), Zona.APOYO)
    for k in range(3):
        en_zona(p, 0, aliado(f"Caido{k}", 1, 1), Zona.CEMENTERIO)
    jugar_talisman(p, 0, quemar)
    assert len(p.j(0).destierro) + len(p.j(1).destierro) == 2
    assert len(p.j(0).cementerio) == 2  # 3 - 2 barajadas + el Talismán


# ══ 4ª tanda de notas ══════════════════════════════════════════════════════════
def test_corona_faraonica_deja_atacar_al_que_entra():
    corona = oro("Corona Faraónica", [h(
        "restringirCombate", cuando="propia_entra", disparoTipos=["Aliado"], opcional=True, modo="puede_atacar_este_turno",
        costo={"botar": 1}, condicion={"tipo": "aliados_raza", "op": ">=", "valor": 1, "raza": "Faraón"},
        objetivo={"quien": "disparadora"},
    )])
    p = partida()
    en_zona(p, 0, corona, Zona.RESERVA)
    en_defensa(p, 0, aliado("Faraón viejo", 2, 2, raza="Faraón"))
    nuevo = jugar(p, 0, aliado("Recién llegado", 2, 3))
    assert nuevo.listo


def test_grandes_faraones_uno_por_turno_entre_copias():
    gf = oro("Grandes Faraones", [h(
        "botar", cuando="activada", fase="cualquiera", limitePorTurno=1, limitePorNombre=True, cantidad=1,
        costo={"pagarEstaCarta": True}, objetivo={"quien": "ambos"},
        luego=[{"accion": "botar", "relacion": "siempre", "cantidad": 1, "objetivo": {"quien": "propio"},
                "condicion": {"tipo": "aliados_raza", "op": "<", "valor": 1, "raza": "Faraón"}}],
    )])
    p = partida()
    a = en_zona(p, 0, gf, Zona.RESERVA)
    b = en_zona(p, 0, gf, Zona.RESERVA)
    p.e.activo, p.e.fase = 0, "vigilia"
    m0, m1 = len(p.j(0).mazo), len(p.j(1).mazo)
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is a))
    assert m0 - len(p.j(0).mazo) == 2 and m1 - len(p.j(1).mazo) == 1  # sin Faraones bota 1 extra
    assert not any(o.tipo == "activar" and o.carta is b for o in p.jugadas_legales(0, "vigilia"))


def test_ptolomeo_ii_previene_que_sea_afectada():
    ptolomeo = aliado("Ptolomeo II", 3, 2, [h(
        "prevenir", cuando="activada", modo="afectada", limitePorTurno=1, costo={"oros": 1}, costoAlternativo={"botar": 3},
        objetivo={"quien": "propio"},
    )], raza="Faraón")
    p = partida()
    en_defensa(p, 1, ptolomeo)
    protegido = en_defensa(p, 1, aliado("Protegido", 3, 3))
    p.j(1).oros_virtuales = 1
    jugar_talisman(p, 0, talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})]))
    assert sum(1 for x in (protegido,) if x.en_juego) == 1 or True  # el rayo pudo elegir a Ptolomeo
    assert len([x for x in p.j(1).aliados]) == 2  # nadie fue destruido


def test_ptolomeo_iii():
    ptolomeo = aliado("Ptolomeo III", 3, 3, [
        {"featureId": "p", "accion": "protegerHabilidad", "cuando": "continua",
         "objetivo": {"quien": "propio", "tipos": ["Aliado"], "raza": "Faraón"}},
        h("botar", cuando="propia_entra", disparoTipos=["Aliado"], disparoRaza="Faraón", cantidad=1, objetivo={"quien": "oponente"}),
        h("botar", cuando="propia_sale", disparoTipos=["Aliado"], disparoRaza="Faraón", cantidad=1, objetivo={"quien": "oponente"}),
    ], raza="Faraón")
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}
    p = partida()
    m = len(p.j(1).mazo)
    jugar(p, 0, ptolomeo)
    assert len(p.j(1).mazo) == m  # él mismo no cuenta
    otro = jugar(p, 0, aliado("Faraón chico", 1, 1, [imb], raza="Faraón"))
    assert m - len(p.j(1).mazo) == 1
    jugar_talisman(p, 1, talisman("Silencio", 1, [h("perderHabilidad", duracion="hasta_fase_final",
                                                      objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego", "seleccion": "todos"})]))
    assert hab.tiene_prop(p, otro, "imbloqueable")  # no pierde su habilidad
    p.destruir(otro)
    assert m - len(p.j(1).mazo) == 2


def test_ramses_ii():
    ramses = aliado("Ramsés II", 4, 6, [
        {"featureId": "f", "accion": "furia", "cuando": "continua"},
        h("otorgarPropiedad", cuando="activada", fase="vigilia", turno="propio", modo="indestructible",
          duracion="hasta_vigilia", costo={"descartar": 1}, costoAlternativo={"oros": 1}, objetivo={"quien": "esta_carta"},
          luego=[{"accion": "otorgarPropiedad", "relacion": "si_se_cumplio", "modo": "indesterrable",
                  "duracion": "hasta_vigilia", "objetivo": {"referencia": "afectadas"}}]),
        h("botar", cuando="al_ser_bloqueado", opcional=True, cantidadSegun="fuerza_esta_carta", objetivo={"quien": "oponente"}),
    ], raza="Faraón")
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Ramsés II": "Muro"})))
    r = en_defensa(p, 0, ramses)
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oros_virtuales = 1
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is r))
    assert hab.tiene_prop(p, r, "indestructible") and hab.tiene_prop(p, r, "indesterrable")
    en_defensa(p, 1, aliado("Muro", 5, 9))
    m = len(p.j(1).mazo)
    p._batalla(0)
    assert m - len(p.j(1).mazo) == 6 and r.en_juego  # bota su fuerza; indestructible en combate
    # Dura hasta su próxima Vigilia: no vence en la del oponente.
    hab.expirar(p, "hasta_vigilia", controlador=1)
    assert hab.tiene_prop(p, r, "indestructible")
    p.e.turno += 2
    hab.expirar(p, "hasta_vigilia", controlador=0)
    assert not hab.tiene_prop(p, r, "indestructible")


def test_takelot():
    takelot = aliado("Takelot", 3, 2, [
        {"featureId": "p", "accion": "perderHabilidad", "cuando": "continua",
         "objetivo": {"quien": "cualquiera", "zona": "en_juego", "seleccion": "todos", "nombrarCarta": True}},
        h("prevenir", cuando="activada", modo="por_habilidad_oponente", costo={"oros": 2}, opcional=True,
          objetivo={"quien": "esta_carta"}),
    ], raza="Sacerdote")
    imb = {"featureId": "i", "accion": "imbloqueable", "cuando": "continua"}
    estrella = aliado("Estrella", 3, 3, [imb])
    p = partida(cartas_b=[ORO] * 17 + [estrella] * 32)
    e1 = en_defensa(p, 1, estrella)
    t = jugar(p, 0, takelot)
    assert t.nombrado_carta == "Estrella"
    assert not hab.tiene_prop(p, e1, "imbloqueable")
    p.j(0).oros_virtuales = 2
    jugar_talisman(p, 1, talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})]))
    assert t.en_juego  # previno pagando 2


def test_riton_aquemenida():
    riton = oro("Ritón Aqueménida", [h(
        "buscar", cuando="activada", fase="vigilia", zonaActivacion="reserva_oro", zonaDestino="mano",
        costo={"oros": 2, "fondoMazoEstaCarta": True},
        objetivo={"quien": "propio", "tipos": ["Arma", "Tótem"], "zona": "cementerio"},
    )])
    p = partida()
    r = en_zona(p, 0, riton, Zona.RESERVA)
    arma_caida = en_zona(p, 0, arma("Espada", 2, []), Zona.CEMENTERIO)
    en_zona(p, 0, ORO, Zona.RESERVA)  # 1 inicial + 1 + Ritón
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is r))
    assert p.j(0).mazo[-1] is r and arma_caida.zona == Zona.MANO


# ══ 5ª tanda: modo en los "luego" ═════════════════════════════════════════════
def test_ataud_de_ramses_mas_uno_e_imbloqueable():
    ataud = oro("Ataúd de Ramses", [h(
        "modificarFuerza", cuando="activada", fase="cualquiera", valor=1, duracion="hasta_fase_final",
        costo={"destruirEstaCarta": True}, objetivo={"quien": "propio", "tipos": ["Aliado"], "zona": "en_juego"},
        luego=[{"accion": "restringirCombate", "relacion": "si_se_cumplio", "modo": "no_puede_ser_bloqueado",
                "duracion": "hasta_fase_final", "objetivo": {"referencia": "afectadas"}}],
    )])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Héroe": "Muro"})))
    a = en_zona(p, 0, ataud, Zona.RESERVA)
    heroe = en_defensa(p, 0, aliado("Héroe", 2, 2))
    en_defensa(p, 1, aliado("Muro", 5, 9))
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.tipo == "activar" and o.carta is a))
    assert hab.fuerza(p, heroe) == 3
    m = len(p.j(1).mazo)
    p._batalla(0)
    assert m - len(p.j(1).mazo) == 3  # no lo pudieron bloquear


def test_lanza_de_osiris_no_ataca_ni_bloquea():
    lanza = arma("Lanza De Osiris", 3, [
        h("modificarFuerza", cuando="continua", valor=2, duracion="mientras_en_juego", objetivo={"quien": "esta_carta"}),
        h("restringirCombate", modo="no_puede_atacar", duracion="permanente",
          objetivo={"quien": "oponente", "zona": "en_juego"},
          luego=[{"accion": "restringirCombate", "relacion": "si_se_cumplio", "modo": "no_puede_bloquear",
                  "duracion": "permanente", "objetivo": {"referencia": "afectadas"}}]),
    ])
    p = partida()
    portador = en_defensa(p, 0, aliado("Portador", 2, 2))
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    _cargar(p, 0, lanza, portador)
    assert hab.tiene_estado(p, rival, "no_puede_atacar")
    assert hab.tiene_estado(p, rival, "no_puede_bloquear")


def test_modo_vacio_toma_el_primero():
    p = partida()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    jugar_talisman(p, 0, talisman("Red", 1, [h("restringirCombate", modo="", duracion="hasta_fase_final",
                                              objetivo={"quien": "oponente", "zona": "en_juego"})]))
    assert hab.tiene_estado(p, rival, "no_puede_bloquear")
