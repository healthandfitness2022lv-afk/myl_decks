"""Funciones nuevas para programar Faraón guerrero, Dragón y Titán Minotauro."""

from myl_sim import habilidades as hab
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Tipo, Zona

from test_acciones_v3b import en_zona
from test_motor import AtacaTodo, BloqueaFijo, ORO, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import arma, oro


class SiempreUsa(Heuristico):
    def usar_opcional(self, p, yo, fuente, hh):
        return True


# ── Guerrero Escorpión: "si Aliados Guerrero fueron declarados atacantes" ────
def test_condicion_atacantes_arquetipo():
    p = partida()
    g = en_defensa(p, 0, aliado("Guerrero Bereber", 2, 2, raza="Faraón"))
    otro = en_defensa(p, 0, aliado("Merodeador", 2, 2, raza="Faraón"))
    cond = {"condicion": {"tipo": "atacantes_arquetipo", "op": ">=", "valor": 1, "arquetipo": "Guerrero"}}
    assert not hab.condicion_ok(p, 0, cond)
    p.ataco_este_turno.add(otro.uid)
    assert not hab.condicion_ok(p, 0, cond)  # atacó, pero no es Guerrero
    p.ataco_este_turno.add(g.uid)
    assert hab.condicion_ok(p, 0, cond)


# ── Ramsés IX: "si entre esas cartas hay un Oro o un Aliado" ────────────────
def _ramses():
    return aliado("Ramses IX", 2, 3, [
        h("botar", objetivo={"quien": "ambos"}, luego=[{
            "accion": "botar", "relacion": "si_afectada_cumple", "cantidad": 2,
            "filtroAfectada": {"tipos": ["Oro", "Aliado"]}, "objetivo": {"quien": "oponente"},
        }])
    ])


def _tope(p, i, carta):
    inst = p._instancia(carta, i, Zona.MAZO)
    p.j(i).mazo.insert(0, inst)
    return inst


def test_botar_mira_lo_botado():
    p = partida()
    r = en_defensa(p, 0, _ramses())
    _tope(p, 0, ORO)
    _tope(p, 1, talisman("T", 1, []))
    antes = (len(p.j(0).mazo), len(p.j(1).mazo))
    hab.resolver(p, 0, r, r.habilidades[0])
    assert antes[0] - len(p.j(0).mazo) == 1 and antes[1] - len(p.j(1).mazo) == 3  # había un Oro: 2 más


def test_botar_sin_oro_ni_aliado_no_bota_de_mas():
    p = partida()
    r = en_defensa(p, 0, _ramses())
    _tope(p, 0, talisman("T0", 1, []))
    _tope(p, 1, talisman("T1", 1, []))
    antes = len(p.j(1).mazo)
    hab.resolver(p, 0, r, r.habilidades[0])
    assert antes - len(p.j(1).mazo) == 1


# ── "Elige una de las opciones" (Luz de Prometeo) ───────────────────────────
def test_grupo_elegir_solo_una_opcion():
    luz = talisman("Luz de Prometeo", 1, [
        h("robar", opcional=True, grupoElegir="luz", objetivo={"quien": "propio"}),
        h("robar", opcional=True, grupoElegir="luz", objetivo={"quien": "propio"}, cantidad=5),
    ])
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))
    inst = p._instancia(luz, 0, Zona.MANO)
    antes = len(p.j(0).mano)
    hab.disparar(p, inst, "al_jugar")
    assert len(p.j(0).mano) - antes == 1  # solo la primera opción


def test_grupo_elegir_en_efectos_luego():
    cuerno = oro("Cuerno", [h("mostrar", opcional=False, objetivo={"quien": "propio", "tipos": ["Aliado"], "zona": "mano"}, luego=[
        {"accion": "robar", "relacion": "siempre", "grupoElegir": "c", "objetivo": {"quien": "propio"}, "cantidad": 1},
        {"accion": "robar", "relacion": "siempre", "grupoElegir": "c", "objetivo": {"quien": "propio"}, "cantidad": 3},
    ])])
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))
    c = p._instancia(cuerno, 0, Zona.RESERVA)
    en_zona(p, 0, aliado("Mostrable", 1, 1), Zona.MANO)
    antes = len(p.j(0).mano)
    hab.resolver(p, 0, c, c.habilidades[0])
    assert len(p.j(0).mano) - antes == 1


