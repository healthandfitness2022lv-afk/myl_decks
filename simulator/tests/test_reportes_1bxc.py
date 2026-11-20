"""Reportes de los desafíos 1bXc (Sacer Tótem vs Caballero Armas), CfHJ
(Desafiante Control vs Faerie Control) y LyCy (Sombra Agro vs Faraón guerrero).
Usan las cartas reales del catálogo local."""

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import en_defensa, partida
from test_reportes_5vxy import C, _Persona


def test_ayu_del_veneno_hace_botar_el_coste_del_totem():
    """1bXc T13: «no se activó la habilidad del Ayu del Veneno, debió darme a elegir un Tótem»."""
    p = partida()
    en_zona(p, 0, C("Saqqara"), Zona.APOYO)
    en_zona(p, 0, C("Tebas"), Zona.APOYO)
    ayu = en_zona(p, 0, C("Ayu del Veneno"), Zona.MANO)
    for _ in range(3):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 0
    antes = len(p.j(1).mazo)
    p.ejecutar_jugada(0, Jugada("jugar", ayu))
    assert antes - len(p.j(1).mazo) == max(C("Saqqara").coste, C("Tebas").coste)


def test_la_persona_elige_el_totem_de_ayu_del_veneno():
    persona = _Persona()
    p = partida(jugadores=(persona, Heuristico(2)))
    en_zona(p, 0, C("Saqqara"), Zona.APOYO)
    ayu = en_zona(p, 0, C("Ayu del Veneno"), Zona.MANO)
    for _ in range(3):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
    p.e.fase, p.e.activo = "vigilia", 0
    p.ejecutar_jugada(0, Jugada("jugar", ayu))
    assert any(t == "confirmar" and "Ayu del Veneno" in (titulo or "") for t, titulo in persona.preguntas)


def test_ayu_se_activa_en_la_guerra_del_turno_rival():
    """1bXc T14: «el Ayu se debe poder activar en guerra cuando el oponente me ataca»."""
    p = partida()
    ayu = en_defensa(p, 0, C("Ayu"))
    en_zona(p, 0, C("Saqqara"), Zona.APOYO)
    p.e.fase, p.e.activo = "guerra_talismanes", 1
    assert any(j.tipo == "activar" and j.carta is ayu for j in p.jugadas_legales(0, "guerra_talismanes"))


def test_melisende_no_se_ofrece_a_bloqueadores_de_fuerza_3():
    """1bXc T14: «el Djedefhor no debería poder bloquear a la Melisende»."""
    capturado = {}

    class Mira(_Persona):
        def __init__(self):
            super().__init__()

            def pedir(tipo, opciones, config):
                capturado[tipo] = opciones
                return {}
            self._pedir = pedir

    persona = Mira()
    p = partida(jugadores=(persona, Heuristico(2)))
    mel = en_defensa(p, 1, C("Melisende"))
    dje = en_defensa(p, 0, C("Djedefhor"))
    kaw = en_defensa(p, 0, C("Kawit"))
    persona.elegir_bloqueos(p, 0, [mel], [dje, kaw])
    assert [b["nombre"] for b in capturado["bloqueos"][0]["bloqueadores"]] == ["Kawit"]


def test_saqqara_cuesta_2():
    """1bXc T15: «¿por qué me cobra 3? Saqqara es coste 2»."""
    assert C("Saqqara").coste == 2


def test_morgana_cambia_un_aliado_ya_usado_por_uno_rival_mejor():
    """CfHJ T12: «¿por qué no activa la Morgana?»: Dama del Lago (ya usada) por Beleth."""
    p = partida()
    morgana = en_defensa(p, 1, C("Morgana"))
    en_defensa(p, 1, C("Dama Del Lago"))
    en_defensa(p, 0, C("Beleth"))
    h = next(x for x in morgana.habilidades if x.get("cuando") == "activada")
    assert J._sacrificio_de_aliados_conviene(p, 1, morgana, h)


@pytest.mark.parametrize("nombre,publica", [
    ("Látigo y Bastón", False), ("Marmita Druida", False), ("Cuerno de la Bestia", False),
    ("Estrella De Belén", True), ("Tom Thumb", True), ("Cáliz Maldito", True), ("Castillo De Bran", True),
    ("Defensa Celestial", True), ("Patroclo", True),
])
def test_mostrar_una_carta_de_la_mano_no_hace_publico_el_tope(nombre, publica):
    """LyCy T2: «el rival no debería ver lo que se ve con Látigo y Bastón, es mirar, no mostrar»."""
    p = partida()
    assert hab._dice_mostrar(en_zona(p, 0, C(nombre), Zona.MANO)) is publica


def test_lo_que_se_baraja_del_cementerio_se_ve_y_de_la_mano_no():
    """«Todo lo que se baraje desde el Cementerio se muestra; la Roseta no,
    porque barajas algo de tu mano»."""
    from myl_sim.desafio import texto_publico

    p = partida(log=True)
    p.e.fase, p.e.activo = "vigilia", 1
    en_zona(p, 1, C("Aine"), Zona.CEMENTERIO)
    en_zona(p, 1, C("Beleth"), Zona.MANO)
    gozosa = en_zona(p, 1, C("Guardia Gozosa"), Zona.APOYO)
    h = next(x for x in gozosa.habilidades if x.get("cuando") == "activada")
    hab.resolver(p, 1, gozosa, h)
    roseta = en_zona(p, 1, C("Piedra Roseta"), Zona.RESERVA)
    hab.pagar_costo(p, 1, roseta, {"costo": {"barajarMano": 1}})
    vista = " ".join(texto_publico(x, humano=0) for x in p.e.log)
    assert "Aine" in vista
    assert "Beleth" not in vista and "(oculto)" in vista
    assert "Beleth" in " ".join(texto_publico(x, humano=1) for x in p.e.log)


