"""Las 11 cartas antiguas reprogramadas el 2026-11-18: figuraban como
programadas pero en la mesa no hacían nada (acciones que el motor no tiene)."""

from myl_sim import habilidades as hab
from myl_sim import lote_20261118 as L
from myl_sim.jugadores import Heuristico
from myl_sim.modelo import Tipo, Zona

from test_acciones_v3b import en_zona
from test_lote_20261117 import _p, activables, activar
from test_motor import ORO, aliado, en_defensa, h, partida, talisman
from test_notas_cartas import jugar

RIVAL = {"quien": "oponente"}


class Elige(Heuristico):
    """Usa lo opcional y toma la opción que se le indique (por su acción)."""

    def __init__(self, accion):
        super().__init__(1)
        self.accion = accion

    def usar_opcional(self, p, yo, fuente, hh):
        return hh.get("grupoElegir") is None or hh.get("accion") == self.accion

    def elegir_opcion(self, p, yo, fuente, opciones):
        return next(k for k, o in enumerate(opciones) if o.get("accion") == self.accion)


def _con(accion):
    return partida(jugadores=(Elige(accion), Heuristico(2)))


def test_el_lote_usa_solo_vocabulario_del_editor():
    assert L.validar() == [] and len(L.CARTAS) == 11
    acciones = {x["accion"] for d in L.CARTAS.values() for x in d["habilidades"]}
    assert not acciones & {"grupoElegir", "fondoMazo", "subirCementerio"}


def test_adonis_se_destierra_para_robar_o_para_botar():
    for accion, mano, rival in (("robar", 2, 49), ("botar", 0, 47)):
        p = _p()
        a = en_defensa(p, 0, L.carta("adonis"))
        p.e.activo = 0
        assert not activables(p, 0, a)  # falta otro Héroe
        en_defensa(p, 0, aliado("Héroe", 2, 2, raza="Héroe"))
        k = next(k for k, x in enumerate(a.habilidades) if x["accion"] == accion)
        activar(p, 0, a, k=k)
        assert a.zona == Zona.DESTIERRO and len(p.j(0).mano) == mano and len(p.j(1).mazo) == rival


def test_ascenso_draco_las_dos_opciones():
    p = _p()
    en_defensa(p, 0, aliado("Draco Sangre", 2, 2, raza="Dragón"))
    en_defensa(p, 0, aliado("Draco Lich", 2, 2, raza="Dragón"))
    r1 = en_defensa(p, 1, aliado("R1", 3, 5))
    r2 = en_defensa(p, 1, aliado("R2", 3, 4))
    jugar(p, 0, L.carta("ascenso_draco"))
    # 2 Dracos: −2 a 2 rivales (mueve 4) contra +1 a 2 Dragones (mueve 2): la IA resta.
    assert (hab.fuerza(p, r1), hab.fuerza(p, r2)) == (3, 2)
    hab.expirar(p, "hasta_fase_final")
    assert hab.fuerza(p, r1) == 5
    # Sin Aliados Draco, restar no hace nada: sube a sus Dragones.
    q = _p()
    d = en_defensa(q, 0, aliado("Dragón de Aire", 2, 2, raza="Dragón"))
    r = en_defensa(q, 1, aliado("R", 3, 5))
    jugar(q, 0, L.carta("ascenso_draco"))
    assert hab.fuerza(q, d) == 3 and hab.fuerza(q, r) == 5


def test_ataque_de_vampiros():
    p = _con("barajar")
    for k in range(5):
        en_zona(p, 0, aliado(f"C{k}", 1, 1), Zona.CEMENTERIO)
    t = jugar(p, 0, L.carta("ataque_de_vampiros"))
    assert len([x for x in p.j(0).cementerio if x is not t]) == 1 and len(p.j(0).mazo) == 53
    assert not hab.tiene_prop(p, t, "noAnulable")
    en_defensa(p, 0, aliado("Drácula", 4, 4))
    assert hab.tiene_prop(p, t, "noAnulable")
    q = _con("desterrar")
    for k in range(3):
        en_zona(q, 1, aliado(f"R{k}", 1, 1), Zona.CEMENTERIO)
    jugar(q, 0, L.carta("ataque_de_vampiros"))
    assert len(q.j(1).destierro) == 2 and len(q.j(1).cementerio) == 1


