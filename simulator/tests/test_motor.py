"""Escenarios fijos de reglas (REGLAS.md) y de cada acción."""

import pytest

from myl_sim import habilidades as hab
from myl_sim.jugadores import Aleatorio, Heuristico
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import FinPartida, Partida
from myl_sim.simulacion import simular, wilson
from myl_sim.datos import Mazo


def aliado(nombre, coste, fuerza, habilidades=(), raza="Caballero"):
    return Carta(nombre, nombre, Tipo.ALIADO, coste, fuerza, raza, "x" if habilidades else "", tuple(habilidades), True)


def talisman(nombre, coste, habilidades):
    return Carta(nombre, nombre, Tipo.TALISMAN, coste, 0, "", "x", tuple(habilidades), True)


ORO = Carta("oro", "Oro", Tipo.ORO, 0, 0, "", "")


def mazo_basico():
    return [ORO] * 17 + [aliado("Soldado", 1, 1)] * 16 + [aliado("Caballero", 2, 2)] * 16


def partida(cartas_a=None, cartas_b=None, jugadores=None, **kw):
    p = Partida(
        (cartas_a or mazo_basico(), cartas_b or mazo_basico()),
        jugadores or (Heuristico(1), Heuristico(2)),
        seed=7,
        **kw,
    )
    return p


def en_defensa(p, i, carta, listo=True):
    inst = p._instancia(carta, i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    p._mover(inst, Zona.DEFENSA)
    inst.listo = listo
    return inst


# ── Preparación y fin ─────────────────────────────────────────────────────────
def test_preparacion_oro_inicial_y_mazo():
    p = partida()
    for i in (0, 1):
        assert len(p.j(i).reserva) == 1
        assert p.j(i).reserva[0].carta.nombre == "Oro inicial"
        assert len(p.j(i).mazo) == 49


def test_mano_inicial_8_y_mulligan_baja_una():
    class SiempreMulligan(Heuristico):
        def __init__(self):
            super().__init__(0)
            self.veces = 0

        def quedarse_mano(self, p, yo):
            self.veces += 1
            return self.veces > 2

    p = partida(jugadores=(SiempreMulligan(), Heuristico(2)))
    p._mano_inicial(0)
    assert len(p.j(0).mano) == 6  # 8 → 7 → 6
    p._mano_inicial(1)
    assert len(p.j(1).mano) == 8


def test_perder_al_quedar_sin_mazo():
    p = partida()
    p.j(1).mazo = p.j(1).mazo[:2]
    with pytest.raises(FinPartida):
        p.botar(1, 5)
    assert p.e.ganador == 0 and p.e.causa == "botar"


def test_empate_si_ambos_quedan_sin_mazo():
    p = partida()
    p.j(0).mazo, p.j(1).mazo = [], []
    with pytest.raises(FinPartida):
        p._comprobar_mazos("botar")
    assert p.e.ganador == -1


# ── Combate (5.3.4) ───────────────────────────────────────────────────────────
class AtacaTodo(Heuristico):
    def elegir_atacantes(self, p, yo, candidatos):
        return candidatos


class BloqueaFijo(Heuristico):
    def __init__(self, mapa):
        super().__init__(0)
        self.mapa = mapa

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        return {a.uid: b for a in atacantes for b in bloqueadores if self.mapa.get(a.nombre) == b.nombre}


@pytest.mark.parametrize(
    "fa,fb,dano,muere_atk,muere_blk",
    [(4, 2, 2, False, True), (3, 3, 0, True, True), (2, 5, 0, True, False)],
)
def test_asignacion_de_dano(fa, fb, dano, muere_atk, muere_blk):
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Atk": "Blk"})))
    atk = en_defensa(p, 0, aliado("Atk", 2, fa))
    blk = en_defensa(p, 1, aliado("Blk", 2, fb))
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == dano
    assert (atk.zona == Zona.CEMENTERIO) == muere_atk
    assert (blk.zona == Zona.CEMENTERIO) == muere_blk


def test_sin_bloqueo_hace_todo_el_dano_y_no_listo_no_ataca():
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({})))
    en_defensa(p, 0, aliado("Atk", 2, 3))
    en_defensa(p, 0, aliado("Nuevo", 2, 5), listo=False)
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 3


