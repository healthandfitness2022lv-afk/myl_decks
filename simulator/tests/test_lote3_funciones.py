"""Funciones nuevas para programar las 58 cartas que estaban en espera."""

from myl_sim import habilidades as hab
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import AtacaTodo, BloqueaFijo, ORO, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import arma, oro
from test_tanda_guerrero_dragon_titan import SiempreUsa


def _p():
    return partida(jugadores=(SiempreUsa(1), SiempreUsa(2)))


# ── Costos ──────────────────────────────────────────────────────────────────
def test_costo_con_filtro_descartar_un_arma():
    p = _p()
    negro = en_defensa(p, 0, aliado("Caballero Negro", 3, 3))
    p.j(0).mano.clear()
    hh = h("prevenir", costo={"descartar": 1, "filtro": {"tipos": ["Arma"]}})
    en_zona(p, 0, aliado("Otro", 1, 1), Zona.MANO)
    assert not hab.puede_pagar_costo(p, 0, negro, hh)
    espada = en_zona(p, 0, arma("Espada", 2, []), Zona.MANO)
    assert hab.pagar_costo(p, 0, negro, hh) and espada.zona == Zona.CEMENTERIO


def test_costos_desterrar_mano_subir_y_destruir_propias():
    p = _p()
    a = en_defensa(p, 0, aliado("Anhur", 4, 2))
    p.j(0).mano.clear()
    x = en_zona(p, 0, ORO, Zona.MANO)
    assert hab.pagar_costo(p, 0, a, h("robar", costo={"desterrarMano": 1})) and x.zona == Zona.DESTIERRO
    daga = en_zona(p, 0, arma("Daga", 1, []), Zona.RESERVA)
    assert hab.pagar_costo(p, 0, daga, h("prevenir", costo={"subirEstaCarta": True})) and daga.zona == Zona.MANO
    en_zona(p, 0, ORO, Zona.RESERVA)
    antes = len(p.j(0).cementerio)
    assert hab.pagar_costo(p, 0, a, h("barajar", costo={"destruirPropias": 1}))
    assert len(p.j(0).cementerio) == antes + 1 and a.en_juego  # destruyó otra carta suya, no a Nemty


# ── Condiciones ─────────────────────────────────────────────────────────────
def test_condiciones_nuevas():
    p = partida()
    d = en_defensa(p, 0, aliado("Sir Dinadan", 1, 2))
    p.ctx_fuente_habilidad = d
    ok = lambda c: hab.condicion_ok(p, 0, {"condicion": c})  # noqa: E731
    assert not ok({"tipo": "porta_armas", "op": ">=", "valor": 1})
    e = en_zona(p, 0, arma("Espada", 1, []), Zona.MANO)
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    p.ejecutar_jugada(0, Jugada("jugar", e, portador=d))
    assert ok({"tipo": "porta_armas", "op": ">=", "valor": 1})
    assert ok({"tipo": "primer_turno", "op": ">=", "valor": 1})
    assert not ok({"tipo": "hizo_dano", "op": ">=", "valor": 1})
    p.dano_hecho.add(d.uid)
    assert ok({"tipo": "hizo_dano", "op": ">=", "valor": 1})
    s = en_zona(p, 0, aliado("Sombra 1", 1, 1, raza="Sombra"), Zona.ATAQUE)
    en_zona(p, 0, aliado("Sombra 2", 1, 1, raza="Sombra"), Zona.ATAQUE)
    assert ok({"tipo": "atacantes_raza", "op": ">=", "valor": 2, "raza": "Sombra"})
    p._mover(s, Zona.DESTIERRO)
    assert ok({"tipo": "destierro_vs_oponente", "op": ">", "valor": 0})


# ── Cantidades y "por cada" ────────────────────────────────────────────────
def test_cantidades_y_por_cada_nuevos():
    p = partida()
    belial = en_defensa(p, 0, aliado("Belial", 3, 3, [h("modificarFuerza", cuando="continua", valor=1,
                                                        valorPorCada="aliado_raza", porCadaRaza="Faerie",
                                                        objetivo={"quien": "esta_carta"})], raza="Faerie"))
    en_defensa(p, 0, aliado("Pixie", 2, 1, raza="Faerie"))
    en_defensa(p, 1, aliado("Faerie rival", 2, 1, raza="Faerie"))
    assert hab.fuerza(p, belial) == 5
    assert hab.cantidad(p, 0, {"cantidadSegun": "aliados_propios"}, []) == 2
    en_defensa(p, 0, aliado("Drácula", 3, 3))
    assert hab.cantidad(p, 0, {"cantidadSegun": "aliados_arquetipo", "porCadaArquetipo": "Drácula"}, []) == 1
    guerreras = en_zona(p, 0, aliado("Guerreras", 1, 1), Zona.ATAQUE)
    en_zona(p, 0, aliado("Otra", 1, 1), Zona.ATAQUE)
    assert hab.por_cada(p, guerreras, {"valorPorCada": "otro_en_ataque"}) == 1


