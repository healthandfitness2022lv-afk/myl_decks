"""Auditor automático: invariantes, patrones y reproducibilidad."""

from myl_sim.auditoria import (PartidaAuditada, agrupar, auditar_cruce, crear_partida,
                               informe_md, invariantes)
from myl_sim.datos import Mazo
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Carta, Tipo, Zona
from collections import Counter


def _aliado(n=3):
    return Carta(id=f"al{n}", nombre=f"Soldado {n}", tipo=Tipo.ALIADO, coste=0, fuerza=n,
                 raza="", texto="", revisada=True)


def _oro():
    return Carta(id="oro", nombre="Oro", tipo=Tipo.ORO, coste=0, fuerza=0, raza="", texto="",
                 revisada=True)


def _mazo(nombre, cartas):
    return Mazo(id=nombre, nombre=nombre, formato="racial", raza="", cartas=cartas, faltantes=[])


class NoAtaca(Heuristico):
    def elegir_atacantes(self, p, yo, candidatos):
        return []


class NoJuegaNada(Heuristico):
    def elegir_jugada(self, p, yo, jugadas):
        return next(j for j in jugadas if j.tipo == "pasar")


class NoBloquea(NoAtaca):
    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        return {}


class AtacaTodo(Heuristico):
    def elegir_atacantes(self, p, yo, candidatos):
        return list(candidatos)


def _partida(j0, j1, mazo0, mazo1, seed=3):
    return PartidaAuditada((mazo0, mazo1), (j0(seed), j1(seed + 1)), inicial=0, seed=seed)


def test_invariantes_detectan_carta_en_dos_zonas():
    p = _partida(Heuristico, Heuristico, [_aliado()] * 49, [_aliado()] * 49)
    j = p.j(0)
    j.mano.append(j.mazo[0])  # la misma instancia en Mazo y Mano
    patrones = {x[0] for x in invariantes(p, p.uids_iniciales)}
    assert "carta_duplicada" in patrones


def test_invariantes_detectan_carta_perdida_y_zona_incorrecta():
    p = _partida(Heuristico, Heuristico, [_aliado()] * 49, [_aliado()] * 49)
    j = p.j(1)
    j.mazo.pop()
    j.mazo[0].zona = Zona.MANO
    patrones = {x[0] for x in invariantes(p, p.uids_iniciales)}
    assert {"carta_perdida", "zona_inconsistente"} <= patrones


def test_partida_normal_no_rompe_invariantes():
    mazo = [_aliado(2)] * 25 + [_oro()] * 24
    p = _partida(Heuristico, Heuristico, mazo, mazo)
    p.jugar()
    assert not [h for h in p.hallazgos if h.tipo == "regla"]


def test_detecta_no_atacar_con_letal():
    mazo = [_aliado(3)] * 25 + [_oro()] * 24
    p = _partida(NoAtaca, NoJuegaNada, mazo, mazo)
    p.jugar()
    assert any(h.patron == "no_ataca_letal" and h.lado == 0 for h in p.hallazgos)


def test_detecta_no_bloquear_el_ataque_que_mata():
    ataca = [_aliado(5)] * 3 + [_oro()] * 46
    defiende = [_aliado(6)] * 10 + [_oro()] * 39
    hallado = False
    for seed in range(1, 6):
        p = _partida(AtacaTodo, NoBloquea, ataca, defiende, seed=seed)
        r = p.jugar()
        if r.ganador == 0 and r.causa == "combate":
            hallado |= any(h.patron == "no_bloquea_letal" and h.lado == 1 for h in p.hallazgos)
    assert hallado


def test_detecta_no_jugar_oro():
    mazo = [_aliado(2)] * 25 + [_oro()] * 24
    p = _partida(NoJuegaNada, Heuristico, mazo, mazo)
    p.jugar()
    assert any(h.patron == "no_juega_oro" and h.lado == 0 for h in p.hallazgos)


def test_lote_reproducible_con_y_sin_narracion():
    a = _mazo("A", [_aliado(3)] * 25 + [_oro()] * 24)
    b = _mazo("B", [_aliado(2)] * 30 + [_oro()] * 19)
    r = auditar_cruce(a, b, 4, seed=50)
    for k in range(4):
        sin = crear_partida(a, b, 50 + k, k % 2)
        con = crear_partida(a, b, 50 + k, k % 2, log=True)
        rs, rc = sin.jugar(), con.jugar()
        assert (rs.ganador, rs.turnos) == (rc.ganador, rc.turnos)
        assert [h.patron for h in sin.hallazgos] == [h.patron for h in con.hallazgos]
        esperados = [h["patron"] for h in r["hallazgos"] if h["seed"] == 50 + k]
        assert esperados == [h.patron for h in sin.hallazgos]