def test_atacantes_no_pueden_bloquear_en_turno_rival():
    p = partida(jugadores=(AtacaTodo(1), AtacaTodo(2)))
    atk = en_defensa(p, 0, aliado("Atk", 2, 3))
    p._batalla(0)
    assert atk.zona == Zona.ATAQUE  # vuelve recién en su Agrupación
    assert atk not in p.j(0).defensa


def test_imbloqueable_e_indestructible():
    imb = {"featureId": "x", "accion": "imbloqueable", "cuando": "continua"}
    ind = {"featureId": "y", "accion": "indestructible", "cuando": "continua"}
    p = partida(jugadores=(AtacaTodo(1), BloqueaFijo({"Atk": "Blk", "Duro": "Blk2"})))
    en_defensa(p, 0, aliado("Atk", 2, 2, [imb]))
    duro = en_defensa(p, 0, aliado("Duro", 2, 1, [ind]))
    en_defensa(p, 1, aliado("Blk", 2, 5))
    en_defensa(p, 1, aliado("Blk2", 2, 5))
    antes = len(p.j(1).mazo)
    p._batalla(0)
    assert antes - len(p.j(1).mazo) == 2  # el imbloqueable pasa entero
    assert duro.en_juego  # indestructible sobrevive al combate


# ── Oro y costes ─────────────────────────────────────────────────────────────
def test_un_oro_por_turno_y_pagar_mueve_a_pagado():
    p = partida()
    p.j(0).mano = []
    for _ in range(3):
        o = p._instancia(ORO, 0, Zona.MANO)
        p.j(0).mano.append(o)
    p.e.fase = "vigilia"
    p._vigilia(0)
    assert len(p.j(0).reserva) + len(p.j(0).pagado) == 2  # inicial + 1


# ── Acciones del catálogo ─────────────────────────────────────────────────────
def h(accion, **kw):
    base = {"featureId": "f", "featureName": accion, "accion": accion, "cuando": "al_jugar", "fase": "cualquiera", "cantidad": 1}
    base.update(kw)
    return base


def jugar_talisman(p, i, carta):
    inst = p._instancia(carta, i, Zona.MANO)
    p.j(i).mano.append(inst)
    p.j(i).oros_virtuales = 10
    p.e.fase = "vigilia"
    p.e.activo = i
    opciones = [o for o in p.jugadas_legales(i, "vigilia") if o.carta is inst]
    assert opciones, "el talismán debería ser jugable"
    p.ejecutar_jugada(i, opciones[0])
    return inst


def test_destruir_aliado_coste_maximo_en_vigilia():
    t = talisman(
        "Rayo", 2,
        [h("destruir", fase="vigilia", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego", "coste": {"op": "<=", "valor": 2}, "seleccion": "elige"})],
    )
    p = partida()
    barato = en_defensa(p, 1, aliado("Barato", 2, 1))
    caro = en_defensa(p, 1, aliado("Caro", 4, 4))
    inst = jugar_talisman(p, 0, t)
    assert barato.zona == Zona.CEMENTERIO
    assert caro.en_juego
    assert inst.zona == Zona.CEMENTERIO


def test_talisman_sin_objetivo_valido_no_se_puede_jugar():
    t = talisman("Rayo", 1, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})])
    p = partida()
    inst = p._instancia(t, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not any(o.carta is inst for o in p.jugadas_legales(0, "vigilia"))


def test_robar_y_botar():
    p = partida()
    mano = len(p.j(0).mano)
    mazo_rival = len(p.j(1).mazo)
    jugar_talisman(p, 0, talisman("Saber", 1, [h("robar", cantidad=2, objetivo={"quien": "propio"})]))
    jugar_talisman(p, 0, talisman("Tormenta", 1, [h("botar", cantidad=3, objetivo={"quien": "oponente"})]))
    assert len(p.j(0).mano) == mano + 2
    assert len(p.j(1).mazo) == mazo_rival - 3


def test_modificar_fuerza_hasta_fase_final_expira():
    p = partida()
    a = en_defensa(p, 0, aliado("A", 2, 2))
    jugar_talisman(
        p, 0,
        talisman("Furor", 1, [h("modificarFuerza", valor=3, duracion="hasta_fase_final", objetivo={"quien": "propio", "tipos": ["Aliado"], "zona": "en_juego"})]),
    )
    assert hab.fuerza(p, a) == 5
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, a) == 2


