import json
import pytest

from myl_sim.datos import Mazo
from myl_sim.entrenamiento import generar_episodios
from myl_sim.aprendizaje import PoliticaAprendida, entrenar, evaluar
from myl_sim.motor import Partida
from myl_sim.jugadores import Heuristico
from myl_sim.exploracion import aprender as aprender_alternativas
from myl_sim.exploracion import evaluar as evaluar_alternativas
from myl_sim.exploracion import recolectar as recolectar_alternativas
from myl_sim.exploracion import PoliticaAlternativas
from myl_sim.politica_meta import crear_registro, jugador_para
from myl_sim.desafio import politica_ia_para

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


def test_modelo_aprendido_se_guarda_y_compite_solo_con_jugadas_legales(tmp_path):
    ma = Mazo("a", "A", "", "", mazo_basico(), [])
    mb = Mazo("b", "B", "", "", mazo_basico(), [])
    episodios = tmp_path / "episodios.jsonl"
    generar_episodios(ma, mb, 10, seed=7, salida=episodios)
    destino = tmp_path / "modelo.json"
    modelo = entrenar(episodios, destino, epocas=2)
    assert destino.exists()
    assert (tmp_path / modelo["informeJugadas"]).exists()
    assert modelo["pesos"]
    assert len(modelo["historia"]) == 2
    assert modelo["historia"][0]["validacion"] > 0
    assert modelo["origen"]["mazoA"]["huella"]

    politica = PoliticaAprendida(json.loads(destino.read_text(encoding="utf-8")), 3)
    p = Partida((ma.cartas, mb.cartas), (politica, Heuristico(4)), seed=15)
    legales = p.jugadas_legales(0, "vigilia")
    assert politica.elegir_jugada(p, 0, legales) in legales
    resultado = evaluar(modelo, ma, mb, pares=2, seed=500)
    assert resultado["modelo"]["partidas"] == 4
    assert resultado["control"]["partidas"] == 4
    assert not resultado["aptoParaDesafio"]


def test_exploracion_compara_semillas_y_exige_huella_del_mazo(tmp_path):
    ma = Mazo("a", "A", "", "", mazo_basico(), [])
    mb = Mazo("b", "B", "", "", mazo_basico(), [])
    episodios = tmp_path / "alternativas.jsonl"
    r = recolectar_alternativas(ma, mb, episodios, pares=3, seed=1000,
                               epsilon=1.0)
    assert r["pares"] == 3 and episodios.exists()
    modelo = aprender_alternativas(episodios, tmp_path / "modelo.json")
    assert (tmp_path / modelo["informeJugadas"]).exists()
    assert modelo["origen"]["mazoA"]["huella"]
    decisiones = []
    informe = evaluar_alternativas(modelo, ma, mb, pares=2, seed=2000,
                                   decisiones=decisiones.append)
    assert informe["partidasValidas"] == 4
    assert len(decisiones) == informe["partidasValidas"]
    assert all(set(e["vista"]["rival"]["mano"]) == {"cantidad"}
               for partida in decisiones for e in partida["eventos"])
    assert not informe["aptoParaDesafio"]
    modificado = Mazo("a", "A", "", "", ma.cartas[:-1], [])
    with pytest.raises(ValueError, match="Cambió el mazo"):
        evaluar_alternativas(modelo, modificado, mb, pares=2, seed=2000)
    otro_rival = Mazo("c", "Otro rival", "", "", mb.cartas[:-1], [])
    fuera = evaluar_alternativas(modelo, ma, otro_rival, pares=1, seed=3000)
    assert fuera["rival"]["nombre"] == "Otro rival"
    assert not fuera["rival"]["usadoEnEntrenamiento"]

    informe = {
        "rival": {"huella": modelo["origen"]["mazoB"]["huella"],
                  "copiasSinProgramar": 0},
        "mazoAprendido": {"huella": modelo["origen"]["mazoA"]["huella"]},
        "partidasValidas": 400, "anomalas": 0,
        "ic95DiferenciaBootstrap": [0.01, 0.04],
        "factor": 20, "minimo": 0.04, "diferencia": 0.02,
        "seed": 1000, "pares": 200,
    }
    archivo_informe = tmp_path / "informe.json"
    archivo_informe.write_text(json.dumps(informe), encoding="utf-8")
    uno = crear_registro([(tmp_path / "modelo.json", archivo_informe)],
                         tmp_path / "registro_uno.json")
    assert not uno["entradas"]
    otro_informe = tmp_path / "informe_dos.json"
    otro_informe.write_text(json.dumps({**informe, "seed": 2000}), encoding="utf-8")
    registro = crear_registro([(tmp_path / "modelo.json", archivo_informe),
                               (tmp_path / "modelo.json", otro_informe)],
                              tmp_path / "registro.json")
    assert len(registro["entradas"]) == 1
    assert isinstance(jugador_para(registro, tmp_path, ma, mb, 1), PoliticaAlternativas)
    assert isinstance(jugador_para(registro, tmp_path, ma, otro_rival, 1), Heuristico)
    assert isinstance(politica_ia_para(mb, ma, 1, tmp_path / "registro.json"),
                      PoliticaAlternativas)
    assert isinstance(politica_ia_para(otro_rival, ma, 1, tmp_path / "registro.json"),
                      Heuristico)
