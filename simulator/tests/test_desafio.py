from myl_sim.desafio import HumanoRemoto, SesionDesafio, respuesta_valida, vista_desafio
from myl_sim.modelo import Carta, Tipo, Zona
from myl_sim.motor import Jugada, Partida
from myl_sim.jugadores import Aleatorio
from dataclasses import replace


def _carta(cid, nombre):
    return Carta(cid, nombre, Tipo.ALIADO, 1, 2, "", "", revisada=True)


def test_vista_desafio_no_revela_mano_rival_y_jugada_vuelve_opcion_legal():
    p = Partida(([_carta("a", "Mi carta")], [_carta("b", "Secreta")]), (Aleatorio(1), Aleatorio(2)))
    p._mover(p.j(0).mazo[0], Zona.MANO)
    p._mover(p.j(1).mazo[0], Zona.MANO)
    vista = vista_desafio(p, 0)

    assert vista["lados"][0]["mano"][0]["nombre"] == "Mi carta"
    assert vista["lados"][1]["mano"] == []
    assert vista["lados"][1]["manoCantidad"] == 1

    pedidos = []

    def pedir(tipo, opciones, config):
        pedidos.append((tipo, opciones, config))
        return "1"

    humano = HumanoRemoto(pedir)
    opciones = [Jugada("pasar"), Jugada("jugar", p.j(0).mano[0])]
    assert humano.elegir_jugada(p, 0, opciones) is opciones[1]
    assert pedidos[0][0] == "jugada"
    assert pedidos[0][1][1]["titulo"] == "jugar Mi carta"


def test_vista_muestra_cementerio_y_destierro_de_ambos_lados():
    p = Partida(([_carta("a", "Caída")], [_carta("b", "Exiliada")]),
                (Aleatorio(1), Aleatorio(2)))
    p._mover(p.j(0).mazo[0], Zona.CEMENTERIO)
    p._mover(p.j(1).mazo[0], Zona.DESTIERRO)
    vista = vista_desafio(p, 0)
    assert vista["lados"][0]["cementerioCartas"][0]["nombre"] == "Caída"
    assert vista["lados"][1]["destierroCartas"][0]["nombre"] == "Exiliada"


def test_vista_indica_cuales_aliados_pueden_iniciar_ataque():
    p = Partida(([_carta("a", "Lista"), _carta("a2", "Agotada")],
                 [_carta("b", "Rival")]), (Aleatorio(1), Aleatorio(2)))
    lista = next(x for x in p.j(0).mazo if x.nombre == "Lista")
    agotada = next(x for x in p.j(0).mazo if x.nombre == "Agotada")
    p._mover(lista, Zona.DEFENSA)
    p._mover(agotada, Zona.DEFENSA)
    lista.listo = True
    agotada.listo = False
    cartas = vista_desafio(p, 0)["lados"][0]["defensa"]
    assert {x["nombre"]: x["puedeAtacar"] for x in cartas} == {
        "Lista": True, "Agotada": False,
    }


def test_ventanas_de_anulacion_y_respuesta_ofrecen_las_cartas():
    p = Partida(([_carta("a", "Anular")], [_carta("b", "Objetivo")]), (Aleatorio(1), Aleatorio(2)))
    carta = p.j(0).mazo[0]
    objetivo = p.j(1).mazo[0]
    vistos = []

    def pedir(tipo, opciones, config):
        vistos.append((tipo, opciones))
        return "0"

    humano = HumanoRemoto(pedir)
    assert humano.anular(p, 0, objetivo, [(carta, {"accion": "anular"})]) == 0
    assert humano.responder(p, 0, objetivo, [(carta, {"accion": "respuesta"})]) == 0
    assert [x[0] for x in vistos] == ["anular", "responder"]
    assert all(x[1][0]["titulo"] == "Anular" for x in vistos)