def test_el_resto_mirado_en_privado_vuelve_al_mazo_sin_nombrarse():
    from myl_sim.desafio import texto_publico

    p = partida(log=True)
    fuente = en_zona(p, 1, C("Látigo y Bastón"), Zona.RESERVA)  # su texto no muestra el Mazo
    h = next(x for x in C("Estrella De Belén").habilidades if x.get("accion") == "mirarTope")
    h = {**h, "muestra": False}  # un «mira» privado que baraja el resto
    tope = p.j(1).mazo[:3]
    hab._mirar_tope(p, 1, fuente, h, 3)
    vista = " ".join(texto_publico(x, humano=0) for x in p.e.log)
    # La que toma con filtro se muestra (reporte dmwP); el resto no se nombra.
    tomadas = {x.nombre for x in tope if x.zona != Zona.MAZO}
    assert not any(x.nombre in vista for x in tope if x.zona == Zona.MAZO and x.nombre not in tomadas)


def test_anillos_de_badbury_dice_que_el_cinturon_lo_impide():
    """fu7V T10: «no siempre tengo disponible Anillos de Badbury para desterrar
    del Cementerio oponente»: el Cinturón De Lady Ann del rival en su Reserva.
    Pagado, ya no lo impide."""
    capturado = {}

    class Mira(_Persona):
        def __init__(self):
            super().__init__()

            def pedir(tipo, opciones, config):
                capturado.update(config)
                return str(len(opciones) - 1)  # pasar
            self._pedir = pedir

    persona = Mira()
    p = partida(jugadores=(persona, Heuristico(2)))
    p.e.fase, p.e.activo = "vigilia", 0
    anillos = en_zona(p, 0, C("Anillos de Badbury"), Zona.APOYO)
    en_defensa(p, 0, C("Beleth"))  # algo en mesa para que la jugada se pregunte
    for nombre in ("Aine", "Beleth"):
        en_zona(p, 1, C(nombre), Zona.CEMENTERIO)
    cinturon = en_zona(p, 1, C("Cinturón De Lady Ann"), Zona.RESERVA)
    persona.elegir_jugada(p, 0, p.jugadas_legales(0, "vigilia"))
    assert "Cinturón De Lady Ann (del rival)" in capturado["motivos"][str(anillos.uid)]
    p._mover(cinturon, Zona.PAGADO)
    assert any(j.tipo == "activar" and j.carta is anillos for j in p.jugadas_legales(0, "vigilia"))


def _jugar_contra_capa(nombre):
    p = partida(log=True)
    p.e.fase, p.e.activo = "vigilia", 0
    carta = en_zona(p, 0, C(nombre), Zona.MANO)
    for _ in range(5):
        en_zona(p, 0, C("Codex Arturicus"), Zona.RESERVA)
        en_zona(p, 1, C("Codex Arturicus"), Zona.RESERVA)
    en_zona(p, 1, C("Capa De Invisibilidad"), Zona.MANO)
    beleth = en_defensa(p, 1, C("Beleth"))
    p.decide(1).responder = lambda *a: 0
    p.decide(0).usar_opcional = lambda *a: True
    p.ejecutar_jugada(0, Jugada("jugar", carta))
    assert carta.zona == Zona.MAZO
    return beleth


def test_conchobar_mueve_aunque_la_capa_lo_baraje():
    """fu7V T10: «Conchobar dice hasta dos, debió mover al menos uno». Su
    habilidad de entrada se resuelve aunque lo barajen (y su zona "defensa"
    no la reconocía el motor)."""
    assert _jugar_contra_capa("Conchobar").zona == Zona.ATAQUE


def test_haquika_barajada_no_toma_el_control():
    """«Con Haquika la carta es tuya mientras ella está en juego: si la
    barajan enseguida, es como si nunca hubiera pasado a tu control»."""
    assert _jugar_contra_capa("Haquika").controlador == 1


def test_zonas_defensa_y_ataque_del_catalogo_se_reconocen():
    assert hab.zonas_de({"zona": "defensa"}) == ["linea_defensa"]
    assert hab.zonas_de({"zonas": ["ataque", "cementerio"]}) == ["linea_ataque", "cementerio"]


def test_morgana_no_paga_mas_de_lo_que_destierra():
    p = partida()
    morgana = en_defensa(p, 1, C("Morgana"))
    en_defensa(p, 1, C("Isengrim el Lobo"))
    en_defensa(p, 0, C("Melisende"))
    h = next(x for x in morgana.habilidades if x.get("cuando") == "activada")
    assert J._valor_carta(p, p.j(1).aliados[1]) > J._valor_carta(p, p.j(0).aliados[0])
    assert not J._sacrificio_de_aliados_conviene(p, 1, morgana, h)