def test_comparacion_segun_la_afectada_y_mismo_valor():
    p = _p()
    castillo = en_zona(p, 0, aliado("Castillo", 3, 0), Zona.APOYO)
    p.ctx_previas = [en_defensa(p, 1, aliado("Desterrada", 3, 3))]
    barato = en_zona(p, 0, aliado("Drácula chico", 2, 2), Zona.MAZO)
    caro = en_zona(p, 0, aliado("Drácula caro", 5, 5), Zona.MAZO)
    hh = h("buscar", objetivo={"quien": "propio", "zona": "mazo", "arquetipo": "Drácula",
                               "coste": {"op": "<=", "valor": 0, "segun": "coste_afectada"}})
    cands = hab.candidatos_validos(p, 0, castillo, hh, zona="mazo")
    assert barato in cands and caro not in cands
    a = en_defensa(p, 1, aliado("A", 2, 2))
    b = en_defensa(p, 1, aliado("B", 2, 3))
    c = en_defensa(p, 1, aliado("C", 4, 2))
    pares = hab._seleccionar(p, 0, castillo, h("barajar", cantidad=2, objetivo={"quien": "oponente", "mismoValor": "coste"}), [a, b, c])
    assert sorted(x.uid for x in pares) == sorted([a.uid, b.uid])


# ── Bedivere y Tumulario ────────────────────────────────────────────────────
def test_buscar_en_la_mano_rival_y_en_ambos_cementerios():
    p = _p()
    bed = en_defensa(p, 0, aliado("Sir Bedivere", 4, 2))
    robado = en_zona(p, 1, aliado("Ramsés II", 4, 6), Zona.MANO)
    hab.resolver(p, 0, bed, h("ponerEnJuego", objetivo={"quien": "oponente", "zona": "mano", "tipos": ["Aliado"]}))
    assert robado.zona == Zona.DEFENSA and robado.controlador == 0 and robado.dueno == 1
    tum = en_defensa(p, 0, aliado("Tumulario", 4, 1))
    mio = en_zona(p, 0, aliado("Mío", 2, 2), Zona.CEMENTERIO)
    suyo = en_zona(p, 1, aliado("Suyo", 2, 2), Zona.CEMENTERIO)
    hab.resolver(p, 0, tum, h("ponerEnJuego", objetivo={"quien": "ambos", "zona": "cementerio", "tipos": ["Aliado"]}))
    assert mio.zona == Zona.DEFENSA and suyo.zona == Zona.DEFENSA and suyo.controlador == 1


# ── Próximo Aliado, quitar Guardián, línea, inmunidad, barajar en vez ──────
def test_proximo_aliado_imbloqueable_y_con_furia():
    p = _p()
    p.e.activo, p.e.fase = 0, "vigilia"
    dc = en_zona(p, 0, oro("Defensores Celtas", []), Zona.RESERVA)
    for m in ("imbloqueable", "furia"):
        hab.resolver(p, 0, dc, h("otorgarPropiedad", modo=m, objetivo={"quien": "proximo", "raza": "Defensor", "tipos": ["Aliado"]}))
    x = en_zona(p, 0, aliado("Defensor", 2, 2, raza="Defensor"), Zona.MANO)
    p.j(0).oros_virtuales = 2
    p.ejecutar_jugada(0, Jugada("jugar", x))
    assert x.listo and hab.tiene_prop(p, x, "imbloqueable") and not p.j(0).proximos


def test_osiris_quita_guardian_y_bonos_por_linea():
    p = partida()
    g = en_defensa(p, 0, aliado("Ptah", 2, 4, [{"featureId": "g", "accion": "guardian", "cuando": "continua"}]))
    assert hab.tiene_prop(p, g, "guardian")
    hab.resolver(p, 0, g, h("otorgarPropiedad", modo="quitarGuardian", objetivo={"quien": "esta_carta"}))
    assert not hab.tiene_prop(p, g, "guardian")
    torc = oro("Torc", [h("modificarFuerza", cuando="continua", valor=1,
                          objetivo={"quien": "propio", "zona": "linea_ataque", "seleccion": "todos", "tipos": ["Aliado"]})])
    en_zona(p, 0, torc, Zona.RESERVA)
    atk = en_zona(p, 0, aliado("Atk", 2, 2), Zona.ATAQUE)
    assert hab.fuerza(p, atk) == 3 and hab.fuerza(p, g) == 4


