"""Alquimista y Cruzada de los Niños (mazo Dragón, programadas por el agente)."""

import json
from pathlib import Path

import pytest

from myl_sim import habilidades as hab
from myl_sim import jugadores as J
from myl_sim.datos import carta_desde_doc
from myl_sim.modelo import Zona
from myl_sim.motor import Jugada

from test_acciones_v3b import en_zona
from test_motor import ORO, en_defensa, partida
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

pytestmark = pytest.mark.skipif("Alquimista" not in _CARTAS, reason="falta el mazo Dragón actualizado en simulator/cache")


def C(nombre):
    if nombre not in _CARTAS:
        pytest.skip(f"{nombre} ya no está en el mazo Dragón")
    return _CARTAS[nombre]


def _dragon(p, oros):
    p.e.activo, p.e.fase = 1, "vigilia"
    for _ in range(oros):
        en_zona(p, 1, ORO, Zona.RESERVA)
    p.j(1).oro_jugado = True


def _mano_rival(p, n):
    del p.j(0).mano[:]
    for _ in range(n):
        en_zona(p, 0, C("Ramses IX"), Zona.MANO)


def test_alquimista_pone_un_oro_en_la_reserva():
    p = partida(log=True)
    _dragon(p, 3)
    codex = en_zona(p, 1, C("Codex Arturicus"), Zona.MAZO)
    alq = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    hab._resolver_efecto(p, 1, alq, alq.habilidades[0])
    assert codex.zona == Zona.RESERVA


def test_alquimista_acelera_temprano():
    p = partida()
    _dragon(p, 3)
    alq = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MANO)
    en_zona(p, 1, C("Killgharrah"), Zona.MANO)
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", alq), Jugada("jugar", gaspar), Jugada("pasar")]).carta is alq


def test_alquimista_contra_agro_busca_el_codex():
    p = partida()
    _dragon(p, 8)
    alq = en_zona(p, 1, C("Alquimista"), Zona.MANO)
    en_zona(p, 1, C("Codex Arturicus"), Zona.MAZO)
    antes = YO._puntaje(p, 1, Jugada("jugar", alq))
    for n in ("Ramsés II", "Guerrero Escorpión"):
        en_defensa(p, 0, C(n))
    assert YO._puntaje(p, 1, Jugada("jugar", alq)) > antes + 3  # +4 (el puntaje trae un desempate al azar)


def test_cruzada_descarta_dos_al_azar():
    p = partida(log=True)
    _dragon(p, 3)
    _mano_rival(p, 3)
    cru = en_zona(p, 1, C("Cruzada de los Niños"), Zona.MANO)
    hab._resolver_efecto(p, 1, cru, cru.habilidades[0])
    assert len(p.j(0).mano) == 1 and len(p.j(0).cementerio) == 2


def test_cruzada_vale_por_lo_que_descarta():
    p = partida()
    _dragon(p, 4)
    cru = en_zona(p, 1, C("Cruzada de los Niños"), Zona.MANO)
    _mano_rival(p, 0)
    assert J._sin_objetivo_al_entrar(p, 1, cru)  # sin mano rival no se juega
    _mano_rival(p, 2)
    deja_vacia = YO._puntaje(p, 1, Jugada("jugar", cru))
    _mano_rival(p, 6)
    assert not J._sin_objetivo_al_entrar(p, 1, cru)
    assert deja_vacia > YO._puntaje(p, 1, Jugada("jugar", cru))  # vaciarle la mano vale más


def test_cultistas_antes_que_la_cruzada():
    p = partida()
    _dragon(p, 4)
    _mano_rival(p, 3)
    en_defensa(p, 1, C("Cultistas del Dragón"))
    cru = en_zona(p, 1, C("Cruzada de los Niños"), Zona.MANO)
    sin = YO._puntaje(p, 1, Jugada("jugar", cru))
    p.j(1).defensa.clear()
    assert YO._puntaje(p, 1, Jugada("jugar", cru)) > sin


# ── Entrenamiento del Dragón contra el Faraón guerrero ──────────────────────
def test_mulligan_mazo_lento_se_queda_con_3_oros_y_algo_barato():
    p = partida()
    del p.j(1).mano[:]
    for n in ("Corona de Arturo", "Vinculo del Aullido", "Carnwennan", "Draig Ifanc",
              "Killgharrah", "Lady Calvaur", "Vouivre", "Capa De Invisibilidad"):
        en_zona(p, 1, C(n), Zona.MANO)
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    assert J._mazo_lento(p, 1)
    assert YO.quedarse_mano(p, 1)


def test_guarda_oros_para_la_capa():
    # Plan del Dragón: los Oros se guardan para la Capa de Invisibilidad o el
    # Toque de Pérsival en el turno rival antes que bajar un Gaspar.
    p = partida()
    _dragon(p, 2)
    en_zona(p, 1, C("Capa De Invisibilidad"), Zona.MANO)
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MANO)
    for n in ("Guerrero Bereber", "Ramses IX"):
        en_defensa(p, 0, C(n))
    assert YO.elegir_jugada(p, 1, [Jugada("jugar", gaspar), Jugada("pasar")]).tipo == "pasar"


