"""La IA buena también simula bloqueos, descartes de fin de turno y, con
`buscar_turno`, cada jugada del turno (no solo cuántas cartas bajar)."""

from myl_sim.busqueda_vigilia import BuscadorVigilia, continuar_descarte
from myl_sim.busqueda_ataques import _copia
from myl_sim.jugadores import Heuristico
from myl_sim.motor import MANO_MAXIMA, Partida

from test_posiciones import _mazo


def _jugar(buscador, seed=4):
    a, b = _mazo("A"), _mazo("B")
    p = Partida((a.cartas, b.cartas), (buscador, Heuristico(seed * 2 + 1)), nombres=("A", "B"), inicial=0, seed=seed)
    return p.jugar()


def test_la_ia_buena_simula_los_bloqueos_y_termina_la_partida():
    ia = BuscadorVigilia(8, muestras=2, max_muestras=10, horizonte=2)
    ia.registro = []
    r = _jugar(ia)
    assert r.ganador in (0, 1, -1)
    assert ia.busquedas_bloqueo > 0
    # Toda desviación anotada trae cuántos pares nuevos la confirmaron.
    assert all(d["muestras"] >= 8 for d in ia.registro if "muestras" in d)


def test_turno_completo_revisa_cada_jugada_de_la_vigilia():
    ia = BuscadorVigilia(8, muestras=2, max_muestras=10, horizonte=2)
    ia.buscar_turno = True
    r = _jugar(ia)
    assert r.ganador in (0, 1, -1)
    assert ia.busquedas_turno > 0 and ia.busquedas_vigilia == 0  # reemplaza a los 4 planes


def test_apagados_no_buscan():
    ia = BuscadorVigilia(8, muestras=2, max_muestras=10, horizonte=2)
    ia.buscar_bloqueos = ia.buscar_descartes = False
    _jugar(ia)
    assert ia.busquedas_bloqueo == 0 and ia.busquedas_descarte == 0


def test_descarte_de_fin_de_turno_se_simula():
    a, b = _mazo("A"), _mazo("B")
    ia = BuscadorVigilia(3, muestras=2, max_muestras=10, horizonte=1)
    p = Partida((a.cartas, b.cartas), (ia, Heuristico(2)), nombres=("A", "B"), inicial=0, seed=3)
    for i in (0, 1):
        p._mano_inicial(i)
    p.e.turno, p.e.activo, p.e.fase = 1, 0, "final"
    p.robar(0, MANO_MAXIMA + 1 - len(p.j(0).mano))
    mano = list(p.j(0).mano)
    assert len(mano) == MANO_MAXIMA + 1
    elegidas = ia.elegir_descartes(p, 0, mano, 1)
    assert len(elegidas) == 1 and elegidas[0] in mano
    assert ia.busquedas_descarte == 1
    # La continuación descarta esa carta y deja la mano en el máximo.
    c = _copia(p, 0, 5)
    continuar_descarte(c, 0, (elegidas[0].uid,), 0, 5)
    assert len(c.j(0).mano) == MANO_MAXIMA and elegidas[0].uid not in {x.uid for x in c.j(0).mano}
    # Fuera del cierre del turno propio decide la regla, sin simular.
    p.e.fase = "vigilia"
    ia.elegir_descartes(p, 0, mano, 1)
    assert ia.busquedas_descarte == 1
