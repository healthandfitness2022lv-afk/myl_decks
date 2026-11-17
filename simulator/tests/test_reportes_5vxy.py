"""Reportes de los desafíos 5VXY (Dragón vs Eterno Control), nOC1 (Dragón vs
Caballero Armas) y 15cB (Faraón Djoser vs Desafiante MidRange). Usan las cartas
reales del catálogo local."""

import pytest

from myl_sim import habilidades as hab
from myl_sim.datos import CACHE, carta_desde_doc
from myl_sim.desafio import HumanoRemoto, describir_habilidad
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona
from myl_sim.motor import FinPartida, Jugada

from test_acciones_v3b import en_zona
from test_motor import en_defensa, partida

if not (CACHE / "catalogo.json").exists():
    pytest.skip("sin catálogo local (python -m myl_sim.sinergias <mazo> --refrescar)", allow_module_level=True)

from myl_sim.sinergias import documentos  # noqa: E402

_DOCS = documentos()
_CARTAS = {}


def C(nombre):
    if nombre not in _CARTAS:
        cid, doc = next((k, d) for k, d in _DOCS.items() if d.get("nombre") == nombre)
        _CARTAS[nombre] = carta_desde_doc(cid, doc)
    return _CARTAS[nombre]


class _Persona(HumanoRemoto):
    """Una persona que acepta la primera opción de cada pregunta."""

    def __init__(self):
        self.preguntas = []

        def pedir(tipo, opciones, config):
            self.preguntas.append((tipo, config.get("titulo")))
            if tipo == "responder":
                return {"id": opciones[0]["id"], "oros": [x["id"] for x in config.get("oros", [])][:1]}
            return opciones[0]["id"] if opciones else None
        super().__init__(pedir)


def test_apophis_hace_botar_aunque_la_bola_lo_destruya():
    """5VXY T13: jugaste Bola de Fuego contra Apophis y no botaste 3."""
    p = partida()
    apophis = en_defensa(p, 1, C("Apophis"))
    bola = en_zona(p, 0, C("Bola De Fuego"), Zona.MANO)
    for _ in range(2):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 0
    antes = len(p.j(0).mazo)
    try:
        p.ejecutar_jugada(0, Jugada("jugar", bola))
    except FinPartida:
        pass
    assert apophis.zona == Zona.CEMENTERIO
    assert len(p.j(0).mazo) == antes - 3


def test_apophis_no_cuenta_los_oros():
    p = partida()
    en_defensa(p, 1, C("Apophis"))
    oro = en_zona(p, 0, C("Codex Arturicus"), Zona.MANO)
    p.e.fase, p.e.activo = "vigilia", 0
    antes = len(p.j(0).mazo)
    p.ejecutar_jugada(0, Jugada("oro", oro))
    assert len(p.j(0).mazo) == antes


def test_la_persona_puede_cancelar_una_activacion_con_desafiar_a_arturo():
    """5VXY T17: Mut se activó y no hubo ventana para Desafiar a Arturo."""
    persona = _Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    mut = en_defensa(p, 1, C("Mut"))
    en_zona(p, 0, C("Desafiar A Arturo"), Zona.MANO)
    en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    en_zona(p, 0, C("Aine"), Zona.CEMENTERIO)
    en_zona(p, 1, C("Aine"), Zona.CEMENTERIO)
    p.e.fase, p.e.activo = "vigilia", 1
    mano = len(p.j(1).mano)
    p.ejecutar_jugada(1, Jugada("activar", mut, habilidad=0))
    assert any(t == "responder" and "Cancelar la habilidad de Mut" in (titulo or "") for t, titulo in persona.preguntas)
    assert len(p.j(1).mano) == mano  # Mut no robó: la habilidad se canceló


def test_la_prevencion_de_ra_se_puede_cancelar():
    """5VXY T26: Ra se previno descartando; Desafiar a Arturo cancela esa habilidad."""
    persona = _Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    ra = en_defensa(p, 1, C("Ra"))
    en_zona(p, 1, C("Aine"), Zona.MANO)
    en_zona(p, 0, C("Desafiar A Arturo"), Zona.MANO)
    en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    p.destruir(ra)
    assert ra.zona == Zona.CEMENTERIO


def test_vouivre_no_se_baraja_a_si_misma():
    """5VXY T18: «baraja un Aliado que controles para barajar 2 Aliados oponentes»."""
    p = partida()
    vouivre = en_defensa(p, 0, C("Vouivre"))
    en_defensa(p, 0, C("Cathach"))
    for n in ("Aker", "Ra"):
        en_defensa(p, 1, C(n))
    h = C("Vouivre").habilidades[0]
    assert [x.nombre for x in hab.candidatos_validos(p, 0, vouivre, h)] == ["Cathach"]