# ── Toque de Pérsival: Aliado declarado atacante o bloqueador ───────────────
def test_objetivo_en_combate():
    p = partida()
    atk = en_defensa(p, 1, aliado("Atacante", 2, 2))
    blk = en_defensa(p, 1, aliado("Bloqueador", 2, 2))
    quieto = en_defensa(p, 1, aliado("Quieto", 2, 2))
    p.ataco_este_turno.add(atk.uid)
    p.bloqueos = {99: blk}
    obj = {"combate": True}
    assert hab.coincide(p, atk, obj) and hab.coincide(p, blk, obj) and not hab.coincide(p, quieto, obj)


# ── Dragones: Oros solo para Aliados Dragón de coste 4 o más ────────────────
def test_oros_restringidos_por_coste_minimo():
    p = partida()
    inst = lambda c: p._instancia(c, 0, Zona.MANO)  # noqa: E731
    r = [2, ["Aliado"], "Dragón", 4]
    assert hab.paga_restringido(inst(aliado("Killgharrah", 6, 6, raza="Dragón")), r)
    assert not hab.paga_restringido(inst(aliado("Cathach", 3, 2, raza="Dragón")), r)
    assert not hab.paga_restringido(inst(aliado("Otro", 5, 5, raza="Titán")), r)
    assert hab.paga_restringido(inst(aliado("Viejo", 1, 1, raza="Dragón")), [1, [], "Dragón"])  # formato antiguo


def test_dragones_genera_oros_con_coste_minimo():
    d = oro("Dragones", [h("generarOro", cuando="activada", valor=2, soloParaTipos=["Aliado"], soloParaRaza="Dragón",
                           soloParaCosteMin=4, objetivo={"quien": "propio"})])
    p = partida()
    inst = p._instancia(d, 0, Zona.RESERVA)
    hab.resolver(p, 0, inst, inst.habilidades[0])
    assert p.j(0).oros_restringidos == [[2, ["Aliado"], "Dragón", 4]]


# ── Monte Killgharrah: "un Aliado de raza Dragón de coste 3 o más" ──────────
def test_disparo_con_coste_minimo():
    monte = {"cuando": "propia_entra", "disparoTipos": ["Aliado"], "disparoRaza": "Dragón", "disparoCosteMin": 3}
    p = partida()
    grande = en_defensa(p, 0, aliado("Killgharrah", 6, 6, raza="Dragón"))
    chico = en_defensa(p, 0, aliado("Gaspar", 2, 2, raza="Dragón"))
    assert hab._dispara_por(grande, monte) and not hab._dispara_por(chico, monte)


# ── Estrella de Belén: las demás cartas se barajan, no van al Cementerio ────
def test_mirar_tope_baraja_el_resto():
    estrella = oro("Estrella", [h("mirarTope", cantidad=3, valor=1, zonaDestino="mano", restoA="barajar",
                                  objetivo={"quien": "propio", "tipos": ["Oro"]})])
    p = partida()
    inst = p._instancia(estrella, 0, Zona.RESERVA)
    _tope(p, 0, ORO)
    _tope(p, 0, talisman("A", 1, []))
    _tope(p, 0, talisman("B", 1, []))
    cementerio, mazo = len(p.j(0).cementerio), len(p.j(0).mazo)
    hab.resolver(p, 0, inst, inst.habilidades[0])
    assert len(p.j(0).cementerio) == cementerio and len(p.j(0).mazo) == mazo - 1


# ── Titán Gorila: el rival no puede jugar la carta barajada ─────────────────
def test_carta_vetada_mientras_este_en_juego():
    gorila = aliado("Titan Gorila", 4, 4, [
        h("barajar", vetaCarta=True, objetivo={"quien": "cualquiera", "tipos": ["Aliado"], "excluirEstaCarta": True})
    ], raza="Titán")
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))
    g = en_defensa(p, 0, gorila)
    objetivo = en_defensa(p, 1, aliado("Rival Fuerte", 5, 5))
    hab.resolver(p, 0, g, g.habilidades[0])
    assert g.carta_vetada == "Rival Fuerte" and objetivo.zona == Zona.MAZO
    copia = p._instancia(aliado("Rival Fuerte", 5, 5), 1, Zona.MANO)
    assert hab.prohibido(p, "jugar_tipo", 1, copia)
    assert not hab.prohibido(p, "jugar_tipo", 0, copia)  # solo el oponente del Gorila
    p.sale_del_juego(g, Zona.CEMENTERIO)
    assert not hab.prohibido(p, "jugar_tipo", 1, copia)


