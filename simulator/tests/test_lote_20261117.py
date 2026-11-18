"""Las 38 cartas nuevas de Helénica y Espada Sagrada (lote del 2026-11-17).

Cada test juega la carta tal como quedó programada (`myl_sim.lote_20261117`)
y comprueba que hace lo que dice su texto. Sin Firestore.
"""

from myl_sim import habilidades as hab
from myl_sim import lote_20261117 as L
from myl_sim.datos import Mazo, carta_desde_doc, copias_maximas, problemas_mazo
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import arma, jugar
from test_tanda_guerrero_dragon_titan import SiempreUsa

PROPIO, RIVAL = {"quien": "propio"}, {"quien": "oponente"}


class Decidido(SiempreUsa):
    """Usa todo lo opcional, ataca con todo y manda al fondo lo que mira."""

    def elegir_atacantes(self, p, yo, candidatos):
        return candidatos

    def tope_o_fondo(self, p, yo, cartas):
        return "mazo_fondo"


def _p(**kw):
    return partida(jugadores=(Decidido(1), Decidido(2)), **kw)


def activar(p, i, inst, k=None, fase="vigilia", oros=5):
    """Activa una habilidad de `inst` (la k-ésima, o la primera disponible)."""
    p.e.fase = fase
    p.j(i).oros_virtuales = oros
    ops = [o for o in p.jugadas_legales(i, fase)
           if o.tipo == "activar" and o.carta is inst and (k is None or o.habilidad == k)]
    assert ops, f"{inst.nombre}: no se puede activar"
    p.ejecutar_jugada(i, ops[0])


def activables(p, i, inst, fase="vigilia", oros=5):
    p.e.fase = fase
    p.j(i).oros_virtuales = oros
    return [o for o in p.jugadas_legales(i, fase) if o.tipo == "activar" and o.carta is inst]


def equipar(p, i, carta_arma, portador):
    e = en_zona(p, i, carta_arma, Zona.MANO)
    p.j(i).oros_virtuales = 10
    p.e.activo, p.e.fase = i, "vigilia"
    p.ejecutar_jugada(i, Jugada("jugar", e, portador=portador))
    return e


def al_fondo(p, i, carta):
    inst = p._instancia(carta, i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    return inst


def test_el_lote_usa_solo_vocabulario_del_editor():
    assert L.validar() == []
    assert len(L.CARTAS) == 38
    assert all(L.carta(cid).programada for cid in L.CARTAS)


# ── Helénica ─────────────────────────────────────────────────────────────────
def test_amazonas_guerreras_gratis_con_dos_amazonas():
    p = _p()
    a = en_zona(p, 0, L.carta("amazonas_guerreras"), Zona.MANO)
    assert p.coste_de(0, a) == 2
    en_defensa(p, 0, aliado("Dioxipe La Amazona", 2, 2, raza="Héroe"))
    assert p.coste_de(0, a) == 2  # una sola Amazona no alcanza
    en_defensa(p, 0, aliado("Atalanta La Amazona", 4, 4, raza="Héroe"))
    assert p.coste_de(0, a) == 0
    p.j(0).reserva.clear()
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is a))
    assert a.zona == Zona.DEFENSA and a.listo  # sin Oros, y puede atacar


def test_anfiarao_juega_gratis_un_aliado_de_las_tres_primeras():
    p = _p()
    caro = en_zona(p, 0, aliado("Caro", 5, 5), Zona.MAZO)
    barato = en_zona(p, 0, aliado("Barato", 3, 3), Zona.MAZO)
    oro = en_zona(p, 0, ORO, Zona.MAZO)
    assert p.j(0).mazo[:3] == [oro, barato, caro]
    jugar(p, 0, L.carta("anfiarao"))
    assert barato.zona == Zona.DEFENSA
    assert {x.uid for x in p.j(0).mazo[-2:]} == {oro.uid, caro.uid}  # el resto, al fondo


def test_aqueloo_destierra_una_para_barajar_otra():
    p = _p()
    aq = en_defensa(p, 0, L.carta("aqueloo"))
    p.e.activo = 0
    en_zona(p, 0, aliado("Uno", 1, 1), Zona.CEMENTERIO)
    assert not activables(p, 0, aq)  # con una sola carta no hay qué barajar
    en_zona(p, 0, aliado("Dos", 4, 4), Zona.CEMENTERIO)
    mazo = len(p.j(0).mazo)
    activar(p, 0, aq)
    assert len(p.j(0).cementerio) == 0 and len(p.j(0).destierro) == 1 and len(p.j(0).mazo) == mazo + 1
    assert not activables(p, 0, aq)  # una vez por turno


