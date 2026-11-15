"""Reportes de Desafiante Control: vs Caballero Armas
(simulations/zJg0U8Vz3FWOFv8caTJk, seed 2047) y vs Eterno Agro
(simulations/Fv8DTusDBCOQwpCJQ6Ov, seed 16202). Cartas tal como están
programadas en los mazos (simulator/cache).

La lógica de fondo: la misma carta no vale siempre lo mismo. Con la mesa
rival más fuerte se busca y se juega removal; con el castillo corto,
reciclaje; con la mesa tranquila, un motor de robo antes que un golpe que me
bota a mí."""

import json
from pathlib import Path

import pytest

from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona

from test_motor import ORO, partida

CACHE = Path(__file__).resolve().parents[1] / "cache"
_MAZO = CACHE / "mazo_OiU2a8CSLtA4IGUTmekw.json"
_CARTAS = {}
for _f in ("mazo_OiU2a8CSLtA4IGUTmekw.json", "mazo_PQQzjvNznnYBs4VA3nz5.json", "mazo_ji9mTy7kp7C0mdNlwlpy.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _CARTAS[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _CARTAS.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))

pytestmark = pytest.mark.skipif(len(_CARTAS) < 30, reason="faltan los mazos en simulator/cache")


def _poner(p, i, nombre, zona):
    inst = p._instancia(_CARTAS[nombre], i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    p._mover(inst, zona)
    if zona == Zona.DEFENSA:
        inst.listo = True
    return inst


def _oro(p, i, zona=Zona.RESERVA):
    inst = p._instancia(ORO, i, Zona.MAZO)
    p.j(i).mazo.append(inst)
    if zona != Zona.MAZO:
        p._mover(inst, zona)


def _armar(*, mano, mesa=(), apoyo=(), oros=3, cementerio=(), mazo=30, mazo_extra=(), rival_mesa=()):
    """Yo (0) en mi Vigilia, con el Oro del turno ya jugado."""
    p = partida()
    p.e.log = []
    for i in (0, 1):
        p.j(i).mano.clear()
        p.j(i).reserva.clear()
        p.j(i).mazo.clear()
    for _ in range(oros):
        _oro(p, 0)
    for _ in range(3):
        _oro(p, 1)
    for n in mazo_extra:
        _poner(p, 0, n, Zona.MAZO)
    resto = [c["nombre"] for c in json.loads(_MAZO.read_text(encoding="utf-8"))["cartas"] if c["nombre"] not in mano]
    for n in resto[: max(0, mazo - len(mazo_extra))]:
        _poner(p, 0, n, Zona.MAZO)
    for _ in range(30):
        _oro(p, 1, Zona.MAZO)
    for n in mano:
        _poner(p, 0, n, Zona.MANO)
    for n in mesa:
        _poner(p, 0, n, Zona.DEFENSA)
    for n in apoyo:
        _poner(p, 0, n, Zona.APOYO)
    for n in cementerio:
        _poner(p, 0, n, Zona.CEMENTERIO)
    for n in rival_mesa:
        _poner(p, 1, n, Zona.DEFENSA)
    p.e.activo, p.e.fase, p.e.turno = 0, "vigilia", 5
    p.j(0).oro_jugado = True
    return p


def _vigilia(p) -> list[str]:
    n = len(p.e.log)
    p._vigilia(0)
    return p.e.log[n:]


def _texto(lineas) -> str:
    return "\n".join(lineas)


# ── G1 T3: con la mesa tranquila, Anand (motor de robo) antes que Nuada ─────
def test_mesa_tranquila_juega_el_motor_antes_que_el_golpe_que_me_bota():
    p = _armar(mano=["Nuada Brazo de Plata", "Red de Plata", "Bodb Derg", "Anand", "Beleth"], mesa=["Niamh"],
               oros=3, mazo=40, rival_mesa=["Duque Godofredo"])
    log = _texto(_vigilia(p))
    assert "juega Anand" in log and "juega Nuada" not in log


# ── G1 T5: me superan en mesa → Beleth busca removal (no Bodb Derg) ──────────
def test_me_superan_beleth_busca_removal():
    p = _armar(mano=["Red de Plata", "Bodb Derg", "Anand", "Beleth"], mesa=["Nuada Brazo de Plata"],
               oros=4, mazo=34, rival_mesa=["Sir Persival", "Duque Godofredo"])
    log = _vigilia(p)
    assert "juega Beleth" in log[0]
    assert any("Beleth: buscar Aine" in l or "Beleth: buscar Cerridwen" in l for l in log)


# ── G1 T7: removal antes que Avalon; Aine a Persival, Cerridwen cubre a Godofredo ─
def test_removal_antes_que_avalon_y_reparte_objetivos():
    p = _armar(mano=["Red de Plata", "Anand", "Beleth", "Avalon", "Cerridwen"], mesa=["Nuada Brazo de Plata"],
               oros=5, mazo=21, rival_mesa=["Sir Persival", "Duque Godofredo"])
    log = _texto(_vigilia(p))
    assert "juega Avalon" not in log
    assert "destierra a Sir Persival" in log  # Godofredo (coste 2) queda para Cerridwen


def _objetivo_de_aine(p, oros_libres):
    """A quién destierra Aine ya pagada, con `oros_libres` Oros en reserva."""
    aine = _poner(p, 0, "Aine", Zona.DEFENSA)
    for x in p.j(0).reserva[oros_libres:]:
        p._mover(x, Zona.PAGADO)
    destierro = aine.habilidades[0]["luego"][0]
    p.ctx_fuente_habilidad = aine
    cands = [c for c in hab_candidatos(p, aine, destierro)]
    return p.decide(0).elegir_objetivos(p, 0, cands, 1, destierro)[0].nombre


def hab_candidatos(p, fuente, h):
    from myl_sim import habilidades as hab
    return hab.candidatos_validos(p, 0, fuente, h)


# El reparto depende de la situación, no es fijo: si Cerridwen no se puede
# jugar hoy y el castillo no aguanta otro turno de Godofredo, Aine lo saca ya.
@pytest.mark.parametrize("oros,mazo,objetivo", [
    (2, 30, "Sir Persival"),     # Cerridwen se juega hoy: Aine a Persival
    (0, 6, "Duque Godofredo"),   # sin Oro para Cerridwen y castillo crítico
])
def test_reparto_de_removal_segun_la_situacion(oros, mazo, objetivo):
    p = _armar(mano=["Cerridwen", "Anand"], oros=oros, mazo=mazo, rival_mesa=["Sir Persival", "Duque Godofredo"])
    assert _objetivo_de_aine(p, oros) == objetivo


# ── G1 T11: castillo crítico → Beleth trae Caturix; Aine no muestra sin objetivo ─
def test_castillo_critico_busca_reciclaje_y_aine_no_muestra_en_vano():
    p = _armar(mano=["Red de Plata", "Anand", "Beleth", "Cerridwen", "Aine"], apoyo=["Avalon"], oros=5, mazo=8,
               mazo_extra=["Caturix"], rival_mesa=["Eriu"],
               cementerio=["Caturix", "Rhiannon", "Aine", "Beleth", "Niamh", "Salmon del Saber", "Anand", "Bodb Derg"])
    log = _texto(_vigilia(p))
    assert "Beleth: buscar Caturix" in log and "juega Caturix" in log
    assert "Aine: muestra" not in log


def test_aine_no_muestra_si_el_unico_rival_es_indesterrable():
    p = _armar(mano=["Aine", "Anand"], oros=3, rival_mesa=["Eriu"])
    aine = next(c for c in p.j(0).mano if c.nombre == "Aine")
    assert not p.decide(0).usar_opcional(p, 0, aine, aine.habilidades[0])


# ── G2 T2: Beleth no busca a Nuada: removal (o robo) ────────────────────────
def test_beleth_no_busca_a_nuada_con_un_aliado_rival_en_mesa():
    p = _armar(mano=["Caturix", "Beleth", "Anand", "Aine", "Ceangal An Fhanaigh"], oros=2, mazo=41,
               rival_mesa=["Ptah"])
    log = _texto(_vigilia(p))
    assert "Beleth: buscar" in log and "buscar Nuada" not in log


# ── G2 T14/T16: Anand se activa (bota 1 cada uno y roba o recicla) ──────────
def test_anand_se_activa_en_la_vigilia():
    p = _armar(mano=["Moy-Mell", "La Traición De Macalpin", "Niamh", "Morir de Pie"], mesa=["Aine", "Anand"],
               oros=3, mazo=25, rival_mesa=["Osiris", "Nefertiti", "Heka", "Ra"])
    assert "activa Anand: Botar" in _texto(_vigilia(p))


def test_anand_recicla_con_el_castillo_corto():
    p = _armar(mano=[], mesa=["Anand"], oros=1, mazo=7, cementerio=["Caturix"])
    anand = p.j(0).aliados[0]
    ops = [e for e in anand.habilidades[0]["luego"]]
    assert ops[p.decide(0).elegir_opcion(p, 0, anand, ops)]["accion"] == "barajar"


# ── G2 T6: Nuada no se destruye a sí misma; con castillo sano bota 3 ────────
@pytest.mark.parametrize("mesa", [["Nuada Brazo de Plata"], ["Nuada Brazo de Plata", "Beleth"]])
def test_nuada_bota_3_con_castillo_sano(mesa):
    p = _armar(mano=[], mesa=mesa, oros=3, mazo=38)
    nuada = p.j(0).aliados[0]
    ops = [h for h in nuada.habilidades if h.get("grupoElegir") == "nuada"]
    assert ops[p.decide(0).elegir_opcion(p, 0, nuada, ops)]["accion"] == "botar"


def test_nuada_no_es_objetivo_de_su_propio_costo():
    from myl_sim import habilidades as hab
    p = _armar(mano=[], mesa=["Nuada Brazo de Plata", "Beleth"], oros=3, mazo=6)
    nuada = p.j(0).aliados[0]
    destruir = next(h for h in nuada.habilidades if h.get("accion") == "destruir")
    assert nuada not in hab.candidatos_validos(p, 0, nuada, destruir)


# ── G2 T9: el Salmón no se revienta por 5 de daño con 39 en el mazo ─────────
@pytest.mark.parametrize("mazo,usa", [(39, False), (7, True)])
def test_salmon_solo_contra_un_golpe_que_importa(mazo, usa):
    p = _armar(mano=[], mesa=["Caturix"], oros=1, mazo=mazo, rival_mesa=["Ra"])
    salmon = _poner(p, 0, "Salmon del Saber", Zona.RESERVA)
    ra = p.j(1).aliados[0]
    p._mover(ra, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [ra], {}
    p.e.activo, p.e.fase = 1, "guerra_talismanes"
    # Desafío 2026-11-14: el Salmón no se usa en la Guerra de Talismanes…
    assert not any(j.carta is salmon for j in p.jugadas_legales(0, "guerra_talismanes"))
    # …sino en la Asignación de Daño.
    p.e.fase = "asignacion_dano"
    jugada = next(j for j in p.jugadas_legales(0, "asignacion_dano") if j.tipo == "activar" and j.carta is salmon)
    assert p.decide(0)._vale_la_pena(p, 0, jugada) is usa


# ── G1 T15: Linaje Celta trae Caturix con el castillo crítico ───────────────
def test_linaje_trae_caturix_con_el_castillo_critico():
    p = _armar(mano=["Red de Plata"], oros=4, mazo=8, rival_mesa=["Sir Persival"],
               cementerio=["Caturix", "Rhiannon", "Aine", "Beleth", "Niamh", "Anand", "Bodb Derg", "Nuada Brazo de Plata"])
    _poner(p, 0, "Linaje Celta", Zona.RESERVA)
    log = _texto(_vigilia(p))
    assert "Linaje Celta: buscar Caturix" in log and "juega Caturix" in log


# ── Las tres Olas: se guarda para cancelar el ataque rival, no se gasta en mi Vigilia
def test_tres_olas_no_se_juega_en_mi_vigilia():
    p = _armar(mano=["Las tres Olas"], oros=3, rival_mesa=["Sir Persival"])
    assert not any(j.carta is not None and j.carta.nombre == "Las tres Olas" for j in p.jugadas_legales(0, "vigilia"))


def test_tres_olas_cancela_el_ataque_rival():
    p = _armar(mano=["Las tres Olas"], oros=3, rival_mesa=["Sir Persival"])
    persival = p.j(1).aliados[0]
    p._mover(persival, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [persival], {}
    p.e.activo, p.e.fase = 1, "declaracion_ataque"
    assert any(j.carta is not None and j.carta.nombre == "Las tres Olas"
               for j in p.jugadas_legales(0, "declaracion_ataque"))


# ── Sidhes del Bosque: la carta clave del Mazo rival según la partida ──────
def _sidhes(mazo_rival, rival_mesa=("Sir Persival",)):
    p = _armar(mano=["SIDHES DEL BOSQUE", "Anand"], oros=5, mazo=30, rival_mesa=list(rival_mesa))
    for n in mazo_rival:
        _poner(p, 1, n, Zona.MAZO)
    return _texto(_vigilia(p))


def test_sidhes_trae_la_carta_clave_del_rival():
    log = _sidhes(["Sir Persival", "Duque Godofredo", "Rey Arturo Pendragón"])
    assert "juega SIDHES DEL BOSQUE" in log and "juega Rey Arturo Pendragón" in log


def test_sidhes_no_se_gasta_por_un_aliado_menor():
    log = _sidhes(["Sir Persival"])
    assert "juega SIDHES DEL BOSQUE" not in log


# ── Rhiannon (reporte en vivo 2026-11-14): mira 3 y elige el modo viéndolas ──
def _rhiannon(tope, elegir=None):
    from myl_sim import habilidades as hab
    from myl_sim.desafio import HumanoRemoto

    p = _armar(mano=["Rhiannon"], oros=2, mazo=10)
    for n in reversed(tope):
        inst = p._instancia(_CARTAS[n], 0, Zona.MAZO)
        p.j(0).mazo.insert(0, inst)
    pedidos = []
    if elegir is not None:
        def pedir(tipo, opciones, config):
            pedidos.append((tipo, opciones, config))
            return elegir(opciones, config)
        humano = HumanoRemoto(pedir)
        humano.usar_opcional = lambda *a: True
        p.jugadores = (humano, p.jugadores[1])
    rh = next(c for c in p.j(0).mano if c.nombre == "Rhiannon")
    p._mover(rh, Zona.DEFENSA)
    hab.disparar(p, rh, "al_jugar")
    return p, pedidos


def test_rhiannon_mira_3_una_sola_vez_y_la_ia_elige_el_modo():
    p, _ = _rhiannon(["Aine", "Red de Plata", "Cerridwen"])
    log = _texto(p.e.log)
    assert log.count("Rhiannon: mira") == 1 and "las 3 primeras" in log
    mano = {c.nombre for c in p.j(0).mano}
    assert mano in ({"Aine", "Cerridwen"}, {"Red de Plata"})


def test_rhiannon_humano_ve_las_3_y_toma_los_aliados():
    def aliados(opciones, config):
        modo = next(m for m in config["modos"] if m["maximo"] == 3)
        return modo["ids"]

    p, pedidos = _rhiannon(["Aine", "Red de Plata", "Cerridwen"], aliados)
    tipo, opciones, config = pedidos[-1]
    assert tipo == "mirar" and len(opciones) == 3 and len(config["modos"]) == 2
    assert {c.nombre for c in p.j(0).mano} == {"Aine", "Cerridwen"}
    assert "Red de Plata" in {c.nombre for c in p.j(0).cementerio}


def test_respuesta_mirar_no_mezcla_modos():
    from myl_sim.desafio import respuesta_valida

    config = {"modos": [{"ids": ["1"], "maximo": 1}, {"ids": ["2", "3"], "maximo": 3}]}
    assert respuesta_valida("mirar", [], config, ["2", "3"])
    assert respuesta_valida("mirar", [], config, ["1"])
    assert respuesta_valida("mirar", [], config, [])
    assert not respuesta_valida("mirar", [], config, ["1", "2"])


# ── Desafío 2026-11-14: Desafiar a Arturo en respuesta se puede anular ──────
def test_talisman_que_cancela_en_respuesta_abre_la_ventana_de_anulacion():
    from myl_sim import habilidades as hab
    from myl_sim.jugadores import Heuristico

    p = _armar(mano=["Morir de Pie"], mesa=["Aine", "Caturix"], oros=3, cementerio=["Beleth"])
    p.e.activo = 0
    desafiar = _poner(p, 1, "Desafiar A Arturo", Zona.MANO)
    caturix = next(a for a in p.j(0).aliados if a.nombre == "Caturix")
    h = next(x for x in caturix.habilidades if x.get("accion") == "barajar")
    ofrecido = []

    class Yo(Heuristico):
        def anular(self, p_, yo, carta, opciones):
            ofrecido.append(carta.nombre)
            return 0

    class Rival(Heuristico):
        def cancelar_habilidad(self, p_, yo, fuente, h_, opciones):
            return 0

    p.jugadores = (Yo(1), Rival(2))
    assert hab.ventana_cancelar(p, 0, caturix, h) is False  # anulado: Caturix se resuelve
    assert ofrecido == ["Desafiar A Arturo"]
    assert desafiar.zona == Zona.CEMENTERIO
    assert "anula Desafiar A Arturo con Morir de Pie" in _texto(p.e.log)


def test_talisman_que_responde_a_tu_jugada_tambien_se_puede_anular():
    from myl_sim import habilidades as hab
    from myl_sim.jugadores import Heuristico

    if "Resplandor de Heka" not in _CARTAS:
        pytest.skip("falta Resplandor de Heka en el caché")
    p = _armar(mano=["Morir de Pie", "Niamh"], mesa=["Aine", "Caturix"], oros=3)
    resplandor = _poner(p, 1, "Resplandor de Heka", Zona.MANO)
    niamh = next(c for c in p.j(0).mano if c.nombre == "Niamh")
    ofrecido = []

    class Yo(Heuristico):
        def anular(self, p_, yo, carta, opciones):
            ofrecido.append(carta.nombre)
            return 0

    class Rival(Heuristico):
        def responder(self, p_, yo, carta, opciones):
            return 0

    p.jugadores = (Yo(1), Rival(2))
    p._mover(niamh, Zona.DEFENSA)
    hab.ventana_respuesta(p, niamh)
    assert ofrecido == ["Resplandor de Heka"]
    assert resplandor.zona == Zona.CEMENTERIO
    assert not niamh.sin_habilidad_hasta  # la respuesta no se resolvió


@pytest.mark.parametrize("mesa, ofrece", [((), False), (("Aine", "Caturix"), True)])
def test_morir_de_pie_solo_anula_con_2_aliados_de_una_misma_raza(mesa, ofrece):
    """Reporte qx6H T10: sin Aliados en juego no se puede jugar Morir de Pie."""
    from myl_sim import habilidades as hab
    from myl_sim.jugadores import Heuristico

    p = _armar(mano=["Morir de Pie"], mesa=mesa, oros=3)
    sidhes = _poner(p, 1, "SIDHES DEL BOSQUE", Zona.MANO)
    ofrecido = []

    class Yo(Heuristico):
        def anular(self, p_, yo, carta, opciones):
            ofrecido.append(carta.nombre)
            return None

    p.jugadores = (Yo(1), Heuristico(2))
    hab.ventana_anulacion(p, 1, sidhes)
    assert bool(ofrecido) is ofrece


# ── Lecciones de tus jugadas (desafío PzofIK, 2026-11-14) ───────────────────
def _primera_jugada(p):
    from myl_sim.motor import Jugada
    js = p.jugadas_legales(0, "vigilia")
    return p.decide(0).elegir_jugada(p, 0, js + [Jugada("pasar")] if not any(j.tipo == "pasar" for j in js) else js)


def test_t1_mesa_vacia_rhiannon_cava_antes_que_niamh():
    p = _armar(mano=["Niamh", "Rhiannon", "Cerridwen"], oros=2, mazo=41)
    assert _primera_jugada(p).carta.nombre == "Rhiannon"


def test_castillo_critico_y_rival_encima_rhiannon_no_bota_por_cavar():
    from myl_sim.jugadores import _valor_cavar
    p = _armar(mano=["Niamh", "Rhiannon"], oros=2, mazo=6, rival_mesa=["Sir Persival", "Duque Godofredo"])
    rh = next(c for c in p.j(0).mano if c.nombre == "Rhiannon")
    assert _valor_cavar(p, 0, rh) < 1.0  # cavar 3 con 6 en el castillo casi no suma


def test_ceangal_antes_que_joya_si_hay_un_objetivo_que_vale():
    p = _armar(mano=["Joya Amatista", "Ceangal An Fhanaigh"], oros=2, rival_mesa=["Yvain Del León"])
    p.j(0).oro_jugado = False
    oros = [j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "oro"]
    assert p.decide(0).elegir_jugada(p, 0, oros).carta.nombre == "Ceangal An Fhanaigh"


def test_sin_objetivo_ceangal_se_guarda():
    p = _armar(mano=["Joya Amatista", "Ceangal An Fhanaigh"], oros=2)
    p.j(0).oro_jugado = False
    oros = [j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "oro"]
    assert p.decide(0).elegir_jugada(p, 0, oros).carta.nombre == "Joya Amatista"


def test_magia_amatista_destruye_una_sola_copia():
    """Reporte en vivo T11: con 2 Godofredo en juego debía morir solo uno."""
    p = _armar(mano=["Magia Amatista"], oros=3, rival_mesa=["Duque Godofredo", "Duque Godofredo"])
    _poner(p, 1, "Duque Godofredo", Zona.MAZO)
    magia = next(c for c in p.j(0).mano if c.nombre == "Magia Amatista")
    from myl_sim.motor import Jugada
    p.ejecutar_jugada(0, Jugada("jugar", magia))
    assert [a.nombre for a in p.j(1).aliados] == ["Duque Godofredo"]


def test_anand_el_jugador_elige_robar_o_barajar():
    """Reporte en vivo 4n5oe T9: con Anand el jugador elige si roba o baraja."""
    from myl_sim.desafio import HumanoRemoto

    p = _armar(mano=[], mesa=["Anand"], oros=3, mazo=20, cementerio=["Caturix"])
    for _ in range(3):
        _poner(p, 1, "Sir Persival", Zona.MAZO)  # el rival bota un Aliado: se cumple
    p.j(1).mazo.reverse()
    pedidos = []

    def pedir(tipo, opciones, config):
        pedidos.append((tipo, opciones))
        if tipo == "opcion":
            return next(o["id"] for o in opciones if o["titulo"].startswith("Barajar"))
        if tipo == "objetivos":
            return [opciones[0]["id"]]
        return "si"

    p.jugadores = (HumanoRemoto(pedir), p.jugadores[1])
    anand = p.j(0).aliados[0]
    activar = next(j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "activar" and j.carta is anand)
    p.ejecutar_jugada(0, activar)
    elegir = [o for t, o in pedidos if t == "opcion"]
    assert elegir and [o["titulo"] for o in elegir[0]] == ["Robar 1", "Barajar en el mazo 1 de tu Cementerio", "No usar"]
    assert "baraja en el mazo" in _texto(p.e.log)


# ── Desafío 4n5oe T7: Anillos de Badbury baraja la amenaza rival ────────────
def test_anillos_baraja_la_amenaza_cuando_me_superan():
    from myl_sim.motor import Jugada
    p = _armar(mano=["Anillos de Badbury", "Caturix"], mesa=["Rhiannon"], oros=4, cementerio=["Beleth"],
               rival_mesa=["Sir Persival", "Duque Godofredo"])
    js = [j for j in p.jugadas_legales(0, "vigilia") if j.tipo == "jugar"]
    elegida = p.decide(0).elegir_jugada(p, 0, js + [Jugada("pasar")])
    assert elegida.carta.nombre == "Anillos de Badbury"
    p.ejecutar_jugada(0, elegida)
    assert len(p.j(1).aliados) == 1 and [a.nombre for a in p.j(0).aliados] == ["Rhiannon"]


def test_sin_amenaza_rival_barajar_no_suma():
    from myl_sim.jugadores import _barajar_rival_que_aporta
    p = _armar(mano=["Anillos de Badbury"], mesa=["Rhiannon"], oros=4)
    anillos = p.j(0).mano[0]
    assert _barajar_rival_que_aporta(p, 0, anillos) == 0.0
