"""Mecánicas que faltaban para dejar fieles al texto las cartas por completar
(Macha, Hienas, Fantasmas, Serpiente Roja, Cerbero, Destrozar la Mente,
Loch Lein, Venganza de Conall, Hipatia, Guerrero Fianna, Shay, Meleagro…)."""

from myl_sim import habilidades as hab
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida, talisman

AL = ["Aliado"]


def carta(nombre, tipo, coste, habs, fuerza=0, raza=""):
    return Carta(nombre, nombre, tipo, coste, fuerza, raza, "x", tuple(habs), True)


def _vigilia(p, oros, i=0):
    p.e.activo, p.e.fase = i, "vigilia"
    p.j(i).oro_jugado = True
    for _ in range(oros):
        en_zona(p, i, ORO, Zona.RESERVA)


def _todos(quien="cualquiera"):
    return {"seleccion": "todos", "zona": "en_juego", "tipos": AL, "quien": quien}


def test_macha_quita_modificadores_mientras_esta_en_juego():
    p = partida()
    x = en_defensa(p, 1, aliado("Bufado", 2, 2))
    en_defensa(p, 1, aliado("Rey", 3, 3, [{"accion": "modificarFuerza", "valor": 2, "cuando": "continua",
                                           "objetivo": _todos("propio")}]))
    assert hab.fuerza(p, x) == 4
    macha = en_defensa(p, 0, aliado("Macha", 4, 3, [
        {"accion": "modificarFuerza", "modoFuerza": "base", "cuando": "continua", "objetivo": _todos()}]))
    assert hab.fuerza(p, x) == 2
    p.sale_del_juego(macha, Zona.CEMENTERIO)
    assert hab.fuerza(p, x) == 4


def test_hienas_y_fantasmas_congelan_la_fuerza():
    p = partida()
    _vigilia(p, 3)
    x = en_defensa(p, 1, aliado("Grande", 3, 5))
    fant = en_zona(p, 0, talisman("Fantasmas", 3, [
        {"accion": "modificarFuerza", "modoFuerza": "fijar", "valor": 1, "congelar": True,
         "duracion": "hasta_fase_final", "cuando": "al_jugar", "cantidad": 99, "objetivo": _todos()}]), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", fant))
    assert hab.fuerza(p, x) == 1
    from myl_sim.modelo import ModFuerza
    x.mods.append(ModFuerza("sumar", 3, "hasta_fase_final", p.e.turno))
    assert hab.fuerza(p, x) == 1  # no puede volver a modificarse
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, x) == 5


def test_serpiente_roja_en_defensa_nadie_sale_del_juego():
    p = partida()
    serp = en_defensa(p, 0, aliado("Serpiente", 2, 4, [
        {"accion": "restriccion", "modo": "salir_del_juego", "cuando": "continua",
         "condicion": {"tipo": "esta_carta_en_linea", "zona": "linea_defensa", "valor": 1},
         "objetivo": {"quien": "ambos", "tipos": AL}}]))
    x = en_defensa(p, 1, aliado("Rival", 2, 2))
    assert not p.destruir(x) and x in p.j(1).aliados
    p._mover(serp, Zona.ATAQUE)
    assert p.destruir(x)


def test_cerbero_protege_solo_su_cementerio():
    p = partida()
    en_defensa(p, 0, aliado("Cerbero", 2, 4, [
        {"accion": "restriccion", "modo": "desterrar_cementerio", "cuando": "continua",
         "objetivo": {"quien": "oponente", "cementerioPropio": True}}], raza="Titán"))
    mio = en_zona(p, 0, aliado("Muerto", 1, 1), Zona.CEMENTERIO)
    suyo = en_zona(p, 1, aliado("Suyo", 1, 1), Zona.CEMENTERIO)
    h = {"accion": "desterrar", "objetivo": {"seleccion": "elige", "zona": "cementerio", "tipos": [],
                                             "quien": "cualquiera"}}
    fuente = en_defensa(p, 1, aliado("Ladron", 1, 1, [h]))
    cands = hab.candidatos_validos(p, 1, fuente, h)
    assert suyo in cands and mio not in cands


