"""Reportes pendientes de los desafíos BibK, dJ00, w3a6 y vUsU, y Dario III
(Héctor 18-11). Usan las cartas reales del catálogo local."""

import pytest

from myl_sim import habilidades as hab
from myl_sim.datos import CACHE
from myl_sim.desafio import HumanoRemoto, describir_costo
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import en_defensa, partida

if not (CACHE / "catalogo.json").exists():
    pytest.skip("sin catálogo local", allow_module_level=True)

from test_reportes_5vxy import C  # noqa: E402


class Persona(HumanoRemoto):
    """Responde con `respuestas[tipo]` (o la primera opción) y anota todo."""

    def __init__(self, **respuestas):
        self.preguntas = []

        def pedir(tipo, opciones, config):
            self.preguntas.append((tipo, config.get("titulo"), [o.get("titulo") or o.get("nombre") for o in opciones]))
            r = respuestas.get(tipo)
            if callable(r):
                return r(opciones, config)
            if r is not None:
                return r
            if tipo == "pago_oro":
                return [x["id"] for x in opciones][-int(config.get("cantidad", 1)):]
            if tipo in ("anular", "responder"):
                return "pasar"
            return opciones[0]["id"] if opciones else None
        super().__init__(pedir)


def test_dario_pregunta_en_la_fase_final_si_atacó():
    """«Dario III cuando ataca, en la Fase Final no me pregunta»: se sube a la
    mano y eliges robar o desterrar de un Cementerio."""
    persona = Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    dario = en_defensa(p, 0, C("Dario III"))
    ay = en_zona(p, 1, C("Ay"), Zona.CEMENTERIO)
    p.ataco_este_turno = {dario.uid}
    p.e.fase, p.e.activo = "final", 0
    hab.disparar_inicio_fase(p, "final")
    assert persona.preguntas[0][2] == ["Subir Dario III a la mano: desterrar 1 de Cementerio",
                                       "Subir Dario III a la mano: robar 1", "No usar"]
    assert dario.zona == Zona.MANO and ay.zona == Zona.DESTIERRO


def test_dario_sin_atacar_no_pregunta():
    persona = Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    dario = en_defensa(p, 0, C("Dario III"))
    p.e.fase, p.e.activo = "final", 0
    hab.disparar_inicio_fase(p, "final")
    assert persona.preguntas == [] and dario.zona == Zona.DEFENSA


def test_orfeo_se_activa_sin_haber_nombrado_antes():
    """vUsU T5: Orfeo recién llegado (por Afrodita) no se podía activar."""
    p = partida(jugadores=(Persona(), Heuristico(2)))
    orfeo = en_defensa(p, 0, C("Orfeo"))
    p.e.fase, p.e.activo = "vigilia", 0
    assert any(j.tipo == "activar" and j.carta is orfeo for j in p.jugadas_legales(0, "vigilia"))


def test_corona_faraonica_no_pide_elegir_al_que_entra():
    """BibK T12: el objetivo es el Aliado que acaba de entrar; solo se pregunta «¿usar?»."""
    persona = Persona(confirmar="si")
    p = partida(jugadores=(persona, Heuristico(2)))
    en_defensa(p, 0, C("Ay"))
    en_zona(p, 0, C("Corona Faraónica"), Zona.RESERVA)
    for _ in range(3):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    djoser = en_zona(p, 0, C("Djoser"), Zona.MANO)
    p.e.fase, p.e.activo = "vigilia", 0
    p.j(0).oro_jugado = True
    p.ejecutar_jugada(0, Jugada("jugar", djoser))
    tipos = [t for t, _, _ in persona.preguntas]
    assert "objetivos" not in tipos
    assert ("confirmar", "¿Usar Corona Faraónica (que Djoser pueda atacar este turno · botar 1)?", []) \
        in persona.preguntas


def test_djoser_destruir_es_opcional():
    """BibK T6: «puedes destruir un Aliado oponente»."""
    h = next(x for x in C("Djoser").habilidades if x.get("accion") == "destruir")
    assert h["opcional"] is True