def test_atalanta_juega_un_arma_gratis_y_es_indestructible_con_ella():
    p = _p()
    espada = en_zona(p, 0, arma("Espada", 3, [h("modificarFuerza", cuando="continua", valor=1,
                                               objetivo={"quien": "esta_carta"})]), Zona.MANO)
    p.j(0).reserva.clear()
    ata = en_zona(p, 0, L.carta("atalanta_la_amazona"), Zona.MANO)
    p.j(0).oros_virtuales = 4  # justo su coste: el Arma entra sin pagar
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is ata))
    assert ata.listo and espada.zona == Zona.PORTADA and espada.portador == ata.uid
    assert hab.tiene_prop(p, ata, "indestructible")
    p._mover(espada, Zona.CEMENTERIO)
    assert not hab.tiene_prop(p, ata, "indestructible")


def test_behemot_sube_a_los_titanes_y_obliga_a_bloquear():
    p = _p()
    titan = en_defensa(p, 0, aliado("Titán", 2, 2, raza="Titán"))
    otro = en_defensa(p, 0, aliado("Héroe", 2, 2, raza="Héroe"))
    b = jugar(p, 0, L.carta("behemot"))
    assert (hab.fuerza(p, titan), hab.fuerza(p, b), hab.fuerza(p, otro)) == (3, 5, 2)
    assert all(hab.tiene_estado(p, x, "debe_ser_bloqueado") for x in (titan, otro, b))
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, titan) == 3 and not hab.tiene_estado(p, titan, "debe_ser_bloqueado")


def test_behemot_el_defensor_debe_bloquear():
    p = partida(jugadores=(Decidido(1), Heuristico(2)))
    en_defensa(p, 0, L.carta("behemot"))
    atk = en_defensa(p, 0, aliado("Grande", 5, 9, raza="Titán"))
    atk.estados.append({"modo": "debe_ser_bloqueado", "duracion": "hasta_fase_final", "turno": 1})
    blk = en_defensa(p, 1, aliado("Chico", 1, 1))
    p.e.activo, p.e.turno = 0, 3
    p._batalla(0)
    assert blk.zona == Zona.CEMENTERIO  # no lo habría bloqueado por gusto: muere


def test_caminar_las_estrellas_el_rival_elige_la_que_va_a_la_mano():
    cara, barata = aliado("Cara", 5, 5), aliado("Barata", 1, 1)
    p = _p(cartas_a=[cara] * 25 + [barata] * 24)
    jugar(p, 0, L.carta("caminar_las_estrellas"))
    assert [x.nombre for x in p.j(0).mano] == ["Barata"]  # la IA rival deja la más barata
    assert [x.nombre for x in p.j(0).cementerio if x.nombre != "Caminar Las Estrellas"] == ["Cara"]
    assert len(p.j(0).mazo) == 47


def test_caminar_las_estrellas_con_un_solo_nombre_trae_una():
    p = _p(cartas_a=[aliado("Igual", 2, 2)] * 49)
    jugar(p, 0, L.carta("caminar_las_estrellas"))
    assert [x.nombre for x in p.j(0).mano] == ["Igual"] and len(p.j(0).mazo) == 48


def test_cornucopia_vuelve_al_fondo_y_sube_otro_oro():
    p = _p()
    c = en_zona(p, 0, L.carta("cornucopia_de_aqueloo"), Zona.PAGADO)  # también sirve pagada
    p.e.activo = 0
    en_zona(p, 0, L.carta("cornucopia_de_aqueloo"), Zona.CEMENTERIO)
    assert not activables(p, 0, c)  # otra Cornucopia no cuenta
    oro = en_zona(p, 0, ORO, Zona.CEMENTERIO)
    activar(p, 0, c, oros=0)
    assert p.j(0).mazo[-1] is c and oro.zona == Zona.MANO
    assert [x.nombre for x in p.j(0).cementerio] == ["Cornucopia De Aqueloo"]


def test_enialio_saca_a_un_atacante_del_combate():
    assert carta_desde_doc("enialio", {"nombre": "Enialio", "tipo": "Aliado", "coste": 2, "fuerza": 22}).fuerza == 2
    p = _p()
    e = en_defensa(p, 0, L.carta("enialio"))
    atk = en_zona(p, 1, aliado("Atacante", 3, 5), Zona.ATAQUE)
    p.e.activo, p.atacantes = 1, [atk]
    ia = Heuristico(1)
    assert ia._objetivo_util(p, 0, e, e.habilidades[1])  # me atacan: sirve
    activar(p, 0, e, fase="guerra_talismanes")
    assert atk.zona == Zona.DEFENSA
    assert not activables(p, 0, e, fase="guerra_talismanes")  # una vez por turno
    # En mi turno, devolverle un bloqueador al rival no conviene.
    otro = en_zona(p, 1, aliado("Quieto", 3, 5), Zona.ATAQUE)
    p.e.activo, p.atacantes = 0, []
    assert otro.zona == Zona.ATAQUE and not ia._objetivo_util(p, 0, e, e.habilidades[1])


