import json
from collections import Counter

from myl_sim.informe_entrenamiento import guardar_informe_bloqueos, guardar_informe_exploracion
from myl_sim.simulacion import intervalo_pareado


def test_informe_de_exploracion_no_atribuye_partidas_con_varias_jugadas(tmp_path):
    origen = tmp_path / "exploracion.jsonl"
    eventos = [{"turno": 3, "base": "a", "alternativa": "b"}]
    filas = [
        {"tipo": "metadata", "esquema": 1, "mazoA": {}, "mazoB": {}},
        {"seed": 11, "control": 0, "explorado": 1, "eventos": eventos},
        {"seed": 12, "control": 1, "explorado": 0, "eventos": eventos * 2},
        {"seed": 13, "control": 1, "explorado": 1, "eventos": []},
    ]
    origen.write_text("\n".join(json.dumps(x) for x in filas) + "\n", encoding="utf-8")

    md, datos = guardar_informe_exploracion(origen)

    informe = json.loads(datos.read_text(encoding="utf-8"))
    assert informe["conUnCambio"] == 1 and informe["conVariosCambios"] == 1
    assert informe["comparaciones"][0]["mejora"] == 1
    assert informe["comparaciones"][0]["empeora"] == 0
    assert "no una prueba" in md.read_text(encoding="utf-8")
    md_segundo, datos_segundo = guardar_informe_exploracion(origen)
    assert md_segundo != md and datos_segundo != datos
    assert md.exists() and datos.exists()


def test_informe_de_bloqueos_guarda_todas_las_opciones_y_muestra_la_comparacion(tmp_path):
    referencia = {"bloqueos": [], "validas": 8, "estimacionVictoria": 0.25,
                  "referenciaHeuristica": True, "elegida": False}
    elegida = {"bloqueos": [{"atacante": "Atacante", "bloqueador": "Defensor"}],
               "validas": 8, "estimacionVictoria": 0.5, "referenciaHeuristica": False,
               "diferenciaConReferencia": 0.25, "muestrasComparables": 8, "elegida": True}
    evento = {"seedPartida": 42, "turno": 5, "resultadoBusqueda": 1, "resultadoControl": 0,
              "vista": {"yo": {"castillo": 10}, "rival": {"castillo": 12}},
              "analisis": {"opciones": [referencia, elegida], "bloqueosObligatorios": []}}
    replica = {**evento, "seedPartida": 43, "analisis": {**evento["analisis"],
        "validacionIndependiente": {"muestras": 8, "estimacionElegida": 0.25,
                                    "estimacionReferencia": 0.5, "diferencia": -0.25}}}
    informe = {"mazo": "Djoser", "rival": "Sacerdote", "partidasValidas": 1}

    detalle, resumen = guardar_informe_bloqueos(informe, iter([evento, replica]), tmp_path / "resultado.json")

    filas = [json.loads(linea) for linea in detalle.read_text(encoding="utf-8").splitlines()]
    assert filas[1]["analisis"]["opciones"] == [referencia, elegida]
    texto = resumen.read_text(encoding="utf-8")
    assert "Defensor bloquea a Atacante" in texto and "+25.0 puntos" in texto
    assert "validación independiente" in texto and "-25.0 puntos" in texto
    assert "no se atribuye por sí solo" in texto


def test_intervalo_pareado_escala_sin_expandir_millones_de_resultados():
    intervalo, metodo = intervalo_pareado(Counter({0.0: 999000, 1.0: 1000}), seed=7)
    assert metodo == "normal_pareado"
    assert intervalo[0] < 0.001 < intervalo[1]
    assert intervalo_pareado(Counter(), seed=7) == (None, "sin_datos")
