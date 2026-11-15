"""Arena de motores y ranking Elo."""

import pytest

from myl_sim import arena
from myl_sim.datos import Mazo
from myl_sim.modelo import Carta, Tipo


@pytest.fixture(autouse=True)
def _sin_versiones_reales(tmp_path, monkeypatch):
    monkeypatch.setattr(arena, "VERSIONES", tmp_path / "versiones")


def _c(cid, tipo=Tipo.ALIADO, fuerza=2):
    return Carta(id=cid, nombre=cid, tipo=tipo, coste=1 if tipo != Tipo.ORO else 0, fuerza=fuerza,
                 raza="X", texto="", revisada=True)


def _mazo(mid, fuerza):
    cartas = [_c(f"a{fuerza}", fuerza=fuerza)] * 25 + [_c("oro", Tipo.ORO, 0)] * 24
    return Mazo(id=mid, nombre=mid, formato="racial", raza="X", cartas=cartas, faltantes=[])


def _reg(x, y, puntos_x, n):
    """n pares en que X saca `puntos_x` (0, 0.5 o 1) por par."""
    r = {1: [1.0, 1.0], 0.5: [1.0, 0.0], 0: [0.0, 0.0]}[puntos_x]
    return [{"x": x, "y": y, "a": "A", "b": "B", "seed": k, "r": r, "seg": [0, 0]} for k in range(n)]


def test_par_intercambia_motores_y_es_reproducible():
    a, b = _mazo("A", 2), _mazo("B", 3)
    args = ("heuristico", "aleatorio", a, b, 7)
    r1, r2 = arena.jugar_par(args), arena.jugar_par(args)
    assert r1["r"] == r2["r"] and len(r1["r"]) == 2
    assert r1["x"].startswith("heuristico#") and r1["y"] == "aleatorio"


def test_heuristico_supera_al_aleatorio():
    mazos = [_mazo("A", 2), _mazo("B", 3)]
    res = arena.jugar(["heuristico", "aleatorio"], mazos, 6, procesos=1, guardar=False)
    d = arena.duelo(res, res[0]["x"], "aleatorio")
    assert d["pares"] == 6 and d["puntos"] > 0.5


def test_elo_ordena_y_respeta_el_ancla():
    reg = _reg("fuerte", "medio", 1, 30) + _reg("fuerte", "medio", 0, 10) + _reg("medio", "debil", 1, 30) \
        + _reg("medio", "debil", 0, 10)
    tabla = arena.elo(reg, ancla="medio")
    assert [f["motor"] for f in tabla] == ["fuerte", "medio", "debil"]
    por = {f["motor"]: f for f in tabla}
    assert por["medio"]["elo"] == 1500
    assert 120 < por["fuerte"]["elo"] - 1500 < 260  # 75 % ≈ +191 Elo
    assert por["fuerte"]["margen"] > 0


def test_elo_no_se_va_al_infinito_con_100():
    tabla = arena.elo(_reg("a", "b", 1, 20))
    assert all(abs(f["elo"]) < 5000 for f in tabla)


def test_duelo_descarta_pares_con_error():
    reg = _reg("a", "b", 1, 4) + [{"x": "a", "y": "b", "a": "A", "b": "B", "seed": 9, "r": [1.0, None], "seg": [0, 0]}]
    d = arena.duelo(reg, "b", "a")
    assert d["pares"] == 4 and d["descartados"] == 1 and d["puntos"] == 0.0


def test_version_congelada_juega_con_las_reglas_actuales():
    huella = arena.identidad("heuristico")
    arena.congelar("prueba_arena")
    assert arena.versiones() == ["prueba_arena"]
    # La IA actual es idéntica a la congelada: entra al ranking con su etiqueta.
    assert huella.startswith("heuristico#") and arena.identidad("heuristico") == "heuristico@prueba_arena"
    assert arena._normalizar(huella, arena._etiqueta_de_huella()) == "heuristico@prueba_arena"
    a, b = _mazo("A", 2), _mazo("B", 3)
    r = arena.jugar_par(("heuristico", "aleatorio", a, b, 3))
    assert r["x"] == "heuristico@prueba_arena"
    r = arena.jugar_par(("heuristico", "heuristico@prueba_arena", a, b, 3))
    # La misma IA en los dos lados: cada par reparte los puntos.
    assert "error" not in r and sum(r["r"]) == 1.0
    congelado = arena.crear("busqueda_vigilia@prueba_arena", 1)
    assert type(congelado).__module__ == "myl_ia_prueba_arena.busqueda_vigilia"


def test_desviaciones_de_la_busqueda_se_agrupan():
    a, b = _mazo("A", 2), _mazo("B", 3)
    r = arena.jugar_par(("busqueda_vigilia", "heuristico", a, b, 5))
    assert "error" not in r
    fila = r["precision"][0]
    assert fila["mazo"] == "A" and set(fila["revisadas"]) == set(fila["distintas"])
    assert all(fila["distintas"][t] <= fila["revisadas"][t] for t in fila["revisadas"])
    assert "| **total** |" in arena.precision_md(r["precision"])
    filas = [{"tipo": "vigilia", "mi_mazo": "A", "antes": "x", "ahora": "plan pasar", "est_antes": 0.4,
              "est_ahora": 0.6}] * 3
    assert "| 3 | A | vigilia | x | plan pasar | +20 pts |" in arena.desviaciones_md(filas)
