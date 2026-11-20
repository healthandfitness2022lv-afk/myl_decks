"""Buzón local de reportes: el worker exporta, el agente horario lee sin red."""

from datetime import datetime, timezone

from myl_sim import buzon_reportes as b


class _Snap:
    def __init__(self, id, data):
        self.id, self._d = id, data

    def to_dict(self):
        return self._d


class _Ref:
    def __init__(self, data, grab=None):
        self._d, self._g = data, grab

    def get(self):
        return _Snap("x", self._d)

    def collection(self, _):
        return self

    def document(self, _):
        return _Ref(self._g or {})


class _Col:
    def __init__(self, docs):
        self.docs = docs

    def select(self, _):
        return self

    def stream(self, **_):
        return [_Snap(k, {"reportes": v["reportes"]}) for k, v in self.docs.items()]

    def document(self, k):
        return _Ref(self.docs[k], {"seed": 3, "registro": [], "mazos": []})


class _Db:
    def __init__(self, cols):
        self.cols = cols

    def collection(self, n):
        return _Col(self.cols.get(n, {}))


def _rep(dia, texto):
    return {"fecha": datetime(2026, 11, dia, 12, tzinfo=timezone.utc), "comentario": texto, "enVivo": True,
            "pasoGrabacion": 4, "turno": 2, "fase": "vigilia"}


def test_exporta_y_lista_solo_lo_nuevo(tmp_path, monkeypatch):
    monkeypatch.setattr(b, "CARPETA", tmp_path)
    monkeypatch.setattr(b, "ATENDIDOS", tmp_path / "atendidos.json")
    cliente = _Db({"ai_challenges": {"AAAA1": {"status": "terminado",
                                               "reportes": [_rep(18, "viejo"), _rep(20, "Sir X no robó")]}}})
    assert b.exportar(cliente) == 1
    assert b.exportar(cliente) == 0  # sin cambios no reescribe
    pend = b.pendientes()
    assert [p["clave"] for p in pend] == ["ai_challenges/AAAA1/1"]  # el del 18 es anterior al corte
    b.atender("ai_challenges/AAAA1/1", "arreglado en habilidades.py")
    assert b.pendientes() == []
    # Un reporte nuevo en el mismo desafío vuelve a exportarse y aparece.
    cliente.cols["ai_challenges"]["AAAA1"]["reportes"].append(_rep(21, "otro"))
    assert b.exportar(cliente) == 1
    assert [p["clave"] for p in b.pendientes()] == ["ai_challenges/AAAA1/2"]