def test_lady_calvaur_vuelve_destruyendo_draig_o_draco():
    p = partida()
    _dragon(p, 3)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    h = lady.habilidades[2]
    killg = en_defensa(p, 1, C("Killgharrah"))
    cathach = en_defensa(p, 1, C("Cathach"))
    assert not J._rescate_conviene(p, 1, lady, h)  # con otros Dragones no hay combo
    draig = en_defensa(p, 1, C("Draig Ifanc"))
    en_zona(p, 1, C("Corona de Arturo"), Zona.MAZO)
    assert J._rescate_conviene(p, 1, lady, h)
    assert YO.elegir_objetivos(p, 1, [killg, cathach, draig], 1, h) == [draig]
    p.j(1).defensa.remove(draig)
    draco = en_defensa(p, 1, C("Draco Putrido"))
    assert not J._rescate_conviene(p, 1, lady, h)  # Draco sin Aliado rival que desterrar
    en_defensa(p, 0, C("Ramses IX"))
    assert YO.elegir_objetivos(p, 1, [killg, cathach, draco], 1, h) == [draco]


def test_cruz_templaria_no_trae_un_aliado_que_no_saca_nada():
    p = partida()
    _dragon(p, 4)
    cruz = en_zona(p, 1, C("Cruz Templaria"), Zona.RESERVA)
    h = cruz.habilidades[0]
    gaspar = en_zona(p, 1, C("Gaspar"), Zona.MAZO)
    magma = en_zona(p, 1, C("Dragón de Magma"), Zona.MAZO)
    en_defensa(p, 0, C("Ramsés II"))
    assert J._aliado_temporal(h)
    assert not J._saca_una_amenaza(p, 1, gaspar) and J._saca_una_amenaza(p, 1, magma)
    assert YO.elegir_objetivos(p, 1, [gaspar, magma], 1, h) == [magma]


def test_dragon_no_ataca_sin_controlar_la_partida():
    p = partida()
    p.e.activo, p.e.fase = 1, "declaracion_ataque"
    for n in ("Killgharrah", "Lady Calvaur", "Ma Arrat An-Numán", "La Llama Fría") * 3:
        en_zona(p, 1, C(n), Zona.MAZO)
    cathach = en_defensa(p, 1, C("Cathach"))
    en_defensa(p, 0, C("Guerrero Bereber"))
    en_defensa(p, 0, C("Ramses IX"))
    assert YO.elegir_atacantes(p, 1, [cathach]) == []
    p.j(0).defensa.clear()  # el rival se quedó sin Aliados: ahora sí
    assert YO.elegir_atacantes(p, 1, [cathach]) == [cathach]


def test_lady_con_otro_dragon_si_se_juega_de_inmediato():
    p = partida()
    _dragon(p, 3)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    h = lady.habilidades[2]
    killg = en_defensa(p, 1, C("Killgharrah"))
    gaspar = en_defensa(p, 1, C("Gaspar"))
    assert not J._rescate_conviene(p, 1, lady, h)  # 3 Oros: Lady (7) no se juega ya
    for _ in range(4):
        en_zona(p, 1, ORO, Zona.RESERVA)
    assert J._rescate_conviene(p, 1, lady, h)  # 7 Oros: vuelve y se juega
    assert YO.elegir_objetivos(p, 1, [killg, gaspar], 1, h) == [gaspar]  # el que menos vale


def test_lady_destruye_la_otra_lady_para_volver_a_jugarla():
    p = partida()
    _dragon(p, 7)
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    h = lady.habilidades[2]
    en_mesa = en_defensa(p, 1, C("Lady Calvaur"))
    gaspar = en_defensa(p, 1, C("Gaspar"))
    assert J._rescate_conviene(p, 1, lady, h)
    assert YO.elegir_objetivos(p, 1, [en_mesa, gaspar], 1, h) == [en_mesa]
    assert lady.jugar_ya_turno == p.e.turno  # y se juega en esta Vigilia


def test_lady_se_juega_con_6_oros_y_dragones():
    p = partida()
    _dragon(p, 4)  # 5 Oros con el inicial
    lady = en_zona(p, 1, C("Lady Calvaur"), Zona.CEMENTERIO)
    assert not J._lady_se_juega_ya(p, 1, lady)
    en_zona(p, 1, C("Dragones"), Zona.RESERVA)  # 6 Oros, uno es Dragones: genera 2
    assert J._lady_se_juega_ya(p, 1, lady)


def test_llama_fria_juega_a_lady_desde_el_mazo():
    p = partida()
    _dragon(p, 5)
    llama = en_zona(p, 1, C("La Llama Fría"), Zona.MANO)
    cands = [en_zona(p, 1, C(n), Zona.MAZO) for n in ("Killgharrah", "Lady Calvaur", "Gaspar", "Vouivre")]
    for n in ("Guerrero Bereber", "Ramses IX"):
        en_defensa(p, 0, C(n))
    assert YO.elegir_objetivos(p, 1, cands, 1, llama.habilidades[0])[0].nombre == "Lady Calvaur"
    assert YO._puntaje(p, 1, Jugada("jugar", llama)) > 20