def test_harma_fuerza_baraja_y_roba():
    p = _p()
    d = en_defensa(p, 0, aliado("Portador", 2, 2))
    for k in range(3):
        en_zona(p, 0, aliado(f"C{k}", 1, 1), Zona.CEMENTERIO)
    mano = len(p.j(0).mano)
    equipar(p, 0, L.carta("harma"), d)
    assert hab.fuerza(p, d) == 4
    assert len(p.j(0).cementerio) == 1 and len(p.j(0).mano) == mano + 1


def test_las_musas_busca_una_musa_y_encarece_los_talismanes():
    p = _p()
    urania = al_fondo(p, 0, L.carta("musa_urania"))
    musas = jugar(p, 0, L.carta("las_musas"))
    assert urania.zona == Zona.MANO
    otra = en_defensa(p, 0, L.carta("musa_caliope"))
    comun = en_defensa(p, 0, aliado("Común", 2, 2, raza="Olímpico"))
    tal = en_zona(p, 1, talisman("Bola", 2, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"]})]),
                  Zona.MANO)
    ali = en_defensa(p, 1, aliado("Rival", 2, 2))
    assert hab.recargo(p, musas, tal) == 1 and hab.recargo(p, otra, tal) == 1
    assert hab.recargo(p, comun, tal) == 0 and hab.recargo(p, otra, ali) == 0
    p.sale_del_juego(musas, Zona.CEMENTERIO)
    assert hab.recargo(p, otra, tal) == 0


def test_las_musas_tambien_busca_en_el_cementerio():
    p = _p()
    cal = en_zona(p, 0, L.carta("musa_caliope"), Zona.CEMENTERIO)
    jugar(p, 0, L.carta("las_musas"))
    assert cal.zona == Zona.MANO


def test_melinoe_bota_dos_y_busca_un_aliado_caro():
    p = _p()
    grande = al_fondo(p, 0, aliado("Grande", 4, 4))
    mazo = len(p.j(0).mazo)
    jugar(p, 0, L.carta("melinoe"))
    assert grande.zona == Zona.MANO and len(p.j(0).cementerio) == 2 and len(p.j(0).mazo) == mazo - 3


def test_men_trae_un_aliado_del_cementerio_y_bota_su_coste():
    p = _p()
    muerto = en_zona(p, 0, aliado("Caído", 3, 4), Zona.CEMENTERIO)
    mazo = len(p.j(0).mazo)
    jugar(p, 0, L.carta("men"))
    assert muerto.zona == Zona.DEFENSA and len(p.j(0).mazo) == mazo - 3 and len(p.j(0).cementerio) == 3


def test_men_la_ia_no_se_bota_el_castillo():
    p = partida()
    en_zona(p, 0, aliado("Enorme", 6, 6), Zona.CEMENTERIO)
    del p.j(0).mazo[7:]
    men = jugar(p, 0, L.carta("men"))
    assert men.zona == Zona.DEFENSA and len(p.j(0).mazo) == 7 and not p.e.terminada


def test_minotauro_del_hades():
    p = _p()
    solo = jugar(p, 0, L.carta("minotauro_del_hades"))
    assert not solo.listo and not p.desterrar(solo) and solo.en_juego  # Indesterrable
    segundo = jugar(p, 0, L.carta("minotauro_del_hades"))
    assert segundo.listo  # con otro Minotauro puede atacar al entrar
    muerto = en_zona(p, 0, L.carta("minotauro_del_hades"), Zona.CEMENTERIO)
    assert not activables(p, 0, muerto)  # falta otra carta que desterrar
    pago = en_zona(p, 0, aliado("Pago", 1, 1), Zona.CEMENTERIO)
    p.j(0).reserva.clear()
    assert not activables(p, 0, muerto, oros=1)  # y 2 Oros
    activar(p, 0, muerto, oros=2)
    assert muerto.zona == Zona.DEFENSA and pago.zona == Zona.DESTIERRO and p.j(0).oro_disponible == 0


def test_musa_caliope_bota_con_oros_y_con_musas():
    p = _p()
    cal = jugar(p, 0, L.carta("musa_caliope"))
    assert len(p.j(1).mazo) == 48  # ella es una Musa que entra
    oro = en_zona(p, 0, ORO, Zona.RESERVA)
    hab.disparar_entrada(p, oro)
    assert len(p.j(1).mazo) == 47
    musas = jugar(p, 0, L.carta("las_musas"))
    assert len(p.j(1).mazo) == 46
    jugar(p, 0, aliado("Otro", 1, 1, raza="Olímpico"))
    assert len(p.j(1).mazo) == 46  # ni Oro ni Musa
    p.destruir(musas)
    assert len(p.j(1).mazo) == 45
    p.destruir(cal)
    assert len(p.j(1).mazo) == 44  # ella es una Musa que sale


def test_el_oro_del_turno_dispara_cuando_un_oro_entra_en_juego():
    class JuegaElOro(Heuristico):
        def elegir_jugada(self, p, yo, jugadas):
            return next((j for j in jugadas if j.tipo == "oro"), jugadas[-1])

    p = partida(jugadores=(JuegaElOro(1), Heuristico(2)))
    en_defensa(p, 0, L.carta("musa_caliope"))
    en_zona(p, 0, ORO, Zona.MANO)
    p.e.activo, p.e.fase = 0, "vigilia"
    p._vigilia(0)
    assert len(p.j(0).reserva) == 2 and len(p.j(1).mazo) == 48


def test_musa_urania_toma_las_musas_o_una_carta_que_no_sea_aliado():
    p = _p()
    u = en_defensa(p, 0, L.carta("musa_urania"))
    p.e.activo = 0
    comun = en_zona(p, 0, aliado("Común", 2, 2), Zona.MAZO)
    m1 = en_zona(p, 0, L.carta("las_musas"), Zona.MAZO)
    m2 = en_zona(p, 0, L.carta("musa_caliope"), Zona.MAZO)
    p.j(0).reserva.clear()
    activar(p, 0, u, oros=1)
    assert m1.zona == Zona.MANO and m2.zona == Zona.MANO and comun.zona == Zona.MAZO
    assert p.j(0).oro_disponible == 0 and not activables(p, 0, u)  # pagó 1; una vez por turno
    u.usos_turno.clear()
    a1 = en_zona(p, 0, aliado("A1", 2, 2), Zona.MAZO)
    oro = en_zona(p, 0, ORO, Zona.MAZO)
    a2 = en_zona(p, 0, aliado("A2", 2, 2), Zona.MAZO)
    activar(p, 0, u, oros=1)
    assert oro.zona == Zona.MANO and a1.zona == Zona.MAZO and a2.zona == Zona.MAZO


def test_pelope():
    p = _p()
    pe = en_zona(p, 0, L.carta("pelope"), Zona.ATAQUE)
    assert hab.fuerza(p, pe) == 2 and not hab.tiene_prop(p, pe, "indestructible")
    en_defensa(p, 0, aliado("Héroe", 2, 2, raza="Héroe"))
    assert hab.fuerza(p, pe) == 3 and hab.tiene_prop(p, pe, "indestructible")
    p.e.activo = 0
    hab.disparar_inicio_fase(p, "final")
    assert pe.zona == Zona.DEFENSA  # se agrupa en su Fase Final


def test_talos():
    p = _p()
    t = en_defensa(p, 0, L.carta("talos"))
    assert not hab.tiene_prop(p, t, "indesterrable")
    en_defensa(p, 0, aliado("Otro Titán", 2, 2, raza="Titán"))
    assert hab.tiene_prop(p, t, "indesterrable")
    pago = en_zona(p, 0, aliado("Pago", 1, 1), Zona.CEMENTERIO)
    en_zona(p, 0, ORO, Zona.CEMENTERIO)  # un Oro no sirve para pagarlo
    assert p.destruir(t)
    assert t.zona == Zona.MANO and pago.zona == Zona.DESTIERRO
    t2 = en_defensa(p, 0, L.carta("talos"))
    p.destruir(t2)
    assert t2.zona == Zona.CEMENTERIO  # sin Aliado que desterrar, se queda


def test_taumante_una_opcion_por_agrupacion_en_cada_turno():
    p = _p()
    t = en_defensa(p, 0, L.carta("taumante"))
    en_zona(p, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    mano = len(p.j(0).mano)
    p.e.activo = 0
    hab.disparar_inicio_fase(p, "agrupacion")
    assert len(p.j(0).mano) == mano + 1 and len(p.j(0).cementerio) == 1  # robó: no barajó ni desterró
    hab.disparar_inicio_fase(p, "agrupacion")
    assert len(p.j(0).mano) == mano + 1
    t.usos_turno.clear()
    p.e.activo = 1  # también en la Agrupación del oponente
    hab.disparar_inicio_fase(p, "agrupacion")
    assert len(p.j(0).mano) == mano + 2


def test_tea_deja_a_un_aliado_en_fuerza_cero():
    p = partida(jugadores=(Heuristico(1), Heuristico(2)))
    tea = en_defensa(p, 0, L.carta("tea"))
    mio = en_defensa(p, 0, aliado("Mío", 3, 6))
    rival = en_zona(p, 1, aliado("Rival", 3, 5), Zona.ATAQUE)
    p.e.activo, p.atacantes = 1, [rival]
    activar(p, 0, tea, fase="guerra_talismanes")
    assert hab.fuerza(p, rival) == 0 and hab.fuerza(p, mio) == 6  # la IA castiga al rival, no a los suyos
    hab.resolver(p, 1, rival, h("modificarFuerza", valor=3, duracion="hasta_fase_final",
                                objetivo={"quien": "esta_carta"}))
    assert hab.fuerza(p, rival) == 0  # no recibe modificadores
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, rival) == 5


def test_tea_costo_alternativo():
    p = _p()
    tea = en_defensa(p, 0, L.carta("tea"))
    rival = en_defensa(p, 1, aliado("Rival", 3, 5))
    p.e.activo = 0
    p.j(0).reserva.clear()
    assert not activables(p, 0, tea, oros=0)
    pago = en_zona(p, 0, aliado("Pago", 1, 1), Zona.CEMENTERIO)
    activar(p, 0, tea, oros=0)
    assert pago.zona == Zona.DESTIERRO and 0 in (hab.fuerza(p, rival), hab.fuerza(p, tea))


def test_telestris():
    p = _p()
    t = en_defensa(p, 0, L.carta("telestris_la_amazona"))
    otra = en_defensa(p, 0, aliado("Dioxipe La Amazona", 2, 2, raza="Héroe"))
    reina = en_defensa(p, 0, aliado("Reina Hipólita", 4, 4, raza="Héroe"))
    comun = en_defensa(p, 0, aliado("Común", 2, 2, raza="Héroe"))
    assert [hab.fuerza(p, x) for x in (t, otra, reina, comun)] == [4, 3, 5, 2]
    p.e.activo = 0
    dory = al_fondo(p, 0, arma("Dory De Amazona", 1, []))
    activar(p, 0, t, k=1)
    assert dory.zona == Zona.MANO
    assert not activables(p, 0, t)  # una búsqueda por turno, sea Amazona o Reina
    t.usos_turno.clear()
    reina2 = al_fondo(p, 0, aliado("Reina Hipólita", 4, 4, raza="Héroe"))
    activar(p, 0, t, k=2)
    assert reina2.zona == Zona.MANO


# ── Espada Sagrada ───────────────────────────────────────────────────────────
def test_draco_aguila_bota_por_cada_copia_y_no_tiene_limite_de_copias():
    p = _p()
    en_defensa(p, 0, L.carta("draco_aguila"))
    en_defensa(p, 0, L.carta("draco_aguila"))
    d = jugar(p, 0, L.carta("draco_aguila"))
    assert len(p.j(1).mazo) == 46 and hab.tiene_prop(p, d, "imbloqueable")
    aguila, comun = L.carta("draco_aguila"), aliado("Soldado", 1, 1)
    # Mercenario: hasta 6 copias (Héctor 18-11), salvo que la Ban List diga otra cosa.
    assert copias_maximas(aguila) == 6 and copias_maximas(comun) == 3
    libre = {"oro": 49}
    assert problemas_mazo(Mazo("m", "Águilas", "racial", "Dragón", [aguila] * 6 + [ORO] * 43, []), ban=libre) == []
    assert problemas_mazo(Mazo("m", "Águilas", "racial", "Dragón", [aguila] * 7 + [ORO] * 42, []), ban=libre) \
        == ["Draco Águila ×7 (máximo 6)"]
    assert problemas_mazo(Mazo("m", "Águilas", "racial", "Dragón", [aguila] * 6 + [ORO] * 43, []),
                          ban={"oro": 49, "draco_aguila": 3}) == ["Draco Águila ×6 (máximo 3)"]


def test_draco_de_inverness():
    p = _p()
    d = en_zona(p, 0, L.carta("draco_de_inverness"), Zona.ATAQUE)
    en_defensa(p, 0, aliado("Dragón 2", 2, 2, raza="Dragón"))
    p.e.activo = 0
    hab.disparar(p, d, "al_atacar")
    assert hab.fuerza(p, d) == 1
    en_defensa(p, 0, aliado("Dragón 3", 2, 2, raza="Dragón"))
    hab.disparar(p, d, "al_atacar")
    assert hab.fuerza(p, d) == 3
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, d) == 1


