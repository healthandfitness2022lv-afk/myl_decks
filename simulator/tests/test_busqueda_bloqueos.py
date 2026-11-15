import copy
import random

from myl_sim.busqueda_bloqueos import (
    BuscadorBloqueos, _copia_muestreada, _continuar, _opciones,
)
from myl_sim.modelo import Zona
from myl_sim.datos import Mazo
from myl_sim.desafio import SesionDesafio
from myl_sim.jugadores import Heuristico
from test_motor import AtacaTodo, aliado, en_defensa, mazo_basico, partida


def test_muestreo_oculta_mano_y_orden_pero_conserva_cartas_reveladas():
    p = partida(log=True)
    p._mover(p.j(0).mazo[0], Zona.MANO)
    p._mover(p.j(0).mazo[0], Zona.MANO)
    p.j(0).mano[0].revelada = True
    revelada = p.j(0).mano[0].uid
    rng_original = p.e.rng.getstate()
    segunda = copy.deepcopy(p)
    mano_oculta = segunda.j(0).mano[1]
    mazo_oculto = segunda.j(0).mazo[0]
    segunda.j(0).mano[1] = mazo_oculto
    segunda.j(0).mazo[0] = mano_oculta
    mano_oculta.zona, mazo_oculto.zona = Zona.MAZO, Zona.MANO

    a = _copia_muestreada(p, 1, 42)
    b = _copia_muestreada(segunda, 1, 42)
    assert revelada in [x.uid for x in a.j(0).mano]
    assert [x.uid for x in a.j(0).mano] == [x.uid for x in b.j(0).mano]
    assert [x.uid for x in a.j(0).mazo] == [x.uid for x in b.j(0).mazo]
    assert p.e.rng.getstate() == rng_original
    assert len(p.j(0).mano) == 2 and p.e.log == []


def test_enumera_asignaciones_legales_y_no_bloquear():
    p = partida()
    imbloqueable = aliado("Imbloqueable", 1, 2, [{"accion": "imbloqueable", "cuando": "continua"}])
    a1 = en_defensa(p, 0, aliado("Atacante", 1, 2))
    a2 = en_defensa(p, 0, imbloqueable)
    b1 = en_defensa(p, 1, aliado("Bloqueador 1", 1, 2))
    b2 = en_defensa(p, 1, aliado("Bloqueador 2", 1, 3))
    opciones, limitada = _opciones(p, [a1, a2], [b1, b2], (), random.Random(1), 8)
    assert not limitada
    assert set(opciones) == {(), ((a1.uid, b1.uid),), ((a1.uid, b2.uid),)}
    a3 = en_defensa(p, 0, aliado("Otro atacante", 1, 2))
    opciones, limitada = _opciones(p, [a1, a3], [b1, b2], (), random.Random(1), 8)
    assert not limitada and len(opciones) == 7
    assert all(len({b for _, b in opcion}) == len(opcion) for opcion in opciones)


def test_eleccion_no_depende_de_la_mano_oculta_real():
    buscador = BuscadorBloqueos(33, muestras=2, max_candidatos=4, max_segundos=None)
    p = partida(jugadores=(AtacaTodo(1), buscador))
    en_defensa(p, 0, aliado("Atacante", 1, 3))
    en_defensa(p, 1, aliado("Bloqueador", 1, 3))
    p._mover(p.j(0).mazo[0], Zona.MANO)
    p.e.turno = 1
    p.turnos_propios[0] = 1
    segunda = copy.deepcopy(p)
    oculta, mazo = segunda.j(0).mano[0], segunda.j(0).mazo[0]
    segunda.j(0).mano[0], segunda.j(0).mazo[0] = mazo, oculta
    oculta.zona, mazo.zona = Zona.MAZO, Zona.MANO

    p._batalla(0)
    segunda._batalla(0)

    analisis_a = {k: v for k, v in buscador.ultimo_analisis.items() if k != "segundos"}
    analisis_b = {k: v for k, v in segunda.jugadores[1].ultimo_analisis.items() if k != "segundos"}
    assert analisis_a == analisis_b