def test_respuestas_validan_cantidad_y_bloqueos_legales():
    cartas = [{"id": "1"}, {"id": "2"}]
    assert respuesta_valida("pago_oro", cartas, {"cantidad": 2}, ["1", "2"])
    assert not respuesta_valida("pago_oro", cartas, {"cantidad": 2}, ["1", "1"])
    assert not respuesta_valida("pago_oro", cartas, {"cantidad": 2}, ["1", "3"])
    opciones = [
        {"atacante": {"id": "a"}, "bloqueadores": [{"id": "1"}]},
        {"atacante": {"id": "b"}, "bloqueadores": [{"id": "2"}]},
    ]
    assert respuesta_valida("bloqueos", opciones, {}, {"a": "1", "b": "2"})
    assert not respuesta_valida("bloqueos", opciones, {}, {"a": "2"})
    assert not respuesta_valida("bloqueos", opciones, {}, {"a": "1", "b": "1"})


def test_pago_preseleccionado_se_confirma_antes_de_jugar():
    p = Partida(([_carta("a", "Mi carta")], [_carta("b", "Otra")]), (Aleatorio(1), Aleatorio(2)))
    carta = p.j(0).mazo[0]
    p._mover(carta, Zona.MANO)
    oro = p.j(0).reserva[0]
    pedidos = []

    def pedir(tipo, opciones, config):
        pedidos.append((tipo, opciones, config))
        return {"id": "0", "oros": [str(oro.uid)]}

    humano = HumanoRemoto(pedir)
    jugada = Jugada("jugar", carta)
    assert humano.elegir_jugada(p, 0, [jugada]) is jugada
    assert pedidos[0][1][0]["cantidadPago"] == 1
    assert respuesta_valida("jugada", pedidos[0][1], pedidos[0][2],
                           {"id": "0", "oros": [str(oro.uid)]})
    assert respuesta_valida("jugada", pedidos[0][1], pedidos[0][2], "0")
    assert humano.elegir_oros(p, 0, [oro], 1) == [oro]
    assert len(pedidos) == 1


def test_agrupacion_y_batalla_sin_atacantes_avanzan_solas():
    class Politica:
        def __init__(self):
            self.fases = []

        def elegir_jugada(self, p, yo, jugadas):
            return next(x for x in jugadas if x.tipo == "pasar")

        def confirmar_fase(self, p, yo, titulo):
            self.fases.append((p.e.fase, titulo))

    humano = Politica()
    p = Partida(([_carta("a", "A"), _carta("a2", "A2")],
                 [_carta("b", "B"), _carta("b2", "B2")]), (humano, Aleatorio(2)))
    p._turno()
    assert humano.fases == [("final", "Terminar turno")]


def test_repeticion_desafio_usa_formato_del_tablero_narrado():
    class Mazo:
        def __init__(self, nombre):
            self.nombre = nombre
            self.cartas = [_carta(f"{nombre}-{i}", f"Carta {i}") for i in range(50)]

    class Referencia:
        def __init__(self):
            self.data = {}

        def update(self, cambios):
            self.data.update(cambios)
            d = cambios.get("decision")
            if d is not None:
                valor = {
                    "mano_inicial": "quedarse",
                    "avance_fase": "continuar",
                    "atacantes": [],
                    "bloqueos": {},
                    "confirmar": "no",
                    "anular": "pasar",
                    "responder": "pasar",
                    "redirigir": "pasar",
                }.get(d["tipo"])
                if d["tipo"] == "jugada":
                    valor = next(x["id"] for x in d["opciones"] if x["tipoJugada"] == "pasar")
                if d["tipo"] in ("descartes", "objetivos", "pago_oro"):
                    valor = [x["id"] for x in d["opciones"][:d.get("cantidad", 0)]]
                if valor is None:
                    valor = d["opciones"][0]["id"]
                self.data["respuesta"] = {"decisionId": d["id"], "valor": valor}

        def get(self):
            return self

        def to_dict(self):
            return self.data

    resultado = SesionDesafio(Referencia(), Mazo("Humano"), Mazo("IA"), seed=7).jugar()
    repeticion = resultado["repeticion"]
    assert repeticion["mazoA"]["nombre"] == "Humano"
    assert repeticion["mazoB"]["nombre"] == "IA"
    assert repeticion["pasos"]
    assert repeticion["cartas"]["oro_inicial"] == "Oro inicial"
    assert "__oro_inicial__" not in repeticion["cartas"]
    assert {"t", "f", "a", "j", "x"} <= repeticion["pasos"][0].keys()