def test_daana_protege_y_baraja_en_vez_de_destruir():
    daana = aliado("Daana", 1, 1, [
        h("inmunidad", cuando="continua", objetivo={"quien": "oponente", "tipos": ["Talismán"]},
          protege={"tipos": ["Aliado"], "raza": "Desafiante", "excluirEstaCarta": True}),
        h("prevenir", cuando="continua", modo="barajar_en_vez",
          objetivo={"quien": "propio", "tipos": ["Aliado"], "raza": "Desafiante", "excluirEstaCarta": True}),
    ], raza="Desafiante")
    p = partida()
    en_defensa(p, 0, daana)
    x = en_defensa(p, 0, aliado("Desafiante", 2, 2, raza="Desafiante"))
    tal = p._instancia(talisman("Rayo", 1, []), 1, Zona.MANO)
    assert hab.inmune(p, x, tal)
    assert not p.destruir(x) and x.zona == Zona.MAZO


# ── Respuestas ──────────────────────────────────────────────────────────────
def test_traicion_de_macalpin_previene_desde_la_mano():
    p = _p()
    x = en_defensa(p, 0, aliado("Valioso", 4, 4))
    t = en_zona(p, 0, talisman("La Traición", 1, [h("prevenir", objetivo={"quien": "propio", "tipos": ["Aliado"]})]), Zona.MANO)
    p.j(0).oros_virtuales = 1
    assert not p.destruir(x) and x.en_juego and t.zona == Zona.CEMENTERIO
    assert not hab.talisman_jugable(p, 0, t, "vigilia")


def test_sombras_areneras_el_rival_paga_3_para_anularla():
    sombras = talisman("Sombras Areneras", 3, [h("restriccion", cuando="continua", modo="anulable_pagando", valor=3)])
    p = _p()
    s = en_zona(p, 0, sombras, Zona.MANO)
    p.j(1).oros_virtuales = 3
    YO = p.decide(1)
    YO.anular = lambda *a: 0
    assert hab.ventana_anulacion(p, 0, s) and p.j(1).oros_virtuales == 0


def test_invocar_chacales_anula_la_anulacion():
    p = _p()
    jugada = en_defensa(p, 0, aliado("Ramsés", 4, 6))
    en_zona(p, 1, talisman("Gran Guardián", 1, [h("anular", cuando="oponente_juega", objetivo={"quien": "oponente"})]), Zona.MANO)
    chacales = en_zona(p, 0, talisman("Invocar Chacales", 0, [h("anular", cuando="oponente_juega",
                                                               objetivo={"quien": "oponente", "anulaAnulacion": True})]), Zona.MANO)
    p.j(1).oros_virtuales = 1
    p.decide(1).anular = lambda *a: 0
    assert not hab.ventana_anulacion(p, 0, jugada)
    assert chacales.zona == Zona.CEMENTERIO


# ── Requisitos y combate ────────────────────────────────────────────────────
def test_tutatis_y_kobold_requisitos():
    tutatis = aliado("Tutatis", 1, 4, [h("restriccion", cuando="continua", modo="requisito_jugar",
                                         condicion={"tipo": "aliados_propios", "op": ">=", "valor": 2})])
    kobold = aliado("Kobold", 0, 3, [h("botar", cantidad=3, objetivo={"quien": "propio"})])
    p = partida()
    t = en_zona(p, 0, tutatis, Zona.MANO)
    assert not hab.requisito_para_jugar(p, 0, t)
    en_defensa(p, 0, aliado("A", 1, 1))
    en_defensa(p, 0, aliado("B", 1, 1))
    assert hab.requisito_para_jugar(p, 0, t)
    k = en_zona(p, 0, kobold, Zona.MANO)
    assert hab.requisito_para_jugar(p, 0, k)
    del p.j(0).mazo[3:]
    assert not hab.requisito_para_jugar(p, 0, k)