def test_dragon_del_agua_protege_a_los_demas_dragones():
    p = _p()
    agua = en_defensa(p, 0, L.carta("dragon_del_agua"))
    dragon = en_defensa(p, 0, aliado("Dragón", 2, 2, raza="Dragón"))
    otro = en_defensa(p, 0, aliado("Faerie", 2, 2, raza="Faerie"))
    tal = en_zona(p, 1, talisman("Bola", 2, [h("destruir", objetivo={"quien": "oponente"})]), Zona.MANO)
    ali = en_defensa(p, 1, aliado("Rival", 2, 2))
    assert hab.inmune(p, dragon, tal) and not hab.inmune(p, agua, tal) and not hab.inmune(p, otro, tal)
    assert not hab.inmune(p, dragon, ali)
    assert hab.tiene_prop(p, agua, "imbloqueable")


def test_espina_de_serpiente():
    p = _p()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    e = en_zona(p, 0, L.carta("espina_de_serpiente"), Zona.RESERVA)
    p.e.activo = 0
    hab.disparar(p, e, "al_jugar")
    assert hab.fuerza(p, rival) == 2
    p._mover(e, Zona.PAGADO)  # también se activa pagada
    activar(p, 0, e, oros=0)
    assert e.zona == Zona.MAZO and hab.fuerza(p, rival) == 1
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, rival) == 2  # el −1 de entrada es permanente


