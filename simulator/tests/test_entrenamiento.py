import json

from myl_sim.datos import Mazo
from myl_sim.entrenamiento import generar_episodios

from test_motor import mazo_basico


def test_recolecta_decisiones_con_vista_legal(tmp_path):
    ma = Mazo("a", "A", "", "", mazo_basico(), [])
    mb = Mazo("b", "B", "", "", mazo_basico(), [])
    archivo = tmp_path / "episodios.jsonl"

    r = generar_episodios(ma, mb, 2, seed=7, salida=archivo)

    filas = [json.loads(x) for x in archivo.read_text(encoding="utf-8").splitlines()]
    assert r.partidas == 2 and r.decisiones == len(filas) - 1
    assert filas[0]["tipo"] == "metadata"
    decision = next(x for x in filas if x["tipo"] == "decision")
    assert set(decision["vista"]["rival"]["mano"]) == {"cantidad"}
    assert "mazo" not in decision["vista"]["rival"]
    assert decision["legales"] and decision["elegida"] in decision["legales"]
    assert decision["recompensa"] in (0.0, 0.5, 1.0)