def test_macda_tho_y_melisende():
    macda = aliado("Macda Tho", 3, 2, [h("restriccion", cuando="continua", modo="atacante_libre_fuerza_1")])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    en_defensa(p, 0, aliado("Grande", 2, 6))
    en_defensa(p, 1, macda)
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 1
    meli = aliado("Melisende", 1, 1, [h("restringirCombate", cuando="continua", modo="no_bloqueable_por_fuerza", valor=3,
                                        objetivo={"quien": "esta_carta"})])
    p = partida()
    m = en_defensa(p, 0, meli)
    assert not p.puede_bloquear(m, en_defensa(p, 1, aliado("Fuerte", 3, 3)))
    assert p.puede_bloquear(m, en_defensa(p, 1, aliado("Débil", 1, 2)))


def test_seth_destierra_el_dano_y_castiga_al_que_lo_afecta():
    seth = aliado("Seth", 3, 3, [h("restriccion", cuando="continua", modo="dano_destierra"),
                                 h("botar", cuando="afectada_por_oponente", cantidad=4, objetivo={"quien": "oponente"},
                                   limitePorTurno=1)])
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    s = en_defensa(p, 0, seth)
    p._batalla(0)
    assert len(p.j(1).destierro) == 3 and not p.j(1).cementerio
    antes = len(p.j(1).mazo)
    hab.resolver(p, 1, en_defensa(p, 1, aliado("Rayo", 1, 1)), h("modificarFuerza", valor=-1, objetivo={"quien": "oponente", "tipos": ["Aliado"]}))
    assert antes - len(p.j(1).mazo) == 4 and s.en_juego


def test_broche_de_tara_dispara_al_pagar_un_aliado():
    broche = oro("Broche de Tara", [h("botar", cuando="al_pagar_aliado", objetivo={"quien": "oponente"}, limitePorTurno=1,
                                      limitePorNombre=True)])
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    en_zona(p, 0, broche, Zona.RESERVA)
    en_zona(p, 0, ORO, Zona.RESERVA)
    x = en_zona(p, 0, aliado("Aliado", 1, 1), Zona.MANO)
    antes = len(p.j(1).mazo)
    p.ejecutar_jugada(0, Jugada("jugar", x))
    assert antes - len(p.j(1).mazo) == 1


def test_nuada_elige_entre_opciones_obligatorias():
    nuada = aliado("Nuada", 3, 5, [
        h("destruir", cuando="al_hacer_dano", grupoElegir="n", objetivo={"quien": "propio", "tipos": ["Aliado"]}),
        h("botar", cuando="al_hacer_dano", grupoElegir="n", cantidad=3, objetivo={"quien": "propio"})])
    p = partida()
    n = en_defensa(p, 0, nuada)
    otro = en_defensa(p, 0, aliado("Otro", 1, 1))
    antes = len(p.j(0).mazo)
    hab.disparar(p, n, "al_hacer_dano")
    hecho = (antes - len(p.j(0).mazo) == 3) != (not otro.en_juego or not n.en_juego)
    assert hecho  # se resolvió exactamente una de las dos


# ── Copiar y convertirse ────────────────────────────────────────────────────
def test_aker_copia_y_nimue_se_convierte_hasta_la_fase_final():
    p = _p()
    aker = en_defensa(p, 0, aliado("Aker", 3, 3))
    modelo = en_defensa(p, 1, aliado("Con habilidad", 2, 2, [h("robar", cuando="activada", objetivo={"quien": "propio"})]))
    hab.resolver(p, 0, aker, h("copiarHabilidad", objetivo={"quien": "cualquiera", "tipos": ["Aliado"]}))
    assert any(x.get("accion") == "robar" for x in aker.habilidades)
    nimue = en_defensa(p, 0, aliado("Nimue", 3, 2, raza="Faerie"))
    en_zona(p, 0, aliado("Morgana", 4, 5, raza="Faerie"), Zona.CEMENTERIO)
    hab.resolver(p, 0, nimue, h("convertirEnCopia", objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"]}))
    assert nimue.nombre == "Morgana" and hab.fuerza(p, nimue) == 5
    hab.expirar(p, "hasta_fase_final")
    assert nimue.nombre == "Nimue" and not aker.copia and modelo.en_juego


def test_acolitos_hace_drácula_y_aed_finn_se_agrupa():
    p = partida()
    x = en_defensa(p, 0, aliado("Soldado", 1, 1))
    hab.resolver(p, 0, x, h("cambiarRaza", arquetipoNuevo="Drácula", objetivo={"quien": "esta_carta"}))
    assert hab.coincide(p, x, {"arquetipo": "Drácula"})
    aed = en_zona(p, 0, aliado("Aed Finn", 2, 3), Zona.ATAQUE)
    hab.resolver(p, 0, aed, h("agrupar", objetivo={"quien": "esta_carta"}))
    assert aed.zona == Zona.DEFENSA