def test_busqueda_bloquea_si_evitar_dano_gana_la_partida():
    buscador = BuscadorBloqueos(7, muestras=2, max_candidatos=4, max_segundos=None)
    p = partida(jugadores=(AtacaTodo(1), buscador))
    atacante = en_defensa(p, 0, aliado("Atacante", 1, 3))
    bloqueador = en_defensa(p, 1, aliado("Bloqueador", 1, 3))
    p.j(0).mazo = p.j(0).mazo[:1]
    p.j(1).mazo = p.j(1).mazo[:3]
    p.e.turno = 1
    p.turnos_propios[0] = 1

    p._batalla(0)

    assert atacante.zona == Zona.CEMENTERIO
    assert bloqueador.zona == Zona.CEMENTERIO
    opciones = buscador.ultimo_analisis["opciones"]
    assert next(x for x in opciones if not x["bloqueos"])["estimacionVictoria"] == 0
    assert next(x for x in opciones if x["bloqueos"])["estimacionVictoria"] == 1


def test_validacion_independiente_compara_sin_cambiar_la_busqueda(monkeypatch):
    monkeypatch.setattr(Heuristico, "elegir_bloqueos", lambda self, p, yo, a, b: {})
    buscador = BuscadorBloqueos(7, muestras=2, max_candidatos=4,
                                max_segundos=None, muestras_validacion=3,
                                guardar_decisiones=True)
    p = partida(jugadores=(AtacaTodo(1), buscador))
    en_defensa(p, 0, aliado("Atacante", 1, 3))
    en_defensa(p, 1, aliado("Bloqueador", 1, 3))
    p.j(0).mazo = p.j(0).mazo[:1]
    p.j(1).mazo = p.j(1).mazo[:3]
    p.e.turno = 1
    p.turnos_propios[0] = 1
    control = copy.deepcopy(p)
    control.jugadores[1].muestras_validacion = 0

    p._batalla(0)
    control._batalla(0)

    validacion = buscador.ultimo_analisis["validacionIndependiente"]
    assert validacion["muestras"] == 3 and validacion["diferencia"] == 1
    assert buscador.rng_busqueda.getstate() == control.jugadores[1].rng_busqueda.getstate()
    assert len(buscador.historial[0]["semillasValidacion"]) == 3
    assert validacion["resultados"][0]["semilla"] == buscador.historial[0]["semillasValidacion"][0]
    assert len(buscador.historial[0]["resultadosBusqueda"]) == 2


def test_continuacion_mantiene_bloqueos_obligatorios_en_la_copia():
    p = partida()
    a1 = en_defensa(p, 0, aliado("Forzado", 1, 2))
    a2 = en_defensa(p, 0, aliado("Libre", 1, 2))
    b1 = en_defensa(p, 1, aliado("Bloqueador forzado", 1, 2))
    b2 = en_defensa(p, 1, aliado("Bloqueador libre", 1, 2))
    p._mover(a1, Zona.ATAQUE)
    p._mover(a2, Zona.ATAQUE)
    p.atacantes = [a1, a2]
    p.bloqueos = {a1.uid: b1}
    p.e.fase = "declaracion_bloqueo"
    p.e.turno = 1
    p.turnos_propios[0] = 1
    p.j(0).mazo = p.j(0).mazo[:1]
    copia = _copia_muestreada(p, 1, 22)

    ganador = _continuar(copia, 1, ((a2.uid, b2.uid),))

    assert ganador == 1
    assert set(copia.bloqueos) == {a1.uid, a2.uid}
    assert {x.uid for x in copia.bloqueos.values()} == {b1.uid, b2.uid}
    assert a1.zona == Zona.ATAQUE and b1.zona == Zona.DEFENSA


def test_desafio_experimental_guarda_las_opciones_evaluadas():
    ma = Mazo("a", "Humano", "", "", mazo_basico(), [])
    mb = Mazo("b", "IA", "", "", mazo_basico(), [])
    sesion = SesionDesafio(None, ma, mb, seed=8, buscar_bloqueos=True)
    p = sesion.partida
    p.jugadores = (AtacaTodo(1), p.jugadores[1])
    en_defensa(p, 0, aliado("Atacante", 1, 3))
    en_defensa(p, 1, aliado("Bloqueador", 1, 3))
    p.j(0).mazo = p.j(0).mazo[:1]
    p.j(1).mazo = p.j(1).mazo[:3]
    p.e.activo = 0
    p.e.turno = 1
    p.turnos_propios[0] = 1

    p._batalla(0)

    evento = next(x for x in sesion.decisiones if x["tipo"] == "bloqueos")
    analisis = evento["analisisBloqueos"]
    assert analisis["muestrasPorOpcion"] == 8
    assert len(analisis["opciones"]) == 2
    assert sum(x["referenciaHeuristica"] for x in analisis["opciones"]) == 1
    assert all(x["muestrasComparables"] == 8 for x in analisis["opciones"])
    assert next(x for x in analisis["opciones"] if x["elegida"])["bloqueos"]