def test_destrozar_la_mente_descarta_solo_la_nombrada():
    p = partida()
    _vigilia(p, 2)
    for _ in range(3):
        en_zona(p, 1, aliado("Otra", 1, 1), Zona.MANO)
    a = en_zona(p, 1, aliado("Nombrada", 2, 2), Zona.MANO)
    b = en_zona(p, 1, aliado("Nombrada", 2, 2), Zona.MANO)
    t = en_zona(p, 0, talisman("Destrozar", 2, [
        {"accion": "descartar", "cuando": "al_jugar", "cantidad": 99,
         "objetivo": {"seleccion": "todos", "zona": "mano", "tipos": ["Aliado", "Talismán", "Arma", "Tótem"],
                      "quien": "oponente", "nombrarCarta": True, "eligeQuienJuega": True}}]), Zona.MANO)
    t.nombrado_carta = "Nombrada"
    hab.resolver(p, 0, t, t.habilidades[0])
    assert a.zona == b.zona == Zona.CEMENTERIO
    assert len(p.j(1).mano) == 3


def test_loch_lein_elige_el_oponente():
    p = partida()
    _vigilia(p, 2)
    loch = carta("Loch", Tipo.TOTEM, 2, [
        {"grupoElegir": "loch", "eligeOponente": True, "accion": "descartar", "cuando": "propia_entra",
         "disparoTipos": AL, "limitePorTurno": 1, "objetivo": {"quien": "oponente"}, "cantidad": 1},
        {"grupoElegir": "loch", "eligeOponente": True, "accion": "botar", "cuando": "propia_entra",
         "disparoTipos": AL, "limitePorTurno": 1, "objetivo": {"quien": "oponente"}, "cantidad": 2}])
    en_zona(p, 0, loch, Zona.APOYO)
    en_zona(p, 1, aliado("En mano", 1, 1), Zona.MANO)
    mazo = len(p.j(1).mazo)
    mano = len(p.j(1).mano)
    x = en_zona(p, 0, aliado("Entra", 1, 1), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", x))
    # Solo una de las dos opciones.
    assert (len(p.j(1).mazo) == mazo - 2) != (len(p.j(1).mano) == mano - 1)


def test_venganza_de_conall_solo_en_respuesta_a_habilidad_de_aliado_oponente():
    p = partida()
    _vigilia(p, 2, i=1)
    for _ in range(2):
        en_zona(p, 0, ORO, Zona.RESERVA)
    venganza = en_zona(p, 0, talisman("Venganza", 2, [
        {"accion": "desterrar", "cuando": "propia_sale", "zonaActivacion": "mano", "causa": "aliado_oponente",
         "cantidad": 1, "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": AL, "quien": "oponente"},
         "luego": [{"relacion": "siempre", "accion": "robar", "objetivo": {"quien": "propio"}, "cantidad": 1}]}]),
        Zona.MANO)
    assert not hab.talisman_jugable(p, 0, venganza, "vigilia")
    mio = en_defensa(p, 0, aliado("Mio", 2, 2))
    destructor = en_defensa(p, 1, aliado("Destructor", 3, 3, [
        {"accion": "destruir", "cuando": "activada",
         "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": AL, "quien": "oponente"}}]))
    hab._intentar(p, 1, destructor, destructor.habilidades[0])
    assert mio.zona == Zona.CEMENTERIO
    assert venganza.zona == Zona.CEMENTERIO and destructor.zona == Zona.DESTIERRO