def test_fenex():
    p = _p()
    f = jugar(p, 0, L.carta("fenex"))
    assert len(p.j(1).mazo) == 48
    p.destruir(f)
    assert len(p.j(1).mazo) == 47 and f.zona == Zona.CEMENTERIO
    p.j(0).reserva.clear()
    assert not activables(p, 0, f, oros=0)
    activar(p, 0, f, oros=1)
    assert f.zona == Zona.MANO and p.j(0).oro_disponible == 0


def test_fiodhain_tiene_las_habilidades_de_un_aliado_del_cementerio():
    p = _p()
    modelo = aliado("Modelo", 3, 3, [h("imbloqueable", cuando="continua"), h("furia", cuando="continua")])
    en_zona(p, 0, modelo, Zona.CEMENTERIO)
    f = jugar(p, 0, L.carta("fiodhain"))
    assert hab.tiene_prop(p, f, "imbloqueable") and f.listo
    hab.expirar(p, "hasta_fase_final")
    assert hab.tiene_prop(p, f, "imbloqueable")  # por el resto del juego
    p.sale_del_juego(f, Zona.MANO)
    assert f.copia == () and not hab.tiene_prop(p, f, "imbloqueable")


def test_fiodhain_sin_aliados_en_el_cementerio_entra_igual():
    p = _p()
    f = jugar(p, 0, L.carta("fiodhain"))
    assert f.zona == Zona.DEFENSA and f.copia == ()