def test_indica_que_hay_que_jugar_roseta_y_neferite_antes_de_activar():
    roseta = replace(_carta("roseta", "Piedra Roseta"), tipo=Tipo.ORO,
                     habilidades=({"cuando": "activada", "zonaActivacion": "reserva_oro",
                                   "fase": "vigilia", "accion": "robar"},))
    neferite = replace(_carta("neferite", "Neferite I"),
                       habilidades=({"cuando": "activada", "fase": "vigilia",
                                     "accion": "desterrar"},))
    p = Partida(([roseta, neferite], [_carta("otro", "Otro")]),
                (Aleatorio(1), Aleatorio(2)))
    p.e.fase = "vigilia"
    p._mover(p.j(0).mazo[0], Zona.MANO)
    p._mover(p.j(0).mazo[0], Zona.MANO)
    capturado = {}

    def pedir(tipo, opciones, config):
        capturado.update(config)
        return "0"

    HumanoRemoto(pedir).elegir_jugada(p, 0, [Jugada("pasar")])
    motivos = capturado["motivos"]
    assert any("baja este Oro" in x for x in motivos.values())
    assert any("Primero juega esta carta" in x for x in motivos.values())


def _referencia_que_responde():
    """Ref falsa: contesta lo mínimo y guarda cada acción de la IA publicada."""
    class Referencia:
        def __init__(self):
            self.data = {}
            self.acciones = []

        def update(self, cambios):
            self.data.update(cambios)
            if cambios.get("accionIa"):
                self.acciones.append((cambios["accionIa"]["texto"], cambios["estado"]))
            d = cambios.get("decision")
            if d is not None:
                valor = {"mano_inicial": "quedarse", "avance_fase": "continuar", "atacantes": [],
                         "bloqueos": {}, "confirmar": "no", "anular": "pasar", "responder": "pasar",
                         "redirigir": "pasar"}.get(d["tipo"])
                if d["tipo"] == "jugada":
                    valor = next(x["id"] for x in d["opciones"] if x["tipoJugada"] == "pasar")
                if d["tipo"] in ("descartes", "objetivos", "pago_oro"):
                    valor = [x["id"] for x in d["opciones"][:d.get("cantidad", 0)]]
                if valor is None:
                    valor = d["opciones"][0]["id"]
                self.data["respuesta"] = {"decisionId": d["id"], "valor": valor}

        def get(self):
            return self

        def to_dict(self):
            return self.data

    return Referencia()


class _MazoPrueba:
    def __init__(self, nombre):
        self.nombre = nombre
        self.cartas = ([replace(_carta(f"{nombre}-oro", "Oro"), tipo=Tipo.ORO)] * 18
                       + [_carta(f"{nombre}-{i}", f"Aliado {i}") for i in range(32)])


def test_desafio_muestra_cada_jugada_de_la_ia_sin_revelar_sus_robos():
    ref = _referencia_que_responde()
    SesionDesafio(ref, _MazoPrueba("Humano"), _MazoPrueba("IA"), seed=3, pausa=1e-6).jugar()
    assert ref.acciones, "la IA debe publicar sus jugadas"
    assert any("IA juega" in t or "IA ataca" in t for t, _ in ref.acciones)
    for texto, estado in ref.acciones:
        assert "J1" not in texto and "J0" not in texto
        assert estado["lados"][1]["mano"] == []  # la mano de la IA nunca se ve
        for linea in estado["log"]:
            assert not linea.startswith("IA roba ") or linea.startswith("IA roba una carta")