def test_arma_continua_da_fuerza_al_portador():
    espada = Carta("Espada", "Espada", Tipo.ARMA, 1, 0, "", "x", (h("modificarFuerza", cuando="continua", valor=2, duracion="mientras_en_juego", objetivo={"quien": "esta_carta"}),), True)
    p = partida()
    a = en_defensa(p, 0, aliado("A", 2, 2))
    inst = p._instancia(espada, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is inst)
    p.ejecutar_jugada(0, jugada)
    assert hab.fuerza(p, a) == 4
    p.destruir(a)
    assert inst.zona == Zona.CEMENTERIO  # el Arma sigue al portador


def test_anulacion_de_talisman():
    anula = talisman("Contrahechizo", 1, [h("anular", cuando="oponente_juega", objetivo={"tipos": ["Talismán"]})])
    p = partida()
    en_mano = p._instancia(anula, 1, Zona.MANO)
    p.j(1).mano.append(en_mano)
    p.j(1).oros_virtuales = 3
    rival = en_defensa(p, 1, aliado("Rival", 3, 3))
    caro = talisman("Gran Rayo", 4, [h("destruir", objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"})])
    jugar_talisman(p, 0, caro)
    assert rival.en_juego  # fue anulado
    assert en_mano.zona == Zona.CEMENTERIO


def test_prevenir_y_subir_a_la_mano():
    oseye = aliado("Oseye", 2, 3, [h("prevenir", cuando="activada", objetivo={"quien": "esta_carta"}, costo={"oros": 2}, zonaDestino="mano", opcional=True)])
    p = partida()
    o = en_defensa(p, 1, oseye)
    p.j(1).oros_virtuales = 2
    p.destruir(o)
    assert o.zona == Zona.MANO


def test_carta_no_revisada_se_juega_sin_habilidad():
    pendiente = Carta("P", "P", Tipo.ALIADO, 1, 1, "", "texto", (h("robar", cantidad=5),), revisada=False)
    p = partida()
    inst = p._instancia(pendiente, 0, Zona.MANO)
    assert inst.habilidades == ()


# ── Simulación completa ──────────────────────────────────────────────────────
def _mazo(nombre, cartas):
    return Mazo(nombre, nombre, "racial", "", cartas, [])


def test_misma_semilla_mismo_resultado():
    a, b = _mazo("A", mazo_basico()), _mazo("B", mazo_basico())
    r1 = simular(a, b, 30, seed=3)
    r2 = simular(a, b, 30, seed=3)
    assert r1["victoriasA"] == r2["victoriasA"] and r1["turnos"] == r2["turnos"]


def test_espejo_cerca_de_50():
    a, b = _mazo("A", mazo_basico()), _mazo("B", mazo_basico())
    r = simular(a, b, 400, seed=5)
    assert r["anomalas"] == 0
    assert 0.40 <= r["winrateA"] <= 0.60


def test_heuristico_le_gana_al_aleatorio():
    from myl_sim.motor import Partida as P

    gana = 0
    for k in range(200):
        jug = (Heuristico(k), Aleatorio(k)) if k % 2 == 0 else (Aleatorio(k), Heuristico(k))
        r = P((mazo_basico(), mazo_basico()), jug, inicial=k % 2, seed=k).jugar()
        heur = 0 if k % 2 == 0 else 1
        gana += r.ganador == heur
    assert gana / 200 > 0.6


def test_wilson():
    lo, hi = wilson(50, 100)
    assert lo < 0.5 < hi and hi - lo < 0.21


# ── Efectos "luego" (caso Abhartach) ─────────────────────────────────────────
def test_luego_destierra_copias_del_mazo_oponente():
    abhartach = aliado(
        "Abhartach", 4, 4,
        [h(
            "desterrar",
            opcional=True,
            objetivo={"quien": "oponente", "tipos": ["Aliado", "Tótem"], "zona": "en_juego", "seleccion": "elige"},
            luego=[{
                "accion": "desterrar",
                "relacion": "si_se_cumplio",
                "objetivo": {"quien": "oponente", "zona": "mazo", "seleccion": "todos", "referencia": "copias"},
            }],
        )],
        raza="Sombra",
    )
    p = partida()
    victima = en_defensa(p, 1, aliado("Víctima", 2, 2))
    copias = [p._instancia(victima.carta, 1, Zona.MAZO) for _ in range(2)]
    for c in copias:
        p.j(1).mazo.append(c)
    inst = p._instancia(abhartach, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).oros_virtuales = 10
    p.e.activo, p.e.fase = 0, "vigilia"
    jugada = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is inst)
    p.ejecutar_jugada(0, jugada)
    assert victima.zona == Zona.DESTIERRO
    assert all(c.zona == Zona.DESTIERRO for c in copias)
    assert not any(c.nombre == "Víctima" for c in p.j(1).mazo)


def test_luego_si_se_cumplio_no_ocurre_si_el_principal_falla():
    duro = aliado("Duro", 2, 2, [{"featureId": "i", "accion": "indesterrable", "cuando": "continua"}])
    t = talisman("Exilio", 1, [h(
        "desterrar",
        objetivo={"quien": "oponente", "tipos": ["Aliado"], "zona": "en_juego"},
        luego=[{"accion": "robar", "relacion": "si_se_cumplio", "cantidad": 2, "objetivo": {"quien": "propio"}}],
    )])
    p = partida()
    en_defensa(p, 1, duro)
    # Un indesterrable no es objetivo válido de "desterrar" (reporte del
    # dueño: "no puedo hacer objetivo a la Haquika"): sin objetivo, el
    # Talismán no se juega ni roba.
    inst = p._instancia(t, 0, Zona.MANO)
    p.j(0).mano.append(inst)
    p.j(0).oros_virtuales = 10
    p.e.fase, p.e.activo = "vigilia", 0
    assert not any(o.carta is inst for o in p.jugadas_legales(0, "vigilia"))
    # Si el efecto principal falla, el "luego" no ocurre.
    mano = len(p.j(0).mano)
    cumplido, _ = hab._resolver_efecto(p, 0, inst, {**t.habilidades[0], "objetivo": {"quien": "oponente", "zona": "mazo", "tipos": ["Tótem"]}})
    hab.aplicar_luego(p, 0, inst, t.habilidades[0], cumplido, [])
    assert not cumplido and len(p.j(0).mano) == mano


def test_dado_decide_quien_empieza():
    from myl_sim.motor import Partida as P
    from myl_sim.jugadores import Heuristico
    empiezan = set()
    for k in range(30):
        p = P((mazo_basico(), mazo_basico()), (Heuristico(1), Heuristico(2)), inicial=None, seed=k, log=True)
        a, b = p.dados[-1]
        assert a != b and p.inicial == (0 if a > b else 1)
        assert all(x == y for x, y in p.dados[:-1])  # las anteriores fueron empates
        r = p.jugar()
        assert r.dado == (a, b)
        assert p.e.log[0].endswith("gana el dado y empieza") or "empate" in p.e.log[0]
        empiezan.add(p.inicial)
    assert empiezan == {0, 1}