# ── Laberinto de Creta: hay que bloquear con al menos un Aliado ─────────────
def test_bloqueo_obligatorio():
    laberinto = aliado("Laberinto", 3, 0, [
        h("restriccion", cuando="continua", modo="bloqueo_obligatorio", objetivo={"quien": "oponente"})
    ])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    en_defensa(p, 0, laberinto, listo=False)
    atk = en_defensa(p, 0, aliado("Atk", 2, 3))
    blk = en_defensa(p, 1, aliado("Blk", 2, 5))
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert len(p.j(1).mazo) == antes  # fue obligado a bloquear
    assert not atk.en_juego or blk.en_juego


def test_sin_laberinto_no_hay_bloqueo():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    en_defensa(p, 0, aliado("Atk", 2, 3))
    en_defensa(p, 1, aliado("Blk", 2, 5))
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 3


# ── Soteira: previene y gana 1 de fuerza permanentemente ────────────────────
def test_prevenir_aplica_luego():
    soteira = oro("Soteira", [h("prevenir", cuando="activada", modo="destruir_desterrar", zonaActivacion="reserva_oro",
                                costo={"desterrarEstaCarta": True}, objetivo={"quien": "propio", "tipos": ["Aliado"]},
                                luego=[{"accion": "modificarFuerza", "relacion": "si_se_cumplio", "valor": 1,
                                        "modoFuerza": "sumar", "duracion": "permanente",
                                        "objetivo": {"quien": "propio", "seleccion": "todos", "referencia": "afectadas"}}])])
    p = partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))
    s = p._instancia(soteira, 0, Zona.MAZO)
    p.j(0).mazo.append(s)
    p._mover(s, Zona.RESERVA)
    a = en_defensa(p, 0, aliado("Cronos", 5, 5))
    assert hab.prevenir(p, a)
    assert hab.fuerza(p, a) == 6 and s.zona == Zona.DESTIERRO


# ── Minotauro Colosal: coste según la cantidad de Minotauros ────────────────
def test_coste_segun_arquetipo():
    p = partida()
    colosal = en_defensa(p, 0, aliado("Minotauro Colosal", 5, 5))
    en_defensa(p, 0, aliado("Minotauro de Creta", 2, 2))
    barato = en_defensa(p, 1, aliado("Barato", 2, 2))
    caro = en_defensa(p, 1, aliado("Caro", 3, 2))
    hh = h("desterrar", objetivo={"quien": "oponente", "coste": {"op": "<=", "segun": "aliados_arquetipo",
                                                                  "arquetipo": "Minotauro"}})
    assert hab.candidatos_validos(p, 0, colosal, hh) == [barato]  # 2 Minotauros → coste ≤ 2
    assert caro.en_juego


# ── Narración y datos ───────────────────────────────────────────────────────
def test_arma_con_jugar_desde_cementerio_sigue_valida():
    espada = arma("Espada Miliciana", 3, [h("jugarDesde", cuando="activada", modo="sin_pagar",
                                            zonaActivacion="cementerio", costo={"oros": 2},
                                            objetivo={"quien": "esta_carta", "zona": "mazo"})])
    p = partida()
    assert espada.habilidades[0]["zonaActivacion"] == "cementerio"


# ── La IA no se bota el castillo con Kamose / Medjay ────────────────────────
def test_no_juega_ni_ataca_si_se_bota_de_mas():
    from myl_sim.jugadores import _se_bota_de_mas

    medjay = aliado("Guerrero Medjay", 2, 3, [h("botar", cuando="al_atacar", objetivo={"quien": "ambos"})])
    p = partida()
    m = en_defensa(p, 0, medjay)
    assert not _se_bota_de_mas(p, 0, m, "al_jugar")  # no tiene ese disparo
    assert not _se_bota_de_mas(p, 0, m, "al_atacar")  # castillo sano
    del p.j(0).mazo[3:]  # castillo de 3: botar 1 lo deja en 2
    assert _se_bota_de_mas(p, 0, m, "al_atacar")
