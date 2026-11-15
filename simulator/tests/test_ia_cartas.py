"""Transcribir la habilidad con IA: flujo con OpenAI y Firestore simulados."""

import io

from myl_sim import ia_cartas as I


class _Ref:
    def __init__(self, datos):
        self.datos = dict(datos)
        self.cambios = None

    def get(self):
        return self

    def to_dict(self):
        return self.datos

    def update(self, cambios):
        self.cambios = cambios


class _Db:
    def __init__(self, ref):
        self.ref = ref

    def collection(self, _):
        return self

    def document(self, _):
        return self.ref


def _preparar(monkeypatch, carta):
    ref = _Ref(carta)
    llamadas = []
    monkeypatch.setattr(I, "db", lambda: _Db(ref))
    monkeypatch.setattr(I, "transcribir", lambda url: llamadas.append(url) or "Única. Cuando entra en juego…")
    return ref, llamadas


def test_transcribe_y_guarda_solo_el_texto(monkeypatch):
    ref, llamadas = _preparar(monkeypatch, {"nombre": "Cleopatra VII", "officialImageUrl": "u",
                                            "habilidades": [{"accion": "robar"}]})
    r = I.procesar_carta("cleo")
    assert r == {"status": "ok", "texto": "Única. Cuando entra en juego…", "api": True}
    assert ref.cambios["habilidadTextoIA"] == "Única. Cuando entra en juego…"
    assert "habilidades" not in ref.cambios and "habilidadesRevisadas" not in ref.cambios
    assert llamadas == ["u"]


def test_no_gasta_api_si_ya_hay_texto(monkeypatch):
    ref, llamadas = _preparar(monkeypatch, {"officialImageUrl": "u", "habilidad": "Texto oficial"})
    assert I.procesar_carta("x") == {"status": "ok", "texto": "Texto oficial", "api": False}
    assert llamadas == [] and ref.cambios is None


def test_forzar_vuelve_a_transcribir(monkeypatch):
    ref, llamadas = _preparar(monkeypatch, {"officialImageUrl": "u", "habilidadTextoIA": "viejo"})
    I.procesar_carta("x", forzar=True)
    assert llamadas == ["u"]


def test_recorta_solo_el_cuadro_de_abajo():
    from PIL import Image

    img = Image.new("RGB", (709, 1016), "white")
    buf = io.BytesIO()
    img.save(buf, "PNG")
    out = Image.open(io.BytesIO(I.recortar_cuadro(buf.getvalue())))
    assert out.width <= I.ANCHO and out.height < 300  # solo la franja de la habilidad


def test_un_punto_no_cuenta_como_texto(monkeypatch):
    ref, llamadas = _preparar(monkeypatch, {"officialImageUrl": "u", "habilidad": "."})
    r = I.procesar_carta("constantino")
    assert r["api"] is True and llamadas == ["u"]


def test_normaliza_listas_en_campos_de_un_valor():
    h = I.normalizar({"accion": "modificarFuerza", "objetivo": {"raza": ["Héroe"], "tipos": ["Aliado"]},
                      "luego": [{"accion": ["robar"]}]})
    assert h["objetivo"] == {"raza": "Héroe", "tipos": ["Aliado"]} and h["luego"][0]["accion"] == "robar"


def test_aplicar_desde_la_cola(monkeypatch):
    from myl_sim import cola_agente as C

    ref = _Ref({"habilidades": [{"accion": "robar"}], "habilidadesRevisadas": False})
    monkeypatch.setattr(C, "db", lambda: _Db(ref))
    C.aplicar("x", [{"accion": "botar"}], notas="ok")
    c = ref.cambios
    assert c["habilidades"] == [{"accion": "botar"}] and c["habilidadesRevisadas"] is True
    assert c["solicitudAgente"]["estado"] == "programada"
    assert c["habilidadesAntesIA"]["habilidades"] == [{"accion": "robar"}]