def test_niveles_de_dificultad():
    from myl_sim.desafio import NIVELES, PoliticaDificultad
    assert sorted(NIVELES) == [1, 2, 3, 4, 5]
    s1 = SesionDesafio(_referencia_que_responde(), _MazoPrueba("H"), _MazoPrueba("I"), seed=1, nivel=1)
    s4 = SesionDesafio(_referencia_que_responde(), _MazoPrueba("H"), _MazoPrueba("I"), seed=1, nivel=4)
    s5 = SesionDesafio(_referencia_que_responde(), _MazoPrueba("H"), _MazoPrueba("I"), seed=1, nivel=5)
    assert isinstance(s1.politica_ia, PoliticaDificultad) and s1.politica_ia.error == 0.6
    assert not isinstance(s4.politica_ia, PoliticaDificultad)
    assert s5.politica_ia.nombre == "busqueda_vigilia"
    # El interruptor de bloqueos solo aplica bajo el nivel 5.
    s4b = SesionDesafio(_referencia_que_responde(), _MazoPrueba("H"), _MazoPrueba("I"), seed=1, nivel=4,
                        buscar_bloqueos=True)
    s5b = SesionDesafio(_referencia_que_responde(), _MazoPrueba("H"), _MazoPrueba("I"), seed=1, nivel=5,
                        buscar_bloqueos=True)
    assert s4b.politica_ia.nombre == "busqueda_bloqueos" and s5b.politica_ia.nombre == "busqueda_vigilia"
    assert s1.jugar()["nivelIa"] == 1


def test_autopsia_reproduce_la_partida_y_revisa_jugadas_marcadas():
    from myl_sim import autopsia as A
    ref = _referencia_que_responde()
    s = SesionDesafio(ref, _MazoPrueba("H"), _MazoPrueba("I"), seed=4, pausa=1e-6)
    resultado = s.jugar()
    cartas = (s.mazo_humano.cartas, s.mazo_ia.cartas)
    nombres = (s.mazo_humano.nombre, s.mazo_ia.nombre)
    # Repetir lo grabado da exactamente la misma partida.
    assert A.reproducir(cartas, nombres, s.seed, s.grabacion, metodos=s.metodos) == resultado["ganadorLado"]
    marcada = next(a for a in s.acciones_ia if a["decision"] is not None)
    informe = s.autopsia({marcada["id"]: "mala"}, resultado["ganadorLado"])
    assert any(r["voto"] == "mala" and r["paso"] == marcada["decision"] for r in informe["revisiones"])
    assert informe["resumen"]


def test_las_partidas_imaginarias_de_la_ia_no_se_publican_en_la_mesa():
    """Reporte 2026-11-14: en el T9 aparecían jugadas de la IA en la fase de
    bloqueo rival (Godofredo jugado y atacando): eran las partidas que simula
    la búsqueda de bloqueos, publicadas como si fueran reales."""
    from myl_sim.busqueda_bloqueos import _copia_muestreada

    ref = _referencia_que_responde()
    s = SesionDesafio(ref, _MazoPrueba("Humano"), _MazoPrueba("IA"), seed=3, pausa=1e-6)
    p = s.partida
    p.e.activo = 1
    copia = _copia_muestreada(p, 0, 7)
    antes = list(p.e.log)
    copia.anotar("J1 juega Duque Godofredo (coste 2)")
    copia.e.anotar("J1 ataca con Duque Godofredo")
    assert ref.acciones == [] and p.e.log == antes
    # El estado real sigue publicando.
    p.anotar("J1 juega Aliado 3 (coste 1)")
    assert ref.acciones and ref.acciones[-1][0] == "IA juega Aliado 3 (coste 1)"


def test_nivel_5_juega_una_partida_completa_y_se_puede_reproducir():
    """La IA buena en el Desafío: termina, no publica sus simulaciones y la
    grabación reproduce la misma partida (autopsia y aprendizaje dependen de eso)."""
    from myl_sim import autopsia as A
    ref = _referencia_que_responde()
    s = SesionDesafio(ref, _MazoPrueba("H"), _MazoPrueba("I"), seed=6, nivel=5, pausa=1e-6)
    resultado = s.jugar()
    assert resultado["politicaIa"] == "busqueda_vigilia" and resultado["ganadorLado"] in (0, 1, -1)
    assert all("analisisBloqueos" not in d for d in s.decisiones)
    cartas = (s.mazo_humano.cartas, s.mazo_ia.cartas)
    ganador = A.reproducir(cartas, (s.mazo_humano.nombre, s.mazo_ia.nombre), s.seed, s.grabacion,
                           metodos=s.metodos)
    assert ganador == resultado["ganadorLado"]
