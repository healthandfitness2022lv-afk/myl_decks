"""Aprender de la persona en el Desafío IA: sus decisiones grabadas se
comparan con lo que haría la heurística en la misma posición."""

from myl_sim import aprendizaje_humano as ah
from myl_sim.autopsia import Grabadora, metodos_de
from myl_sim.jugadores import Heuristico
from myl_sim.motor import FinPartida, Partida

from test_posiciones import _mazo


class _AtacaConTodo(Heuristico):
    """La "persona": ataca siempre con todo (distinto de la heurística)."""

    def elegir_atacantes(self, p, yo, candidatos):
        return list(candidatos)


def _jugar(seed):
    a, b = _mazo("A"), _mazo("B")
    registro, ref = [], [None]
    base = (_AtacaConTodo(seed * 2), Heuristico(seed * 2 + 1))
    metodos = [metodos_de(j) for j in base]
    p = Partida((a.cartas, b.cartas), (Grabadora(base[0], 0, registro, ref, revisable=True),
                                       Grabadora(base[1], 1, registro, ref)),
                nombres=(a.nombre, b.nombre), inicial=None, seed=seed)
    ref[0] = p
    try:
        r = p.jugar()
        ganador, turnos = r.ganador, r.turnos
    except FinPartida:
        ganador, turnos = p.e.ganador, p.e.turno
    return (a.cartas, b.cartas), (a.nombre, b.nombre), registro, metodos, ganador, turnos


def test_la_grabacion_reproduce_la_misma_partida():
    cartas, nombres, registro, metodos, ganador, turnos = _jugar(3)
    assert ah.verificar_reproduccion(cartas, nombres, 3, registro, metodos, ganador, turnos)[0]
    # Una grabación alterada se detecta y no se saca ninguna conclusión.
    malo = [dict(e) for e in registro]
    k = next(k for k, e in enumerate(malo) if e["lado"] == 0 and e["m"] == "elegir_atacantes" and e["v"])
    malo[k]["v"] = []
    inf = ah.informe(cartas, nombres, 3, malo, metodos, ganador, turnos, maximo=1, muestras=2)
    assert not inf["reproduccionOk"] and inf["diferencias"] == []


def test_detecta_donde_la_ia_jugaria_distinto_y_lo_simula():
    for seed in range(1, 15):
        cartas, nombres, registro, metodos, ganador, turnos = _jugar(seed)
        inf = ah.informe(cartas, nombres, seed, registro, metodos, ganador, turnos, maximo=2, muestras=3,
                         confirmaciones={})
        assert inf["reproduccionOk"], inf["resumen"]
        if inf["diferencias"]:
            break
    x = inf["diferencias"][0]
    assert x["tipo"] == "atacantes" and x["humano"] != x["ia"] and x["humano"].startswith("atacar con")
    assert 0 <= x["ganaHumano"] <= 1 and x["mejor"] in ("humano", "ia", "parejo")
    # Lo que la persona confirma ✓ queda como lección aunque la simulación sea pareja.
    x["confirmacion"], x["mejor"] = "si", "parejo"
    assert ah.lecciones(inf)[0] is x


def test_reporte_en_vivo_reproduce_el_momento_exacto():
    from myl_sim.reportes_desafio import mesa, posicion

    a, b = _mazo("A"), _mazo("B")
    cartas, nombres, registro, metodos, ganador, turnos = _jugar(5)
    k = next(k for k, e in enumerate(registro) if e["lado"] == 0 and e.get("turno", 0) >= 4)
    g = {"seed": 5, "registro": registro, "metodos": metodos, "mazos": [a.to_json(), b.to_json()]}
    p = posicion(g, k)  # la app reportó justo antes de la decisión k
    assert (p.e.turno, p.e.fase) == (registro[k]["turno"], registro[k]["fase"])
    assert p.cursor == k and "castillo" in mesa(p)


def test_con_el_final_decidido_compara_a_dos_turnos():
    """T11 del desafío PzofIK: las dos opciones daban 0% (la IA juega por la
    persona desde ahí) y la persona ganó; se compara cómo queda la partida."""
    for seed in range(1, 15):
        cartas, nombres, registro, metodos, ganador, turnos = _jugar(seed)
        k = next((k for k, e in enumerate(registro) if e["lado"] == 0 and e["m"] == "elegir_atacantes"
                  and e.get("turno", 0) >= 3), None)
        if k is not None:
            break
    hz = ah.comparar_a_horizonte(cartas, nombres, seed, registro, k, metodos, muestras=2)
    assert hz is not None and 0 <= hz["estimaHumano"] <= 1 and 0 <= hz["estimaIa"] <= 1
    x = {"turno": 5, "fase": "batalla", "humano": "atacar con A", "ia": "no atacar", "ganaHumano": 0.0,
         "ganaIa": 0.0, **hz, "mejor": "humano"}
    assert "a 2 turnos" in ah.explicar(x) and "tu jugada fue mejor" in ah.explicar(x)
