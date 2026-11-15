"""Matriz del meta v2 y optimizador."""

from collections import Counter
import random

from myl_sim import meta, optimizador
from myl_sim.datos import Mazo
from myl_sim.modelo import Carta, Tipo


def _c(cid, tipo=Tipo.ALIADO, fuerza=2):
    return Carta(id=cid, nombre=cid, tipo=tipo, coste=1 if tipo != Tipo.ORO else 0, fuerza=fuerza,
                 raza="X", texto="", revisada=True)


def _mazo(mid, fuerza):
    cartas = [_c(f"a{fuerza}", fuerza=fuerza)] * 25 + [_c("oro", Tipo.ORO, 0)] * 24
    return Mazo(id=mid, nombre=mid, formato="racial", raza="X", cartas=cartas, faltantes=[])


def test_matriz_usa_cache_y_extiende(tmp_path, monkeypatch):
    monkeypatch.setattr(meta, "CRUCES", tmp_path)
    mazos = [_mazo("A", 2), _mazo("B", 3), _mazo("C", 4)]
    r1 = meta.matriz(mazos, 4, procesos=1)
    assert len(r1) == 3 and all(len(v) == 4 for v in r1.values())
    assert meta.matriz(mazos, 4, procesos=1) == r1  # nada que jugar
    r3 = meta.matriz(mazos, 6, procesos=1)
    assert all(v[:4] == r1[k] for k, v in r3.items())  # conserva lo jugado y solo agrega


def test_score_meta_pondera_y_cuenta_espejo():
    fila = [None, {"winrate": 1.0, "partidas": 100}, {"winrate": 0.0, "partidas": 100}]
    assert abs(meta.score_meta(fila, [1, 1, 1], 0)["score"] - 0.5) < 1e-9
    assert abs(meta.score_meta(fila, [0, 3, 1], 0)["score"] - 0.75) < 1e-9


def test_mutaciones_respetan_tipo_y_copias():
    base = _mazo("A", 2)
    otro = Mazo(id="B", nombre="B", formato="racial", raza="X", faltantes=[],
                cartas=[_c("nuevo", fuerza=5)] * 2 + [_c("oro2", Tipo.ORO, 0)] * 3 + base.cartas[:44])
    pool, maximo = optimizador.pool_de(base, [base, otro])
    assert maximo["nuevo"] == 2 and maximo["oro2"] == 3
    muts = optimizador.mutaciones(base.cartas, pool, maximo, random.Random(1), 50)
    assert set(muts) == {("a2", "nuevo"), ("oro", "oro2")}
    v = optimizador.aplicar(base.cartas, "a2", "nuevo", pool)
    assert len(v) == 49 and Counter(c.id for c in v)["nuevo"] == 1


def test_meta_evolutivo_y_equilibrio():
    # Piedra, papel y tijera + un mazo malo: el malo desaparece y el equilibrio reparte.
    w = [[.5, 1, 0, 1], [0, .5, 1, 1], [1, 0, .5, 1], [0, 0, 0, .5]]
    x = meta.pesos_evolutivos(w, pasos=20, piso=0)
    assert x[3] < 0.01 and abs(sum(x) - 1) < 1e-9
    eq = meta.equilibrio(w)
    assert eq[3] < 0.01 and all(abs(v - 1 / 3) < 0.05 for v in eq[:3])


def test_pool_del_side_deck_con_ban_list():
    base = _mazo("A", 2)
    base.side = [_c("side1", fuerza=4)] * 2 + [_c("side2", fuerza=5)]
    pool, maximo = optimizador.pool_de(base, [], ban={"side2": 1}, solo_side=True)
    assert set(pool) == {"a2", "oro", "side1", "side2"}
    assert maximo["side1"] == 3 and maximo["side2"] == 1
    muts = optimizador.mutaciones(base.cartas, pool, maximo, random.Random(1), 50)
    assert set(muts) == {("a2", "side1"), ("a2", "side2")}


def test_mazo_guarda_el_side_en_json():
    base = _mazo("A", 2)
    base.side = [_c("side1")]
    assert [c.id for c in Mazo.from_json(base.to_json()).side] == ["side1"]


def test_pendientes_ordena_por_mazos_que_destraba():
    a, b = _mazo("A", 2), _mazo("B", 3)
    x = Carta(id="x", nombre="Pendiente", tipo=Tipo.ALIADO, coste=1, fuerza=1, raza="X", texto="Habilidad",
              revisada=False)
    a.cartas = a.cartas[:48] + [x]
    md = meta.pendientes_md([a, b], "racial")
    assert "| Pendiente | X | 1 | 1 | 1 |" in md and "1 listos para simular" in md


def test_side_mas_raza_prioriza_el_side():
    base = _mazo("A", 2)
    base.side = [_c("side1", fuerza=4)]
    otro = Mazo(id="B", nombre="B", formato="racial", raza="X", faltantes=[],
                cartas=[_c(f"r{k}", fuerza=3) for k in range(10)] + base.cartas[:39])
    pool, maximo = optimizador.pool_de(base, [base, otro])
    assert "side1" in pool and "r0" in pool
    muts = optimizador.mutaciones(base.cartas, pool, maximo, random.Random(1), 3, {"side1"})
    assert muts[0] == ("a2", "side1")


def test_trabajos_comandos_y_evaluador(tmp_path):
    import pytest

    from myl_sim import trabajos
    from myl_sim.evaluador import cargar_carta, evaluar, informe_md as md_eval
    from myl_sim.meta import raciales_del_cache

    s = tmp_path / "x"
    assert trabajos.comando("meta_matriz", {"n": 999}, s)[1:5] == ["myl_sim.meta", "matriz", "--app", "--formato"]
    assert "200" in trabajos.comando("meta_matriz", {"n": 999}, s)
    c = trabajos.comando("optimizar", {"deckBase": "abc", "soloSide": True, "fuente": "cache"}, s)
    assert c[1:3] == ["myl_sim.optimizador", "abc"] and "--solo-side" in c and "--cache" in c
    with pytest.raises(ValueError):
        trabajos.comando("otro", {}, s)

    carta = cargar_carta("dominios_de_ra_oseye")
    todos = raciales_del_cache()
    mazos = [m for m in todos if m.raza == carta.raza][:1]
    r = evaluar(carta, mazos, todos[:3], n0=1, n_conf=1, procesos=1, log=lambda *a: None)
    assert len(r["mazos"]) == 1 and "veredicto" in r
    assert "Evaluación de carta" in md_eval(r)
    res = trabajos.resumen("evaluar_carta", r)
    assert res["carta"] == "Oseye" and res["mazos"][0]["mazo"] == mazos[0].nombre
