"""Reportes de la partida Dragón vs Faraón guerrero
(simulations/c0p0EPlNBD04P4XmftXb, seed 36082). Un test por arreglo, con las
cartas tal como están programadas en los mazos (simulator/cache)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
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


def C(nombre):
    if nombre not in _CARTAS:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _CARTAS[nombre]


def _dragon(p, oros, fase="vigilia"):
    p.e.activo, p.e.fase = 1, fase
    for _ in range(oros):
        en_zona(p, 1, ORO, Zona.RESERVA)
    p.j(1).oro_jugado = True


# ── #1/#2: Desleal a Neferite I antes que Cathach ──────────────────────────
def test_desleal_a_neferite():
    p = partida()
    _dragon(p, 4)
    en_defensa(p, 1, C("Dragón Nival"))
    neferite = en_defensa(p, 0, C("Neferite I"))
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    cathach = en_zona(p, 1, C("Cathach"), Zona.MANO)
    en_zona(p, 1, C("Capa De Invisibilidad"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", desleal), Jugada("jugar", cathach), Jugada("pasar")])
    assert elegida.carta is desleal
    assert YO.elegir_objetivos(p, 1, [neferite], 1, desleal.habilidades[0]) == [neferite]


# ── #3: con Dragones en juego no se baja otro (Errante) ────────────────────
def test_no_segundo_dragones():
    p = partida()
    _dragon(p, 2)
    p.j(1).oro_jugado = False
    en_zona(p, 1, C("Dragones"), Zona.RESERVA)
    otro = en_zona(p, 1, C("Dragones"), Zona.MANO)
    assert not any(j.carta is otro for j in p.jugadas_legales(1, "vigilia"))


# ── #4: Alquimista no retrasa una jugada de impacto tardía ─────────────────
def test_alquimista_tardio_no_se_adelanta_a_desleal():
    p = partida()
    _dragon(p, 5)  # 6 Oros: ya no es aceleración de curva temprana.
    en_defensa(p, 0, C("Guerrero Escorpión"))
    alq = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", alq), Jugada("jugar", desleal), Jugada("pasar")])
    assert elegida.carta is desleal


# ── #5/#6: Carnwennan no a Guerreros Egipcios (el Dragón no va a atacar) ────
def test_carnwennan_no_si_el_dragon_no_ataca():
    p = partida()
    _dragon(p, 3)
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    carn = en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)
    en_defensa(p, 1, C("Dragón Nival"))
    en_defensa(p, 0, C("Guerreros Egipcios"))
    en_defensa(p, 0, C("Neferite I"))
    en_defensa(p, 0, C("Guerrero Ptolemaico"))
    objetivos = J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0])
    assert all(t.nombre != "Guerreros Egipcios" for t in objetivos)


# ── #7/#8: Dragones no genera Oros que no se usan ───────────────────────────
def test_dragones_solo_con_un_dragon_caro_que_pagar():
    p = partida()
    _dragon(p, 2)
    dragones = en_zona(p, 1, C("Dragones"), Zona.RESERVA)
    en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)  # coste 3: no le sirve
    activar = Jugada("activar", dragones, habilidad=1)
    assert not YO._vale_la_pena(p, 1, activar)
    en_zona(p, 1, C("Dragón Nival"), Zona.MANO)  # coste 4: sí, si tiene a quién barrer
    for n in ("Guerrero Bereber", "Nephre-Ka"):
        en_defensa(p, 0, C(n))
    assert YO._vale_la_pena(p, 1, activar)


# ── #9: Draig Ifanc primero y después Lady desde el Cementerio ─────────────
def test_draig_antes_de_rescatar_a_lady():
    p = partida()
    _dragon(p, 7)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    en_defensa(p, 1, C("Dragón Nival"))
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)
    assert not J._rescate_conviene(p, 1, lady, lady.habilidades[2])  # no destruye al Nival
    p.j(1).mano.remove(draig)
    en_defensa(p, 1, C("Draig Ifanc"))  # ya lo bajé
    assert J._rescate_conviene(p, 1, lady, lady.habilidades[2])


# ── #10: Capa de Invisibilidad contra el Guerrero Medjay ────────────────────
def test_capa_contra_medjay():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    capa = en_zona(p, 1, C("Capa De Invisibilidad"), Zona.MANO)
    medjay = en_defensa(p, 0, C("Guerrero Medjay"))
    assert YO.responder(p, 1, medjay, [(capa, capa.habilidades[0])]) == 0
    flojo = en_defensa(p, 0, aliado("Peón", 1, 1))
    assert YO.responder(p, 1, flojo, [(capa, capa.habilidades[0])]) is None


# ── #11: Cruz Templaria no trae a Lady si está en la mano y se paga ────────
def test_cruz_no_trae_a_lady_si_esta_en_la_mano():
    p = partida()
    _dragon(p, 7)
    cruz = en_zona(p, 1, C("Cruz Templaria"), Zona.RESERVA)
    en_zona(p, 1, C("Lady Calvaur"), Zona.MANO)
    en_zona(p, 1, C("Lady Calvaur"), Zona.MAZO)
    en_defensa(p, 0, C("Ramsés II"))
    assert not YO._utiles_jugar_desde(p, 1, cruz, cruz.habilidades[0])


# ── #12: con el Codex listo no bloquea con Cathach ──────────────────────────
def test_no_bloquea_con_cathach_si_tiene_codex():
    p = partida()
    p.e.activo = 0
    del p.j(1).mazo[11:]
    en_zona(p, 1, C("Codex Arturicus"), Zona.PAGADO)
    cathach = en_defensa(p, 1, C("Cathach"))
    atk = [en_defensa(p, 0, C(n)) for n in ("Guerrero Medjay", "Merodeador de las arenas", "Ramses IX", "Guerrero Bereber")]
    assert YO.elegir_bloqueos(p, 1, atk, [cathach]) == {}


# ── #13: Lady desde la mano antes que Draig Ifanc ──────────────────────────
def test_lady_antes_que_draig():
    p = partida()
    _dragon(p, 4)  # 5 Oros + Dragones = 7
    en_zona(p, 1, C("Dragones"), Zona.RESERVA)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.MANO)
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)
    for n in ("Guerrero Medjay", "Ramses IX", "Guerrero Bereber"):
        en_defensa(p, 0, C(n))
    jugadas = [Jugada("jugar", draig), Jugada("pasar")]
    if p.puede_pagar(1, lady):
        jugadas.insert(0, Jugada("jugar", lady))
    else:
        jugadas.insert(0, Jugada("activar", p.j(1).reserva[-1], habilidad=1))
    elegida = YO.elegir_jugada(p, 1, jugadas)
    assert elegida.carta is lady or (elegida.tipo == "activar" and elegida.carta.nombre == "Dragones")


# ── Draig Ifanc + Lady: prioridad temprana hasta poder pagar a Lady ────────
def test_draig_lady_es_prioridad_temprana():
    p = partida()
    _dragon(p, 2)  # turno 2: 3 Oros
    en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)
    alquimista = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    otro = en_zona(p, 1, C("Cathach"), Zona.MANO)
    temprano = YO._puntaje(p, 1, Jugada("jugar", draig))
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", alquimista), Jugada("jugar", otro),
                                    Jugada("jugar", draig), Jugada("pasar")]).carta is draig
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)  # 7 Oros: ya puedo pagar a Lady
    assert J._capacidad_lady(p, 1)
    assert YO._puntaje(p, 1, Jugada("jugar", draig)) < temprano - 8


def test_frena_el_agro_antes_que_el_combo():
    p = partida()
    _dragon(p, 4)
    en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.MANO)
    bola = en_zona(p, 1, C("Bola De Fuego"), Zona.MANO)
    for n in ("Guerrero Medjay", "Ramses IX"):
        en_defensa(p, 0, C(n))
    assert J._frenar_agro_primero(p, 1, draig)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", draig), Jugada("jugar", bola), Jugada("pasar")])
    assert elegida.carta is bola


# ══ Partida 3W4djxGcupObgr8f5rRp ═══════════════════════════════════════════

def test_nival_se_guarda_contra_uno_y_se_juega_contra_tres():
    p = partida()
    _dragon(p, 4)
    nival = en_zona(p, 1, C("Dragón Nival"), Zona.MANO)
    draco = en_zona(p, 1, C("Draco Cometa"), Zona.MANO)
    en_defensa(p, 0, C("Guerrero Bereber"))
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", nival), Jugada("jugar", draco), Jugada("pasar")]).carta is draco
    for n in ("Merodeador de las arenas", "Guerreros Egipcios"):
        en_defensa(p, 0, C(n))
    assert J._victimas_barrida(p, 1, nival) == (3, 0)
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", nival), Jugada("jugar", draco), Jugada("pasar")]).carta is nival


def test_draig_trae_mercaderes_con_corona_de_arturo_y_codex_contra_agro():
    p = partida()
    _dragon(p, 3)
    draig = en_zona(p, 1, C("Draig Ifanc"), Zona.CEMENTERIO)
    h = draig.habilidades[1]
    cands = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Corona de Arturo", "Codex Arturicus", "Mercaderes")]
    for n in ("Ramses IX", "Guerrero Bereber", "Nephre-Ka", "Merodeador de las arenas"):
        en_zona(p, 0, C(n), Zona.MAZO)  # el Faraón guerrero es un mazo agro
    assert YO.elegir_objetivos(p, 1, cands, 1, h)[0].nombre == "Codex Arturicus"
    en_zona(p, 1, C("Corona de Arturo"), Zona.RESERVA)
    en_defensa(p, 1, C("Dragón Nival"))
    en_defensa(p, 1, C("Cathach"))
    assert YO.elegir_objetivos(p, 1, cands, 1, h)[0].nombre == "Mercaderes"


def test_corona_faraonica_se_paga_despues_de_latigo():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(0).reserva[:]
    corona = en_zona(p, 0, C("Corona Faraónica"), Zona.RESERVA)
    for n in ("Látigo y Bastón", "Látigo y Bastón"):
        en_zona(p, 0, C(n), Zona.RESERVA)
    kamose = en_zona(p, 0, C("Kamose el Guerrero"), Zona.MANO)
    p._pagar_oro(0, 2, carta=kamose)
    assert corona.zona == Zona.RESERVA


# ══ Partida EZMtIBHwyZqoHrC2tc9k ═══════════════════════════════════════════

def test_dragones_no_se_activa_para_un_nival_contra_uno():
    p = partida()
    _dragon(p, 2)
    dragones = en_zona(p, 1, C("Dragones"), Zona.RESERVA)
    en_zona(p, 1, C("Dragón Nival"), Zona.MANO)
    en_zona(p, 1, C("Draco Cometa"), Zona.MANO)
    en_defensa(p, 0, C("Guerrero Bereber"))
    assert not YO._vale_la_pena(p, 1, Jugada("activar", dragones, habilidad=1))


def test_lady_no_se_descarta_si_ya_se_puede_pagar():
    p = partida()
    _dragon(p, 4)
    en_zona(p, 1, C("Dragones"), Zona.RESERVA)  # 6 Oros con Dragones
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.MANO)
    otras = [en_zona(p, 1, C(n), Zona.MANO) for n in ("Capa De Invisibilidad", "Estrella De Belén")]
    assert lady not in YO.elegir_descartes(p, 1, [lady, *otras], 1)


def test_carnwennan_no_a_quien_no_puede_bloquear():
    # #4 EZMt: los Guerreros Egipcios están en la línea de ataque: este turno
    # no bloquean, su habilidad al bloquear no importa. No se quema un Oro.
    p = partida()
    _dragon(p, 7)
    carn = en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)
    en_defensa(p, 1, C("Dragón Nival"))
    egip = en_zona(p, 0, C("Guerreros Egipcios"), Zona.ATAQUE)
    assert egip not in J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0])


def test_dragon_no_ataca_si_le_llena_el_cementerio_al_faraon():
    p = partida()
    p.e.activo, p.e.fase = 1, "declaracion_ataque"
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    en_zona(p, 0, C("Jinetes de Fuego"), Zona.MAZO)  # se juega desde el Cementerio
    nival = en_defensa(p, 1, C("Dragón Nival"))
    assert J._rival_usa_cementerio(p, 0)
    assert YO.elegir_atacantes(p, 1, [nival]) == []


def test_lady_destierra_lo_mas_peligroso():
    p = partida()
    _dragon(p, 7)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.MANO)
    nk = [en_defensa(p, 0, C("Nephre-Ka")) for _ in range(2)]
    mero = en_defensa(p, 0, C("Merodeador de las arenas"))
    egip = en_defensa(p, 0, C("Guerreros Egipcios"))
    elegidos = YO.elegir_objetivos(p, 1, [*nk, mero, egip], 2, lady.habilidades[1])
    assert set(c.nombre for c in elegidos) == {"Merodeador de las arenas", "Guerreros Egipcios"}


def test_carnwennan_no_a_egipcios_ya_declarados_atacantes():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    carn = en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)
    egip = en_zona(p, 0, C("Guerreros Egipcios"), Zona.ATAQUE)
    p.atacantes, p.bloqueos = [egip], {}
    assert egip not in J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0])


def test_carnwennan_al_merodeador_bloqueado_por_uno_que_le_gana():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    carn = en_zona(p, 1, C("Carnwennan"), Zona.RESERVA)
    mero = en_zona(p, 0, C("Merodeador de las arenas"), Zona.ATAQUE)
    en_zona(p, 0, ORO, Zona.CEMENTERIO)  # tiene con qué subirse la fuerza
    nival = en_defensa(p, 1, C("Dragón Nival"))
    p.atacantes, p.bloqueos = [mero], {mero.uid: nival}
    assert mero in J._objetivos_perder_habilidad(p, 1, carn, carn.habilidades[0])


def test_nephre_ka_fuera_del_juego_no_frena_el_ataque():
    p = partida()
    del p.j(0).mazo[:]
    nk = en_zona(p, 0, C("Nephre-Ka"), Zona.MAZO)
    assert J._rival_usa_cementerio(p, 0)
    p.j(0).mazo.remove(nk)
    en_zona(p, 0, C("Nephre-Ka"), Zona.DESTIERRO)
    en_zona(p, 0, C("Nephre-Ka"), Zona.CEMENTERIO)
    assert not J._rival_usa_cementerio(p, 0)


def test_codex_fuera_del_rango_de_papiros_y_jinetes():
    # Con Papiros en juego, un Jinetes en el Cementerio y 6 Oros, el Faraón me
    # hace 9 sin atacar: un ataque que me deja en 6 se frena con el Codex.
    p = partida()
    p.e.activo, p.e.fase = 0, "asignacion_dano"
    codex = en_zona(p, 1, C("Codex Arturicus"), Zona.PAGADO)
    for _ in range(4):
        en_zona(p, 0, ORO, Zona.RESERVA)
    en_zona(p, 0, C("Papiros de Lahun"), Zona.RESERVA)
    en_zona(p, 0, C("Jinetes de Fuego"), Zona.CEMENTERIO)
    assert J._quemado_rival(p, 1) >= 6
    del p.j(1).mazo[12:]
    assert YO.usar_opcional(p, 1, codex, {**codex.habilidades[0], "_dano": 6})  # quedaría en 6


# ── Cinturón de Lady Ann en la Reserva contra el Faraón guerrero ────────────
def test_cinturon_en_reserva_frena_el_cementerio_del_faraon():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    for _ in range(4):
        en_zona(p, 0, ORO, Zona.RESERVA)
    jinetes = en_zona(p, 0, C("Jinetes de Fuego"), Zona.CEMENTERIO)
    mero = en_defensa(p, 0, C("Merodeador de las arenas"))
    k = next(i for i, h in enumerate(mero.habilidades) if h.get("accion") == "modificarFuerza")
    assert any(j.carta is jinetes for j in p.jugadas_legales(0, "vigilia"))
    assert hab.puede_pagar_costo(p, 0, mero, mero.habilidades[k])
    cint = en_zona(p, 1, C("Cinturón De Lady Ann"), Zona.RESERVA)
    assert not any(j.carta is jinetes for j in p.jugadas_legales(0, "vigilia"))
    assert not hab.puede_pagar_costo(p, 0, mero, mero.habilidades[k])
    p._mover(cint, Zona.PAGADO)  # pagado no sirve: tiene que estar en la Reserva
    assert hab.puede_pagar_costo(p, 0, mero, mero.habilidades[k])


def test_dragon_baja_el_cinturon_en_turnos_medios():
    p = partida()
    _dragon(p, 2)
    p.j(1).oro_jugado = False
    for n in ("Jinetes de Fuego", "Nephre-Ka"):
        en_zona(p, 0, C(n), Zona.MAZO)
    cint = en_zona(p, 1, C("Cinturón De Lady Ann"), Zona.MANO)
    otro = en_zona(p, 1, C("Estrella De Belén"), Zona.MANO)
    assert not J._cementerio_rival_sirve(p, 1)  # Cementerio vacío: el Cinturón puede esperar
    for n in ("Nephre-Ka", "Guerrero Bereber", "Ramses IX"):
        en_zona(p, 0, C(n), Zona.CEMENTERIO)  # turnos medios: ya tiene con qué
    elegida = YO.elegir_jugada(p, 1, [Jugada("oro", otro), Jugada("oro", cint), Jugada("pasar")])
    assert elegida.carta is cint


# ══ Partida m8iiOEPVDupI6fdidUHw ═══════════════════════════════════════════

def test_bereber_da_mas_2_a_otro_guerrero():
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    ber = en_defensa(p, 0, C("Guerrero Bereber"))
    yo_mismo = next(h for h in ber.habilidades if (h.get("objetivo") or {}).get("quien") == "esta_carta")
    assert YO.usar_opcional(p, 0, ber, yo_mismo)  # único Guerrero: se bonifica a sí mismo
    en_defensa(p, 0, C("Guerrero Escorpión"))
    assert not YO.usar_opcional(p, 0, ber, yo_mismo)  # mejor +2 al Escorpión
    en_defensa(p, 1, aliado("Muro", 2, hab.fuerza(p, ber)))  # el +1 le gana a un bloqueador igual
    assert YO.usar_opcional(p, 0, ber, yo_mismo)


def test_killgharrah_baraja_las_lady_si_tengo_la_llama():
    p = partida()
    _dragon(p, 3)
    kill = en_defensa(p, 1, C("Killgharrah"))
    h = next(x for x in kill.habilidades if x.get("accion") == "barajar")
    ladies = [en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO) for _ in range(2)]
    kills = [en_zona(p, 1, C("Killgharrah"), Zona.CEMENTERIO) for _ in range(2)]
    en_zona(p, 1, C("La Llama Fría"), Zona.MANO)
    elegidas = YO.elegir_objetivos(p, 1, ladies + kills, 2, h)
    assert any(c.nombre == "Lady Calvaur" for c in elegidas)


def test_usa_los_oros_de_dragones_antes_que_los_normales():
    p = partida()
    _dragon(p, 3)
    p.j(1).oros_restringidos.append([2, ["Aliado"], "Dragón", 4])
    magma = en_zona(p, 1, C("Dragón de Magma"), Zona.MANO)
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    en_defensa(p, 0, C("Guerrero Escorpión"))
    en_defensa(p, 0, C("Ramses IX"))
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", desleal), Jugada("jugar", magma), Jugada("pasar")])
    assert elegida.carta is magma


# ══ Partida smWjJgJM4YY1WtcVcB1M ═══════════════════════════════════════════

def test_turno_1_no_activa_dragones_sin_nada_que_pagar():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    del p.j(1).reserva[:]
    en_zona(p, 1, ORO, Zona.RESERVA)
    drag = en_zona(p, 1, C("Dragones"), Zona.RESERVA)
    p.j(1).oro_jugado = True
    for n in ("Ma Arrat An-Numán", "Lady Calvaur", "Guardia Gozosa", "Capa De Invisibilidad", "Gaspar", "Dragón de Magma"):
        en_zona(p, 1, C(n), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, p.jugadas_legales(1, "vigilia"))
    assert not (elegida.tipo == "activar" and elegida.carta is drag)


def test_mulligan_dos_dragones_cuentan_como_un_oro():
    p = partida()
    p.e.activo = 1
    del p.j(1).mano[:]
    for n in ("Dragones", "Dragones", "Ma Arrat An-Numán", "Lady Calvaur", "Guardia Gozosa",
              "Capa De Invisibilidad", "Gaspar", "Dragón de Magma"):
        en_zona(p, 1, C(n), Zona.MANO)
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    assert not YO.quedarse_mano(p, 1)


# ══ Partida mBp5JdWNLa7YWRWJQZ5g ═══════════════════════════════════════════

def test_vinculo_descarta_lady_y_no_la_bola_de_fuego():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for n in ("Ramses IX", "Guerrero Bereber", "Nephre-Ka", "Merodeador de las arenas"):
        en_zona(p, 0, C(n), Zona.MAZO)  # el Faraón guerrero es agro
    mano = [en_zona(p, 1, C(n), Zona.MANO) for n in (
        "Cultistas del Dragón", "Corona de Arturo", "Draco Cometa", "Lady Calvaur", "Desleal",
        "La Llama Fría", "Dragón Nival", "Bola De Fuego")]
    assert [c.nombre for c in YO.elegir_descartes(p, 1, mano, 1)] != ["Bola De Fuego"]


def test_gaspar_baraja_un_oro_si_faltan_oros():
    p = partida()
    p.e.activo, p.e.fase, p.e.turno = 1, "vigilia", 9  # su 5º turno con 2 Oros: muy corto
    del p.j(1).reserva[:]
    en_zona(p, 1, ORO, Zona.RESERVA)
    en_zona(p, 1, C("Corona de Arturo"), Zona.RESERVA)
    gaspar = en_defensa(p, 1, C("Gaspar"))
    una, dos = gaspar.habilidades
    for n in ("Draco Cometa", "Lady Calvaur"):
        en_zona(p, 1, C(n), Zona.CEMENTERIO)
    oro = en_zona(p, 1, C("Vinculo del Aullido"), Zona.CEMENTERIO)
    assert J._faltan_oros(p, 1)
    assert not J._otra_opcion_mejor(p, 1, gaspar, una)  # la de 1 carta sí vale
    assert J._otra_opcion_mejor(p, 1, gaspar, dos)      # la de 2 Dragones no
    p.ctx_fuente_habilidad = gaspar
    cands = [c for c in p.j(1).cementerio]
    assert YO.elegir_objetivos(p, 1, cands, 1, una) == [oro]


def test_gaspar_baraja_dragones_que_remueven():
    p = partida()
    _dragon(p, 5)  # Oros al día: baraja 2 Dragones
    gaspar = en_defensa(p, 1, C("Gaspar"))
    una, dos = gaspar.habilidades
    cands = [en_zona(p, 1, C(n), Zona.CEMENTERIO) for n in ("Killgharrah", "Lady Calvaur", "Dragón de Magma", "Cathach")]
    en_zona(p, 1, C("Vinculo del Aullido"), Zona.CEMENTERIO)
    assert J._otra_opcion_mejor(p, 1, gaspar, una)
    p.ctx_fuente_habilidad = gaspar
    elegidos = YO.elegir_objetivos(p, 1, cands, 2, dos)
    assert set(c.nombre for c in elegidos) == {"Dragón de Magma", "Cathach"}


# ══ Partida qSMgOfKBRUH9Bm3iYFpf ═══════════════════════════════════════════

def test_dragon_guarda_oros_para_toque_y_bola():
    p = partida()
    _dragon(p, 2)  # 3 Oros: Toque (1) + Bola (2)
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    for n in ("Ramses IX", "Guerrero Bereber", "Nephre-Ka", "Merodeador de las arenas"):
        en_zona(p, 0, C(n), Zona.MAZO)
    draco = en_zona(p, 1, C("Draco Cometa"), Zona.MANO)
    en_zona(p, 1, C("Toque de Pérsival"), Zona.MANO)
    en_zona(p, 1, C("Bola De Fuego"), Zona.MANO)
    en_defensa(p, 0, C("Guerrero Bereber"))
    assert J._reserva_reactiva(p, 1) == 3
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", draco), Jugada("pasar")]).tipo == "pasar"


def test_merodeador_no_destierra_la_furia_irracional():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    mero = en_defensa(p, 0, C("Merodeador de las arenas"))
    p._mover(mero, Zona.ATAQUE)
    p.atacantes, p.bloqueos = [mero], {}
    k = next(i for i, h in enumerate(mero.habilidades) if h.get("accion") == "modificarFuerza")
    furia = en_zona(p, 0, C("Furia Irracional"), Zona.CEMENTERIO)
    assert J._vale_en_cementerio(furia)
    assert not YO._vale_la_pena(p, 0, Jugada("activar", mero, habilidad=k))
    otra = en_zona(p, 0, C("Guerrero Bereber"), Zona.CEMENTERIO)
    assert YO.elegir_destierro_costo(p, 0, mero, [furia, otra], 1) == [otra]


# ══ Partida i4b3F1y1JHGtaVerlS3F ═══════════════════════════════════════════

def test_bola_y_toque_contra_dos_atacantes():
    p = partida()
    p.e.activo, p.e.fase = 0, "guerra_talismanes"
    for _ in range(2):
        en_zona(p, 1, ORO, Zona.RESERVA)  # 3 Oros con el inicial
    atk = [en_defensa(p, 0, C(n)) for n in ("Guerrero Bereber", "Guerrero Medjay")]
    for a in atk:
        p._mover(a, Zona.ATAQUE)
    p.atacantes, p.bloqueos = atk, {}
    p.ataco_este_turno = {a.uid for a in atk}
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    bola = en_zona(p, 1, C("Bola De Fuego"), Zona.MANO)
    toque = en_zona(p, 1, C("Toque de Pérsival"), Zona.MANO)
    js = [Jugada("jugar", x) for x in (desleal, bola, toque)] + [Jugada("pasar")]
    assert YO.elegir_jugada(p, 1, js).carta is toque  # la barata primero, después la Bola


def test_cultistas_saca_lo_que_da_recursos_o_dano():
    p = partida()
    cands = [en_zona(p, 0, C(n), Zona.MANO) for n in ("Nephre-Ka", "Guerrero Medjay", "Amosis I")]
    luego = C("Cultistas del Dragón").habilidades[0]["luego"][0]
    assert YO.elegir_objetivos(p, 1, cands, 1, luego)[0].nombre in ("Guerrero Medjay", "Amosis I")


def test_llama_trae_lady_y_no_cathach():
    p = partida()
    _dragon(p, 4)
    llama = en_zona(p, 1, C("La Llama Fría"), Zona.MANO)
    cands = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Cathach", "Lady Calvaur")]
    for n in ("Nephre-Ka", "Guerreros Egipcios", "Ramsés II", "Nephre-Ka", "Ptolomeo II"):
        en_defensa(p, 0, C(n))
    assert YO.elegir_objetivos(p, 1, cands, 1, llama.habilidades[0])[0].nombre == "Lady Calvaur"


def test_bereber_mas_2_al_egipcio_con_muchos_atacantes():
    p = partida()
    p.e.activo, p.e.fase = 0, "declaracion_ataque"
    ber = en_defensa(p, 0, C("Guerrero Bereber"))
    otros = [en_defensa(p, 0, C(n)) for n in ("Guerreros Egipcios", "Nephre-Ka", "Ramsés II")]
    for a in [ber, *otros]:
        p._mover(a, Zona.ATAQUE)
    p.atacantes = [ber, *otros]
    en_defensa(p, 1, aliado("Muro", 2, hab.fuerza(p, ber)))  # un solo bloqueador, de su fuerza
    yo_mismo = next(h for h in ber.habilidades if (h.get("objetivo") or {}).get("quien") == "esta_carta")
    assert not YO.usar_opcional(p, 0, ber, yo_mismo)


# ══ Partida 1uF1ASva9GyXuPAUEejK ═══════════════════════════════════════════

def _faraon_agro(p):
    for n in ("Ramses IX", "Guerrero Bereber", "Nephre-Ka", "Merodeador de las arenas"):
        en_zona(p, 0, C(n), Zona.MAZO)


def _dragon_lento(p):
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)


def test_desleal_no_se_lleva_los_oros_del_toque_y_la_bola():
    p = partida()
    _dragon(p, 2)  # 3 Oros
    _faraon_agro(p)
    _dragon_lento(p)
    en_zona(p, 0, C("Guerrero Bereber"), Zona.ATAQUE)
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    bola = en_zona(p, 1, C("Bola De Fuego"), Zona.MANO)
    en_zona(p, 1, C("Toque de Pérsival"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", desleal), Jugada("jugar", bola), Jugada("pasar")])
    assert elegida.carta is not desleal  # la Bola (deja 1 para el Toque) o pasar


def test_alquimista_no_se_frena_y_trae_estrella():
    p = partida()
    _dragon(p, 2)
    _faraon_agro(p)
    _dragon_lento(p)
    alq = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MANO)
    en_zona(p, 1, C("Toque de Pérsival"), Zona.MANO)
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", alq), Jugada("jugar", gaspar), Jugada("pasar")]).carta is alq
    cands = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Codex Arturicus", "Estrella De Belén")]
    p.ctx_fuente_habilidad = alq
    assert YO.elegir_objetivos(p, 1, cands, 1, alq.habilidades[0])[0].nombre == "Estrella De Belén"


def test_draco_cometa_no_bloquea_si_sostiene_el_candado():
    p = partida()
    p.e.activo = 0
    draco = en_defensa(p, 1, C("Draco Cometa"))
    amosis = en_defensa(p, 0, C("Amosis I"))
    amosis.sin_habilidad_hasta, amosis.sin_habilidad_fuente = "mientras_en_juego", draco.uid
    mero = en_defensa(p, 0, C("Merodeador de las arenas"))
    assert YO.elegir_bloqueos(p, 1, [mero], [draco]) == {}


# ══ Partida UBsSIWchnJZGR1VoxrtY ═══════════════════════════════════════════

def test_guarda_toque_y_bola_si_el_rival_tiene_la_corona():
    p = partida()
    _dragon(p, 2)
    _faraon_agro(p)
    _dragon_lento(p)
    en_zona(p, 0, C("Corona Faraónica"), Zona.RESERVA)
    en_zona(p, 0, C("Guerrero Medjay"), Zona.MANO)
    en_zona(p, 0, C("Guerrero Bereber"), Zona.ATAQUE)
    bola = en_zona(p, 1, C("Bola De Fuego"), Zona.MANO)
    en_zona(p, 1, C("Toque de Pérsival"), Zona.MANO)
    assert J._atacantes_esperados(p, 1) >= 2
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", bola), Jugada("pasar")]).tipo == "pasar"


def test_llama_fria_no_para_traer_a_draig():
    p = partida()
    _dragon(p, 5)
    llama = en_zona(p, 1, C("La Llama Fría"), Zona.MANO)
    del p.j(1).mazo[:]
    en_zona(p, 1, C("Draig Ifanc"), Zona.MAZO)
    en_defensa(p, 0, C("Merodeador de las arenas"))
    assert not YO._jugar_desde_conviene(p, 1, llama, llama.habilidades[0], 0)
    en_zona(p, 1, C("Lady Calvaur"), Zona.MAZO)
    assert YO._jugar_desde_conviene(p, 1, llama, llama.habilidades[0], 0)


def test_lady_aunque_haya_oros_reservados():
    p = partida()
    _dragon(p, 6)  # 7 Oros
    _faraon_agro(p)
    _dragon_lento(p)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.MANO)
    draco = en_zona(p, 1, C("Draco Cometa"), Zona.MANO)
    en_zona(p, 1, C("Desleal"), Zona.MANO)
    for n in ("Merodeador de las arenas", "Guerrero Escorpión", "Guerrero Bereber"):
        en_zona(p, 0, C(n), Zona.ATAQUE)
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", lady), Jugada("jugar", draco), Jugada("pasar")]).carta is lady


def test_desleal_no_al_ya_inhabilitado():
    p = partida()
    _dragon(p, 3)
    desleal = en_zona(p, 1, C("Desleal"), Zona.MANO)
    esc = en_zona(p, 0, C("Guerrero Escorpión"), Zona.DEFENSA)
    esc.sin_habilidad_hasta = "mientras_en_juego"
    esc.estados += [{"modo": "no_puede_atacar", "duracion": "permanente"},
                    {"modo": "no_puede_bloquear", "duracion": "permanente"}]
    mero = en_zona(p, 0, C("Merodeador de las arenas"), Zona.DEFENSA)
    assert YO.elegir_objetivos(p, 1, [esc, mero], 1, desleal.habilidades[0]) == [mero]


def test_corona_faraonica_pagada_tambien_cuenta():
    p = partida()
    en_zona(p, 0, C("Corona Faraónica"), Zona.PAGADO)
    en_zona(p, 0, C("Guerrero Medjay"), Zona.MANO)
    en_zona(p, 0, C("Guerrero Bereber"), Zona.ATAQUE)
    assert J._atacantes_esperados(p, 1) == 2


def test_ma_arrat_saca_varios_aunque_sea_talisman():
    p = partida()
    ma = en_zona(p, 1, C("Ma Arrat An-Numán"), Zona.MANO)
    for n in ("Merodeador de las arenas", "Guerrero Escorpión", "Guerrero Bereber"):
        en_zona(p, 0, C(n), Zona.ATAQUE)
    assert J._saca_varios(p, 1, ma)


# ══ Partida dZ3ANqNBkKHfFQCQfSjX ═══════════════════════════════════════════

def test_cultistas_con_la_mesa_rival_vacia():
    p = partida()
    _dragon(p, 2)
    del p.j(0).mano[:]
    for n in ("Amosis I", "Nephre-Ka", "Biblioteca Eterna", "Guerrero Ptolemaico"):
        en_zona(p, 0, C(n), Zona.MANO)
    cult = en_zona(p, 1, C("Cultistas del Dragón"), Zona.MANO)
    draco = en_zona(p, 1, C("Draco Cometa"), Zona.MANO)
    assert YO._puntaje(p, 1, Jugada("jugar", cult)) > YO._puntaje(p, 1, Jugada("jugar", draco))


def test_cultistas_presiona_la_ultima_carta_de_agro():
    p = partida()
    _dragon(p, 2)
    del p.j(0).mano[:]
    en_zona(p, 0, C("Amosis I"), Zona.MANO)
    cult = en_zona(p, 1, C("Cultistas del Dragón"), Zona.MANO)
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", cult), Jugada("jugar", gaspar), Jugada("pasar")])
    assert elegida.carta is cult


def test_cultistas_no_fuerza_una_mano_rival_grande():
    p = partida()
    _dragon(p, 2)
    for _ in range(6):
        en_zona(p, 0, C("Amosis I"), Zona.MANO)
    assert not J._cultista_tiene_mano(p, 1)


def test_nival_no_se_juega_sin_nadie_que_barrer():
    p = partida()
    _dragon(p, 3)
    nival = en_zona(p, 1, C("Dragón Nival"), Zona.MANO)
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MANO)
    en_defensa(p, 0, C("Guerrero Ptolemaico"))  # fuerza 3: Nival no lo destruye
    assert YO._puntaje(p, 1, Jugada("jugar", nival)) < YO._puntaje(p, 1, Jugada("jugar", gaspar))


# ══ Partida FtbjPveCJbzHJR2lo8ew (Héroe vs Caballero Armas) ════════════════
_HEROE = {}
for _f in ("mazo_LzFuAgHhbZv4qdaSrskn.json", "mazo_PQQzjvNznnYBs4VA3nz5.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _HEROE[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _HEROE.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))


def H(nombre):
    if nombre not in _HEROE:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _HEROE[nombre]


def test_orfeo_no_nombra_una_unica_en_mesa():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    orfeo = en_defensa(p, 1, H("Orfeo"))
    en_defensa(p, 0, H("Rey Arturo Pendragón"))
    del p.j(0).mazo[:]
    en_zona(p, 0, H("Yvain Del León"), Zona.MAZO)
    p.ctx_fuente_habilidad = orfeo
    assert YO.elegir_carta(p, 1, ["Rey Arturo Pendragón", "Yvain Del León"]) == "Yvain Del León"
    k = next(i for i, h in enumerate(orfeo.habilidades) if (h.get("objetivo") or {}).get("nombrarCarta"))
    assert YO._vale_la_pena(p, 1, Jugada("activar", orfeo, habilidad=k))


def test_idmon_primero_y_rey_minos_antes_que_ganimedes():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(3):
        en_zona(p, 1, ORO, Zona.RESERVA)
    idmon = en_defensa(p, 1, H("Idmon el Adivino"))
    k = next(i for i, h in enumerate(idmon.habilidades) if h.get("accion") == "mirarTope")
    minos = en_zona(p, 1, H("Rey Minos"), Zona.MANO)
    gani = en_zona(p, 1, H("Ganimedes"), Zona.MANO)
    en_defensa(p, 0, H("Sir Gaheris"))
    js = [Jugada("activar", idmon, habilidad=k), Jugada("jugar", minos), Jugada("jugar", gani), Jugada("pasar")]
    assert YO.elegir_jugada(p, 1, js).tipo == "activar"
    assert YO.elegir_jugada(p, 1, js[1:]).carta is minos


# ══ Partida tuK8t4d0FBzIPKKuKMZf (Héroe vs Caballero Armas) ════════════════
def test_exceso_de_mano_guarda_los_oros_y_bota_el_repetido():
    p = partida()
    p.e.activo, p.e.fase = 1, "final"
    en_zona(p, 1, ORO, Zona.RESERVA)
    en_zona(p, 1, H("Ave de Hera"), Zona.RESERVA)
    mano = [en_zona(p, 1, H(n), Zona.MANO) for n in (
        "Idmon el Adivino", "Focea", "Teseo de Atenas", "Teseo de Atenas", "Ganimedes",
        "Epicuro De Samos", "Caja de Pandora", "Trono Dorado", "Heroes")]
    assert YO.elegir_descartes(p, 1, mano, 1)[0].nombre == "Teseo de Atenas"


def test_focea_no_vale_como_destruir_y_teseo_va_primero():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oro_jugado = True
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    en_defensa(p, 1, H("Rey Minos"))
    en_defensa(p, 1, H("Ganimedes"))
    yvain = en_defensa(p, 0, H("Yvain Del León"))
    espada = en_zona(p, 0, H("Espada Larga"), Zona.DEFENSA)
    p.j(0).defensa.remove(espada)
    espada.portador = yvain.uid
    p.e.portadas.append(espada)
    focea = en_zona(p, 1, H("Focea"), Zona.MANO)
    teseo = en_zona(p, 1, H("Teseo de Atenas"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", focea), Jugada("jugar", teseo), Jugada("pasar")])
    assert elegida.carta is teseo


def test_idmon_no_ataca_a_morir_aunque_sobren_atacantes():
    p = partida()
    p.e.activo, p.e.fase = 1, "declaracion_ataque"
    minos = en_defensa(p, 1, H("Rey Minos"))
    gani = en_defensa(p, 1, H("Ganimedes"))
    idmon = en_defensa(p, 1, H("Idmon el Adivino"))
    en_defensa(p, 0, H("Melisende"))
    atacan = YO.elegir_atacantes(p, 1, [minos, gani, idmon])
    assert idmon not in atacan and minos in atacan and gani in atacan


def test_bedivere_no_nombra_una_unica_en_mesa():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    bedivere = en_defensa(p, 0, H("Sir Bedivere"))
    en_defensa(p, 1, H("Marco Antonio"))
    del p.j(1).mazo[:]
    en_zona(p, 1, H("Ganimedes"), Zona.MAZO)
    en_zona(p, 1, H("Caja de Pandora"), Zona.MAZO)
    p.ctx_fuente_habilidad = bedivere
    assert YO.elegir_carta(p, 0, ["Caja de Pandora", "Ganimedes", "Marco Antonio"]) == "Ganimedes"


def test_epicuro_sube_a_ganimedes_y_no_al_teseo_potenciado():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(3):
        en_zona(p, 1, ORO, Zona.RESERVA)
    gani = en_defensa(p, 1, H("Ganimedes"))
    epi = en_defensa(p, 1, H("Epicuro De Samos"))
    teseo = en_defensa(p, 1, H("Teseo de Atenas"))
    en_defensa(p, 0, H("Sir Gaheris"))
    k = next(i for i, h in enumerate(epi.habilidades) if h.get("accion") == "subirMano")
    assert YO.elegir_objetivos(p, 1, [gani, epi, teseo], 1, epi.habilidades[k]) == [gani]


# ══ Partida rqHs2jNRq2AYQ0zCRKgR (Héroe vs Caballero Armas) ════════════════
def test_trono_dorado_no_se_gasta_por_un_gaheris():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.PAGADO)
    trono = en_zona(p, 1, H("Trono Dorado"), Zona.RESERVA)
    en_zona(p, 0, H("Sir Gaheris"), Zona.CEMENTERIO)
    for n in ("Focea", "Epicuro De Samos", "Focea"):  # la mano de la partida
        en_zona(p, 1, H(n), Zona.MANO)
    assert not YO._vale_la_pena(p, 1, Jugada("activar", trono, habilidad=0))


def test_melisende_busca_un_caballero_aunque_el_castillo_este_corto():
    p = partida()
    p.e.activo, p.e.fase = 0, "vigilia"
    del p.j(0).mazo[:]
    for n in ("Sir Erec", "Sir Persival", "Duque Godofredo"):
        en_zona(p, 0, H(n), Zona.MAZO)
    meli = en_defensa(p, 0, H("Melisende"))
    h = next(x for x in meli.habilidades if x.get("accion") == "buscar")
    for _ in range(4):
        en_defensa(p, 1, H("Rey Minos"))
    assert YO.usar_opcional(p, 0, meli, h)


def test_marco_antonio_impide_talismanes_desde_el_cementerio():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(3):
        en_zona(p, 1, ORO, Zona.RESERVA)
    en_defensa(p, 1, H("Marco Antonio"))
    en_defensa(p, 1, H("Rey Minos"))
    doce = en_zona(p, 1, H("Doce Pruebas"), Zona.CEMENTERIO)
    assert not any(j.carta is doce for j in hab.jugadas_desde_otra_zona(p, 1))


def _trono(p, oros=4):
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(oros):
        en_zona(p, 1, ORO, Zona.PAGADO)
    return en_zona(p, 1, H("Trono Dorado"), Zona.RESERVA)


def test_trono_hace_mazo_si_el_ataque_rival_me_gana():
    p = partida()
    trono = _trono(p)
    del p.j(1).mazo[:]
    for _ in range(5):
        en_zona(p, 1, ORO, Zona.MAZO)
    en_defensa(p, 0, H("Rey Arturo Pendragón"))
    en_zona(p, 0, H("Sir Gaheris"), Zona.CEMENTERIO)
    assert YO._vale_la_pena(p, 1, Jugada("activar", trono, habilidad=0))


def test_trono_destierra_la_carta_importante_que_el_rival_recicla():
    p = partida()
    trono = _trono(p)
    en_zona(p, 0, H("Sir Erec"), Zona.MAZO)
    gaheris = en_zona(p, 0, H("Sir Gaheris"), Zona.CEMENTERIO)
    arturo = en_zona(p, 0, H("Rey Arturo Pendragón"), Zona.CEMENTERIO)
    assert YO._vale_la_pena(p, 1, Jugada("activar", trono, habilidad=0))
    assert YO.elegir_objetivos(p, 1, [gaheris, arturo], 1, trono.habilidades[0]) == [arturo]


def test_trono_roba_con_urgencia_y_oros_de_sobra():
    p = partida()
    trono = _trono(p, oros=5)
    en_zona(p, 0, H("Sir Gaheris"), Zona.CEMENTERIO)
    assert YO._vale_la_pena(p, 1, Jugada("activar", trono, habilidad=0))
    en_zona(p, 1, H("Ganimedes"), Zona.MANO)
    en_zona(p, 1, H("Teseo de Atenas"), Zona.MANO)
    assert not YO._vale_la_pena(p, 1, Jugada("activar", trono, habilidad=0))


# ══ Partida FqvRu3BYiNL6L98kmF46 (Titán Minotauro vs Faerie Control) ═══════
_TITAN = {}
for _f in ("mazo_P88I7s2vtgfmiRyyVWlS.json", "mazo_N4Qmm9WA5GCiX6YCgOIf.json", "mazo_ji9mTy7kp7C0mdNlwlpy.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _TITAN[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _TITAN.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))


def T(nombre):
    if nombre not in _TITAN:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _TITAN[nombre]


def _titan(p, oros=3):
    p.e.activo, p.e.fase = 0, "vigilia"
    p.j(0).oro_jugado = True
    for _ in range(oros):
        en_zona(p, 0, ORO, Zona.RESERVA)


def test_focea_saca_al_bloqueador_antes_que_gastar_la_expulsion():
    p = partida()
    _titan(p)
    asterion = en_defensa(p, 0, T("Asterion El Minotauro"))
    asterion.listo = True
    duphon = en_defensa(p, 1, T("Duphon"))
    en_zona(p, 1, T("Tótem de Nwyre"), Zona.APOYO)
    focea = en_zona(p, 0, T("Focea"), Zona.MANO)
    expulsion = en_zona(p, 0, T("Expulsión de Titanes"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 0, [Jugada("jugar", focea), Jugada("jugar", expulsion), Jugada("pasar")])
    assert elegida.carta is focea
    cands = hab.candidatos_validos(p, 0, focea, focea.habilidades[0])
    assert YO.elegir_objetivos(p, 0, cands, 1, focea.habilidades[0]) == [duphon]


def test_diente_de_la_bestia_no_revienta_un_oro_sin_necesidad():
    p = partida()
    _titan(p, oros=2)
    diente = en_zona(p, 0, T("Diente De La Bestia"), Zona.RESERVA)
    en_defensa(p, 0, T("Asterion El Minotauro"))
    en_defensa(p, 1, T("Belial"))
    assert not YO._vale_la_pena(p, 0, Jugada("activar", diente, habilidad=0))


def test_iliada_vuelve_a_activarse_el_turno_siguiente():
    p = partida()
    iliada = en_zona(p, 0, T("La Ilíada"), Zona.PAGADO)
    iliada.usos_turno[0] = 1
    p.e.activo = 1
    p._turno = getattr(p, "_turno", None)
    for x in p.e.jugadores:
        for inst in list(p.e.instancias_en_juego(x.indice)) + x.pagado:
            pass
    # El motor limpia los usos al comenzar el turno, también en los Oros pagados.
    import inspect
    from myl_sim import motor
    assert "x.pagado" in inspect.getsource(motor.Partida._turno)


def test_homunculus_destierra_aliados_para_rea_y_guarda_oros():
    p = partida()
    _titan(p)
    en_zona(p, 0, T("Rea"), Zona.MANO)
    homu = en_zona(p, 0, T("Homunculus"), Zona.CEMENTERIO)
    oro = en_zona(p, 0, T("Figuras Negras"), Zona.CEMENTERIO)
    focea = en_zona(p, 0, T("Focea"), Zona.CEMENTERIO)
    nac = en_zona(p, 0, T("Nacimiento De Pegaso"), Zona.CEMENTERIO)
    assert YO.elegir_destierro_costo(p, 0, homu, [oro, focea, nac], 1) == [nac]
    cartago = en_zona(p, 0, T("Minotauro de Cartago"), Zona.CEMENTERIO)
    assert YO.elegir_destierro_costo(p, 0, homu, [oro, focea, nac, cartago], 1) == [cartago]


def test_atenas_busca_al_final_aunque_el_rival_ya_me_alcance():
    p = partida()
    _titan(p, oros=2)
    del p.j(0).mazo[:]
    for _ in range(11):
        en_zona(p, 0, ORO, Zona.MAZO)
    atenas = en_zona(p, 0, T("Atenas"), Zona.APOYO)
    en_defensa(p, 0, T("Asterion El Minotauro"))
    for n in ("Belial", "Taliesin", "Morgana"):
        en_defensa(p, 1, T(n))
    k = next(i for i, h in enumerate(atenas.habilidades) if h.get("cuando") == "activada")
    j = Jugada("activar", atenas, habilidad=k)
    assert YO._vale_la_pena(p, 0, j) and YO.elegir_jugada(p, 0, [j, Jugada("pasar")]).tipo == "activar"


# ══ Partidas ZsfYX9qL (vs Eterno Agro) y lKffvAXL (vs Sombra Agro) ═════════
def test_homunculus_no_reserva_oros_y_temis_va_en_el_turno_1():
    p = partida()
    _titan(p, oros=2)
    p.j(1).mazo[:] = []
    en_zona(p, 0, T("Homunculus"), Zona.MANO)
    assert J._reserva_reactiva(p, 0) == 0


def test_temis_trae_el_minotauro_que_se_juega_pronto():
    p = partida()
    _titan(p, oros=2)
    temis = en_defensa(p, 0, T("Temis"))
    en_zona(p, 0, T("Asterion El Minotauro"), Zona.MANO)
    h = next(x for x in temis.habilidades if x.get("accion") == "buscar")
    cands = [en_zona(p, 0, T(n), Zona.MAZO) for n in ("Liontari", "Medusa", "Minotauro de Cartago")]
    assert YO.elegir_objetivos(p, 0, cands, 1, h)[0].nombre == "Minotauro de Cartago"


def test_luz_de_prometeo_trae_la_iliada():
    p = partida()
    _titan(p, oros=2)
    luz = en_zona(p, 0, T("Luz de Prometeo"), Zona.MANO)
    cands = [en_zona(p, 0, T(n), Zona.MAZO) for n in ("Titanes", "La Ilíada", "Caja de Pandora")]
    assert YO.elegir_objetivos(p, 0, cands, 1, luz.habilidades[0])[0].nombre == "La Ilíada"


def test_odisea_rea_al_destierro_y_homunculus_al_cementerio():
    p = partida()
    _titan(p, oros=4)
    en_zona(p, 0, T("Rea"), Zona.MANO)
    cands = [en_zona(p, 0, T(n), Zona.MAZO) for n in ("Rea", "Caja de Pandora", "Homunculus")]
    a_mano = YO.elegir_objetivos(p, 0, cands, 1, {"accion": "repartir", "zonaDestino": "mano"})[0]
    assert a_mano.nombre == "Caja de Pandora"
    resto = [c for c in cands if c is not a_mano]
    assert YO.elegir_objetivos(p, 0, resto, 1, {"accion": "repartir", "zonaDestino": "cementerio"})[0].nombre == "Homunculus"


def test_siete_contra_tebas_cancela_a_anhur():
    p = partida()
    _titan(p, oros=2)
    anhur = en_defensa(p, 1, T("Anhur"))
    siete = en_zona(p, 0, T("Siete contra Tebas"), Zona.MANO)
    h = next(x for x in anhur.habilidades if x.get("cuando") == "activada")
    assert YO.cancelar_habilidad(p, 0, anhur, h, [(siete, siete.habilidades[0])]) == 0


def test_temis_busca_otra_cosa_si_ya_tengo_un_cartago():
    p = partida()
    _titan(p, oros=2)
    temis = en_defensa(p, 0, T("Temis"))
    en_zona(p, 0, T("Minotauro de Cartago"), Zona.MANO)
    h = next(x for x in temis.habilidades if x.get("accion") == "buscar")
    cands = [en_zona(p, 0, T(n), Zona.MAZO) for n in ("Medusa", "Minotauro de Cartago")]
    assert YO.elegir_objetivos(p, 0, cands, 1, h)[0].nombre == "Medusa"


# ══ Partidas MscU (Faraón Djoser) y PYDO (Olímpico vs Apophis) ═════════════
_RONDA3 = {}
for _f in ("mazo_I2mTJL4QPoDQrGu5Y8ue.json", "mazo_ji9mTy7kp7C0mdNlwlpy.json", "mazo_P88I7s2vtgfmiRyyVWlS.json"):
    if (CACHE / _f).exists():
        for _c in json.loads((CACHE / _f).read_text(encoding="utf-8"))["cartas"]:
            _RONDA3[_c["nombre"]] = carta_desde_doc(_c["id"], _c)
    # Cartas que ya salieron del mazo: la versión más reciente del historial.
    for _h in sorted((CACHE / "historial_mazos").glob(_f[5:-5] + "_*.json"), key=lambda x: -x.stat().st_mtime):
        for _c in json.loads(_h.read_text(encoding="utf-8"))["cartas"]:
            _RONDA3.setdefault(_c["nombre"], carta_desde_doc(_c["id"], _c))


def R3(nombre):
    if nombre not in _RONDA3:
        pytest.skip(f"falta {nombre} en simulator/cache")
    return _RONDA3[nombre]


def test_roxana_antes_que_ay_con_solo_esas_dos_en_mano():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oro_jugado = True
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    ay = en_zona(p, 1, R3("Ay"), Zona.MANO)
    roxana = en_zona(p, 1, R3("Roxana de Bactria"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 1, [Jugada("jugar", ay), Jugada("jugar", roxana), Jugada("pasar")])
    assert elegida.carta is roxana


def test_contra_apophis_primero_focea_y_no_otro_aliado():
    p = partida()
    _titan(p, oros=5)
    apophis = en_defensa(p, 1, R3("Apophis"))
    en_defensa(p, 1, T("Belial"))
    en_defensa(p, 0, T("Asterion El Minotauro")).listo = True
    focea = en_zona(p, 0, T("Focea"), Zona.MANO)
    cartago = en_zona(p, 0, T("Minotauro de Cartago"), Zona.MANO)
    elegida = YO.elegir_jugada(p, 0, [Jugada("jugar", cartago), Jugada("jugar", focea), Jugada("pasar")])
    assert elegida.carta is focea
    cands = hab.candidatos_validos(p, 0, focea, focea.habilidades[0])
    assert YO.elegir_objetivos(p, 0, cands, 1, focea.habilidades[0]) == [apophis]


def test_roxana_se_guarda_sin_otro_faraon_en_mano():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oro_jugado = True
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    roxana = en_zona(p, 1, R3("Roxana de Bactria"), Zona.MANO)
    con_ay = YO._puntaje(p, 1, Jugada("jugar", roxana))
    sola = YO._puntaje(p, 1, Jugada("jugar", roxana))
    en_zona(p, 1, R3("Ay"), Zona.MANO)
    con_ay = YO._puntaje(p, 1, Jugada("jugar", roxana))
    assert con_ay >= sola + 4


def test_roxana_se_baja_si_ay_ya_esta_en_mesa():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    p.j(1).oro_jugado = True
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    roxana = en_zona(p, 1, R3("Roxana de Bactria"), Zona.MANO)
    sola = YO._puntaje(p, 1, Jugada("jugar", roxana))
    en_defensa(p, 1, R3("Ay"))
    assert YO._puntaje(p, 1, Jugada("jugar", roxana)) >= sola + 4


def test_ay_destierra_a_roxana_para_pagar():
    p = partida()
    p.e.activo, p.e.fase = 1, "vigilia"
    en_defensa(p, 1, R3("Ay"))
    roxana = en_defensa(p, 1, R3("Roxana de Bactria"))
    otro = en_defensa(p, 1, aliado("Guerrero", 2, 2))
    assert YO.elegir_descartes(p, 1, [otro, roxana], 1) == [roxana]


def test_killgharrah_salva_a_la_lady_del_escarabeo_sin_cinturon():
    """Héctor: Escarabeo rival a la vista y sin Cinturón de Lady Ann: barajar
    salva a Lady Calvaur de que la destierren del Cementerio."""
    p = partida()
    _dragon(p, 3)
    kill = en_defensa(p, 1, C("Killgharrah"))
    h = next(x for x in kill.habilidades if x.get("accion") == "barajar")
    ladies = [en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO) for _ in range(2)]
    kills = [en_zona(p, 1, C("Killgharrah"), Zona.CEMENTERIO) for _ in range(2)]
    en_zona(p, 0, C("Escarabeo"), Zona.RESERVA)
    elegidas = YO.elegir_objetivos(p, 1, ladies + kills, 2, h)
    assert {c.nombre for c in elegidas} == {"Lady Calvaur"}
