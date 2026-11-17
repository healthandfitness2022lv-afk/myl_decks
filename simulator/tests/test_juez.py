"""El juez de decisiones: no ve la mano del rival y no confunde ruido con ventaja."""

import random

from myl_sim import precision
from myl_sim.autopsia import remuestrear_ocultas, reproducir
from myl_sim.busqueda_ataques import comparar_opciones
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona
from myl_sim.motor import Partida

from test_posiciones import _mazo


def _partida(seed=3):
    a, b = _mazo("A"), _mazo("B")
    p = Partida((a.cartas, b.cartas), (Heuristico(1), Heuristico(2)), nombres=("A", "B"), inicial=0, seed=seed)
    for i in (0, 1):
        p._mano_inicial(i)
    return p


def test_remuestrear_cambia_la_mano_oculta_y_conserva_tamanos():
    p = _partida()
    rival = p.j(1)
    antes_mano, antes_mazo = [x.uid for x in rival.mano], [x.uid for x in rival.mazo]
    revelada = rival.mano[0]
    revelada.revelada = True
    remuestrear_ocultas(p, 1, random.Random(5))
    assert len(rival.mano) == len(antes_mano) and len(rival.mazo) == len(antes_mazo)
    assert revelada in rival.mano  # lo que ya se vio no se cambia
    assert [x.uid for x in rival.mano] != antes_mano  # la mano oculta es otra
    assert sorted(x.uid for x in rival.mano + rival.mazo) == sorted(antes_mano + antes_mazo)
    assert all(x.zona == Zona.MANO for x in rival.mano) and all(x.zona == Zona.MAZO for x in rival.mazo)


def test_remuestrear_no_toca_la_mano_si_la_decision_la_nombra():
    p = _partida()
    rival = p.j(1)
    antes = [x.uid for x in rival.mano]
    remuestrear_ocultas(p, 1, random.Random(5), usadas=([rival.mano[2]],))
    assert [x.uid for x in rival.mano] == antes


def test_el_juez_reparte_otra_mano_al_rival_en_cada_muestra():
    a, b = _mazo("A"), _mazo("B")
    _, registro, metodos = precision.jugar_grabada(a, b, 11)
    k = next(i for i, e in enumerate(registro) if e["m"] == "elegir_atacantes" and e["lado"] == 0)
    manos = {True: set(), False: set()}
    for ocultar in (True, False):
        for m in range(4):
            def opcion(p, metodo, args, _o=ocultar):
                manos[_o].add(tuple(sorted(x.uid for x in p.j(1).mano)))
                raise StopIteration  # solo interesa la mesa al ramificar

            try:
                reproducir((a.cartas, b.cartas), ("A", "B"), 11, registro, rama=k, opcion=opcion, muestra=m,
                           metodos=metodos, ocultar=ocultar)
            except (StopIteration, RuntimeError):
                pass
    assert len(manos[False]) == 1  # antes: siempre la mano real del rival
    assert len(manos[True]) > 1    # ahora: una mano posible distinta por muestra


def test_comparar_no_se_aparta_por_ruido():
    # 8 opciones idénticas (puro ruido): elegir la mejor de 8 con 4 muestras
    # casi siempre "encuentra" una ventaja; la confirmación con muestras nuevas no.
    desvios = 0
    for semilla in range(200):
        ruido = random.Random(semilla * 7 + 1)
        elegido, _, _ = comparar_opciones(lambda i, seed: ruido.random(), 8, random.Random(semilla),
                                          muestras=4, max_muestras=16, margen=0.04, z=2.0)
        desvios += elegido != 0
    assert desvios <= 20, f"{desvios} de 200 desviaciones sin ventaja real"


def test_comparar_encuentra_una_ventaja_real():
    aciertos = 0
    for semilla in range(50):
        ruido = random.Random(semilla * 13 + 5)
        elegido, valores, conf = comparar_opciones(
            lambda i, seed: (0.75 if i == 3 else 0.45) + ruido.uniform(-0.15, 0.15), 6, random.Random(semilla),
            muestras=4, max_muestras=16, margen=0.04, z=2.0)
        aciertos += elegido == 3
        if elegido == 3:
            assert conf["muestras"] >= 8 and len(valores[3]) == len(valores[0])
    assert aciertos >= 45


def test_comparar_respeta_la_base_y_el_limite_de_tiempo():
    import time

    # Sin tiempo para confirmar se queda con la base aunque otra pinte mejor.
    elegido, _, conf = comparar_opciones(lambda i, seed: float(i), 3, random.Random(1), muestras=4,
                                         max_muestras=16, margen=0.04, z=2.0, base=1,
                                         limite=time.monotonic() - 1)
    assert elegido == 1 and conf["muestras"] == 0


def test_revisar_mide_la_perdida_con_muestras_que_no_eligieron():
    a, b = _mazo("A"), _mazo("B")
    _, registro, metodos = precision.jugar_grabada(a, b, 11)
    tareas = precision.tareas_de((a.cartas, b.cartas), ("A", "B"), 11, registro, metodos,
                                 muestras=2, max_muestras=4, turnos=2, max_decisiones=6)
    revisiones = [r for r in map(precision.revisar, tareas) if r is not None]
    assert revisiones
    for r in revisiones:
        assert r["clase"] in ("exacta", "imprecision", "error", "grave")
        assert r["muestras"] == 4 and r["opciones"] >= 2
        if r["clase"] != "exacta":
            assert r["perdida"] >= precision.IMPRECISION and r["mejor"] != r["elegida"]
    nota = precision._nota(revisiones)
    assert nota["decisiones"] == len(revisiones) and nota["ic95"][0] <= nota["perdidaMedia"] <= nota["ic95"][1]