def test_agrupar_pone_bugs_de_regla_primero():
    base = {"mazoA": {"id": "a"}, "mazoB": {"id": "b"}, "seed": 1, "inicial": 0,
            "turno": 3, "fase": "vigilia", "detalle": "", "rival": "B"}
    hallazgos = [
        {**base, "patron": "guarda_jugables", "tipo": "jugada", "gravedad": "baja",
         "mazo": "A", "carta": "X"},
        {**base, "patron": "carta_perdida", "tipo": "regla", "gravedad": "alta",
         "mazo": "(motor)", "carta": ""},
        {**base, "patron": "no_ataca_letal", "tipo": "jugada", "gravedad": "alta",
         "mazo": "A", "carta": "Y"},
    ]
    grupos = agrupar(hallazgos, Counter({"A": 10}))
    assert [g["patron"] for g in grupos] == ["carta_perdida", "no_ataca_letal", "guarda_jugables"]
    md = informe_md({"creado": "2026-11-12T00:00", "motorHuella": "x", "mazos": [],
                     "cruces": [{"partidas": 10}], "grupos": grupos})
    assert "Bugs de regla" in md and "repetir a b --seed 1" in md


def test_heuristica_ataca_con_letal_aunque_este_en_peligro():
    """Auditoría 2026-11-12: con el rival a 3 de castillo y sin bloqueadores
    libres, se atacaba solo si no estaba "en peligro"; ahora gana la partida."""
    mazo = [_aliado(5)] * 25 + [_oro()] * 24
    p = _partida(Heuristico, Heuristico, mazo, mazo)
    p.robar(0, 8, inicial=True)
    p.robar(1, 8, inicial=True)
    yo, rival = p.j(0), p.j(1)
    mios = [x for x in yo.mano if x.tipo == Tipo.ALIADO][:2]
    suyos = [x for x in rival.mano if x.tipo == Tipo.ALIADO][:3]
    for x in mios:
        p._mover(x, Zona.DEFENSA)
        x.listo = True
    for x in suyos:  # 15 de fuerza: me botan el castillo el próximo turno
        p._mover(x, Zona.ATAQUE)
    del yo.mazo[10:]
    del rival.mazo[3:]
    p.e.activo, p.e.fase = 0, "batalla"
    elegidos = Heuristico(1).elegir_atacantes(p, 0, list(mios))
    assert sum(x.carta.fuerza for x in elegidos) >= 3


def test_creencias_descuentan_lo_visto_y_estiman_la_mano():
    from myl_sim import creencias

    flechas = Carta(id="fl", nombre="Flechas", tipo=Tipo.TALISMAN, coste=2, fuerza=0,
                    raza="", texto="", revisada=True)
    lista = [flechas] * 3 + [_aliado(2)] * 46
    p = _partida(Heuristico, Heuristico, [_aliado()] * 49, lista)
    p.robar(1, 8, inicial=True)
    rival = p.j(1)
    # Dos Flechas ya en el Cementerio: queda a lo más una entre mano y mazo.
    vistas = [x for x in rival.mazo + rival.mano if x.carta.id == "fl"][:2]
    for x in vistas:
        p._mover(x, Zona.CEMENTERIO)
    assert creencias.vistas(p, 1)["fl"] == 2
    prob = creencias.prob_en_mano(p, 0, lambda c: c.id == "fl")
    mano, mazo = creencias.ocultas(p, 1)
    assert abs(prob - mano / (mano + mazo)) < 1e-9
    # Con una lista del meta sin Flechas, la probabilidad cae a cero.
    p.meta_listas = [[_aliado(2)] * 49]
    assert creencias.prob_en_mano(p, 0, lambda c: c.id == "fl") == 0
    mano_m, mazo_m = creencias.muestrear(p, 1, __import__("random").Random(1))
    assert (len(mano_m), len(mazo_m)) == (mano, mazo)