def test_hipatia_convierte_un_totem_en_aliado_indestructible():
    p = partida()
    _vigilia(p, 0)
    totem = en_zona(p, 0, carta("Templo", Tipo.TOTEM, 3, []), Zona.APOYO)
    hip = en_defensa(p, 0, aliado("Hipatia", 2, 2, [
        {"fase": "vigilia", "turno": "propio", "unaVez": True, "limitePorTurno": 1, "cuando": "activada",
         "accion": "convertirEnAliado", "duracion": "hasta_fase_final",
         "objetivo": {"quien": "propio", "tipos": ["Tótem"]}}], raza="Sacerdote"))
    hab.resolver(p, 0, hip, hip.habilidades[0])
    assert totem.tipo == Tipo.ALIADO and totem.zona == Zona.DEFENSA and hab.fuerza(p, totem) == 3
    assert hab.tiene_prop(p, totem, "indestructible")
    hab.expirar(p, "hasta_fase_final")
    assert totem.tipo == Tipo.TOTEM and totem.zona == Zona.APOYO


def test_guerrero_fianna_paga_un_oro_por_cada_fianna():
    p = partida()
    h = {"accion": "restriccion", "modo": "pagar_para_combatir", "cuando": "continua",
         "costo": {"oros": 1, "porCadaMismoNombre": True}, "objetivo": {"quien": "esta_carta"}}
    a = en_defensa(p, 0, aliado("Guerrero Fianna", 0, 2, [h], raza="Defensor"))
    en_defensa(p, 0, aliado("Guerrero Fianna", 0, 2, [h], raza="Defensor"))
    p.e.activo = 0
    p.j(0).reserva.clear()
    en_zona(p, 0, ORO, Zona.RESERVA)
    assert not p._paga_para_atacar(0, a)  # 2 Fianna: 2 Oros, tiene 1
    en_zona(p, 0, ORO, Zona.RESERVA)
    assert p._paga_para_atacar(0, a) and not p.j(0).reserva


def test_shay_roba_del_fondo_y_ordena():
    p = partida()
    en_defensa(p, 0, aliado("Shay", 3, 3, [
        {"accion": "restriccion", "modo": "robar_fondo", "cuando": "continua", "objetivo": {"quien": "propio"}}],
        raza="Eterno"))
    fondo = p.j(0).mazo[-1]
    p.robar(0, 1)
    assert fondo in p.j(0).mano


def test_meleagro_veta_aliados_el_turno_siguiente_del_oponente():
    p = partida()
    _vigilia(p, 4)
    mel = en_zona(p, 0, aliado("Meleagro", 4, 1, [
        {"accion": "vetarAliados", "cuando": "al_jugar", "objetivo": {"quien": "oponente"}}], raza="Héroe"), Zona.MANO)
    p.ejecutar_jugada(0, Jugada("jugar", mel))
    x = en_zona(p, 1, aliado("Bajar", 1, 1), Zona.MANO)
    assert not hab.prohibido(p, "jugar_tipo", 1, x)
    p.e.turno += 1
    assert hab.prohibido(p, "jugar_tipo", 1, x)
    p.e.turno += 1
    assert not hab.prohibido(p, "jugar_tipo", 1, x)


def test_carruaje_negro_previene_destruir_pero_no_desterrar():
    p = partida()
    en_zona(p, 0, carta("Carruaje", Tipo.ORO, 0, [
        {"accion": "prevenir", "modo": "destruir", "cuando": "activada", "zonaActivacion": "reserva_oro",
         "costo": {"desterrarEstaCarta": True},
         "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": AL, "quien": "propio",
                      "arquetipo": "Drácula"}}]), Zona.RESERVA)
    d = en_defensa(p, 0, aliado("Conde Drácula", 3, 3, raza="Sombra"))
    assert not hab.prevenir(p, d)  # desterrar: no lo cubre
    assert hab.prevenir(p, d, destruir=True)


def test_espada_encantada_destierra_el_dano_del_portador():
    p = partida()
    atk = en_defensa(p, 0, aliado("Portador", 2, 2))
    assert not hab.dano_destierra(p, atk)
    arma = p._instancia(carta("Espada Encantada", Tipo.ARMA, 2, [
        {"accion": "restriccion", "modo": "dano_destierra", "cuando": "continua", "objetivo": {"quien": "esta_carta"}}]),
        0, Zona.PORTADA)
    arma.portador = atk.uid
    p.e.portadas.append(arma)
    assert hab.dano_destierra(p, atk)