def test_pianjy_y_dragon_nube_eligen_una_sola():
    p = _con("botar")
    en_zona(p, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    en_zona(p, 0, aliado("D", 1, 1), Zona.CEMENTERIO)
    jugar(p, 0, L.carta("dominios_de_ra_pianjy"))
    assert len(p.j(1).mazo) == 47 and len(p.j(0).cementerio) == 2
    q = _con("barajar")
    en_zona(q, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    en_zona(q, 0, aliado("D", 1, 1), Zona.CEMENTERIO)
    jugar(q, 0, L.carta("dominios_de_ra_pianjy"))
    assert len(q.j(1).mazo) == 49 and len(q.j(0).cementerio) == 0
    for accion, mano, rival in (("robar", 2, 49), ("botar", 0, 47)):
        n = _con(accion)
        jugar(n, 0, L.carta("espada_sagrada_dragon_nube"))
        assert len(n.j(0).mano) == mano and len(n.j(1).mazo) == rival


def test_traicion_de_seth_elige_una_roba_y_vuelve_del_cementerio():
    p = _con("botar")
    t = jugar(p, 0, L.carta("dominios_de_ra_traicion_de_seth"))
    assert len(p.j(1).mazo) == 48 and len(p.j(0).mano) == 1 and t.zona == Zona.CEMENTERIO
    # Desde el Cementerio se puede volver a jugar, y entonces se destierra.
    p.j(0).oros_virtuales = 5
    p.e.activo, p.e.fase = 0, "vigilia"
    otra = next(o for o in p.jugadas_legales(0, "vigilia") if o.carta is t)
    p.ejecutar_jugada(0, otra)
    assert t.zona == Zona.DESTIERRO and len(p.j(1).mazo) == 47 and len(p.j(0).mano) == 2
    q = _con("desterrar")
    victima = en_zona(q, 1, aliado("V", 1, 1), Zona.CEMENTERIO)
    jugar(q, 0, L.carta("dominios_de_ra_traicion_de_seth"))
    assert victima.zona == Zona.DESTIERRO and len(q.j(1).mazo) == 49 and len(q.j(0).mano) == 1


def test_eneas_al_ser_destruido():
    p = _con("robar")
    e = en_defensa(p, 0, L.carta("helenica_eneas"))
    assert hab.tiene_prop(p, e, "furia")
    p.destruir(e)
    assert len(p.j(0).mano) == 1
    q = _con("barajar")
    e = en_defensa(q, 0, L.carta("helenica_eneas"))
    en_zona(q, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    en_zona(q, 0, aliado("D", 1, 1), Zona.CEMENTERIO)
    q.destruir(e)
    assert len(q.j(0).mano) == 0 and len(q.j(0).mazo) == 51  # barajó 2 (Eneas puede ser una)
    # Si se destierra, no fue destruido: no pasa nada.
    r = _con("robar")
    e = en_defensa(r, 0, L.carta("helenica_eneas"))
    r.desterrar(e)
    assert len(r.j(0).mano) == 0


def test_cadena_espiritual_devuelve_todo_el_destierro():
    p = _p()
    for k in range(3):
        en_zona(p, 0, aliado(f"X{k}", 1, 1), Zona.DESTIERRO)
    ajena = en_zona(p, 1, aliado("Ajena", 1, 1), Zona.DESTIERRO)
    jugar(p, 0, L.carta("cadena_espiritual"))
    assert len(p.j(0).destierro) == 0 and len(p.j(0).cementerio) == 4 and ajena.zona == Zona.DESTIERRO


def test_danza_sidhe_vuelve_al_fondo_del_mazo():
    p = _p()
    d = jugar(p, 0, L.carta("hijos_de_daana_danza_sidhe"))
    assert d.zona == Zona.CEMENTERIO and len(p.j(0).mano) == 0  # roba 2 y descarta 2
    assert not activables(p, 0, d)  # sin Aliados Sidhe
    en_defensa(p, 0, aliado("Fear Sidhe", 3, 4))
    p.j(0).reserva.clear()
    activar(p, 0, d, oros=1)
    assert p.j(0).mazo[-1] is d and p.j(0).oro_disponible == 0


def test_fear_sidhe_paga_el_coste_del_sidhe_que_trae():
    p = _p()
    f = en_defensa(p, 0, L.carta("hijos_de_daana_fear_sidhe"))
    sidhe = en_zona(p, 0, aliado("Ceilican Sidhe", 2, 2), Zona.CEMENTERIO)
    en_zona(p, 0, aliado("Otro", 1, 1), Zona.CEMENTERIO)
    p.e.activo = 0
    p.j(0).reserva.clear()
    assert not activables(p, 0, f, oros=1)  # no alcanza para su coste (2)
    activar(p, 0, f, oros=2)
    assert sidhe.zona == Zona.DEFENSA and p.j(0).oro_disponible == 0
    assert not activables(p, 0, f, oros=5)  # una vez por turno
    # Descartado: baraja 2 cartas del Cementerio.
    q = _p()
    en_mano = en_zona(q, 0, L.carta("hijos_de_daana_fear_sidhe"), Zona.MANO)
    en_zona(q, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    q.descartar(en_mano)
    assert len(q.j(0).cementerio) == 0 and len(q.j(0).mazo) == 51
    # Héctor 18-11: descartarla por exceso de mano no es "por una habilidad".
    r = _p()
    otra = en_zona(r, 0, L.carta("hijos_de_daana_fear_sidhe"), Zona.MANO)
    en_zona(r, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    r.descartar(otra, por_habilidad=False)
    assert len(r.j(0).cementerio) == 2 and len(r.j(0).mazo) == 49
    # Por exceso de mano al final de su turno, tampoco.
    s = _p()
    en_zona(s, 0, aliado("C", 1, 1), Zona.CEMENTERIO)
    for _ in range(8):
        en_zona(s, 0, L.carta("hijos_de_daana_fear_sidhe"), Zona.MANO)
    s.e.activo = 0
    s._finalizar_turno(0)
    assert len(s.j(0).mano) == 8 and len(s.j(0).cementerio) == 2


def test_absalon_devuelve_al_mazo_el_talisman_jugado():
    p = _p()
    ab = en_defensa(p, 0, L.carta("dominios_de_ra_absalon"))
    t = jugar(p, 0, talisman("Daño", 1, [h("botar", objetivo=RIVAL)]))
    assert len(p.j(1).mazo) == 48  # el Talismán se resolvió…
    assert t.zona == Zona.MAZO and any(x is t for x in p.j(0).mazo)  # …y volvió barajado
    assert not any(x.tipo == Tipo.TALISMAN for x in p.j(0).cementerio)
    p._mover(ab, Zona.ATAQUE)  # fuera de la Línea de Defensa no rige
    t2 = jugar(p, 0, talisman("Daño", 1, [h("botar", objetivo=RIVAL)]))
    assert t2.zona == Zona.CEMENTERIO
    assert ORO.tipo == Tipo.ORO
