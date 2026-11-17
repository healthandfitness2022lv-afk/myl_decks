"""Dudas de la IA: una posición grabada se muestra en el tablero y la persona la resuelve."""

from myl_sim import desafio, dudas, posiciones
from myl_sim.autopsia import REVISABLES
from myl_sim.datos import Mazo
from myl_sim.modelo import Carta, Tipo
from myl_sim.precision import jugar_grabada

from test_desafio import _referencia_que_responde


def _mazo(nombre):
    oro = Carta(f"{nombre}-oro", "Oro", Tipo.ORO, 0, 0, "", "", revisada=True)
    aliados = [Carta(f"{nombre}-{i}", f"Aliado {i}", Tipo.ALIADO, 1 + i % 3, 1 + i % 4, "", "", revisada=True)
               for i in range(31)]
    return Mazo(nombre, nombre, "racial", "", [oro] * 18 + aliados, [])


def _duda(lado, metodo="elegir_atacantes"):
    """Una duda armada a mano sobre la primera decisión de ese tipo de `lado`."""
    a, b = _mazo("A"), _mazo("B")
    _, registro, metodos = jugar_grabada(a, b, 5)
    k = next(i for i, e in enumerate(registro) if e["m"] == metodo and e["lado"] == lado and e.get("turno", 0) >= 4)
    assert registro[k]["m"] in REVISABLES
    return {"id": f"prueba_{k}", "tipo": metodo.replace("elegir_", ""), "lado": lado, "paso": k, "seed": 5,
            "semillaIa": 10 + lado, "metodos": metodos, "registro": registro[: k + 1],
            "mazos": [a.to_json(), b.to_json()], "opciones": [], "eligioIa": "?",
            "situacion": {"mazo": "AB"[lado], "rival": "BA"[lado], "turno": registro[k].get("turno")}}


def _preparar(monkeypatch, tmp_path, duda):
    monkeypatch.setattr(dudas, "RESPUESTAS", tmp_path / "respuestas.jsonl")
    monkeypatch.setattr(dudas, "CARPETA", tmp_path)
    monkeypatch.setattr(posiciones, "CARPETA", tmp_path / "posiciones")
    monkeypatch.setattr(posiciones, "DISPUTA", tmp_path / "disputa")
    monkeypatch.setattr(desafio, "_urls_imagenes", lambda ids: {})
    monkeypatch.setattr(dudas, "leer", lambda: [duda])


def test_la_duda_se_juega_como_turno_completo_en_la_mesa(monkeypatch, tmp_path):
    duda = _duda(1, "elegir_jugada")
    _preparar(monkeypatch, tmp_path, duda)
    vistas = []

    class Ref(type(_referencia_que_responde())):
        def update(self, cambios):
            if cambios.get("decision") is not None:
                vistas.append((cambios["estado"], cambios["decision"]))
            super().update(cambios)

    ref = Ref()
    r = dudas.atender_desafio(ref, {"modo": "duda"}, pausa=0.0, confirmar=2)
    estado, decision = vistas[0]
    yo, rival = estado["lados"]
    # Dudaba el lado 1: en la mesa publicada es el de abajo, con su mano a la vista.
    assert yo["nombre"] == "B" and len(yo["mano"]) == yo["manoCantidad"]
    assert rival["nombre"] == "A" and rival["mano"] == []
    assert decision["tipo"] == "jugada" and estado["activo"] == 0
    # Se le pide todo lo que queda del turno (Vigilia y ataque), y nada del siguiente.
    assert len(vistas) >= 2 and "atacantes" in {d["tipo"] for _, d in vistas}
    assert {e["turno"] for e, _ in vistas} == {estado["turno"]}
    assert ref.data["status"] == "terminado" and ref.data["resultadoDuda"]["tuTurno"] == r["tuTurno"] == ["no atacar"]
    # La IA jugó ese mismo turno desde la misma posición.
    assert r["turnoIa"] and isinstance(r["jugadaIa"], str)
    # El turno queda fijado en el banco como el correcto; si la simulación
    # prefiere el de la IA (aquí «no atacar» rinde menos), queda en disputa.
    import json

    carpeta = posiciones.DISPUTA if ref.data["resultadoDuda"].get("enDisputa") else posiciones.CARPETA
    assert (posiciones.cargar_todas() == []) is (carpeta is posiciones.DISPUTA)
    pos = json.loads(next(carpeta.glob("*.json")).read_text(encoding="utf-8"))
    assert pos["tipo"] == "turno" and pos["turnoDebe"] == ["no atacar"] and pos["origen"] == "duda"
    assert posiciones.cumple(pos)[0] is (not pos["pendiente"])
    assert [x["id"] for x in dudas.respuestas()] == [duda["id"]]


def test_el_mismo_turno_se_repite_identico_y_se_valora():
    from myl_sim import turnos
    from myl_sim.datos import Mazo
    from myl_sim.jugadores import Heuristico

    d = _duda(0, "elegir_jugada")
    mazos = [Mazo.from_json(m) for m in d["mazos"]]
    cartas, nombres = tuple(m.cartas for m in mazos), tuple(m.nombre for m in mazos)
    a = turnos.jugar(cartas, nombres, d["seed"], d["registro"], d["paso"], d["metodos"], 0, Heuristico(3))
    b = turnos.jugar(cartas, nombres, d["seed"], d["registro"], d["paso"], d["metodos"], 0, Heuristico(3))
    assert a["decisiones"] == b["decisiones"] and a["registro"] == b["registro"]
    assert len(a["registro"]) > d["paso"]
    v = turnos.valorar(cartas, nombres, d["seed"], a["registro"], d["paso"], d["metodos"], a["metodosTurno"], 0, 4)
    assert v is not None and 0.0 <= v <= 1.0


def test_abandonar_la_duda_no_guarda_nada(monkeypatch, tmp_path):
    duda = _duda(0)
    _preparar(monkeypatch, tmp_path, duda)

    class Ref(type(_referencia_que_responde())):
        def update(self, cambios):
            self.data.update(cambios)
            if cambios.get("decision") is not None:
                self.data["status"] = "abandonado"

    try:
        dudas.atender_desafio(Ref(), {"modo": "duda"}, pausa=0.0)
    except RuntimeError as e:
        assert "abandonado" in str(e)
    else:
        raise AssertionError("debía cortar al abandonar")
    assert dudas.respuestas() == [] and posiciones.cargar_todas() == []
