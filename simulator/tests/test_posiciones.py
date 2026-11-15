"""Posiciones fijadas (tests/posiciones/*.json): cada lección corregida de la
IA queda como test para que ningún cambio posterior la vuelva a romper."""

from dataclasses import replace

import pytest

from myl_sim import mineria, posiciones
from myl_sim.datos import Mazo
from myl_sim.modelo import Carta, Tipo

_TODAS = posiciones.cargar_todas()


@pytest.mark.parametrize("pos", [p for _, p in _TODAS], ids=[f.stem for f, _ in _TODAS])
def test_posicion_fijada(pos):
    try:
        ok, texto = posiciones.cumple(pos)
    except posiciones.PosicionObsoleta:
        pytest.skip("el motor ya no llega a esa decisión con lo grabado")
    if pos.get("pendiente") and not ok:
        pytest.xfail(f"pendiente de corregir: {texto}")
    assert ok, f"{pos['nombre']}: {texto}"


def _mazo(nombre):
    oro = Carta(f"{nombre}-oro", "Oro", Tipo.ORO, 0, 0, "", "", revisada=True)
    aliados = [Carta(f"{nombre}-{i}", f"Aliado {i}", Tipo.ALIADO, 1 + i % 3, 1 + i % 4, "", "", revisada=True)
               for i in range(32)]
    return Mazo(nombre, nombre, "racial", "", [replace(oro)] * 18 + aliados, [])


def test_mineria_encuentra_errores_y_se_fijan_como_posicion(tmp_path, monkeypatch):
    monkeypatch.setattr(posiciones, "CARPETA", tmp_path)
    a, b = _mazo("A"), _mazo("B")
    lecciones = []
    for seed in range(1, 40):
        lecciones += mineria.minar_partida(a, b, seed, revisar=2, muestras=4)
        if lecciones:
            break
    assert lecciones, "en 40 partidas la heurística debería cometer algún error"
    x = lecciones[0]
    assert x["revision"]["error"] and x["categoria"].startswith(x["revision"]["tipo"])
    assert mineria.resumen(lecciones)["patrones"][0]["veces"] >= 1

    x["mazos"] = [a.to_json(), b.to_json()]
    destino = posiciones.fijar(x, debe=None, no_debe=None, nombre="prueba")
    pos = posiciones.cargar_todas()[0][1]
    assert destino.exists() and pos["noDebe"] == x["revision"]["elegida"]
    # La heurística no cambió: hoy repite el error que se encontró.
    hoy, opciones = posiciones.decision_actual(pos)
    assert hoy == x["revision"]["elegida"] and x["revision"]["mejor"] in opciones
    assert not posiciones.cumple(pos)[0] and pos["pendiente"]