def test_fruto_fiodhain_al_jugar_un_talisman():
    p = _p()
    en_zona(p, 0, L.carta("fruto_fiodhain"), Zona.RESERVA)
    en_zona(p, 0, L.carta("fruto_fiodhain"), Zona.PAGADO)
    arriba = list(p.j(0).mazo[:2])
    jugar(p, 0, aliado("Aliado", 1, 1))
    assert p.j(0).mazo[:2] == arriba  # un Aliado no lo dispara
    jugar(p, 0, talisman("Daño", 1, [h("botar", objetivo=RIVAL)]))
    assert p.j(0).mazo[-2:] == arriba
    siguientes = list(p.j(0).mazo[:2])
    jugar(p, 0, talisman("Daño", 1, [h("botar", objetivo=RIVAL)]))
    assert p.j(0).mazo[:2] == siguientes  # un solo Fruto Fiodhain por turno, aunque haya dos


def test_goblin_berserker():
    p = _p()
    en_zona(p, 0, aliado("Goblin", 1, 1, raza="Faerie"), Zona.CEMENTERIO)
    en_zona(p, 0, aliado("Hobgoblin", 2, 2, raza="Faerie"), Zona.CEMENTERIO)
    otro = en_zona(p, 0, aliado("Pixie", 1, 1, raza="Faerie"), Zona.CEMENTERIO)
    g = jugar(p, 0, L.carta("goblin_berserker"))
    assert hab.fuerza(p, g) == 6 and g.listo
    assert len(p.j(0).destierro) == 2 and otro.zona == Zona.CEMENTERIO
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, g) == 4


def test_goblin_berserker_la_ia_lo_usa_en_su_turno():
    p = partida()
    en_zona(p, 0, aliado("Goblin", 1, 1, raza="Faerie"), Zona.CEMENTERIO)
    g = jugar(p, 0, L.carta("goblin_berserker"))
    assert hab.fuerza(p, g) == 5


def test_jared_baraja_un_aliado_de_coste_igual_o_menor_al_talisman():
    p = _p()
    en_defensa(p, 0, L.carta("jared_el_mago"))
    chico = en_defensa(p, 1, aliado("Chico", 2, 2))
    grande = en_defensa(p, 1, aliado("Grande", 4, 4))
    jugar(p, 0, talisman("Daño", 2, [h("botar", objetivo=RIVAL)]))
    assert chico.zona == Zona.MAZO and grande.zona == Zona.DEFENSA
    otro = en_defensa(p, 1, aliado("Otro", 1, 1))
    jugar(p, 0, talisman("Daño", 2, [h("botar", objetivo=RIVAL)]))
    assert otro.zona == Zona.DEFENSA  # una vez por turno
    assert hab.tiene_prop(p, p.j(0).defensa[0], "errante")


