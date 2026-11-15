"""Reportes de la partida Faraón guerrero vs Dragón
(simulations/UUOX7aK6rZyapX3iuHe1, seed 74639). Un test por arreglo, con las
cartas tal como están programadas en los mazos (simulator/cache)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import ModFuerza, Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, aliado, en_defensa, partida
from test_reportes_partida import YO

CACHE = Path(__file__).resolve().parents[1] / "cache"
_CARTAS = {}
for _f in ("mazo_pVmJzkf7GLl5bW3AwWht.json", "mazo_MrS4zt3yCdpPkAr2zsaE.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _CARTAS[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _CARTAS.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))

pytestmark = pytest.mark.skipif(len(_CARTAS) < 10, reason="faltan los mazos en simulator/cache")


def C(nombre):
    if nombre not in _CARTAS:
        pytest.skip(f"{nombre} ya no está en los mazos")
    return _CARTAS[nombre]


def _oros(p, i, n):
    for _ in range(n):
        en_zona(p, i, ORO, Zona.RESERVA)


# ── #1: Cultistas baraja a Ramsés IX, no al Guerrero Escorpión ─────────────
def test_cultistas_baraja_a_ramses_ix():
    p = partida()
    cands = [en_zona(p, 0, C(n), Zona.MANO) for n in ("Guerrero Escorpión", "Ramses IX", "Nephre-Ka", "Kamose el Guerrero")]
    luego = C("Cultistas del Dragón").habilidades[0]["luego"][0]
    assert YO.elegir_objetivos(p, 1, cands, 1, luego)[0].nombre == "Ramses IX"


def test_escorpion_solo_roba_con_otro_guerrero_en_mesa():
    p = partida()
    escorpion = en_defensa(p, 0, C("Guerrero Escorpi\u00f3n"))
    h = {**escorpion.habilidades[-1], "condicion": {
        "tipo": "aliados_arquetipo", "valor": 1, "op": ">=", "arquetipo": "Guerrero",
    }}
    p.ctx_disparadora = escorpion
    assert not hab.condicion_ok(p, 0, h)
    en_defensa(p, 0, C("Guerrero Medjay"))
    assert hab.condicion_ok(p, 0, h)


# ── #2: Guardia Gozosa no se baraja a sí misma ─────────────────────────────
def test_guardia_gozosa_no_se_baraja_a_si_misma():
    p = partida()
    gozosa = en_zona(p, 1, C("Guardia Gozosa"), Zona.CEMENTERIO)  # ya se destruyó para pagar
    toque = en_zona(p, 1, C("Toque de Pérsival"), Zona.CEMENTERIO)
    assert hab.candidatos(p, 1, gozosa, gozosa.habilidades[1]) == [toque]


# ── #3: Guardia Gozosa sin Aliados rivales no se juega ─────────────────────
def test_guardia_gozosa_sin_objetivo():
    p = partida()
    gozosa = en_zona(p, 1, C("Guardia Gozosa"), Zona.MANO)
    assert J._sin_objetivo_al_entrar(p, 1, gozosa)
    en_defensa(p, 0, C("Ramses IX"))
    assert not J._sin_objetivo_al_entrar(p, 1, gozosa)


# ── #4: Cruz Templaria no, si el Dragón de Magma de la mano ya alcanza ──────
def test_cruz_templaria_no_si_magma_alcanza():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    _oros(p, 1, 4)
    cruz = en_zona(p, 1, C("Cruz Templaria"), Zona.RESERVA)
    en_defensa(p, 0, C("Nephre-Ka"))
    activar = Jugada("activar", cruz, habilidad=0)
    magma = en_zona(p, 1, C("Dragón de Magma"), Zona.MANO)
    assert not YO._vale_la_pena(p, 1, activar)
    p.j(1).mano.remove(magma)
    assert J._remociones_a_mano(p, 1) == []
    # Sin Magma tampoco se quema la Cruz: Nival se destierra al final y ese
    # Aliado de fuerza 2, sin impacto adicional, no justifica perder la Cruz.
    assert not YO._vale_la_pena(p, 1, activar)


# ── #5: Vouivre no se baraja a sí misma ────────────────────────────────────
def test_vouivre_no_se_baraja_a_si_misma():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    vouivre = en_defensa(p, 1, C("Vouivre"))
    en_defensa(p, 0, C("Guerrero Bereber"))
    en_defensa(p, 0, C("Nephre-Ka"))
    assert not YO.usar_opcional(p, 1, vouivre, vouivre.habilidades[0])


def test_vouivre_se_juega_para_barajar_dos_rivales():
    p = partida()
    _oros(p, 1, 5)
    vouivre = en_zona(p, 1, C("Vouivre"), Zona.MANO)
    en_defensa(p, 1, C("Draig Ifanc"))
    en_defensa(p, 0, C("Guerrero Bereber"))
    en_defensa(p, 0, C("Nephre-Ka"))
    assert YO.usar_opcional(p, 1, vouivre, vouivre.habilidades[0])


def test_barajar_cementerio_conserva_lady_recuperable():
    p = partida()
    cathach = en_defensa(p, 1, C("Cathach"))
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    draco = en_zona(p, 1, C("Draco Putrido"), Zona.CEMENTERIO)
    milano = en_zona(p, 1, C("Milano Rojo"), Zona.CEMENTERIO)
    h = cathach.habilidades[0]
    elegidas = YO.elegir_objetivos(p, 1, [lady, draco, milano], 2, h)
    assert lady not in elegidas
    assert milano in elegidas


def test_nephre_ka_prefiere_killgharrah_a_lady_recuperable():
    p = partida()
    nephre = en_defensa(p, 1, C("Nephre-Ka"))
    lady = en_defensa(p, 0, C("Lady Calvaur"))
    kill = en_defensa(p, 0, C("Killgharrah"))
    h = nephre.habilidades[0]
    assert YO.elegir_objetivos(p, 1, [lady, kill], 1, h) == [kill]


def test_milano_se_guarda_si_no_hay_riesgo():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    milano = en_zona(p, 1, C("Milano Rojo"), Zona.RESERVA)
    en_zona(p, 1, aliado("Dragón de Aire", 4, 4, raza="Dragón"), Zona.CEMENTERIO)
    en_zona(p, 1, C("Draco Putrido"), Zona.CEMENTERIO)
    assert not YO._vale_la_pena(p, 1, Jugada("activar", milano, habilidad=0))


def test_no_juega_killgharrah_si_ya_hay_uno_vivo():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    _oros(p, 1, 6)
    en_defensa(p, 1, C("Killgharrah"))
    copia = en_zona(p, 1, C("Killgharrah"), Zona.MANO)
    assert not YO._vale_la_pena(p, 1, Jugada("jugar", copia))


def test_lady_sacrifica_ifanc_para_recuperarse_y_rampear_oro():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    ifanc = en_defensa(p, 1, C("Draig Ifanc"))
    en_zona(p, 1, ORO, Zona.MAZO)
    h = lady.habilidades[2]
    p.ctx_fuente_habilidad = lady
    assert YO.elegir_objetivos(p, 1, [ifanc], 1, h) == [ifanc]
    assert YO._puntaje(p, 1, Jugada("activar", lady, habilidad=2)) >= 25


def test_lady_sacrifica_putrido_para_desterrar_rival():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    putrido = en_defensa(p, 1, C("Draco Putrido"))
    ifanc = en_defensa(p, 1, C("Draig Ifanc"))
    del p.j(1).mazo[:]
    en_defensa(p, 0, C("Nephre-Ka"))
    h = lady.habilidades[2]
    p.ctx_fuente_habilidad = lady
    assert YO.elegir_objetivos(p, 1, [ifanc, putrido], 1, h) == [putrido]


def test_dragones_antes_de_vinculo_si_habilita_killgharrah():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    _oros(p, 1, 5)
    dragones = en_zona(p, 1, C("Dragones"), Zona.MANO)
    vinculo = en_zona(p, 1, C("Vinculo del Aullido"), Zona.MANO)
    en_zona(p, 1, C("Killgharrah"), Zona.MANO)
    assert YO.elegir_jugada(p, 1, [Jugada("oro", dragones), Jugada("oro", vinculo)]).carta is dragones


def test_furia_irracional_se_prioriza_si_el_refuerzo_es_letal():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(1).mazo[9:]
    en_defensa(p, 0, C("Guerrero Medjay"))
    en_defensa(p, 0, C("Kamose el Guerrero"))
    en_defensa(p, 0, C("Kamose el Guerrero"))
    furia = en_zona(p, 0, C("Furia Irracional"), Zona.CEMENTERIO)
    assert YO._puntaje(p, 0, Jugada("jugar", furia)) == 40.0


# ── #6: Adiós Belleza no se gasta en la Corona de Arturo ───────────────────
def test_adios_belleza_no_a_corona_de_arturo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    adios = en_zona(p, 0, C("Adiós Belleza"), Zona.MANO)
    corona = en_zona(p, 1, C("Corona de Arturo"), Zona.RESERVA)
    objetivos = J._objetivos_perder_habilidad(p, 0, adios, adios.habilidades[0])
    assert corona not in objetivos


# ── #7 / #11: Fe Sin Límite anula la Forma de Lince ────────────────────────
def test_fe_sin_limite_anula_forma_de_lince():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    atk = en_defensa(p, 0, C("Guerreros Egipcios"))
    p._mover(atk, Zona.ATAQUE)
    p.atacantes = [atk]
    en_zona(p, 0, C("Guerrero Escorpión"), Zona.MANO)  # le queda 1 carta en la mano
    forma = en_zona(p, 0, C("Forma de Lince"), Zona.MANO)
    _oros(p, 1, 1)
    fe = en_zona(p, 1, C("Fe Sin Limite"), Zona.MANO)
    assert YO.anular(p, 1, forma, [(fe, fe.habilidades[0])]) is not None


def test_medjay_potenciado_por_merodeador_ataca():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    # Atacar deja el castillo en tres y el rival amenaza tres. Sin inversión
    # previa la IA es conservadora; con dos mejoras debe concretar el ataque.
    del p.j(0).mazo[4:]
    medjay = en_defensa(p, 0, C("Guerrero Medjay"))
    en_defensa(p, 1, C("Nephre-Ka"))
    medjay.mods.extend([
        ModFuerza("sumar", 1, "hasta_fase_final", p.e.turno),
        ModFuerza("sumar", 1, "hasta_fase_final", p.e.turno),
    ])
    assert medjay in YO.elegir_atacantes(p, 0, [medjay])


# ── #8: el Codex se guarda para un daño crítico ────────────────────────────
def test_codex_se_guarda():
    p = partida()
    codex = en_zona(p, 1, C("Codex Arturicus"), Zona.PAGADO)
    h = codex.habilidades[0]
    del p.j(1).mazo[27:]
    assert not YO.usar_opcional(p, 1, codex, {**h, "_dano": 6})
    assert YO.usar_opcional(p, 1, codex, {**h, "_dano": 27})  # letal
    del p.j(1).mazo[12:]
    assert YO.usar_opcional(p, 1, codex, {**h, "_dano": 6})  # me deja en 6


# ── #9: Carnwennan no a Guerreros Egipcios si no lo voy a atacar ───────────
def test_carnwennan_no_a_guerreros_egipcios():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    carn = en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)
    en_defensa(p, 0, C("Guerreros Egipcios"))
    en_defensa(p, 1, C("Draig Ifanc"), listo=False)  # recién jugado: no ataca
    assert J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0]) == []


# ── #10: Cathach antes que Draig Ifanc contra Aliados chicos ───────────────
def test_cathach_antes_que_draig_ifanc():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    _oros(p, 1, 3)
    en_defensa(p, 0, C("Guerreros Egipcios"))
    en_defensa(p, 0, C("Guerrero Escorpión"))
    cathach = en_zona(p, 1, C("Cathach"), Zona.MANO)
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)
    assert YO._puntaje(p, 1, Jugada("jugar", cathach)) > YO._puntaje(p, 1, Jugada("jugar", draig))