def test_escudo_miliciano_en_tu_propio_ataque():
    """BibK T12 / AkOg T13: «en respuesta a un Ataque» (también el tuyo)."""
    p = partida(jugadores=(Persona(), Heuristico(2)))
    en_defensa(p, 0, C("Guerrero Medjay"))
    escudo = en_zona(p, 0, C("Escudo Miliciano"), Zona.CEMENTERIO)
    for _ in range(3):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    for activo in (0, 1):
        p.e.fase, p.e.activo = "declaracion_ataque", activo
        assert any(j.tipo == "activar" and j.carta is escudo for j in p.jugadas_legales(0, "declaracion_ataque"))


def test_dos_bereber_se_bonifican_entre_si():
    """w3a6 T5: «hay 2 Bereber en mesa, cada uno puede bonificar con 2 al otro»."""
    persona = Persona(opcion=lambda ops, cfg: next(o["id"] for o in ops if o["titulo"].startswith("+2")))
    p = partida(jugadores=(persona, Heuristico(2)))
    b1, b2 = en_defensa(p, 0, C("Guerrero Bereber")), en_defensa(p, 0, C("Guerrero Bereber"))
    p.e.fase, p.e.activo = "declaracion_ataque", 0
    for b in (b1, b2):
        hab.disparar(p, b, "al_atacar")
    assert "+2 de fuerza a otro Guerrero" in persona.preguntas[0][2]
    assert hab.fuerza(p, b1) == hab.fuerza(p, b2) == C("Guerrero Bereber").fuerza + 2


def test_costo_alternativo_explicito():
    """dJ00 T7: «no preguntes por costes alternativos, sé explícito»."""
    persona = Persona(opcion="alternativo")
    p = partida(jugadores=(persona, Heuristico(2)))
    ptolomeo = en_defensa(p, 0, C("Ptolomeo II"))
    h = next(x for x in ptolomeo.habilidades if x.get("costoAlternativo"))
    assert persona.preferir_alternativo(p, 0, ptolomeo, h) is True
    _, titulo, opciones = persona.preguntas[-1]
    assert titulo == "Ptolomeo II: ¿cómo pagas?"
    assert opciones == [describir_costo(h["costo"]), describir_costo(h["costoAlternativo"])]
    assert describir_costo({"botar": 3}) == "Botar 3" and describir_costo({"oros": 1}) == "Pagar 1 Oro"


def test_eros_busca_coronas_del_dia_y_ofrenda():
    """vUsU T3: «el Olímpico se busca las 2 Coronas del Día; si no, Corona y Ofrenda»."""
    ia = Heuristico(2)
    p = partida(jugadores=(Heuristico(1), ia))
    eros = en_defensa(p, 1, C("Eros"))
    mazo = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Olímpicos", "Corona del Día", "Ofrenda a los Dioses",
                                                       "Corona del Día", "Titanes")]
    h = eros.habilidades[0]
    p.ctx_fuente_habilidad = eros
    elegidos = ia.elegir_objetivos(p, 1, mazo, 2, h)
    assert [x.nombre for x in elegidos] == ["Corona del Día", "Corona del Día"]
    elegidos = ia.elegir_objetivos(p, 1, [x for x in mazo if x is not mazo[3]], 2, h)
    assert [x.nombre for x in elegidos] == ["Corona del Día", "Ofrenda a los Dioses"]


def test_desglose_de_fuerza():
    """vUsU T9: al tocar un Aliado se ve quién lo bonifica o perjudica."""
    persona = Persona(opcion=lambda ops, cfg: next(o["id"] for o in ops if o["titulo"].startswith("+2")))
    p = partida(jugadores=(persona, Heuristico(2)))
    b1, b2 = en_defensa(p, 0, C("Guerrero Bereber")), en_defensa(p, 0, C("Guerrero Bereber"))
    hab.disparar(p, b1, "al_atacar")
    assert hab.desglose_fuerza(p, b2) == [("Guerrero Bereber", "+2")]
    assert hab.desglose_fuerza(p, b1) == []