def test_busqueda_de_ataque_no_rompe_la_partida_y_es_reproducible():
    from myl_sim.busqueda_ataques import BuscadorAtaques

    mazo = [_aliado(3)] * 25 + [_oro()] * 24
    res = []
    for _ in range(2):
        p = PartidaAuditada((mazo, mazo), (BuscadorAtaques(5, muestras=2), Heuristico(6)),
                            inicial=0, seed=5)
        r = p.jugar()
        assert not [h for h in p.hallazgos if h.tipo == "regla"]
        res.append((r.ganador, r.turnos))
    assert res[0] == res[1]


def test_lote_en_paralelo_da_lo_mismo_que_en_serie():
    from myl_sim.auditoria import auditar_lote

    a = _mazo("A", [_aliado(3)] * 25 + [_oro()] * 24)
    b = _mazo("B", [_aliado(2)] * 30 + [_oro()] * 19)
    c = _mazo("C", [_aliado(4)] * 20 + [_oro()] * 29)
    serie = auditar_lote([a, b, c], 2, seed=11, procesos=1)
    paralelo = auditar_lote([a, b, c], 2, seed=11, procesos=2)
    assert serie["hallazgos"] == paralelo["hallazgos"]


def _flechas():
    h = {"accion": "cancelarAtaque", "cuando": "al_jugar", "fase": "declaracion_ataque",
         "turno": "oponente", "modo": "todo_el_ataque",
         "luego": [{"accion": "botar", "relacion": "siempre",
                    "cantidadSegun": "fuerza_mayor_aliado_oponente"}]}
    return Carta(id="fl", nombre="Flechas de Lava", tipo=Tipo.TALISMAN, coste=3, fuerza=0,
                 raza="", texto="", habilidades=(h,), revisada=True)


def test_no_ataca_si_flechas_de_lava_lo_deja_sin_castillo():
    """Auditoría 2026-11-12 (Killgharrah con castillo 7): Flechas cancela y
    bota la fuerza de mi mayor Aliado; con el robo final, perdía."""
    mazo = [_aliado(6)] * 25 + [_oro()] * 24
    rival = [_flechas()] * 3 + [_aliado(1)] * 22 + [_oro()] * 24
    p = _partida(Heuristico, Heuristico, mazo, rival)
    p.robar(0, 8, inicial=True)
    p.robar(1, 8, inicial=True)
    yo, otro = p.j(0), p.j(1)
    mio = next(x for x in yo.mano if x.tipo == Tipo.ALIADO)
    p._mover(mio, Zona.DEFENSA)
    mio.listo = True
    for x in [x for x in otro.mano + otro.mazo if x.tipo == Tipo.ORO][:3]:
        p._mover(x, Zona.RESERVA)
    p.e.activo, p.e.fase = 0, "batalla"
    del yo.mazo[20:]
    assert Heuristico(1).elegir_atacantes(p, 0, [mio])  # castillo holgado: ataca
    del yo.mazo[7:]
    assert Heuristico(1).elegir_atacantes(p, 0, [mio]) == []  # 7 − 6 = 1: no


def test_segundo_killgharrah_no_se_ofrece():
    """"Sólo puedes tener un Kilgharrah en juego" funciona como Errante."""
    k = Carta(id="kg", nombre="Killgharrah", tipo=Tipo.ALIADO, coste=0, fuerza=6, raza="",
              texto="Sólo puedes tener un Kilgharrah en juego. Imbloqueable.", revisada=True)
    p = _partida(Heuristico, Heuristico, [k] * 49, [_aliado()] * 49)
    p.robar(0, 8, inicial=True)
    yo = p.j(0)
    p._mover(yo.mano[0], Zona.DEFENSA)
    p.e.activo, p.e.fase = 0, "vigilia"
    assert not [j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "jugar" and j.carta.carta.id == "kg"]


def test_cambio_de_castillo_cuenta_barajar_y_robar():
    from myl_sim.jugadores import _cambio_de_castillo

    cathach = [{"accion": "barajar", "cuando": "al_jugar", "cantidad": 2,
                "objetivo": {"zona": "cementerio"}}]
    vinculo = [{"accion": "robar", "cuando": "al_jugar", "cantidad": 2, "objetivo": {"quien": "propio"},
                "luego": [{"accion": "descartar", "cantidad": 1, "objetivo": {"quien": "propio"}}]}]
    killgharrah = [{**cathach[0], "luego": [{"accion": "robar", "cantidad": 2, "objetivo": {"quien": "propio"}}]}]
    assert _cambio_de_castillo(cathach) == 2
    assert _cambio_de_castillo(vinculo) == -2
    assert _cambio_de_castillo(killgharrah) == 0