def test_lady_rachel_destruye_un_arma_propia_para_destruir():
    p = _p()
    lady = en_defensa(p, 0, L.carta("lady_rachel"))
    barato = en_defensa(p, 1, aliado("Barato", 2, 2))
    caro = en_defensa(p, 1, aliado("Caro", 4, 4))
    p.e.activo = 0
    assert not activables(p, 0, lady)  # sin Arma no hay con qué pagar
    espada = equipar(p, 0, arma("Espada", 1, []), lady)
    activar(p, 0, lady)
    assert espada.zona == Zona.CEMENTERIO and barato.zona == Zona.CEMENTERIO and caro.zona == Zona.DEFENSA
    assert lady.en_juego


def test_martillo_de_galehaut():
    p = partida()
    d = en_defensa(p, 0, aliado("Portador", 2, 2))
    en_zona(p, 0, arma("Espada rota", 1, []), Zona.CEMENTERIO)
    comun = en_zona(p, 0, aliado("Común", 3, 3), Zona.CEMENTERIO)
    suya = en_zona(p, 1, aliado("Del rival", 5, 5), Zona.CEMENTERIO)
    equipar(p, 0, L.carta("martillo_de_galehaut"), d)
    # La IA destierra su Arma (suma fuerza) y la carta del rival; no su Aliado común.
    assert suya.zona == Zona.DESTIERRO and comun.zona == Zona.CEMENTERIO
    assert hab.fuerza(p, d) == 3
    en_zona(p, 0, aliado("Sir Tor", 1, 1), Zona.DESTIERRO)
    en_zona(p, 0, aliado("Osiris", 4, 4), Zona.DESTIERRO)  # no es un Aliado Sir
    en_zona(p, 0, ORO, Zona.DESTIERRO)
    assert hab.fuerza(p, d) == 4


def test_nathair_teine_suma_un_atacante_que_se_destruye_al_final():
    p = _p()
    n = en_defensa(p, 0, L.carta("nathair_teine"))
    aguila = en_zona(p, 0, L.carta("draco_aguila"), Zona.CEMENTERIO)
    caro = en_zona(p, 0, aliado("Dragón caro", 3, 3, raza="Dragón"), Zona.CEMENTERIO)
    p.e.activo, p.e.turno = 0, 3
    p._batalla(0)
    assert aguila in p.atacantes and aguila.uid in p.ataco_este_turno and caro.zona == Zona.CEMENTERIO
    # Entra el Águila (bota 1) y pegan Nathair (2) y el Águila (1).
    assert len(p.j(1).mazo) == 49 - 1 - 3
    assert aguila.zona == Zona.ATAQUE and n.zona == Zona.ATAQUE
    hab.resolver_pendientes_final(p)
    assert aguila.zona == Zona.CEMENTERIO and n.en_juego


def test_oberon():
    p = _p()
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    ob = jugar(p, 0, L.carta("oberon"))
    assert rival.zona == Zona.MAZO and hab.tiene_prop(p, ob, "errante")
    mano = len(p.j(0).mano)
    activar(p, 0, ob, oros=1)
    assert len(p.j(0).mano) == mano + 1  # roba 2 y descarta 1
    assert not activables(p, 0, ob)
    ob.usos_turno.clear()
    p.j(0).reserva.clear()
    otro = en_defensa(p, 0, aliado("Sacrificio", 1, 1))
    activar(p, 0, ob, oros=0)  # sin Oros: destruye un Aliado suyo
    assert Zona.CEMENTERIO in (otro.zona, ob.zona) and len(p.j(0).mano) == mano + 2


def test_oberon_la_ia_no_baraja_una_carta_propia():
    p = partida()
    mio = en_defensa(p, 0, aliado("Mío", 3, 3))
    ob = jugar(p, 0, L.carta("oberon"))
    assert mio.en_juego and ob.en_juego


def test_sir_bleoberis():
    p = _p()
    d = en_defensa(p, 0, aliado("Portador", 2, 2))
    barato = en_defensa(p, 1, aliado("Barato", 1, 1))
    caro = en_defensa(p, 1, aliado("Caro", 3, 3))
    jugar(p, 0, L.carta("sir_bleoberis"))
    assert barato.en_juego and caro.en_juego  # sin Armas: coste 0 o menos
    equipar(p, 0, arma("Espada", 1, []), d)
    jugar(p, 0, L.carta("sir_bleoberis"))
    assert barato.zona == Zona.CEMENTERIO and caro.en_juego


def test_sir_galehodin_abarata_a_los_sir():
    p = _p()
    en_defensa(p, 0, L.carta("sir_galehodin"))
    sir = en_zona(p, 0, aliado("Sir Lamorak", 3, 3), Zona.MANO)
    osiris = en_zona(p, 0, aliado("Osiris", 3, 3), Zona.MANO)
    assert p.coste_de(0, sir) == 2 and p.coste_de(0, osiris) == 3
    assert p.coste_de(1, en_zona(p, 1, aliado("Sir Rival", 3, 3), Zona.MANO)) == 3


