"""Ciclo de una simulación en el worker: pending → running → done | error.

Firestore se reemplaza por uno falso en memoria (no toca la base real).
"""

import dataclasses

import pytest

from myl_sim import worker
from myl_sim.datos import Mazo

from test_motor import mazo_basico


class _Snap:
    def __init__(self, datos):
        self._datos = datos

    def to_dict(self):
        return dict(self._datos)


class _Ref:
    """Documento falso: guarda los datos y cada update en orden."""

    def __init__(self, datos):
        self.datos = dict(datos)
        self.updates = []

    def get(self, transaction=None):
        return _Snap(self.datos)

    def update(self, cambios):
        self.updates.append(dict(cambios))
        self.datos.update(cambios)

    def set(self, datos, **_kwargs):
        self.datos = dict(datos)


class _Tx:
    def update(self, ref, cambios):
        ref.update(cambios)


class _Doc:
    def __init__(self, ref):
        self.reference = ref

    def to_dict(self):
        return dict(self.reference.datos)


class _Db:
    def __init__(self):
        self.estado = _Ref({})

    def transaction(self):
        return _Tx()

    def collection(self, _nombre):
        db = self

        class _Col:
            def document(self, _id):
                return db.estado

        return _Col()


def _revisadas(cartas):
    return [dataclasses.replace(c, revisada=True) for c in cartas]


@pytest.fixture
def entorno(monkeypatch):
    from google.cloud import firestore

    db = _Db()
    monkeypatch.setattr(worker, "db", lambda: db)
    monkeypatch.setattr(firestore, "transactional", lambda f: f)
    mazos = {
        "a": Mazo("a", "Mazo A", "racial", "", _revisadas(mazo_basico()), []),
        "b": Mazo("b", "Mazo B", "racial", "", _revisadas(mazo_basico()), []),
    }
    monkeypatch.setattr(worker, "cargar_mazo", lambda owner, id_: mazos[id_])
    # Los mazos de prueba repiten cartas: sin tope de copias salvo en los tests de Ban List.
    monkeypatch.setattr(worker, "cargar_ban_list", lambda formato: {c.id: 99 for c in mazo_basico()})
    return db


def _pedido(**extra):
    return _Ref({"ownerUid": "u", "deckA": "a", "deckB": "b", "seed": 7, "status": "pending", **extra})


def test_n_partidas_pasa_por_running_y_termina_done(entorno):
    ref = _pedido(n=30)
    worker.procesar(_Doc(ref))
    estados = [u["status"] for u in ref.updates if "status" in u]
    assert estados == ["running", "done"]
    r = ref.datos["resultado"]
    assert r["partidas"] == 30 and len(r["resultados"]) == 30
    assert ref.datos["progreso"] == 1


def test_partida_narrada_termina_done_con_pasos(entorno):
    ref = _pedido(n=1)
    worker.procesar(_Doc(ref))
    assert ref.datos["status"] == "done"
    assert ref.datos["resultado"]["pasos"] and ref.datos["resultado"]["narracion"]


def test_no_toma_una_que_ya_no_esta_pendiente(entorno):
    ref = _pedido(n=30)
    ref.datos["status"] = "running"  # la tomó otro worker
    worker.procesar(_Doc(ref))
    assert ref.updates == []


def test_un_error_queda_marcado_en_la_simulacion(entorno, monkeypatch):
    def falla(owner, id_):
        raise RuntimeError("mazo inexistente")

    monkeypatch.setattr(worker, "cargar_mazo", falla)
    ref = _pedido(n=30)
    worker.procesar(_Doc(ref))
    assert ref.datos["status"] == "error" and "mazo inexistente" in ref.datos["error"]


def test_latido_avisa_que_el_worker_esta_vivo(entorno):
    worker.latido(forzar=True)
    assert "lastSeen" in entorno.estado.datos


def test_no_simula_con_cartas_sin_marcar(entorno, monkeypatch):
    mazos = {
        "a": Mazo("a", "Mazo A", "racial", "", mazo_basico(), []),
        "b": Mazo("b", "Mazo B", "racial", "", _revisadas(mazo_basico()), []),
    }
    monkeypatch.setattr(worker, "cargar_mazo", lambda owner, id_: mazos[id_])
    ref = _pedido(n=1)
    worker.procesar(_Doc(ref))
    assert ref.datos["status"] == "error"
    assert "sin marcar como programadas" in ref.datos["error"] and "Oro" in ref.datos["error"]


def test_no_simula_mazos_fuera_de_reglamento(entorno, monkeypatch):
    cartas = _revisadas(mazo_basico())
    mazos = {
        "a": Mazo("a", "Mazo A", "racial", "", cartas[:-2], []),
        "b": Mazo("b", "Mazo B", "racial", "", cartas, []),
    }
    monkeypatch.setattr(worker, "cargar_mazo", lambda owner, id_: mazos[id_])
    ref = _pedido(n=1)
    worker.procesar(_Doc(ref))
    assert ref.datos["status"] == "error"
    assert "49 cartas y Ban List" in ref.datos["error"] and "Mazo A: tiene 47 cartas" in ref.datos["error"]


def test_no_simula_con_mas_copias_que_la_ban_list(entorno, monkeypatch):
    ban = {c.id: 99 for c in mazo_basico()}
    ban[mazo_basico()[0].id] = 0
    monkeypatch.setattr(worker, "cargar_ban_list", lambda formato: ban)
    ref = _pedido(n=1)
    worker.procesar(_Doc(ref))
    assert ref.datos["status"] == "error" and "(prohibida)" in ref.datos["error"]