def test_estrella_de_belen_muestra_las_3_cartas():
    """5VXY T4: «puedes mostrar las 3 primeras»: las ves aunque no haya Oro que tomar."""
    vistas = {0: [], 1: []}

    class Mira(Heuristico):
        def ver_cartas(self, p, yo, titulo, cartas):
            vistas[yo].append([c.nombre for c in cartas])

    p = partida(jugadores=(Mira(1), Mira(2)))
    estrella = en_zona(p, 0, C("Estrella De Belén"), Zona.RESERVA)
    for _ in range(3):
        p.j(0).mazo.insert(0, p._instancia(C("Aine"), 0, Zona.MAZO))
    hab.disparar(p, estrella, "al_jugar")
    assert vistas[0] == [["Aine"] * 3] and vistas[1] == [["Aine"] * 3]


def test_escudo_celestial_baraja_tantas_como_dano():
    """15cB: «barajar tantas cartas como daño haya hecho»: era siempre 1."""
    p = partida()
    h = C("Escudo Celestial").habilidades[0]
    p.ctx_dano = 4
    assert hab.cantidad(p, 0, h, []) == 4


def test_galatine_solo_aliados_de_coste_4_o_menos():
    """nOC1: Galatine no podía mandar a Lady Calvaur (coste 7) al fondo del Mazo."""
    p = partida()
    galatine = en_zona(p, 1, C("Galatine"), Zona.MANO)
    en_defensa(p, 0, C("Lady Calvaur"))
    en_defensa(p, 0, C("Cathach"))
    h = C("Galatine").habilidades[1]
    assert [x.nombre for x in hab.candidatos(p, 1, galatine, h) if hab.coincide(p, x, h["objetivo"])] == ["Cathach"]


def test_las_activaciones_dicen_que_hacen():
    """5VXY T4: Gaspar y Pixie mostraban dos «activar» iguales."""
    for nombre in ("Gaspar", "Pixie"):
        textos = [describir_habilidad(h) for h in C(nombre).habilidades if h.get("cuando") == "activada"]
        assert len(textos) == 2 and textos[0] != textos[1]


@pytest.mark.parametrize("nombre,pagado", [
    ("Clochafarmore", True), ("La Llama De Brigit", True), ("Arcas del Imperio", True),
    ("Joya Amatista", False), ("Rito de Aton", False),  # su texto dice «de tu Reserva»
])
def test_oros_que_se_sacan_a_si_mismos_se_activan_pagados(nombre, pagado):
    """BwBe T10: «la Clochafarmore debe poder desterrarse desde Oro pagado, como la Piedra Roseta»."""
    h = next(x for x in C(nombre).habilidades if x.get("cuando") == "activada")
    assert (hab.zona_activacion(h) == "reserva_o_pagado") is pagado


def test_sir_erec_tiene_fuerza_2():
    """gXXd T3: «Sir Erec sale con fuerza 3 y realmente tiene 2»."""
    assert C("Sir Erec").fuerza == 2


def test_la_llama_dice_que_tu_carmix_impide_desterrarla():
    """gXXd T9: «¿por qué no puedo activar la Llama de Brigit?»."""
    persona = _Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    en_zona(p, 0, C("Carmix"), Zona.RESERVA)
    en_zona(p, 0, C("La Llama De Brigit"), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 0
    p.j(0).oro_jugado = True
    capturado = {}

    def pedir(tipo, opciones, config):
        capturado.update(config)
        return next(o["id"] for o in opciones if o.get("tipoJugada") == "pasar")
    persona._pedir = pedir
    persona.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert any("Carmix (tuyo)" in m for m in capturado["motivos"].values())


def test_en_la_guerra_sin_nada_que_hacer_la_fase_pasa_sola():
    """gXXd T5: «si estamos en guerra y ya no puedo hacer nada, sáltate la fase»."""
    persona = _Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    en_zona(p, 0, C("La Llama De Brigit"), Zona.MANO)  # antes abría la ventana solo para explicarla
    p.e.fase, p.e.activo = "guerra_talismanes", 1
    jugadas = p.jugadas_legales(0, "guerra_talismanes")
    assert all(j.tipo == "pasar" for j in jugadas)
    assert persona.elegir_jugada(p, 0, jugadas).tipo == "pasar"
    assert persona.preguntas == []