def test_sir_owen_roba_tres_y_destierra_una_de_la_mano():
    p = _p()
    jugar(p, 0, L.carta("sir_owen"))
    assert len(p.j(0).mano) == 2 and len(p.j(0).destierro) == 1 and len(p.j(0).mazo) == 46


def test_sir_tor():
    p = _p()
    tor = en_zona(p, 0, L.carta("sir_tor"), Zona.ATAQUE)
    s2 = en_zona(p, 0, aliado("Sir Kay", 2, 2), Zona.ATAQUE)
    p.e.activo = 0
    p.ataco_este_turno.update({tor.uid, s2.uid})
    hab.disparar(p, tor, "al_atacar")
    assert len(p.j(0).mazo) == 49 and len(p.j(1).mazo) == 49  # con un solo Sir más no pasa nada
    s3 = en_zona(p, 0, aliado("Sir Gawain", 2, 2), Zona.ATAQUE)
    p.ataco_este_turno.add(s3.uid)
    hab.disparar(p, tor, "al_atacar")
    assert len(p.j(0).mazo) == 47 and len(p.j(1).mazo) == 47
    assert len(p.j(0).cementerio) == 1 and len(p.j(0).destierro) == 1
    assert hab.tiene_prop(p, tor, "imbloqueable") and hab.tiene_prop(p, tor, "furia")


def test_yddraig_ddall():
    p = _p()
    solo = jugar(p, 0, L.carta("yddraig_ddall"))
    assert solo.en_juego and len(p.j(0).mano) == 0  # sin otro Dragón no hace nada
    en_mano = en_zona(p, 0, aliado("Dragón de mano", 3, 3, raza="Dragón"), Zona.MANO)
    buscado = al_fondo(p, 0, aliado("Dragón del mazo", 5, 5, raza="Dragón"))
    jugar(p, 0, L.carta("yddraig_ddall"))
    assert len(p.j(0).mano) == 1 and p.j(0).mano[0].raza == "Dragón"
    assert Zona.MAZO in (en_mano.zona, buscado.zona)  # uno fue al mazo, el otro vino a la mano


# ── Funciones del motor que se agregaron para este lote ─────────────────────
def test_arquetipo_sir_es_palabra_completa():
    p = _p()
    assert hab._arquetipo_ok(en_defensa(p, 0, aliado("Sir Tor", 1, 1)), "Sir")
    assert not hab._arquetipo_ok(en_defensa(p, 0, aliado("Osiris", 4, 4)), "Sir")
    assert not hab._arquetipo_ok(en_defensa(p, 0, aliado("Siroco", 1, 1)), "Sir")
    assert hab._arquetipo_ok(en_defensa(p, 0, aliado("Hobgoblin", 2, 2)), "Goblin")  # los largos, como antes


def test_condicion_armas_propias_y_arquetipo_con_la_fuente():
    p = _p()
    d = en_defensa(p, 0, aliado("Minotauro", 2, 2))
    p.ctx_fuente_habilidad = d
    cond = {"condicion": {"tipo": "aliados_arquetipo", "arquetipo": "Minotauro", "op": ">=", "valor": 1}}
    assert not hab.condicion_ok(p, 0, cond)  # sin incluyeFuente no se cuenta a sí mismo
    cond["condicion"]["incluyeFuente"] = True
    assert hab.condicion_ok(p, 0, cond)
    p.ctx_fuente_habilidad = None
    armas = {"condicion": {"tipo": "armas_propias", "op": ">=", "valor": 1}}
    assert not hab.condicion_ok(p, 0, armas)
    equipar(p, 0, arma("Espada", 1, []), d)
    assert hab.condicion_ok(p, 0, armas) and not hab.condicion_ok(p, 1, armas)


def test_mover_a_ataque_sin_prefijo_linea():
    """Brian Boru y Asaltar la Caravana guardan zonaDestino "ataque"."""
    p = _p()
    brian = en_defensa(p, 0, aliado("Brian Boru", 4, 4))
    rival = en_defensa(p, 1, aliado("Defensor", 2, 2))
    hab.resolver(p, 0, brian, h("mover", zonaDestino="ataque",
                                objetivo={"quien": "oponente", "zona": "defensa", "tipos": ["Aliado"]}))
    assert rival.zona == Zona.ATAQUE


def test_oro_pagado_no_ve_jugadas_si_pide_reserva():
    p = _p()
    fruto = dict(L.CARTAS["fruto_fiodhain"]["habilidades"][0], zonaActivacion="reserva_oro")
    en_zona(p, 0, carta_desde_doc("f", {"nombre": "Fruto", "tipo": "Oro", "habilidades": [fruto],
                                        "habilidadesRevisadas": True}), Zona.PAGADO)
    arriba = list(p.j(0).mazo[:2])
    jugar(p, 0, talisman("Daño", 1, [h("botar", objetivo=RIVAL)]))
    assert p.j(0).mazo[:2] == arriba
