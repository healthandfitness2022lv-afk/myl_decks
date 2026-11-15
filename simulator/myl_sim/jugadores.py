"""Jugadores: quién toma las decisiones en la partida.

Interfaz común (la usarán también MCTS y la IA entrenada):
    quedarse_mano(partida, yo) -> bool
    elegir_jugada(partida, yo, jugadas_legales) -> Jugada
    elegir_atacantes(partida, yo, candidatos) -> list[Instancia]
    elegir_bloqueos(partida, yo, atacantes, bloqueadores) -> {uid_atacante: bloqueador}
    elegir_objetivos(partida, yo, candidatos, n, habilidad) -> list[Instancia]
    elegir_descartes(partida, yo, mano, n) -> list[Instancia]
    usar_opcional(partida, yo, fuente, habilidad) -> bool
    anular(partida, yo, carta_jugada, opciones) -> índice | None
"""

from __future__ import annotations

import random

from . import habilidades as hab
from .modelo import Instancia, Tipo, Zona


class Aleatorio:
    """Elige al azar entre las opciones legales. Sirve de referencia."""

    nombre = "aleatorio"

    def __init__(self, seed: int | None = None):
        self.rng = random.Random(seed)

    def quedarse_mano(self, p, yo):
        return self.rng.random() < 0.8

    def elegir_jugada(self, p, yo, jugadas):
        return self.rng.choice(jugadas)

    def elegir_atacantes(self, p, yo, candidatos):
        return [c for c in candidatos if self.rng.random() < 0.5]

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        libres = list(bloqueadores)
        out = {}
        for atk in atacantes:
            if libres and self.rng.random() < 0.5:
                out[atk.uid] = libres.pop(self.rng.randrange(len(libres)))
        return out

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        return self.rng.sample(candidatos, min(n, len(candidatos)))

    def elegir_descartes(self, p, yo, mano, n):
        return self.rng.sample(mano, min(n, len(mano)))

    def usar_opcional(self, p, yo, fuente, h):
        return self.rng.random() < 0.5

    def anular(self, p, yo, carta, opciones):
        return self.rng.randrange(len(opciones)) if self.rng.random() < 0.5 else None

    def redirigir(self, p, yo, objetivo, opciones):
        return self.rng.randrange(len(opciones)) if self.rng.random() < 0.5 else None

    def elegir_raza(self, p, yo, razas, h):
        return self.rng.choice([r for r in razas if r != hab.OTRA_RAZA] or razas)

    def elegir_carta(self, p, yo, nombres):
        return self.rng.choice(nombres)


# ── Heurístico ────────────────────────────────────────────────────────────────
_BENEFICIO_PROPIO = {"robar", "generarOro", "buscar", "ponerEnJuego", "prevenir"}
_DANINO = {"destruir", "desterrar", "subirMano", "barajar", "perderHabilidad", "botar", "descartar"}


def _valor_carta(p, inst: Instancia) -> float:
    """Qué tan valiosa es una carta (para elegir objetivos y descartes)."""
    if inst.tipo == Tipo.ALIADO:
        f = hab.fuerza(p, inst) if inst.en_juego else inst.carta.fuerza
        return f * 1.5 + inst.carta.coste + 0.5 * len(inst.habilidades)
    if inst.tipo == Tipo.ORO:
        return 1.0 + 0.5 * len(inst.habilidades)
    return inst.carta.coste + 0.7 * len(inst.habilidades)


_RESPUESTAS = {"anular", "cancelarAtaque", "redirigir"}
_DURACIONES_PERMANENTES = {"permanente", "mientras_en_juego"}

_RESERVA_REACTIVA = True  # Dragón vs agro: guarda Oros para Toque/Bola en la Guerra rival
_NO_ATACAR_EN_PELIGRO = True  # PYDO #7: si el rival me gana el próximo turno, se bloquea
_REFUERZO_ACTIVABLE = True  # I4Sl2 #1: contar La Ilíada del rival al atacar
_REMOCION_ACTIVADA = True  # I4Sl2 #2: el Tártaro vale lo que saca (y lo que recupera)
_GUARDAR_PARA_RESPUESTA = True  # I4Sl2 #4: guardar los Oros de Siete contra Tebas
_MULLIGAN_LENTO_V2 = True  # mulligan del Dragón: 2 Oros + Vínculo / respuesta / algo barato


def _mazo_lento(p, yo) -> bool:
    """Mazo de control: 1 de cada 6 cartas (o más) cuesta 5 o más (Dragón)."""
    cartas = [c for c in p.j(yo).mano + p.j(yo).mazo if c.tipo != Tipo.ORO]
    return bool(cartas) and sum(1 for c in cartas if c.carta.coste >= 5) * 6 >= len(cartas)


def _mazo_agresivo(p, quien) -> bool:
    """Mazo agro (Faraón guerrero): la mitad o más de lo que no es Oro cuesta 2 o menos."""
    cartas = [c for c in p.j(quien).mazo + p.j(quien).mano + p.j(quien).cementerio
              + list(p.e.instancias_en_juego(quien)) if c.tipo != Tipo.ORO]
    return bool(cartas) and sum(1 for c in cartas if c.carta.coste <= 2) * 2 >= len(cartas)


def _victimas_barrida(p, yo, inst: Instancia) -> tuple[int, int]:
    """Dragón Nival: cuántos Aliados rivales y propios destruye al entrar."""
    suyos = mios = 0
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in _REMOCION \
                or obj.get("seleccion") != "todos" or "Aliado" not in (obj.get("tipos") or ["Aliado"]):
            continue
        quien = obj.get("quien", "oponente")
        if quien in ("oponente", "cualquiera", "ambos"):
            suyos += sum(1 for a in p.j(1 - yo).aliados if hab.coincide(p, a, obj))
        if quien in ("propio", "cualquiera", "ambos"):
            mios += sum(1 for a in p.j(yo).aliados if a is not inst and hab.coincide(p, a, obj))
    return suyos, mios


def _partida_controlada(p, yo) -> bool:
    """El rival no me presiona: no tiene Aliados en mesa, o le doblo la
    fuerza, y no está al ataque (agro)."""
    fuerza = lambda q: sum(max(0, hab.fuerza(p, a)) for a in p.j(q).aliados)  # noqa: E731
    if _rival_agro(p, yo):
        return False
    return not p.j(1 - yo).aliados or fuerza(yo) >= 2 * fuerza(1 - yo)


def _util_en_turno_1(c: Instancia) -> bool:
    if c.tipo in (Tipo.ALIADO, Tipo.TOTEM):
        return c.carta.coste <= 2
    if c.tipo == Tipo.TALISMAN:
        return c.carta.coste <= 2 and any(h.get("accion") in _RESPUESTAS for h in c.habilidades)
    return False


def _se_juega_desde(c: Instancia) -> set[str]:
    """Zonas desde las que la carta se puede jugar sola (Qer-Her: Cementerio)."""
    zonas: set[str] = set()
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("accion") == "jugarDesde" and obj.get("quien") == "esta_carta":
            zonas |= set(hab.zonas_de(obj, "mano"))
    return zonas


_UMBRAL_ANULAR = 7.0
_MAZO_LENTO_PASIVO = False
_FLECHAS_HECTOR = True  # Dragón no atacaba hasta controlar la partida
_COMBO_IFANC_LADY = True  # jugar Ifanc/Pútrido con Lady en el Cementerio
_ESTRELLA_BUSCA = True  # Estrella de Belén antes que otro Oro bajo presión
_COMETA_ESPERA = True  # Draco Cometa espera un objetivo que valga
_TOPE_SIN_REPETIDOS = True  # Estrella no toma un errante repetido
_CORRECCIONES_19965 = True  # remoción bajo presión, Lady→Haquika, Bola no al Cometa robado, descarte
_CORRECCIONES_2 = True  # partidas 97465 y 2376
_CODEX_MINIMO = True  # el Codex no se gasta en 1-2 de daño
_VINCULO_FRENA = True  # no pagar el Vínculo si me impide bajar el Aliado de este turno
_VINCULO_MANO_MIN = 4  # ...solo con la mano de al menos estas cartas
_USAR_GENERADOS = True  # Dragones: los 2 Oros generados se usan en el Dragón caro, no se pierden
_CARNWENNAN_TURNO = True  # Carnwennan en el turno rival, no en mi Vigilia
_NO_ALIMENTAR_ABISMO = False  # lo caro no entra contra un Abismo a la vista
_BOLA_ESPERA = True  # Bola en mi turno solo a motores o armados
_LECCIONES_QX6 = True  # desafío qx6H: Anand es motor; removal sin blanco se guarda
_FLECHAS_QUEMAR = True  # ataco aunque haya Flechas reveladas si no me matan
# 2026-11-14 · Gestión de mano (Héctor): no vaciar la mano bajando cuerpos de
# más cuando la mesa ya está bien. Atributo por jugador: `gestion_mano`.
_GESTION_MANO = False
_MANO_MIN = 2  # cartas que quiero conservar en la mano después de jugar
_MANO_UMBRAL = 15.0  # una jugada con este puntaje o más se hace igual
_MANO_MESA_MIN = 2  # Aliados propios mínimos para guardar (y no menos que el rival)


def _bloqueo_con_tocador_conviene(p, yo, atk: Instancia) -> bool:
    """Bloquear a Ramsés II con Tocador: el rival bota lo mismo que yo. Solo
    conviene si lo deja a tiro de perder en 1 o 2 turnos (daño de combate o
    botar), y sin dejarme a mí a tiro de su próximo ataque."""
    if not _devuelvo_lo_botado(p, yo):
        return False
    castigo = _castigo_si_lo_bloquean(p, atk)
    su_castillo = len(p.j(1 - yo).mazo) - castigo
    mi_castillo = len(p.j(yo).mazo) - castigo
    mi_ataque = sum(max(0, hab.fuerza(p, a)) for a in p.j(yo).aliados if _puede_atacar(p, a))
    potencial = mi_ataque + _botar_posible(p, yo)
    su_ataque = sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados)
    return su_castillo <= 2 * potencial and mi_castillo > su_ataque


def _devuelvo_lo_botado(p, yo) -> bool:
    """Tocador: cuando boto por una habilidad del rival, él bota lo mismo."""
    return any(h.get("cuando") == "al_botar_por_oponente" for c in p.e.instancias_en_juego(yo) for h in c.habilidades)


def _importancia(p, quien: int, c: Instancia, *, solo_al_jugar: bool = False) -> float:
    """Cuánto pesa en la mesa que esta carta se resuelva (no lo que cuesta):
    remover o robar un Aliado, un Aliado fuerte o con habilidades que seguirá
    usando, sacar cartas de más (más con poca mano)."""
    v = 0.0
    mano = len(p.j(quien).mano)
    temprano = len(p.j(quien).reserva) + len(p.j(quien).pagado) <= 3
    # Para decidir una respuesta como Resplandor importa lo que se evita
    # ahora, antes de resolver la entrada. No hay que gastarlo solo porque
    # la carta tendrá una habilidad útil al morir o activarse más tarde.
    principales = [
        h for h in c.habilidades
        if not solo_al_jugar or h.get("cuando") in ("al_jugar", None)
    ]
    efectos = principales + [
        e for h in principales for e in (h.get("luego") or [])
        if isinstance(e, dict)
    ]
    for h in efectos:
        accion = h.get("accion")
        obj = h.get("objetivo") or {}
        if accion == "buscar" and "Oro" in (obj.get("tipos") or []):
            v += 4.5 if temprano else 1.0  # #8 Kawit: acelera un Oro
            continue
        if accion in ("destruir", "desterrar", "subirMano", "mover", "ganarControl") and obj.get("quien", "oponente") != "propio":
            # Pesa según lo mejor que puede sacarme (o robarme, con Haquika).
            mejor = max((_valor_vivo(p, x) for x in p.j(1 - quien).aliados), default=0)
            v += 4 + mejor * (1.5 if accion == "ganarControl" else 1.0)
        elif accion in ("robar", "buscar"):
            v += int(h.get("cantidad", 1)) * (2.5 if mano <= 2 else 1.0)
        elif accion == "perderHabilidad" and obj.get("seleccion") == "todos" and obj.get("quien", "oponente") != "propio" \
                and _nombrar_raza_sirve(p, quien, c):
            # #93 Cleopatra VII: casi siempre hay que anularla (deja sin
            # habilidad a toda una raza mientras esté en juego).
            v += 6 + 1.5 * len(p.j(1 - quien).aliados)
        elif accion == "botar" and obj.get("quien", "oponente") == "oponente":
            # Héctor 2026-11-12: Mercado Egipcio / Flechas de Lava botan
            # "tantas como…": se cuenta lo que botarían ahora, no 1. Con el
            # castillo corto, cada carta pesa más.
            n = hab.cantidad(p, quien, h, []) if h.get("cantidadSegun") else int(h.get("cantidad", 1))
            v += n * (0.8 if len(p.j(1 - quien).mazo) > 20 else 1.3)
        elif accion == "cancelarAtaque" and p.e.activo != quien:
            # Flechas de Lava: además del bote, se pierde todo el ataque.
            v += sum(hab.fuerza(p, a) for a in getattr(p, "atacantes", []) or [])
    if c.tipo == Tipo.ALIADO:
        # Su presencia en la mesa: fuerza y habilidades que seguirá usando.
        sigue = sum(
            1 for h in c.habilidades
            if h.get("cuando") not in ("al_jugar", "al_salir_del_juego", None) and h.get("accion") not in hab.PROPIEDADES
        )
        v += 1.2 * max(0, hab.fuerza(p, c) if c.en_juego else c.carta.fuerza) + 1.5 * sigue
    return v


def _valor_para_el_plan(p, yo, c: Instancia) -> float:
    """#19 Jentakus: qué Aliado buscar según la partida. Combo con la mesa
    (Ay ↔ Amyrteos), Djoser si tengo Armas, Ramsés si voy agresivo,
    Ptolomeo II si necesito controlar la mesa."""
    mios, suyos = p.j(yo).aliados, p.j(1 - yo).aliados
    v = _valor_carta(p, c) * 0.3
    # lKff #1: Temis en el turno 1 trae el Minotauro de Cartago (3), que se
    # juega ya el turno siguiente; Liontari (5) queda lejos.
    oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
    # lKff #1: el Minotauro de Cartago antes que Medusa: Asterion lo potencia y
    # el Minotauro Colosal cuenta Minotauros (sinergia por arquetipo).
    jug = p.j(yo)
    arquetipos = {o.get("arquetipo") or (o.get("coste") or {}).get("arquetipo")
                  for x in jug.mazo + jug.mano + list(p.e.instancias_en_juego(yo)) if x is not c
                  for h in x.habilidades for o in [h.get("objetivo") or {}]}
    v += 2.0 * sum(1 for a in arquetipos if a and hab.coincide(p, c, {"arquetipo": a, "quien": None}))
    # El Cartago trae otro Minotauro directo a la mesa (dos Aliados por uno);
    # si ya tengo un Cartago en la mano, busco algo distinto.
    if any(h.get("cuando") == "al_jugar" and h.get("accion") in ("jugarDesde", "ponerEnJuego")
           and "Aliado" in ((h.get("objetivo") or {}).get("tipos") or []) for h in c.habilidades):
        v += -3.0 if any(x.nombre == c.nombre for x in jug.mano) else 6.0
    if oros >= 2:  # con el Oro inicial solo, la curva aún no dice nada
        v -= 3.0 * max(0, c.carta.coste - (oros + 1))
    if (_es_salida(c) and any(_gana_al_morir(a) for a in mios)) or (_gana_al_morir(c) and any(_es_salida(a) for a in mios)):
        v += 10  # combo
    armas = sum(1 for x in p.j(yo).mano if x.tipo == Tipo.ARMA) + sum(
        1 for a in p.e.portadas if a.controlador == yo
    )
    if armas and any(h.get("valorPorCada") == "arma_portada" or h.get("accion") == "sinLimiteArmas" for h in c.habilidades):
        v += 4 * armas  # Djoser
    mi_fuerza = sum(max(0, hab.fuerza(p, a)) for a in mios)
    su_fuerza = sum(max(0, hab.fuerza(p, a)) for a in suyos)
    if su_fuerza > mi_fuerza:  # control: me superan en mesa
        if any(h.get("accion") in ("prevenir", "protegerHabilidad") for h in c.habilidades):
            v += 6  # Ptolomeo II
    elif len(p.j(1 - yo).mazo) <= len(p.j(yo).mazo):  # agresivo: voy por delante
        v += 1.5 * c.carta.fuerza  # Ramsés
    if _pieza_clave(c) and not any(a.carta.nombre == c.carta.nombre for a in mios) and _nombrar_raza_sirve(p, yo, c):
        # Ptolomeo II protege todo: armar el candado (con Neferite y Cleopatra).
        v += 8 + 2 * sum(1 for a in mios if _pieza_clave(a))
    if _anulacion_a_la_vista(p, yo, c):
        v -= 8
    return v


def _busca_oro_defensivo(p, yo, oro: Instancia) -> bool:
    """Estrella de Belén (mira 3 y toma un Oro) cuando me superan en mesa y
    en el mazo queda un Oro que me defiende (Codex Arturicus)."""
    if not any(h.get("accion") == "mirarTope" and "Oro" in ((h.get("objetivo") or {}).get("tipos") or [])
               for h in oro.habilidades):
        return False
    if not any(c.tipo == Tipo.ORO and _oro_defiende(c) for c in p.j(yo).mazo):
        return False
    mia = sum(max(0, hab.fuerza(p, a)) for a in p.j(yo).aliados)
    suya = sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados)
    return suya >= 6 and suya > mia


def _castigo_barrida_propia(p, yo, carta: Instancia) -> float:
    """Héctor (2376 T23): Dragón Nival destruyó solo a mi Gaspar. Una barrida
    al entrar que no saca nada rival y me mata Aliados no se juega."""
    for h in carta.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in ("destruir", "desterrar") \
                or obj.get("seleccion") != "todos" or obj.get("quien") not in ("cualquiera", "ambos"):
            continue
        afectados = [c for c in hab.candidatos_validos(p, yo, carta, h) if c is not carta]
        mios = [c for c in afectados if c.controlador == yo]
        suyos = [c for c in afectados if c.controlador != yo]
        if mios and not suyos:
            return -40.0
        if mios:
            return -4.0 * sum(_valor_vivo(p, c) for c in mios) / max(1.0, sum(_valor_vivo(p, c) for c in suyos))
    return 0.0


def _remocion_al_entrar(c: Instancia) -> list:
    """Habilidades al entrar que sacan un Aliado rival: destruir/desterrar, o
    perder la habilidad y luego destruir (Guardia Gozosa)."""
    out = []
    for h in c.habilidades:
        if h.get("cuando") not in ("al_jugar", None) or (h.get("objetivo") or {}).get("quien") not in ("oponente", "cualquiera"):
            continue
        if h.get("accion") in ("destruir", "desterrar") or (
                h.get("accion") == "perderHabilidad" and h.get("duracion") == "instantaneo"
                and any(x.get("accion") in ("destruir", "desterrar") for x in h.get("luego") or [])):
            out.append(h)
    return out


def _robado_por(p, yo, a: Instancia) -> Instancia | None:
    """Haquika: si controla algo mío, sacarla me lo devuelve."""
    if not any(x.get("accion") == "ganarControl" for x in a.habilidades):
        return None
    mios = [x for x in p.e.instancias_en_juego(1 - yo) if getattr(x, "dueno", 1 - yo) == yo]
    return max(mios, key=lambda x: _valor_carta(p, x), default=None)


def _sostiene_anulacion(p, yo, c: Instancia) -> bool:
    """Draco Cometa robado: mientras siga en juego, el Demoledor sigue sin
    habilidad. Destruirlo se la devuelve."""
    if getattr(c, "dueno", None) != yo or c.controlador == yo:
        return False
    if not any(h.get("accion") == "perderHabilidad" and h.get("duracion") == "mientras_en_juego" for h in c.habilidades):
        return False
    return any(_neutralizado(p, a) and _anular_siempre(p, a) for a in p.j(1 - yo).aliados if a is not c)


def _ajuste_remocion_hector(p, yo, carta: Instancia, base: float) -> float:
    """Héctor 2026-11-12 (19965 bis): bajo presión, sacar Aliados rivales va
    antes que reciclar (Gozosa al Werin y Bola al Demoledor en vez de
    Cathach); Lady que destierra a la Haquika me devuelve lo robado."""
    habs = _remocion_al_entrar(carta)
    if not habs:
        return 0.0
    suyos = [a for a in p.j(1 - yo).aliados if not _neutralizado(p, a) and not _sostiene_anulacion(p, yo, a)]
    if not suyos:
        return 0.0
    extra = 0.0
    for h in habs:
        cands = [a for a in hab.candidatos_validos(p, yo, carta, h) if a in suyos]
        if not cands:
            continue
        for a in cands:
            robado = _robado_por(p, yo, a)
            if robado is not None and h.get("accion") == "desterrar":
                extra = max(extra, 6.0 + 0.5 * _valor_carta(p, robado))
        if h.get("accion") == "perderHabilidad" and base < 14.0:
            extra = max(extra, 14.0 - base)  # Gozosa destruye: vale como una Bola
    mia = sum(max(0, hab.fuerza(p, a)) for a in p.j(yo).aliados)
    suya = sum(max(0, hab.fuerza(p, a)) for a in suyos)
    if suya - mia >= 6:
        extra += 6.0
    return extra


def _hay_carnada(p, yo, inst: Instancia) -> bool:
    """#115: ¿tengo otra carta que el rival también anularía pero importa
    menos? Esa va primero y gasta su Abismo; si no, juego esta igual."""
    mia = _importancia(p, yo, inst)
    return any(
        c is not inst and c.tipo != Tipo.ORO and p.puede_pagar(yo, c)
        and _UMBRAL_ANULAR <= _importancia(p, yo, c) < mia
        for c in p.j(yo).mano
    )


def _anulacion_a_la_vista(p, yo, inst: Instancia) -> bool:
    """El rival tiene en la mesa algo que anula esta carta y puede usarlo
    (Abismo en su Línea de Apoyo), o un anulador revelado en la mano."""
    rival = 1 - yo
    if _importancia(p, yo, inst) < _UMBRAL_ANULAR:
        return False  # no la va a gastar en esto
    for s in p.e.instancias_en_juego(rival):
        for h in s.habilidades:
            if h.get("accion") == "anular" and h.get("cuando") == "activada" \
                    and hab.coincide(p, inst, h.get("objetivo") or {}) and hab.puede_pagar_costo(p, rival, s, h):
                return True
    return any(
        getattr(c, "revelada", False) and p.coste_de(rival, c) <= p.j(rival).oro_disponible
        and any(h.get("accion") == "anular" and hab.coincide(p, inst, h.get("objetivo") or {}) for h in c.habilidades)
        for c in p.j(rival).mano
    )


def _valor_motor_de_entradas(p, yo, inst: Instancia) -> float:
    """#101 Ptolomeo III: si dispara cada vez que entra o sale un Aliado mío
    (bota 1), conviene jugarlo antes que los demás que voy a bajar este turno."""
    disparos = [h for h in inst.habilidades if h.get("cuando") in ("propia_entra", "propia_sale")]
    if not disparos:
        return 0.0
    oros = p.j(yo).oro_disponible - p.coste_de(yo, inst)
    siguientes = 0
    for c in sorted(p.j(yo).mano, key=lambda x: x.carta.coste):
        if c is inst or c.tipo == Tipo.ORO or c.carta.coste > oros:
            continue
        if any(hab._dispara_por(c, h) for h in disparos):
            siguientes += 1
            oros -= c.carta.coste
    return 3.0 * siguientes


def _es_protector(c: Instancia) -> bool:
    """Ptolomeo II: previene que las otras cartas propias sean afectadas. Es
    de lo más importante del mazo: no se arriesga bloqueando."""
    return c.tipo == Tipo.ALIADO and any(
        h.get("accion") in ("prevenir", "protegerHabilidad") and h.get("modo", "afectada") == "afectada"
        and (h.get("objetivo") or {}).get("quien") == "propio"
        for h in c.habilidades
    )


def _pieza_clave(c: Instancia) -> bool:
    """El candado Ptolomeo II + Neferite I + Cleopatra VII: se cuidan a toda
    costa (no se arriesgan en combates parejos) y se busca armarlo."""
    if c.tipo != Tipo.ALIADO:
        return False
    # Por la carta impresa: Neferite sin habilidad por un Resplandor sigue
    # siendo parte del candado (la recupera).
    habs = c.carta.habilidades if hasattr(c, "carta") else c.habilidades
    if any(
        h.get("accion") in ("prevenir", "protegerHabilidad") and h.get("modo", "afectada") == "afectada"
        and (h.get("objetivo") or {}).get("quien") == "propio"
        for h in habs
    ):
        return True
    for h in habs:
        obj = h.get("objetivo") or {}
        # Cleopatra VII: deja sin habilidad a los Aliados rivales mientras esté.
        if h.get("accion") == "perderHabilidad" and h.get("duracion") == "mientras_en_juego"                 and obj.get("seleccion") == "todos" and obj.get("quien", "oponente") != "propio":
            return True
        # Neferite I: remoción que se repite cada turno sin pagar Oros.
        if h.get("cuando") == "activada" and h.get("accion") in ("destruir", "desterrar")                 and obj.get("quien") == "oponente" and not (h.get("costo") or {}).get("oros")                 and not (h.get("costo") or {}).get("destruirEstaCarta"):
            return True
    return False


def _lo_previene_ptolomeo(p, yo, carta: Instancia) -> bool:
    """¿Lo que hace `carta` al entrar es sacar UNA carta mía, y tengo a
    Ptolomeo II en mesa con su prevención disponible? (Akhet)."""
    habs = [h for h in carta.habilidades if h.get("cuando") in ("al_jugar", None) and not hab.es_permiso_jugar(h)]
    if not habs or not all(
        h.get("accion") in _REMOCION and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente"
        and (h.get("objetivo") or {}).get("seleccion", "elige") == "elige" and int(h.get("cantidad", 1)) <= 1
        for h in habs
    ):
        return False
    for s in p.j(yo).aliados:
        if not _es_protector(s):
            continue
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "prevenir":
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and hab.usos(p, yo, s, h, k) >= limite:
                continue
            if hab.puede_pagar_costo(p, yo, s, h):
                return True
    return False


def _fuerza_que_aporta(p, c: Instancia) -> int:
    if not c.en_juego or not c.habilidades:
        return 0
    aliados = [a for a in p.j(c.controlador).aliados if a is not c]
    antes = sum(hab.fuerza(p, a) for a in aliados)
    anterior = c.sin_habilidad_hasta
    try:
        c.sin_habilidad_hasta = "hasta_fase_final"
        return max(0, antes - sum(hab.fuerza(p, a) for a in aliados))
    finally:
        c.sin_habilidad_hasta = anterior


def _valor_robar(p, yo, c: Instancia) -> float:
    """Haquika: lo que vale robar `c`. Además de lo que aporta en la mesa,
    si tiene una remoción activable sin Oros (Neferite I) la uso este mismo
    turno contra otra carta suya (Djoser)."""
    v = _valor_vivo(p, c) + 2 * _fuerza_que_aporta(p, c)
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") == "continua" and h.get("accion") == "modificarFuerza" and obj.get("quien") == "propio":
            raza = obj.get("raza")
            v += max(0, int(h.get("valor", 0) or 0)) * sum(
                1 for a in p.j(yo).aliados if not raza or a.raza.lower() == raza.lower()
            )
    for h in c.habilidades:
        if h.get("cuando") != "activada" or h.get("accion") not in _REMOCION or (h.get("costo") or {}).get("oros"):
            continue
        if (h.get("objetivo") or {}).get("quien") != "oponente":
            continue
        cands = [x for x in hab.candidatos_validos(p, yo, c, h) if x is not c and x.tipo == Tipo.ALIADO]
        if (h.get("costo") or {}).get("desterrarCementerioSegun") == "coste_objetivo":
            cands = [x for x in cands if x.carta.coste <= len(p.j(yo).cementerio)]
        if cands:
            v += max(_valor_vivo(p, x) for x in cands)
    return v


def _valor_masiva(p, yo, inst: Instancia) -> float:
    """Quemar los Templos: lo que pierde el rival (sus Armas y Tótems, y la
    fuerza que le daban al portador) menos lo mío, más lo que baraja."""
    v = 0.0
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in ("destruir", "desterrar"):
            continue
        if obj.get("seleccion") != "todos" or obj.get("quien") not in ("cualquiera", "ambos", "oponente"):
            continue
        tipos = obj.get("tipos") or []
        afectadas = [
            c for c in p.e.instancias_en_juego()
            if c.tipo != Tipo.ORO and hab.coincide(p, c, obj) and (not tipos or c.tipo.value in tipos or c.tipo.name.title() in tipos)
        ]
        suyas = [c for c in afectadas if c.controlador != yo]
        mias = [c for c in afectadas if c.controlador == yo]
        v += 1.5 * sum(_valor_carta(p, c) for c in suyas) - 1.5 * sum(_valor_carta(p, c) for c in mias)
        if any(x.get("accion") == "barajar" for x in h.get("luego") or []):
            v += len(afectadas)  # baraja tantas como afectó
    return v


def _lo_necesito_para_defender(p, yo, c: Instancia) -> bool:
    """Si ataca no bloquea en el turno rival: ¿su próximo ataque me deja
    a tiro sin él?"""
    suyo = sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados if _puede_atacar(p, a))
    return suyo >= len(p.j(yo).mazo) - 5


def _amenaza_ofensiva(p, c: Instancia) -> float:
    if hab.tiene_prop(p, c, "guardian"):
        return -10.0  # no ataca igual
    v = float(hab.fuerza(p, c))
    if hab.tiene_prop(p, c, "imbloqueable"):
        v += 3.0
    if any(x.get("cuando") in ("al_hacer_dano", "al_atacar") for x in c.habilidades):
        v += 2.0
    return v


def _bonus_carnada(p, yo, j) -> float:
    """#6 0VzQ: con un Abismo rival en la mesa, un Aliado barato que no es
    clave va primero: obliga al rival a decidir si lo gasta."""
    if j.tipo != "jugar" or j.carta.tipo != Tipo.ALIADO or j.carta.carta.coste > 3:
        return 0.0
    if _anular_siempre(p, j.carta) or _pieza_clave(j.carta):
        return 0.0
    rival = 1 - yo
    for s in p.e.instancias_en_juego(rival):
        for h in s.habilidades:
            if h.get("accion") == "anular" and h.get("cuando") == "activada" \
                    and hab.coincide(p, j.carta, h.get("objetivo") or {}):
                return 4.0
    return 0.0


def _oro_que_acelera_ataques(c: Instancia) -> bool:
    """Corona Faraónica: los Aliados que entran pueden atacar ese turno."""
    return c.tipo == Tipo.ORO and any(
        h.get("accion") == "restringirCombate" and h.get("modo") == "puede_atacar_este_turno"
        for h in c.habilidades
    )


def _corona_sirve_ya(p, yo, c: Instancia) -> bool:
    """#2 ZOlJ: la Corona Faraónica es el Oro principal del Faraón guerrero:
    se baja apenas se pueda, si no hay otra en juego."""
    if not _oro_que_acelera_ataques(c) or len(p.j(yo).mazo) <= 5:
        return False
    return not any(_oro_que_acelera_ataques(x) for x in p.e.instancias_en_juego(yo))


def _juntando_oros(p, yo) -> bool:
    """Mazo de control (Dragón) que aún no llega a 7 Oros en juego (Lady
    Calvaur): los Oros no se sacrifican salvo para no perder."""
    return _mazo_lento(p, yo) and len(p.j(yo).reserva) + len(p.j(yo).pagado) < 7


def _vale_gastar_un_oro(p, yo, objetivos) -> bool:
    """Carnwennan / Cruz Templaria juntando Oros: solo contra una pieza clave
    o un Aliado de fuerza 4 o más."""
    return any(_pieza_clave(t) or (t.tipo == Tipo.ALIADO and hab.fuerza(p, t) >= 4) for t in objetivos)


def _bloquearia_con(p, yo, fuerza_b: int) -> bool:
    """Mercaderes se vuelve un bloqueador de fuerza 3: solo si de verdad
    bloquearía con él. No contra Ramsés II (bloquearlo hace botar 6); y si
    no mata al atacante, solo apurado y sin un Codex que deje el daño en 0."""
    castillo = len(p.j(yo).mazo)
    total = sum(max(0, hab.fuerza(p, a)) for a in p.atacantes)
    apurado = total >= castillo - 3
    codex = any(
        x.get("accion") == "reducirDano" and x.get("cuando") == "activada"
        for c in p.e.instancias_en_juego(yo) for x in c.habilidades
    )
    if _oros_indestructibles(p, yo):
        # Corona de Arturo con 2 Aliados propios (Héctor: sin contar a
        # Mercaderes, que en la Fase Final vuelve a ser Oro): bloquea sin
        # morir y vuelve a la zona de Oros.
        return any(_castigo_si_lo_bloquean(p, a) == 0 for a in p.atacantes)
    if _juntando_oros(p, yo):
        # Bloqueando muere y se pierde un Oro: solo para no perder la partida.
        return total >= castillo and not codex and any(_castigo_si_lo_bloquean(p, a) == 0 for a in p.atacantes)
    # Héctor 2026-11-12: matar con Mercaderes solo a un Aliado importante
    # (no un Kawit sin Arma), o salvar la partida.
    return any(
        _castigo_si_lo_bloquean(p, a) == 0
        and ((fuerza_b > hab.fuerza(p, a) and (_anular_siempre(p, a) or _valor_vivo(p, a) > 3
                                               or any(x.portador == a.uid for x in p.e.portadas)))
             or (apurado and not codex))
        for a in p.atacantes
    )


def _oros_indestructibles(p, yo, *, aliados_extra: int = 0) -> bool:
    """Corona de Arturo: "mientras controles 2 o más Aliados, los Oros son
    indestructibles" (`aliados_extra`: los que se suman antes, Mercaderes)."""
    aliados = len(p.j(yo).aliados) + aliados_extra
    for c in p.e.instancias_en_juego(yo):
        for x in c.habilidades:
            cond = x.get("condicion") or {}
            if x.get("accion") == "otorgarPropiedad" and x.get("modo") == "indestructible" \
                    and x.get("cuando") == "continua" and "Oro" in ((x.get("objetivo") or {}).get("tipos") or []) \
                    and (cond.get("tipo") != "aliados_propios" or aliados >= int(cond.get("valor", 0) or 0)):
                return True
    return False


def _otra_opcion_mejor(p, yo, fuente: Instancia, h: dict) -> bool:
    """Gaspar: "baraja 1 carta o 2 Aliados Dragón". Si hay 2 Dragones en el
    Cementerio, la opción de 1 carta no se usa."""
    if int(h.get("cantidad", 1)) >= 2:
        # mBp5 #2: faltan Oros y hay uno (o una remoción) en el Cementerio: la
        # opción de 1 carta (ese Oro) es mejor que barajar 2 Dragones.
        return any(x is not h and x.get("grupoLimite") == h.get("grupoLimite") and int(x.get("cantidad", 1)) < 2
                   and _recurso_para_barajar(p, yo, x, fuente) for x in fuente.habilidades)
    if _recurso_para_barajar(p, yo, h, fuente):
        return False
    for x in fuente.habilidades:
        if x is h or x.get("grupoLimite") != h.get("grupoLimite") or int(x.get("cantidad", 1)) < 2:
            continue
        if len(hab.candidatos_validos(p, yo, fuente, x)) >= int(x.get("cantidad", 1)):
            return True
    return False


def _faltan_oros(p, yo) -> bool:
    """Tengo menos Oros en juego que turnos jugados (y menos de 6): estoy corto."""
    propios = (p.e.turno + (1 if p.e.activo == yo else 0)) // 2
    oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
    return oros < 6 and oros < propios


def _recurso_para_barajar(p, yo, h: dict, fuente: Instancia) -> bool:
    """Barajar 1 carta del Cementerio: un Oro si me faltan, o una remoción contra agro."""
    cands = hab.candidatos_validos(p, yo, fuente, h)
    # Solo si de verdad faltan (2 o más Oros por detrás de los turnos): lo
    # normal es barajar 2 Dragones útiles (Cathach, Draco Cometa, Magma).
    propios = (p.e.turno + (1 if p.e.activo == yo else 0)) // 2
    oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
    if not (oros < 6 and oros <= propios - 2):
        return False
    if any(c.tipo == Tipo.ORO for c in cands):
        return True
    return _mazo_agresivo(p, 1 - yo) and any(
        c.tipo == Tipo.TALISMAN and any(x.get("accion") in _REMOCION for x in c.habilidades) for c in cands)


def _amenaza_botar(c: Instancia) -> int:
    """Cuánto le bota al rival esta carta (Ramsés IX: 1 y 2 más; Kamose: 2)."""
    total = 0
    for h in c.habilidades:
        if h.get("accion") != "botar" or h.get("cuando") not in ("al_atacar", "al_jugar"):
            continue
        if (h.get("objetivo") or {}).get("quien", "oponente") not in ("oponente", "ambos"):
            continue
        total += int(h.get("cantidad", 1) or 1) + sum(
            int(e.get("cantidad", 1) or 1) for e in h.get("luego") or []
            if e.get("accion") == "botar" and (e.get("objetivo") or {}).get("quien") == "oponente"
        )
    return total


def _es_sacrificio(h: dict) -> bool:
    """Vouivre: "baraja un Aliado tuyo para barajar 2 del rival"."""
    obj = h.get("objetivo") or {}
    return h.get("accion") in ("barajar", "destruir", "desterrar") and obj.get("quien") == "propio" and any(
        e.get("accion") in _REMOCION | {"barajar"} and (e.get("objetivo") or {}).get("quien") == "oponente"
        for e in h.get("luego") or []
    )


_ORO_ETB_INUTIL = False  # 2026-11-13: neutro (−0,1 ±0,2 en 7.224 partidas); apagado


def _entrada_de_oro_inutil(p, yo, carta: Instancia) -> bool:
    """Un Oro que vale por lo que hace al entrar (Salmón, Ib-Mut, Ceangal,
    Látigo y Bastón, Marmita, Árbol de Sangre...) y hoy no tiene sobre qué
    actuar: mejor bajar otro y guardarlo. Solo si TODA su habilidad es de
    entrada (Salmón también protege desde la Reserva: no cuenta)."""
    habs = carta.habilidades
    entrada = [h for h in habs if h.get("cuando") == "al_jugar"]
    if not entrada or len(entrada) != len([h for h in habs if h.get("accion") != "errante"]):
        return False
    for h in entrada:
        accion = h.get("accion")
        obj = h.get("objetivo") or {}
        if accion in ("robar", "mirarTope", "botar", "otorgarPropiedad", "generarOro"):
            return False  # siempre hace algo
        if accion == "barajar" and obj.get("zona") == "cementerio":
            if obj.get("quien") in ("ambos", "cualquiera"):
                return False  # Ib-Mut: baraja el rival también y roba
            if p.j(yo).cementerio:
                return False
            continue
        if accion == "mostrar":
            if any(hab.coincide(p, c, {**obj, "quien": None}) for c in p.j(yo).mano if c is not carta):
                # Látigo y Bastón: además hace falta algo que barajar
                if not any(e.get("accion") == "barajar" for e in h.get("luego") or []) or p.j(yo).cementerio:
                    return False
            continue
        if accion == "destruir" and (h.get("costo") or {}).get("orosSegun") == "coste_objetivo":
            # Ceangal: paga el coste del objetivo con los Oros que quedan
            oro = p.j(yo).oro_disponible  # este Oro se mueve a pagado como parte del costo
            if any(x.controlador != yo and x.tipo != Tipo.ORO and x.carta.coste <= oro
                   and hab.coincide(p, x, obj) for x in p.e.instancias_en_juego(1 - yo)):
                return False
            continue
        return False  # acción que no sé evaluar: no la castigo
    return True


_VETO_ATAQUE_SIMETRICO = True  # 2026-11-13 auditoría de cartas (Tebas)


def _veto_ataque_me_perjudica(p, yo, inst: Instancia) -> bool:
    """Tebas: "los Aliados de fuerza 3 o más no pueden ser declarados
    atacantes" vale para los dos lados. Se baja solo si frena más al rival
    que a mí (lo que tengo en mesa y en la mano), no por ser lo más caro."""
    habs = [h for h in inst.habilidades if h.get("accion") == "restringirCombate"
            and h.get("modo") == "no_puede_atacar" and h.get("cuando") == "continua"
            and (h.get("objetivo") or {}).get("quien") in ("cualquiera", "ambos")]
    if not habs:
        return False
    obj = habs[0].get("objetivo") or {}
    filtro = {k: v for k, v in obj.items() if k in ("tipos", "fuerza", "fuerzaMin", "fuerzaMax", "raza")}

    def frenados(i):
        return sum(hab.fuerza(p, a) for a in p.j(i).aliados
                   if hab.coincide(p, a, filtro) and not hab.tiene_prop(p, a, "guardian"))
    mios = frenados(yo) + 0.5 * sum(c.carta.fuerza for c in p.j(yo).mano
                                    if c.tipo == Tipo.ALIADO and hab.coincide(p, c, filtro))
    suyos = frenados(1 - yo)
    if suyos == 0 and mios == 0:
        return any(x.nombre == inst.nombre for x in p.e.instancias_en_juego())  # 2a copia: nada
    return suyos <= mios


def _sin_objetivo_al_entrar(p, yo, inst: Instancia) -> bool:
    """#3 UUOX: Guardia Gozosa entra a quitarle la habilidad y destruir un
    Aliado rival: sin Aliados rivales no se juega."""
    if inst.tipo == Tipo.TALISMAN and _descarte_rival(inst) and not p.j(1 - yo).mano:
        return True  # Cruzada de los Niños con el rival sin cartas en la mano
    if inst.tipo != Tipo.TOTEM:
        return False
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") == "al_jugar" and not h.get("opcional") and obj.get("quien") == "oponente" \
                and h.get("accion") in _REMOCION | {"perderHabilidad"} and "Aliado" in (obj.get("tipos") or []):
            return not any(hab.coincide(p, x, obj) and not hab.inmune(p, x, inst) for x in hab.candidatos(p, yo, inst, h))
    return False


def _sacrificio_sin_combo(p, yo, inst: Instancia) -> bool:
    """Vouivre se baja para barajar 2 Aliados rivales (barajando otro mío).
    Sin ese combo, solo en un caso extremo: en peligro o sin nada más en la mano."""
    if inst.tipo != Tipo.ALIADO:
        return False
    habs = [h for h in inst.habilidades if h.get("cuando") == "al_jugar" and _es_sacrificio(h)]
    if not habs:
        return False
    if any(hab.condicion_ok(p, yo, h) and _sacrificio_que_remueve(p, yo, inst, h) for h in habs):
        return False
    # Héctor 2026-11-12: Vouivre es el motor del mazo (busca un Dragón cada
    # turno). Su entrada es opcional: no se guarda esperando el combo.
    if any(
            _habilidad_repetible(h) for h in inst.habilidades):
        return False
    return not (_en_peligro(p, yo) or len(p.j(yo).mano) <= 1)


def _aliado_temporal(h: dict) -> bool:
    """Cruz Templaria: el Aliado que trae se destierra en la Fase Final."""
    return h.get("accion") == "jugarDesde" and any(
        e.get("momento") == "fase_final" and e.get("accion") == "desterrar" for e in h.get("luego") or []
    )


def _saca_una_amenaza(p, yo, c: Instancia) -> bool:
    """El Aliado saca al entrar un Aliado rival que pesa (Dragón de Magma a Ramsés II)."""
    for x in c.habilidades:
        obj = x.get("objetivo") or {}
        if x.get("cuando") in ("al_jugar", None) and x.get("accion") in _REMOCION \
                and obj.get("quien") in ("oponente", "cualquiera") and "Aliado" in (obj.get("tipos") or ["Aliado"]):
            if any(_amenaza_en_mesa(p, a) and hab.coincide(p, a, obj) for a in p.j(1 - yo).aliados):
                return True
    return False


def _amenaza_en_mesa(p, a: Instancia) -> bool:
    """Un Aliado rival que pesa: fuerza 3 o más, o con habilidades que sigue
    usando (no solo la de "al entrar", que ya gastó)."""
    return hab.fuerza(p, a) >= 3 or any(
        h.get("cuando") not in ("al_jugar", None) and h.get("accion") not in hab.PROPIEDADES
        for h in a.habilidades
    )


def _roba(c: Instancia) -> bool:
    """La carta hace robar a quien la juega (Forma de Lince en la Fase Final)."""
    return any(
        x.get("accion") == "robar" and (x.get("objetivo") or {}).get("quien", "propio") == "propio"
        for h in c.habilidades for x in [h, *(h.get("luego") or [])]
    )


def _recupera_desde_cementerio(c: Instancia) -> bool:
    """Lady Calvaur: desde el Cementerio sacrifica un Dragón y vuelve a mano.

    No es una carta que convenga reciclar con Cathach/Killgharrah/Milano:
    deja de ser una amenaza recuperable y se pierde ese intercambio.
    """
    return any(
        h.get("zonaActivacion") == "cementerio"
        and any(e.get("accion") == "subirMano" and (e.get("objetivo") or {}).get("quien") == "esta_carta"
                for e in h.get("luego") or [])
        for h in c.habilidades
    )


def _reciclable_prioritario(c: Instancia) -> bool:
    """Soporte y motores de reciclaje son mejores objetivos de barajar.

    Con Killgharrah se quieren recuperar herramientas antes que Aliados que
    se pueden volver a jugar o recuperar por sus propias habilidades.
    """
    return c.tipo != Tipo.ALIADO or any(h.get("accion") == "barajar" for h in c.habilidades)


def _descarte_rival(c: Instancia) -> int:
    """Cruzada de los Niños: cuántas cartas descarta de la mano rival al jugarse."""
    return sum(
        int(h.get("cantidad", 1) or 1) for h in c.habilidades
        if h.get("cuando") in ("al_jugar", None) and h.get("accion") == "descartar"
        and (h.get("objetivo") or {}).get("quien") == "oponente"
        and (h.get("objetivo") or {}).get("zona", "mano") == "mano"
    )


def _ramp_de_oro(c: Instancia) -> bool:
    """Alquimista: busca un Oro y lo pone en la Reserva al jugarse."""
    return any(
        h.get("cuando") in ("al_jugar", None) and h.get("accion") == "buscar"
        and h.get("zonaDestino") == "reserva_oro" for h in c.habilidades
    )


def _ramp_temprano(p, yo) -> bool:
    """La aceleración gana prioridad solo durante la curva inicial."""
    return len(p.j(yo).reserva) + len(p.j(yo).pagado) <= 4


def _potenciador_de_ataque(c: Instancia) -> bool:
    """Forma de Lince: Talismán que sube la fuerza (y además roba)."""
    return c.tipo == Tipo.TALISMAN and any(
        h.get("accion") == "modificarFuerza" and int(h.get("valor", 0) or 0) > 0 for h in c.habilidades
    )


def _potenciado_este_turno(p, c: Instancia) -> bool:
    """Se invirtió una mejora temporal en este Aliado durante esta Vigilia.

    Es relevante antes de declarar ataques: si gastamos el Cementerio y una o
    más activaciones del Merodeador para mejorar al Medjay, no tiene sentido
    dejarlo en casa por el filtro conservador de que también bota mi castillo.
    Aun así nunca se permite el ataque que me derrota de inmediato.
    """
    return any(
        m.turno == p.e.turno and m.modo == "sumar" and m.valor > 0
        and m.duracion in ("hasta_fase_final", "hasta_vigilia")
        for m in c.mods
    )


def _lince_puede_robar(p, carta: Instancia) -> bool:
    """La razón táctica para anular Forma de Lince es cortar su robo.

    La carta roba solo si el Aliado afectado llega a hacer daño. En Guerra de
    Talismanes la jugada viene con atacantes ya declarados; uno libre es la
    señal segura de que ese robo mantendría al rival con mano corta.
    """
    if not (_potenciador_de_ataque(carta) and _roba(carta)):
        return False
    return any(
        a.controlador == carta.controlador and a.en_juego
        and p.bloqueos.get(a.uid) is None
        for a in p.atacantes
    )


def _rescate_lady(h: dict) -> bool:
    """Lady Calvaur: desde el Cementerio, destruye un Dragón propio para
    volver a la mano."""
    obj = h.get("objetivo") or {}
    return (h.get("zonaActivacion") == "cementerio" and h.get("accion") in ("destruir", "desterrar", "barajar")
            and obj.get("quien") == "propio" and any(
                e.get("accion") == "subirMano" and (e.get("objetivo") or {}).get("quien") == "esta_carta"
                for e in h.get("luego") or []))


def _sale_con_premio(p, yo, c: Instancia) -> bool:
    """Dragón que al salir del juego me deja algo: Draig Ifanc pone un Oro en
    la Reserva (si solo controlo Dragones); Draco Pútrido destierra un Aliado
    rival de coste 4 o menos (si hay uno)."""
    for x in c.habilidades:
        if x.get("cuando") != "al_salir_del_juego" or not hab.condicion_ok(p, yo, x):
            continue
        obj = x.get("objetivo") or {}
        if obj.get("quien", "propio") == "propio" and x.get("accion") in ("ponerEnJuego", "buscar", "robar", "generarOro"):
            return True
        if obj.get("quien") == "oponente" and x.get("accion") in _REMOCION and any(
            hab.coincide(p, a, obj) for a in p.j(1 - yo).aliados
        ):
            return True
    return False


def _victima_rescate(p, yo, candidatos, *, la_juego_ya: bool = False, lady: Instancia | None = None):
    """A quién destruyo para recuperar a Lady Calvaur: Draig Ifanc o Draco
    Pútrido, que al morir me dejan algo. Otro Dragón (el que menos vale) solo
    si Lady se juega de inmediato."""
    propios = [c for c in candidatos if c.controlador == yo]
    premio = [c for c in propios if _sale_con_premio(p, yo, c)]
    if premio:
        return min(premio, key=lambda c: _valor_vivo(p, c))
    if la_juego_ya and propios:
        # Otra Lady en mesa también sirve: se destruye, vuelve la del
        # Cementerio y se juega (destierra 2 de nuevo, casi todos los turnos).
        otra_lady = [c for c in propios if lady is not None and c.nombre == lady.nombre]
        if _CORRECCIONES_2:
            # Héctor (2376 T25): destruir una Lady para recuperar otra no gana
            # nada si el rival no tiene qué desterrar; solo vale con objetivos.
            suyas = [x for x in p.e.instancias_en_juego(1 - yo) if x.tipo != Tipo.ORO]
            if otra_lady and len(suyas) >= 1:
                return otra_lady[0]
            resto = [c for c in propios if c not in otra_lady]
            return min(resto, key=lambda c: _valor_vivo(p, c)) if resto and suyas else None
        return otra_lady[0] if otra_lady else min(propios, key=lambda c: _valor_vivo(p, c))
    return None


def _capacidad_lady(p, yo, *, extra: int = 0) -> bool:
    """Ya puedo pagar a Lady Calvaur con lo que tengo en juego: 7 Oros, o 5
    más Dragones (que se paga y genera 2 para un Dragón de coste 4+).
    `extra`: Oros que agrego antes (el del próximo turno)."""
    oros = p.j(yo).reserva + p.j(yo).pagado
    dragones = any(h.get("accion") == "generarOro" and int(h.get("soloParaCosteMin", 0) or 0) <= 7
                   and h.get("soloParaRaza") for o in oros for h in o.habilidades)
    n = len(oros) + extra
    return n >= 7 or (dragones and n >= 6)


def _frenar_agro_primero(p, yo, salvo: Instancia | None = None) -> bool:
    """El rival me presiona (4+ de fuerza en mesa o más que yo) y tengo en la
    mano una remoción que pago ahora (Bola de Fuego, Guardia Gozosa, Desleal):
    eso va antes que el combo Draig Ifanc + Lady."""
    if sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados) < 4 and not _rival_agro(p, yo):
        return False
    for c in p.j(yo).mano:
        if c is salvo or c.tipo == Tipo.ORO or not p.puede_pagar(yo, c):
            continue
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION | {"perderHabilidad"} \
                    and obj.get("quien") in ("oponente", "cualquiera") \
                    and any(hab.coincide(p, a, obj) for a in p.j(1 - yo).aliados):
                return True
    return False


def _rival_usa_cementerio(p, quien) -> bool:
    """El rival saca provecho de su Cementerio: cartas que se juegan desde ahí
    (Jinetes de Fuego, Espada Miliciana) o que pagan desterrando de ahí
    (Nephre-Ka). Atacarlo le llena el Cementerio."""
    jug = p.j(quien)
    # Solo lo que todavía puede usarlo: un Nephre-Ka ya desterrado o en el
    # Cementerio no cuenta; un Jinetes de Fuego en el Cementerio sí (se juega de ahí).
    for c in jug.mazo + jug.mano + list(p.e.instancias_en_juego(quien)) + jug.cementerio:
        en_cementerio = c.zona == Zona.CEMENTERIO
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            costo = h.get("costo") or {}
            if h.get("accion") == "jugarDesde" and "cementerio" in hab.zonas_de(obj, ""):
                return True
            if not en_cementerio and any(k.startswith("desterrarCementerio") for k in costo):
                return True
    return False


def _tutor_en_mano(p, yo):
    """Devuelve una función que puntúa cuánto conviene tener una carta en el
    mazo para que la busque algo de mi mano (La Llama Fría trae un Aliado del
    mazo: Lady Calvaur si no queda ninguna ahí)."""
    from .motor import Jugada

    jug = p.j(yo)
    filtros = []
    for c in jug.mano:
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("cuando") in ("al_jugar", None) and h.get("accion") in ("jugarDesde", "buscar") \
                    and obj.get("quien", "propio") == "propio" and "mazo" in hab.zonas_de(obj, ""):
                filtros.append(obj)

    def puntaje(c):
        if not filtros or c.tipo == Tipo.ORO or any(x.nombre == c.nombre for x in jug.mazo):
            return 0.0
        if not any(hab.coincide(p, c, {**o, "zona": "cementerio", "zonas": []}) for o in filtros):
            return 0.0
        return Heuristico(0)._puntaje(p, yo, Jugada("jugar", c))

    return puntaje


def _trono_conviene(p, yo, trono: Instancia) -> bool:
    """Trono Dorado (baraja este Oro: destierra del Cementerio rival y roba):
    1) hacer mazo si el ataque rival me gana; 2) desterrar la carta más
    importante del Cementerio rival (la que juega o recicla desde ahí);
    3) robar con urgencia teniendo Oros de sobra."""
    jug, rival = p.j(yo), p.j(1 - yo)
    castillo = len(jug.mazo)
    if p.atacantes and p.e.activo != yo:
        golpe = sum(max(0, hab.fuerza(p, a)) for a in p.atacantes)
    else:
        golpe = sum(max(0, hab.fuerza(p, a)) for a in rival.aliados)
    if golpe >= castillo - 1:
        return True  # 1) una carta más en el castillo
    if p.__dict__.get("trono_usado", {}).get(yo) == p.e.turno:
        return False  # I4Sl2 #6: un Trono por turno (no se queman Oros en cadena)
    recicla = _rival_recicla_cementerio(p, 1 - yo)
    if any(_vale_en_cementerio(c) or (recicla and (_pieza_clave(c) or _valor_carta(p, c) >= 9))
           for c in rival.cementerio):
        return True  # 2) Jinetes de Fuego, o un Rey Arturo que Sir Erec recuperaría
    sin_jugar = not any(c.tipo != Tipo.ORO and p.puede_pagar(yo, c) for c in jug.mano if c is not trono)
    oros = len(jug.reserva) + len(jug.pagado)
    return len(jug.mano) <= 1 and sin_jugar and oros >= 5 and not _juntando_oros(p, yo)  # 3)


def _rival_recicla_cementerio(p, quien) -> bool:
    """El rival tiene cómo recuperar cartas de su Cementerio (Sir Erec,
    Diadema Feerica, Guardia Gozosa): barajar, subir o jugar desde ahí."""
    jug = p.j(quien)
    # I4Sl2 #6: solo lo que se ve (en juego, mano revelada, su Cementerio); antes
    # miraba su mazo y su mano ocultos y casi siempre daba "sí".
    visibles = list(p.e.instancias_en_juego(quien)) + list(jug.cementerio) \
        + [c for c in jug.mano if getattr(c, "revelada", False)]
    for c in visibles:
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("accion") in ("barajar", "subirMano", "jugarDesde", "ponerEnJuego", "mover") \
                    and obj.get("quien") == "propio" and "cementerio" in hab.zonas_de(obj, ""):
                return True
    return False


def _vale_en_cementerio(c: Instancia) -> bool:
    """Se juega o se recupera desde el Cementerio (Furia Irracional, Jinetes de
    Fuego, Lady Calvaur, Corona de Arturo): no se destierra para pagar."""
    return _se_juega_del_cementerio(c) or any(
        hab.zona_activacion(h) == "cementerio" for h in c.habilidades
    )


def _reserva_reactiva(p, yo, salvo: Instancia | None = None) -> int:
    """qSMg #1: el Dragón (control) contra un agro guarda Oros para sus
    remociones de la Guerra de Talismanes rival: Toque de Pérsival (1) cuando
    ataque y Bola de Fuego (2) al siguiente. Devuelve los Oros a guardar
    (`salvo`: sin contar esa carta, la que estoy pensando jugar ya)."""
    if p.e.fase != "vigilia" or p.e.activo != yo or not _mazo_lento(p, yo) or not _mazo_agresivo(p, 1 - yo):
        return 0
    costes = []
    for c in p.j(yo).mano:
        if c.tipo != Tipo.TALISMAN or c is salvo:
            continue
        if any(h.get("accion") in _REMOCION | {"barajar"}
               and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
               and "Aliado" in ((h.get("objetivo") or {}).get("tipos") or ["Aliado"])
               # lKff: el Homunculus destierra del Cementerio: no frena un ataque.
               and "en_juego" in hab.zonas_de(h.get("objetivo") or {}, "en_juego")
               and h.get("fase") in (None, "cualquiera", "guerra_talismanes") for h in c.habilidades) \
                and p.coste_de(yo, c) <= 2:
            # kFaZ: solo respuestas baratas (Toque, Bola, Capa); el Desleal (3)
            # se juega en mi turno: no se guarda todo y se propone algo.
            costes.append(p.coste_de(yo, c))
    total = 0
    for k in sorted(costes):
        if total + k <= p.j(yo).oro_disponible:
            total += k
    return total


def _cementerio_rival_sirve(p, yo) -> bool:
    """El Cementerio del rival ya le rinde: 3+ cartas, un Jinetes de Fuego para
    jugar de ahí, o un Aliado en mesa que paga desterrando de ahí (Merodeador,
    Neferite). Con el Cementerio vacío (y sin atacarlo) el Cinturón espera."""
    rival = 1 - yo
    if not _rival_usa_cementerio(p, rival):
        return False
    cem = p.j(rival).cementerio
    if len(cem) >= 3 or any(_se_juega_del_cementerio(c) and c.tipo == Tipo.TALISMAN for c in cem):
        return True
    return any(any(k.startswith("desterrarCementerio") for h in a.habilidades for k in (h.get("costo") or {}))
               for a in p.e.instancias_en_juego(rival)) and len(cem) >= 1


def _peligro(p, a: Instancia) -> float:
    """#6 EZMt: qué tan peligroso es un Aliado rival en mesa: fuerza, lo que
    bota, si castiga el bloqueo, si es Imbloqueable y si tiene habilidades que
    sigue usando (Merodeador, Guerreros Egipcios). Nephre-Ka ya gastó la suya."""
    vivas = sum(1 for h in a.habilidades
                if h.get("cuando") not in ("al_jugar", None) and h.get("accion") not in hab.PROPIEDADES)
    v = (max(0, hab.fuerza(p, a)) + _amenaza_botar(a) + _castigo_si_lo_bloquean(p, a)
         + (3 if hab.tiene_prop(p, a, "imbloqueable") else 0) + 2.5 * vivas
         + (6 if _pieza_clave(a) else 0))
    # UBsS #4: el Escorpión ya inhabilitado por Draco Cometa no se vuelve a sacar.
    return v * 0.1 if _inhabilitado(p, a) else v


def _inhabilitado(p, a: Instancia) -> bool:
    """Sin habilidad y sin poder atacar ni bloquear (Draco Cometa)."""
    return (a.sin_habilidad_hasta is not None and hab.tiene_estado(p, a, "no_puede_atacar")
            and hab.tiene_estado(p, a, "no_puede_bloquear"))


def _atacantes_esperados(p, yo) -> int:
    """Con cuántos Aliados me puede atacar el rival en su próximo turno: los
    que tiene en mesa (no inhabilitados) y uno más si tiene con qué darle
    ataque inmediato (Corona Faraónica, Guerrero Escorpión) y cartas en la mano."""
    rival = 1 - yo
    n = sum(1 for a in p.j(rival).aliados if not _inhabilitado(p, a) and hab.fuerza(p, a) > 0)
    oros_rival = p.j(rival).reserva + p.j(rival).pagado
    rapido = any(_oro_que_acelera_ataques(c) for c in oros_rival) or any(
        h.get("accion") == "otorgarPropiedad" and h.get("modo") == "furia" and h.get("cuando") == "continua"
        for a in p.j(rival).aliados for h in a.habilidades)
    return n + (1 if rapido and p.j(rival).mano else 0)


def _combo_al_entrar(p, yo, c: Instancia) -> bool:
    """Vouivre con 2+ Aliados rivales y otro mío que barajar: su entrada vale
    aunque cueste 5 (para La Llama Fría)."""
    return c.tipo == Tipo.ALIADO and any(
        h.get("cuando") == "al_jugar" and _es_sacrificio(h) and hab.condicion_ok(p, yo, h)
        and any(a is not c for a in p.j(yo).aliados)
        for h in c.habilidades)


def _valor_busqueda_vouivre(p, yo, c: Instancia) -> float:
    """El Dragón que Vouivre busca debe responder al estado, no al coste.

    Prioriza la herramienta que falta: remover o debilitar la mesa rival,
    reciclar cuando el castillo está corto o reponer la mano. El valor base
    conserva los combos y otras prioridades generales del mazo.
    """
    valor = _valor_para_el_plan(p, yo, c)
    rival = p.j(1 - yo)
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION \
                and obj.get("quien") in ("oponente", "cualquiera"):
            valor += 6 * sum(1 for a in rival.aliados if hab.coincide(p, a, obj))
        if h.get("accion") == "modificarFuerza" and int(h.get("valor", 0) or 0) < 0 \
                and obj.get("quien") in ("oponente", "cualquiera"):
            valor += 3 * len(rival.aliados)
        if h.get("accion") == "robar" and len(p.j(yo).mano) <= 3:
            valor += 6
        if h.get("accion") == "barajar" and "cementerio" in hab.zonas_de(obj, "") \
                and len(p.j(yo).mazo) <= 12:
            valor += 7
    if _OP("VB"):
        valor += _vouivre_plan_hector(p, yo, c)
    return valor


def _OP(k: str) -> bool:
    """Jugadas de Vouivre enseñadas por Héctor (2026-11-12); todas activas."""
    return True


def _vouivre_espera(p, yo) -> bool:
    """Héctor 2026-11-12: con Vouivre en la mano y pagable el próximo turno,
    a veces conviene no bloquear: mi Aliado sigue vivo para barajarlo y el
    rival conserva 2+ Aliados, así Vouivre baraja 2 de los suyos."""
    jug = p.j(yo)
    v = next((c for c in jug.mano if any(_es_sacrificio(h) for h in c.habilidades)), None)
    if v is None or len(p.j(1 - yo).aliados) < 2 or not jug.aliados:
        return False
    return hab.oros_en_juego(p, yo) + 1 >= p.coste_de(yo, v)


def _motor_reciclaje(c: Instancia) -> bool:
    """Gaspar: baraja del Cementerio cada turno (activada repetible)."""
    return any(h.get("accion") == "barajar" and h.get("cuando") == "activada"
               and _habilidad_repetible(h) and "cementerio" in hab.zonas_de(h.get("objetivo") or {}, "")
               for h in c.habilidades)


def _vouivre_plan_hector(p, yo, c: Instancia) -> float:
    """Héctor 2026-11-12: con Vouivre (1) traer Cultistas y jugarlo ya para
    sacarle un Aliado de la mano al rival; (2) sin motor de reciclaje en mesa,
    traer Gaspar (o Cathach) para empezar a barajar desde el próximo turno."""
    v = 0.0
    jug, rival = p.j(yo), p.j(1 - yo)
    if any(_cultista(h) for h in c.habilidades) and len(rival.mano) >= 2 \
            and p.e.activo == yo and p.e.fase == "vigilia" and hab.oro_para(p, yo, c) >= p.coste_de(yo, c):
        v += 12.0
    # Reciclar solo bajo presión (su agro o mi castillo corto); con la mesa
    # controlada, Vouivre sigue con removal o Killgharrah (el orden de siempre).
    presionado = _rival_agro(p, yo) or _en_peligro(p, yo) or len(jug.mazo) <= 20
    if not presionado:
        return v
    if _motor_reciclaje(c) and not any(_motor_reciclaje(a) for a in jug.aliados):
        v += 12.0
    elif any(h.get("cuando") == "al_jugar" and h.get("accion") == "barajar"
             and "cementerio" in hab.zonas_de(h.get("objetivo") or {}, "") for h in c.habilidades) \
            and len(jug.cementerio) >= 2 and len(jug.mazo) <= 30:
        v += 3.0
    return v


def _saca_varios(p, yo, inst: Instancia) -> bool:
    """UBsS #3: al entrar saca 2 o más Aliados rivales (Lady destierra 2, Nival
    barre, Ma Arrat destierra todos) sin llevarse más de los míos."""
    if inst.tipo == Tipo.ORO:
        return False
    suyos, mios = _victimas_barrida(p, yo, inst)
    if suyos >= 2 and suyos > mios:
        return True
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION \
                and obj.get("quien") == "oponente" and int(h.get("cantidad", 1) or 1) >= 2:
            if sum(1 for a in p.j(1 - yo).aliados if hab.coincide(p, a, obj) and not _inhabilitado(p, a)) >= 2:
                return True
    return False


def _lady_se_juega_ya(p, yo, lady: Instancia | None) -> bool:
    """Lady Calvaur vuelve a la mano y se paga en esta misma Vigilia: 7 Oros,
    o 6 y Dragones (pagarlo genera 2 para un Dragón de coste 4 o más)."""
    return (lady is not None and p.e.activo == yo and p.e.fase == "vigilia"
            and hab.oro_para(p, yo, lady) + _oro_por_generar(p, yo, lady) >= p.coste_de(yo, lady))


def _oro_por_generar(p, yo, carta: Instancia) -> int:
    """Oros extra que puedo generar ahora para pagar esta carta: Dragones en
    la Reserva se paga a sí mismo (−1) y da 2 para un Dragón de coste 4+."""
    extra = 0
    for o in p.j(yo).reserva:
        for h in o.habilidades:
            if h.get("accion") != "generarOro" or h.get("cuando") != "activada":
                continue
            if h.get("fase") not in (None, "cualquiera", p.e.fase):
                continue
            tipos, raza = h.get("soloParaTipos") or [], h.get("soloParaRaza") or ""
            minimo = int(h.get("soloParaCosteMin", 0) or 0)
            if ((tipos and carta.tipo.value not in tipos) or (raza and raza not in (carta.raza or ""))
                    or carta.carta.coste < minimo):
                continue
            paga = 1 if (h.get("costo") or {}).get("pagarEstaCarta") else 0
            extra += max(0, int(h.get("valor", 0) or 0) - paga)
            break
    return extra


def _rescate_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Combo del Dragón: Draig Ifanc (rampea un Oro) o Draco Pútrido
    (destierra un Aliado rival) se destruyen y Lady Calvaur vuelve a la mano."""
    cands = [c for c in hab.candidatos_validos(p, yo, fuente, h) if c is not fuente]
    if any(_sale_con_premio(p, yo, c) for c in cands if c.controlador == yo):
        return True
    if any(_gana_al_morir(c) and c.raza == "Dragón" and p.puede_pagar(yo, c) for c in p.j(yo).mano):
        return False  # #9 c0p0: primero bajo a Draig Ifanc y lo uso a él (rampea un Oro)
    return _victima_rescate(p, yo, cands, la_juego_ya=_lady_se_juega_ya(p, yo, fuente), lady=fuente) is not None


def _genera_restringido_inutil(p, yo, h: dict) -> bool:
    """#7/#8 c0p0: Dragones genera 2 solo para Dragones de coste 4+: no se
    paga si no hay en la mano uno así que se juegue con eso."""
    if h.get("accion") != "generarOro":
        return False
    tipos, raza = h.get("soloParaTipos") or [], h.get("soloParaRaza") or ""
    minimo = int(h.get("soloParaCosteMin", 0) or 0)
    if not (tipos or raza or minimo):
        return False  # los generadores restringidos se evalÃºan con su regla propia
    oros = p.j(yo).oro_disponible - 1 + int(h.get("valor", 0) or 0)
    return not any(
        c.tipo != Tipo.ORO and (not tipos or c.tipo.value in tipos) and (not raza or raza in (c.raza or ""))
        and c.carta.coste >= minimo and p.coste_de(yo, c) <= oros
        for c in p.j(yo).mano
    )


def _generar_oro_inutil(p, yo, h: dict) -> bool:
    """No activa un generador si el Oro temporal expirar\u00eda sin habilitar nada."""
    if h.get("accion") != "generarOro":
        return False
    tipos, raza = h.get("soloParaTipos") or [], h.get("soloParaRaza") or ""
    minimo = int(h.get("soloParaCosteMin", 0) or 0)
    if tipos or raza or minimo:
        return False
    costo = int((h.get("costo") or {}).get("oros", 0) or 0)
    disponibles = p.j(yo).oro_disponible - costo
    extra = int(h.get("valor", 0) or 0)
    return not any(
        c.tipo != Tipo.ORO
        and (not tipos or c.tipo.value in tipos)
        and (not raza or raza in (c.raza or ""))
        and c.carta.coste >= minimo
        and disponibles < p.coste_de(yo, c) <= disponibles + extra
        and not _sin_objetivo_al_entrar(p, yo, c)
        for c in p.j(yo).mano
    )


def _amenaza_que_entra(p, c: Instancia) -> bool:
    """#10 c0p0: vale una Capa de Invisibilidad (sacarla del juego al entrar):
    fuerza 3+, Imbloqueable, que bota, castiga el bloqueo o es pieza clave."""
    if c.tipo != Tipo.ALIADO:
        return c.carta.coste >= 3
    f = hab.fuerza(p, c) if c.en_juego else c.carta.fuerza
    return (f >= 3 or hab.tiene_prop(p, c, "imbloqueable") or _amenaza_botar(c) > 0
            or _castigo_si_lo_bloquean(p, c) > 0 or _pieza_clave(c))


def _remocion_clave(p, yo, inst: Instancia) -> bool:
    """#1/#2 c0p0: Desleal tiene a mano una pieza clave rival (Neferite I
    destierra cada turno) o un Aliado que bota."""
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in _REMOCION \
                or obj.get("quien") != "oponente":
            continue
        for a in p.j(1 - yo).aliados:
            if hab.coincide(p, a, obj) and (_pieza_clave(a) or any(
                x.get("cuando") == "activada" and x.get("accion") in _REMOCION
                and (x.get("objetivo") or {}).get("quien") == "oponente" for x in a.habilidades
            ) or _amenaza_botar(a) > 0):
                return True
    return False


def _genera_recursos(c: Instancia) -> int:
    """i4b3 #1: lo que le da recursos al rival al entrar o en cada turno:
    Aton busca un Oro, Amosis I mira y toma, Guerrero Escorpión roba."""
    n = 0
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("accion") in ("robar", "mirarTope", "generarOro") and obj.get("quien", "propio") != "oponente":
            n += 1
        elif h.get("accion") in ("buscar", "ponerEnJuego") and obj.get("quien", "propio") == "propio":
            n += 1
    return n


def _peligro_en_mano(p, c: Instancia) -> float:
    """Daño que hará al entrar en mesa: fuerza, Imbloqueable, Furia."""
    f = c.carta.fuerza if c.tipo == Tipo.ALIADO else 0
    return f + (3 if hab.tiene_prop(p, c, "imbloqueable") else 0) + (2 if hab.tiene_prop(p, c, "furia") else 0)


def _nombra_en_mazo_rival(fuente: Instancia) -> bool:
    """Orfeo: nombra una carta y destierra una copia del Mazo rival."""
    return any((h.get("objetivo") or {}).get("nombrarCarta") and (h.get("objetivo") or {}).get("zona") == "mazo"
               and (h.get("objetivo") or {}).get("quien") == "oponente" for h in fuente.habilidades)


def _nombra_en_mano_rival(fuente: Instancia) -> bool:
    """Sir Bedivere: nombra un Aliado y lo toma de la Mano rival."""
    return any((h.get("objetivo") or {}).get("nombrarCarta") and (h.get("objetivo") or {}).get("zona") == "mano"
               and (h.get("objetivo") or {}).get("quien") == "oponente" for h in fuente.habilidades)


def _copias_posibles_en_mazo(p, yo) -> dict:
    """Con información pública: copias de cada carta del rival que todavía
    pueden estar en su Mazo (su lista menos las vistas en mesa, Cementerio,
    Destierro o reveladas; una Única vista ya no está). Valor: (copias, valor)."""
    import collections
    rival = p.j(1 - yo)
    todas = rival.mazo + rival.mano + rival.cementerio + rival.destierro + rival.pagado \
        + list(p.e.instancias_en_juego(1 - yo))
    total = collections.Counter(c.nombre for c in todas)
    vistas = collections.Counter(
        c.nombre for c in rival.cementerio + rival.destierro + rival.pagado + list(p.e.instancias_en_juego(1 - yo))
    ) + collections.Counter(c.nombre for c in rival.mano if getattr(c, "revelada", False))
    valor = {}
    for c in todas:
        if c.nombre in valor:
            continue
        unica = "única" in (c.carta.texto or "").casefold()[:12]
        quedan = (0 if unica and vistas[c.nombre] else total[c.nombre] - vistas[c.nombre])
        valor[c.nombre] = (max(0, quedan), _valor_carta(p, c))
    return valor


def _cultista(h: dict) -> bool:
    """Cultistas del Dragón: se destruye para mirar la mano rival y barajar
    un Aliado de ahí en su Mazo."""
    return h.get("accion") == "mirar" and any(
        e.get("accion") == "barajar" and (e.get("objetivo") or {}).get("zona") == "mano"
        and (e.get("objetivo") or {}).get("quien") == "oponente" for e in h.get("luego") or []
    )


def _cultista_tiene_mano(p, yo) -> bool:
    """Cultistas presiona la mano corta de un mazo agro.

    Entre una y cinco cartas, cada Aliado que pueda quitarse puede ser su
    próximo desarrollo o motor. Con seis o más cartas todavía hay demasiadas
    alternativas (Oros y Talismanes incluidos), así que no se fuerza.
    """
    # Héctor 2026-11-12: el Cultista se juega para activarlo de inmediato.
    return len(p.j(1 - yo).mano) >= 1


def _combo_draig_lady_listo(p, yo) -> bool:
    """Draig Ifanc en mano y Lady recuperable: es mejor curva que Alquimista."""
    lady_en_cementerio = any(
        any(_rescate_lady(h) for h in carta.habilidades)
        for carta in p.j(yo).cementerio
    )
    return lady_en_cementerio and any(
        carta.nombre.casefold() == "draig ifanc" and p.puede_pagar(yo, carta)
        for carta in p.j(yo).mano
    )


def _sacrificio_que_remueve(p, yo, fuente: Instancia, h: dict) -> bool:
    """#7 Zrfq: Vouivre baraja un Aliado propio para barajar 2 del rival.
    Conviene si lo del rival vale más (Draig Ifanc al irse rampea un Oro)."""
    obj = h.get("objetivo") or {}
    if h.get("accion") not in ("barajar", "destruir", "desterrar") or obj.get("quien") != "propio":
        return False
    luego = [e for e in h.get("luego") or [] if e.get("accion") in _REMOCION | {"barajar"}
             and (e.get("objetivo") or {}).get("quien") == "oponente"]
    if not luego:
        return False
    mios = [c for c in hab.candidatos_validos(p, yo, fuente, h) if c is not fuente]
    if not mios:
        return False
    costo = min(_valor_vivo(p, c) - (4 if _gana_al_morir(c) else 0) for c in mios)
    ganancia = 0.0
    for e in luego:
        suyos = sorted((_valor_vivo(p, c) for c in hab.candidatos_validos(p, yo, fuente, {**e, "cuando": None})),
                       reverse=True)
        ganancia += sum(suyos[: int(e.get("cantidad", 1) or 1)])
    return ganancia > costo


def _ataca_este_turno(p, c: Instancia) -> bool:
    """Puede ser declarado atacante ahora (no el Medjay recién jugado)."""
    return (c.zona == Zona.DEFENSA and c.listo  # la Furia ya lo deja listo al entrar
            and not hab.tiene_prop(p, c, "guardian") and not hab.tiene_estado(p, c, "no_puede_atacar")
            and hab.fuerza(p, c) > 0)


def _bono_al_atacar(c: Instancia) -> int:
    """Guerrero Bereber: +1 a sí mismo al ser declarado atacante."""
    return max([0] + [
        int(h.get("valor", 0) or 0) for h in c.habilidades
        if h.get("cuando") == "al_atacar" and h.get("accion") == "modificarFuerza"
        and (h.get("objetivo") or {}).get("quien") == "esta_carta" and not (h.get("costo") or {})
    ])


def _mejor_en_casa(p, yo, c: Instancia) -> bool:
    """#6 Zrfq: Draig Ifanc bloquea y, al morir, rampea un Oro. Contra un
    rival que ataca con varios, se queda en la Línea de Defensa."""
    rival = p.j(1 - yo)
    if not _gana_al_morir(c) or len(rival.mazo) <= 12 or _letal_al_atacar(p, yo, c):
        return False
    suyos = [a for a in rival.aliados if not hab.tiene_prop(p, a, "guardian")]
    return len(suyos) >= 2 and any(hab.fuerza(p, a) >= hab.fuerza(p, c) for a in suyos)


def _ultimo_defensor(p, yo, c: Instancia) -> bool:
    """#1 ZiXU: Bereber con el Escudo Miliciano es mi único bloqueador. Si
    ataca, el rival me pega con todo en su turno; en casa frena y mata a
    cualquiera de sus atacantes. Se queda, salvo que el rival esté corto."""
    rival = p.j(1 - yo)
    if len(rival.mazo) <= 12 or _letal_al_atacar(p, yo, c):
        return False
    otros = [a for a in p.j(yo).defensa if a is not c and not hab.tiene_estado(p, a, "no_puede_bloquear")]
    if otros or hab.tiene_estado(p, c, "no_puede_bloquear"):
        return False
    suyos = [a for a in rival.aliados if not hab.tiene_prop(p, a, "guardian")]
    if len(suyos) < 2:
        return False
    golpe = sum(max(0, hab.fuerza(p, a)) for a in suyos)
    return golpe >= hab.fuerza(p, c) and hab.fuerza(p, c) > max(hab.fuerza(p, a) for a in suyos)


def _bono_por_arma(a: Instancia) -> int:
    """Djoser: fuerza extra que gana por cada Arma que porta."""
    return sum(int(h.get("valor", 0) or 0) for h in a.habilidades
               if h.get("accion") == "modificarFuerza" and h.get("valorPorCada") == "arma_portada")


def _anular_siempre(p, c: Instancia) -> bool:
    """#2 0VzQ: lo que no se deja entrar nunca: un motor que se repite cada
    turno (Nuh), robar un Aliado (Haquika) u obligar a bloquear (Demoledor)."""
    return c.tipo == Tipo.ALIADO and (
        _motor_activable(p, c)
        or any(h.get("accion") in ("ganarControl", "obligarBloqueo") for h in c.habilidades)
    )


def _acelera_al_entrar(c: Instancia) -> bool:
    """Kawit (busca un Oro), Djedefhor (roba): dan recursos al entrar."""
    return c.tipo == Tipo.ALIADO and any(
        h.get("cuando") in ("al_jugar", None) and h.get("accion") in ("robar", "buscar")
        and (h.get("objetivo") or {}).get("quien", "propio") == "propio"
        for h in c.habilidades
    )


def _valor_restringir(p, c: Instancia, h: dict) -> float:
    """#3/#7/#12 0VzQ: Lanza de Osiris. Vale lo que pierde el rival: su ataque
    (más si se arma, como Djoser) y su bloqueo (Ay es el que bloquea). Lo que
    ya no podía hacer no cuenta (Roxana ya restringida, Ay es Guardián)."""
    modos = {h.get("modo")} | {
        e.get("modo") for e in h.get("luego") or [] if e.get("accion") == "restringirCombate"
    }
    v = 0.0
    if "no_puede_atacar" in modos and not hab.tiene_prop(p, c, "guardian") \
            and not hab.tiene_estado(p, c, "no_puede_atacar"):
        v += _amenaza_ofensiva(p, c)
        if any(x.get("accion") == "sinLimiteArmas" or x.get("valorPorCada") == "arma_portada"
               for x in c.habilidades):
            v += 3.0  # Djoser pega más con cada Arma
    if "no_puede_bloquear" in modos and not hab.tiene_estado(p, c, "no_puede_bloquear"):
        v += 2.0 * max(0, hab.fuerza(p, c))
    return v


def _muere_en_combate(p, t: Instancia) -> bool:
    """¿`t` está peleando un combate que pierde (o empata) este turno?"""
    if hab.tiene_prop(p, t, "indestructible"):
        return False
    for a in p.atacantes:
        b = p.bloqueos.get(a.uid)
        if b is None or not a.en_juego or not b.en_juego:
            continue
        if b is t:
            return hab.fuerza(p, a) >= hab.fuerza(p, t)
        if a is t:
            return hab.fuerza(p, b) >= hab.fuerza(p, t)
    return False


def _valor_defensivo_arma(p, yo, arma: Instancia, portador: Instancia) -> float:
    """#80: Escudo Miliciano (+3) en Djoser lo vuelve un bloqueador que mata al
    Demoledor: vale lo que vale el atacante rival que pasa a poder frenar."""
    if portador.controlador != yo:
        return 0.0
    bono = sum(
        int(h.get("valor", 0)) for h in arma.habilidades
        if h.get("accion") == "modificarFuerza" and h.get("cuando") == "continua"
        and (h.get("objetivo") or {}).get("quien") == "esta_carta"
    )
    if bono <= 0 or hab.tiene_estado(p, portador, "no_puede_bloquear"):
        return 0.0
    f = hab.fuerza(p, portador)
    amenazas = [a for a in p.j(1 - yo).aliados if hab.fuerza(p, a) > 0 and _puede_atacar(p, a)]
    frenados = [a for a in amenazas if f <= hab.fuerza(p, a) < f + bono]
    return max([0.0] + [_valor_vivo(p, a) for a in frenados])


def _rinde_al_atacar(c: Instancia) -> bool:
    return any(h.get("cuando") in ("al_atacar", "al_hacer_dano") for h in c.habilidades)


def _motor_de_cartas(c: Instancia) -> int:
    """Oro que roba o busca cada turno (Piedra Roseta) antes que uno de un
    solo uso que se destierra al activarse (Rito de Aton)."""
    if c.tipo != Tipo.ORO:
        return 0
    return sum(
        1 for h in c.habilidades
        if h.get("cuando") == "activada" and h.get("accion") in ("robar", "buscar")
        and not (h.get("costo") or {}).get("desterrarEstaCarta")
        and not (h.get("costo") or {}).get("destruirEstaCarta")
    )


def _motor_activable(p, c: Instancia) -> bool:
    """Aliado con una habilidad activada que se repite cada turno sin pagar
    Oros ni sacrificarse (Nuh juega un Arma gratis): perderla es para siempre.
    Neferite I sin Cementerio para pagar no desterrará pronto: no amerita."""
    if c.tipo != Tipo.ALIADO:
        return False
    for h in c.habilidades:
        costo = h.get("costo") or {}
        # Reporte qx6H T15: Anand bota y "luego" roba o baraja cada turno
        # desde la defensa (no ataca: esperar la Guerra no sirve).
        acciones = {h.get("accion")} | ({e.get("accion") for e in h.get("luego") or []} if _LECCIONES_QX6 else set())
        if (
            h.get("cuando") != "activada"
            or not acciones & {"jugarDesde", "buscar", "robar", "ponerEnJuego", "destruir", "desterrar"}
            or any(costo.get(k) for k in ("oros", "destruirEstaCarta", "desterrarEstaCarta"))
        ):
            continue
        if not _remocion_pagable(p, c.controlador, h):
            continue
        return True
    return False


def _remocion_pagable(p, quien, h: dict) -> bool:
    """Neferite I / Nephre-Ka pagan desterrando de su Cementerio tantas cartas
    como el coste del objetivo: sin Cementerio suficiente no sacan nada."""
    if (h.get("costo") or {}).get("desterrarCementerioSegun") != "coste_objetivo":
        return True
    objetivos = [x for x in p.e.instancias_en_juego(1 - quien) if x.tipo != Tipo.ORO]
    return bool(objetivos) and len(p.j(quien).cementerio) >= min(x.carta.coste for x in objetivos)


def _jugables_restantes(p, yo) -> int:
    """Cuántas cartas de la mano alcanzo a jugar todavía este turno con los
    Oros que quedan (las más baratas primero), más el Oro de la jugada."""
    jug = p.j(yo)
    oros, n = jug.oro_disponible, 0
    for coste in sorted(p.coste_de(yo, c) for c in jug.mano if c.tipo != Tipo.ORO):
        if coste > oros:
            break
        oros -= coste
        n += 1
    if not jug.oro_jugado and any(c.tipo == Tipo.ORO for c in jug.mano):
        n += 1
    return n


def _recursos_de_sobra(p, yo) -> bool:
    """Ya tengo todo en la mano: aunque juegue lo que me alcanza este turno
    me quedan al menos 3 cartas para los próximos, y un Oro para bajar."""
    jug = p.j(yo)
    sobrantes = sum(1 for c in jug.mano if c.tipo != Tipo.ORO) - _jugables_restantes(p, yo)
    oro_proximo = any(c.tipo == Tipo.ORO for c in jug.mano) or len(jug.reserva) + len(jug.pagado) >= 7
    return sobrantes >= 3 and oro_proximo


def _vinculo(h: dict) -> bool:
    """Vínculo del Aullido: al entrar se paga (con otro Oro) para robar y
    descartar: filtra la mano desde el turno 1."""
    return h.get("accion") == "robar" and h.get("cuando") == "al_jugar"         and (h.get("costo") or {}).get("pagarEstaCarta")         and any(e.get("accion") == "descartar" for e in h.get("luego") or [])


def _vinculo_frena(p, yo) -> bool:
    """Pagar el Vínculo gasta 2 Oros del turno: no se paga si con ellos bajo
    un Aliado de coste 3+ que después ya no alcanzo, con la mano llena."""
    if p.e.activo != yo or p.e.fase != "vigilia" or len(p.j(yo).mano) < _VINCULO_MANO_MIN:
        return False
    disp = p.j(yo).oro_disponible
    def mejor(oros):
        return max([0] + [p.coste_de(yo, c) for c in p.j(yo).mano
                          if c.tipo == Tipo.ALIADO and p.coste_de(yo, c) <= oros])
    ahora = mejor(disp)
    return ahora >= 3 and mejor(disp - 2) < ahora


def _robo_obliga_a_descartar(p, yo, h: dict) -> bool:
    """Robar de más. En la Fase Final se roba 1 y se descarta hasta 8: cada
    carta que sobra es una que se tira y un paso menos en el castillo.

    - Con costo real (Ay paga un Aliado): no se hace si ya tengo todos los
      recursos en la mano, o si obligaría a descartar.
    - Gratis (Kawit): descartar 1 no es problema; 2 o más, sí."""
    from .motor import MANO_MAXIMA

    obj = h.get("objetivo") or {}
    if h.get("accion") != "robar" or obj.get("quien", "propio") != "propio" or p.e.activo != yo:
        return False
    if _vinculo(h):
        return False  # Vínculo del Aullido: roba 2 y descarta 1, la mano no crece de más
    n = int(hab.cantidad(p, yo, h, []) or 1)
    exceso = len(p.j(yo).mano) - _jugables_restantes(p, yo) + n + 1 - MANO_MAXIMA
    if not hab._costo_gratis(h):
        return exceso >= 1 or _recursos_de_sobra(p, yo)
    return exceso >= 2


def _robo_suicida(p, yo, h: dict) -> bool:
    """Robar de mi castillo cuando queda corto: me deja sin cartas para la
    próxima Fase de Robo o al alcance del ataque del rival."""
    obj = h.get("objetivo") or {}
    if obj.get("quien", "propio") != "propio":
        return False
    # Kawit: buscar un Oro en mi mazo también me adelgaza el castillo.
    if not (h.get("accion") == "robar" or (h.get("accion") == "buscar" and obj.get("zona", "mazo") == "mazo")):
        return False
    if h.get("accion") == "buscar" and h.get("zonaDestino") in ("mazo_tope", "mazo_fondo", "mazo"):
        return False  # rqHs #2: Melisende deja el Caballero arriba: el castillo no baja
    queda = len(p.j(yo).mazo) - int(h.get("cantidad", 1) or 1)
    alcance = _alcance_rival(p, yo)
    if h.get("accion") == "buscar" and "Oro" in (obj.get("tipos") or []):
        return queda <= 2 or queda < alcance  # #9 Zrfq: Draig Ifanc rampea igual
    if h.get("accion") == "buscar" and len(p.j(yo).mazo) <= alcance:
        return queda <= 2  # FqvR #6: si ya me alcanza igual, Atenas busca el Oro que falta
    return queda <= 2 or queda <= alcance


def _costo_suicida(p, yo, fuente: Instancia, h: dict) -> bool:
    """El costo que pagaría (el principal, o el alternativo si no alcanza)
    bota todo mi castillo."""
    costo = h.get("costo") or {}
    if not hab._puede_pagar(p, yo, fuente, h):
        costo = h.get("costoAlternativo") or {}
    return int(costo.get("botar", 0) or 0) >= len(p.j(yo).mazo)


def _alcance_rival(p, yo) -> int:
    """Lo que el rival puede quitarme de castillo en su turno: sus Oros que
    botan (Papiros de Lahun 3, si le alcanzan los Oros) más su fuerza en mesa."""
    rival = 1 - yo
    oros = len(p.j(rival).reserva) + len(p.j(rival).pagado)
    bota = 0
    for c in p.j(rival).reserva + p.j(rival).pagado:
        for h in c.habilidades:
            if h.get("cuando") == "activada" and h.get("accion") == "botar" \
                    and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente":
                gasta = int((h.get("costo") or {}).get("oros", 0) or 0)
                if gasta < oros:  # el que se destierra no se paga a sí mismo
                    oros -= gasta
                    bota += int(h.get("cantidad", 1) or 1)
    fuerza = sum(max(0, hab.fuerza(p, a)) for a in p.j(rival).aliados if _puede_atacar(p, a))
    return bota + fuerza


def _quemado_rival(p, yo) -> int:
    """Daño directo (sin combate) que el rival me puede hacer en su próximo
    turno: Papiros de Lahun en juego, Jinetes de Fuego en su Cementerio (se
    juegan de ahí) y uno estimado en la mano si le quedan copias. Con 6 Oros
    el Faraón guerrero hace 9 así: hay que quedar fuera de ese rango."""
    rival = 1 - yo
    jug = p.j(rival)
    oros = len(jug.reserva) + len(jug.pagado) + 1  # + el Oro que baja en su turno
    fuentes = []  # (coste en Oros, cartas que bota)
    for c in jug.reserva + jug.pagado:
        for h in c.habilidades:
            if h.get("cuando") == "activada" and h.get("accion") == "botar" \
                    and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente":
                fuentes.append((int((h.get("costo") or {}).get("oros", 0) or 0), int(h.get("cantidad", 1) or 1)))

    def bota_al_jugar(c):
        return sum(int(h.get("cantidad", 1) or 1) for h in c.habilidades
                   if h.get("cuando") in ("al_jugar", None) and h.get("accion") == "botar"
                   and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente")

    cinturon = any(h.get("accion") == "restriccion" and h.get("modo") == "desterrar_cementerio"
                   for c in p.j(yo).reserva for h in c.habilidades)
    for c in jug.cementerio:
        # Héctor: con el Cinturón de Lady Ann en mi Reserva, Jinetes no se
        # puede jugar del Cementerio (se tendría que desterrar).
        if c.tipo == Tipo.TALISMAN and bota_al_jugar(c) and _se_juega_del_cementerio(c) and not cinturon:
            fuentes.append((c.carta.coste, bota_al_jugar(c)))
    quemadores = [c for c in jug.mano + jug.mazo if c.tipo == Tipo.TALISMAN and bota_al_jugar(c)]
    if jug.mano and quemadores:
        c = quemadores[0]
        fuentes.append((c.carta.coste, bota_al_jugar(c)))  # uno en la mano (no lo veo, pero puede)
    total = 0
    for coste, n in sorted(fuentes, key=lambda x: x[0] / max(1, x[1])):
        if coste <= oros:
            oros -= coste
            total += n
    return total


def _me_adelgaza(c: Instancia) -> int:
    """Cartas que saca de mi castillo al jugarse (Kawit busca un Oro y roba)."""
    n = 0
    for h in c.habilidades:
        if h.get("cuando") not in ("al_jugar", None):
            continue
        for e in [h] + [x for x in h.get("luego") or [] if isinstance(x, dict)]:
            obj = e.get("objetivo") or {}
            if obj.get("quien", "propio") != "propio" or e.get("opcional"):
                continue  # "puedes": lo rechazo si me deja a tiro
            if e.get("accion") == "robar" or (e.get("accion") == "buscar" and obj.get("zona", "mazo") == "mazo"):
                n += int(e.get("cantidad", 1) or 1)
    return n


def _candado_tocador(p, yo, j) -> bool:
    """Papiros con Tocador en juego: dejo al rival con tan pocas cartas que
    botarme lo mataría a él (Tocador le devuelve lo mismo)."""
    n = _botar_de(p, yo, j)
    if n <= 0 or not _devuelvo_lo_botado(p, yo):
        return False
    suyo = len(p.j(1 - yo).mazo) - n - 1  # tras su robo
    su_botar = _alcance_rival(p, yo) - sum(
        max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados if _puede_atacar(p, a)
    )
    return 0 < suyo < max(su_botar, 1) and len(p.j(yo).mazo) - 1 > 0


def _puede_atacar(p, a: Instancia) -> bool:
    return not hab.tiene_prop(p, a, "guardian") and not hab.tiene_estado(p, a, "no_puede_atacar")


def _neutralizado(p, c: Instancia) -> bool:
    """No ataca, no bloquea y no tiene habilidades que siga usando (Jentakus
    con la Lanza de Osiris): sacarlo de la mesa le hace un favor al rival."""
    if c.tipo != Tipo.ALIADO:
        return False
    sigue = any(
        h.get("cuando") not in ("al_jugar", None) and h.get("accion") not in hab.PROPIEDADES
        for h in c.habilidades
    )
    return (
        hab.tiene_estado(p, c, "no_puede_atacar") and hab.tiene_estado(p, c, "no_puede_bloquear") and not sigue
    )


def _se_juega_del_cementerio(c: Instancia) -> bool:
    """Escudo Miliciano, Qer-Her, Jinetes de Fuego: se juegan desde el
    Cementerio, así que descartarlos no los pierde."""
    if any(
        h.get("accion") == "jugarDesde" and (h.get("objetivo") or {}).get("quien") == "esta_carta"
        and (hab.zona_activacion(h) == "cementerio" or "cementerio" in hab.zonas_de(h.get("objetivo") or {}, ""))
        for h in c.habilidades
    ):
        return True
    # #2 Zrfq: Lady Calvaur, desde el Cementerio, vuelve a la mano.
    return any(
        h.get("cuando") == "activada" and hab.zona_activacion(h) == "cementerio"
        and any(e.get("accion") in ("subirMano", "jugarDesde")
                and (e.get("objetivo") or {}).get("quien") == "esta_carta" for e in h.get("luego") or [])
        for h in c.habilidades
    )


def _descarte_gratis(p, yo, c: Instancia) -> bool:
    """Descartar `c` no la pierde: se juega igual desde el Cementerio (Escudo
    Miliciano, Qer-Her). No vale para un Talismán como Jinetes de Fuego: desde
    la mano va al Cementerio y se juega dos veces; descartado, solo una. Ni si
    el rival tiene a la vista con qué desterrar del Cementerio (Escarabeo)."""
    if not _se_juega_del_cementerio(c) or c.tipo == Tipo.TALISMAN:
        return False
    return not _rival_destierra_cementerio(p, yo)


def _rival_destierra_cementerio(p, yo) -> bool:
    for x in p.j(1 - yo).reserva + p.j(1 - yo).aliados + p.j(1 - yo).apoyo:
        for h in x.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("accion") in ("desterrar", "barajar") and obj.get("quien") in ("oponente", "ambos", None)                     and "cementerio" in hab.zonas_de(obj, ""):
                return True
    return False


_CONTRA = {"destruir": "indestructible", "desterrar": "indesterrable"}


def _amenazas_a_la_vista(p, yo) -> list[str]:
    """Remociones activables que el rival tiene en mesa contra mis Aliados
    (Qer-Her y Jeroglíficos suben a la mano cuando quieren)."""
    out = []
    for x in p.j(1 - yo).reserva + p.j(1 - yo).pagado + p.j(1 - yo).aliados + p.j(1 - yo).apoyo:
        for h in x.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("cuando") != "activada" or h.get("accion") not in _REMOCION:
                continue
            if obj.get("quien") != "oponente" or "Aliado" not in (obj.get("tipos") or ["Aliado"]):
                continue
            if not hab._en_zona_activacion(x, h) or (h.get("costo") or {}).get("oros"):
                continue
            out.append(h.get("accion"))
    return out


def _se_lo_llevan(p, yo, c: Instancia, protege: str | None = None) -> bool:
    """¿El rival puede sacar a `c` con lo que tiene a la vista, aunque yo le
    dé `protege` (Indestructible no frena un "subir a la mano")?"""
    return any(not (protege and _CONTRA.get(a) == protege) for a in _amenazas_a_la_vista(p, yo))


def _valor_arma_que_entra(p, yo) -> float:
    """Djoser: cuando entra un Arma mía, destruye un Aliado rival (una vez
    por turno). Lo que vale el mejor Aliado que se lleva."""
    mejor = 0.0
    for a in p.j(yo).aliados:
        for k, h in enumerate(a.habilidades):
            if h.get("cuando") != "propia_entra" or "Arma" not in (h.get("disparoTipos") or []):
                continue
            if h.get("accion") not in _REMOCION or (h.get("objetivo") or {}).get("quien") != "oponente":
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and hab.usos(p, yo, a, h, k) >= limite:
                continue
            cands = [c for c in hab.candidatos_validos(p, yo, a, h) if not _neutralizado(p, c)]
            if h.get("accion") == "destruir":
                cands = [c for c in cands if not hab.tiene_prop(p, c, "indestructible")]
            mejor = max([mejor] + [1.5 * _valor_vivo(p, c) - (6 if _gana_al_morir(c) else 0) for c in cands])
    return mejor


def _valor_a_futuro(p, yo, c: Instancia) -> float:
    """Ajustes para decidir qué tirar por exceso de mano, mirando lo que la
    carta rendirá en los próximos turnos y no solo hoy."""
    v = 0.0
    oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
    # Lejos de poder pagarse: pesa menos que lo que se juega ya.
    v -= 1.5 * max(0, c.carta.coste - (oros + 1)) if c.tipo != Tipo.ORO else 0.0
    # Un Arma con Djoser (destruye un Aliado al entrar) vale más de lo que dice su coste.
    if c.tipo == Tipo.ARMA and any(
        h.get("cuando") == "propia_entra" and "Arma" in (h.get("disparoTipos") or []) and h.get("accion") in _REMOCION
        for x in p.j(yo).mano + p.e.instancias_en_juego(yo) for h in x.habilidades
    ):
        v += 3.0
    # Destrucción masiva de todos los Aliados (Qadesh): contra mi propia mesa.
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") in ("al_jugar", None) and h.get("accion") in ("destruir", "desterrar") \
                and obj.get("seleccion") == "todos" and obj.get("quien") in ("cualquiera", "ambos"):
            mios = len(p.j(yo).aliados) + sum(1 for x in p.j(yo).mano if x.tipo == Tipo.ALIADO)
            suyos = len(p.j(1 - yo).aliados)
            v -= min(5.0, max(-2.0, 1.5 * mios - 0.8 * suyos))
    # Una anulación (Abismo) protege lo importante: se guarda.
    if any(h.get("accion") == "anular" for h in c.habilidades):
        v += 2.0
    return v


def _solo_recupera(c: Instancia) -> bool:
    """Arma cuyo único aporte es barajar desde el Cementerio (Escudo Celestial,
    coste 0): no suma fuerza."""
    habs = [h for h in c.habilidades if h.get("accion") not in hab.PROPIEDADES]
    return bool(habs) and all(h.get("accion") == "barajar" for h in habs)


def _recupera(c: Instancia) -> bool:
    """La carta devuelve cartas al Mazo Castillo (Escudo Celestial)."""
    return any(h.get("accion") == "barajar" for h in c.habilidades)


def _tipo_ok(c: Instancia, h: dict) -> bool:
    tipos = (h.get("objetivo") or {}).get("tipos") or []
    return not tipos or c.tipo.value in tipos


def _en_zonas(p, yo, h: dict) -> list[Instancia]:
    jug = p.j(yo)
    por_zona = {"mazo": jug.mazo, "cementerio": jug.cementerio, "mano": jug.mano, "destierro": jug.destierro}
    out = []
    for z in hab.zonas_de(h.get("objetivo") or {}, "mano"):
        out += por_zona.get(z, [])
    return out


def _ya_vigente(p, yo, fuente: Instancia, h: dict) -> bool:
    """Otorgar una propiedad que ya tiene (Ramsés II activándose 3 veces)."""
    if h.get("accion") != "otorgarPropiedad":
        return False
    modos = [h.get("modo") or ""] + [
        e.get("modo") or "" for e in h.get("luego") or [] if isinstance(e, dict) and e.get("accion") == "otorgarPropiedad"
    ]
    obj = h.get("objetivo") or {}
    objetivos = [fuente] if obj.get("quien") == "esta_carta" else hab.candidatos_validos(p, yo, fuente, h)
    def vigente_mia(t, m):
        # #55: la que le dio Faraón a su Ramsés vence en la Vigilia de Faraón;
        # si ahora lo controlo yo, conviene renovarla para que dure mi turno.
        otorgadas = [e for e in t.estados if e.get("modo") == f"prop:{m}"]
        if otorgadas:
            return any(e.get("creador", yo) == yo for e in otorgadas)
        return hab.tiene_prop(p, t, m)  # propia de la carta

    return bool(objetivos) and all(vigente_mia(t, m) for t in objetivos for m in modos if m)


def _sacrificio_de_oro_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Destruir o desterrar un Oro propio como costo: solo en combate, sobre
    un Aliado que pelea, o contra una carta cara (coste ≥ 4)."""
    c = h.get("costo") or {}
    if fuente.tipo != Tipo.ORO or not (c.get("destruirEstaCarta") or c.get("desterrarEstaCarta")
                                       or c.get("barajarEstaCarta")):
        return True
    if h.get("accion") in ("prevenir", "cancelarAtaque", "reducirDano"):
        return True
    if h.get("accion") in ("perderHabilidad", "modificarFuerza"):
        # FqvR #2: Diente de la Bestia no revienta un Oro por un Belial de 3: el
        # Titán vive de tener muchos Oros. Solo en casos extremos o con gran ventaja.
        oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
        cands = hab.candidatos_validos(p, yo, fuente, h)
        return _en_peligro(p, yo) or len(p.j(yo).mazo) <= 10 or any(_pieza_clave(t) for t in cands) \
            or (oros >= 8 and not _juntando_oros(p, yo)) \
            or any(t.tipo == Tipo.ALIADO and hab.fuerza(p, t) >= 4 for t in cands)  # Carnwennan (Dragón)
    if h.get("accion") in ("jugarDesde", "perderHabilidad", "otorgarPropiedad", "modificarFuerza", "anular"):
        # Joya Amatista, Figuras Negras, Clochafarmore: lo decide el efecto
        # (_objetivo_util: si hay qué jugar, qué anular o si cambia un combate).
        return True
    if h.get("accion") == "ponerEnJuego":
        # Aceite de Oliva: cambiar este Oro por uno que haga algo.
        return any(c.habilidades for c in hab.candidatos_validos(p, yo, fuente, h))
    if h.get("accion") == "buscar" and _en_peligro(p, yo) and any(
        _defensivo(c) for c in hab.candidatos_validos(p, yo, fuente, h)
    ):
        return True  # #85: Rito de Aton trae de vuelta Flechas de Lava
    roba_tope = h.get("accion") == "mirarTope" and "mano" in ((h.get("repartir") or []) + [h.get("zonaDestino")])
    if (h.get("accion") in ("robar", "buscar") or roba_tope)             and (h.get("objetivo") or {}).get("quien", "propio") == "propio":
        # #90: Biblioteca Eterna (y La Llama de Brigit: mira 2, una a la mano). Con Oros de sobra y nada en qué gastarlos,
        # cambiar uno por cartas da recursos.
        jug = p.j(yo)
        en_juego = len(jug.reserva) + len(jug.pagado)
        por_gastar = _por_gastar(p, yo)
        corta = len(jug.mano) <= 5
        # Primero lo que ya puedo jugar (Akhet, que además roba): desterrar
        # la Biblioteca solo si después no hay nada que hacer ni Oro para el
        # próximo turno.
        jugable = any(c.tipo != Tipo.ORO and p.puede_pagar(yo, c) for c in jug.mano if c is not fuente)
        sin_oro = not any(c.tipo == Tipo.ORO for c in jug.mano)
        # Busco un Arma: mis Aliados no tienen, no hay ninguna en la mano y
        # quedan en el mazo (dos Escudos Milicianos sin salir). Si ya hay una
        # que se juega desde el Cementerio, guardo los Oros para esa.
        portadores = {a.portador for a in p.e.portadas if a.controlador == yo}
        busca_arma = (
            en_juego >= 5 and por_gastar < jug.oro_disponible
            and (any(a.uid not in portadores for a in jug.aliados) or any(c.tipo == Tipo.ALIADO for c in jug.mano))
            and not any(c.tipo == Tipo.ARMA for c in jug.mano)
            and not any(c.tipo == Tipo.ARMA and _se_juega_del_cementerio(c) for c in jug.cementerio)
            and any(c.tipo == Tipo.ARMA for c in jug.mazo)
        )
        return (en_juego >= 6 and por_gastar < jug.oro_disponible) or busca_arma or (
            en_juego >= 5 and corta and not jugable and sin_oro
        )  # #64
    cands = hab.candidatos_validos(p, yo, fuente, h) if hab._necesita_objetivo(h) else []
    if h.get("accion") == "subirMano" and p.atacantes and p.e.activo != yo:
        # #9 0VzQ: subir al atacante solo retrasa al rival; con el castillo
        # sano, recibir el golpe es mejor que gastar el Oro.
        libres = [a for a in p.atacantes if a.en_juego and p.bloqueos.get(a.uid) is None]
        entrante = sum(max(0, hab.fuerza(p, a)) for a in libres)
        mayor = max((hab.fuerza(p, a) for a in libres), default=0)
        if mayor <= 4 and len(p.j(yo).mazo) - entrante > 15 and not _en_peligro(p, yo):
            return False
    return any(_impacto_quitar(p, yo, t) >= _costo_oro(p, yo) for t in cands)


def _relevo_sin_objetivo(p, yo, c: Instancia) -> bool:
    """Bennu: se juega para sacrificarse y traer al tiro un Aliado del
    Cementerio. Sin ninguno que pueda traer, es solo un cuerpo caro."""
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if (
            h.get("accion") == "jugarDesde" and h.get("cuando") == "activada"
            and (h.get("costo") or {}).get("destruirEstaCarta")
            and "cementerio" in hab.zonas_de(obj, "")
        ):
            return not any(
                x.tipo == Tipo.ALIADO and hab.coincide(p, x, obj) for x in p.j(yo).cementerio
            )
    return False


def _por_gastar(p, yo) -> int:
    """Oros que pienso gastar en mi turno: la mano, sin Oros ni Talismanes de
    respuesta (Relámpago Arcano, Flechas de Lava se guardan para el rival)."""
    return sum(
        c.carta.coste for c in p.j(yo).mano
        if c.tipo != Tipo.ORO and not _defensivo(c) and not any(
            h.get("cuando") == "oponente_juega" or h.get("accion") in _RESPUESTAS for h in c.habilidades
        )
    )


def _atacara_si_puede(p, yo, c: Instancia) -> bool:
    if hab.tiene_prop(p, c, "furia") or hab.tiene_prop(p, c, "guardian"):
        return False
    if hab.tiene_estado(p, c, "no_puede_atacar") or hab.fuerza(p, c) <= 0:
        return False
    # El que voy a sacrificar con Ay (el Aliado de menos valor) no ataca.
    propios = [a for a in p.j(yo).aliados]
    if _hay_salida(p, yo, c) and propios and c is min(propios, key=lambda a: _valor_carta(p, a)):
        return False
    rival = [b for b in p.j(1 - yo).defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")]
    return not rival or hab.fuerza(p, c) >= max(hab.fuerza(p, b) for b in rival)


def _obliga_a_bloquear(c: Instancia) -> bool:
    return any(h.get("accion") == "obligarBloqueo" and h.get("cuando") == "al_atacar" for h in c.habilidades)


def _prioridad_obligar(p, b: Instancia):
    """#39: obligar a bloquear (y dejar sin habilidad) a quien tiene
    habilidades que seguirá usando (Ay roba cada turno), no a quien ya gastó
    la suya al entrar (Jentakus I)."""
    utiles = sum(
        1 for h in b.habilidades
        if h.get("cuando") not in ("al_jugar", None) and h.get("accion") not in hab.PROPIEDADES
    )
    antes = sum(hab.fuerza(p, a) for a in p.j(b.controlador).aliados)
    anterior = b.sin_habilidad_hasta
    try:
        b.sin_habilidad_hasta = "hasta_fase_final"
        perdida = antes - sum(hab.fuerza(p, a) for a in p.j(b.controlador).aliados)
    finally:
        b.sin_habilidad_hasta = anterior
    return (utiles + max(0, perdida), _valor_carta(p, b))


def _castigo_si_lo_bloquean(p, c: Instancia) -> int:
    """Ramsés II: si lo bloquean, el rival bota tanto como su fuerza."""
    total = 0
    for h in c.habilidades:
        if h.get("cuando") == "al_ser_bloqueado" and h.get("accion") == "botar":
            if h.get("cantidadSegun") == "fuerza_esta_carta":
                total += max(0, hab.fuerza(p, c) if c.en_juego else c.carta.fuerza)
            else:
                total += int(h.get("cantidad", 1))
    return total


def _letal_al_atacar(p, yo, c: Instancia) -> bool:
    """Gana atacando con este Aliado: pase o lo bloqueen, el rival se queda sin
    castillo (Ramsés II con 6 de fuerza ante un castillo de 6 o menos)."""
    castillo = len(p.j(1 - yo).mazo)
    f = hab.fuerza(p, c) if c.en_juego else c.carta.fuerza
    return (f >= castillo and _castigo_si_lo_bloquean(p, c) >= castillo) or _bota_letal_al_atacar(p, yo, c)


def _bota_letal_al_atacar(p, yo, c: Instancia) -> bool:
    """Ramsés IX: al atacar el rival bota 1 sí o sí (lo bloqueen o no), y si
    entre lo botado cae un Oro o un Aliado, bota 2 más. Letal si lo seguro
    alcanza, o si lo extra alcanza y es probable según lo que queda en los mazos."""
    castillo = len(p.j(1 - yo).mazo)
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") != "al_atacar" or h.get("accion") != "botar" \
                or obj.get("quien", "oponente") not in ("oponente", "ambos"):
            continue
        base = int(h.get("cantidad", 1) or 1)
        if base >= castillo:
            return True
        for e in h.get("luego") or []:
            if e.get("relacion") != "si_afectada_cumple" or e.get("accion") != "botar" \
                    or (e.get("objetivo") or {}).get("quien") != "oponente":
                continue
            if base + int(e.get("cantidad", 1) or 1) < castillo:
                continue
            filtro = e.get("filtroAfectada") or {}
            lados = [1 - yo] + ([yo] if obj.get("quien") == "ambos" else [])
            falla = 1.0
            for lado in lados:
                mazo = p.j(lado).mazo
                if mazo:
                    falla *= 1 - sum(1 for x in mazo if hab.coincide(p, x, filtro)) / len(mazo)
            if 1 - falla >= 0.6:
                return True
    return False


def _se_bota_de_mas(p, yo, c: Instancia, cuando: str) -> bool:
    """Kamose, Guerrero Medjay, Ramsés IX: "cada jugador bota…" también me bota
    a mí. No se juega ni se ataca con ellos si eso me deja al alcance de la
    derrota (castillo en 2 o menos, o dentro del ataque del rival)."""
    n = sum(
        int(h.get("cantidad", 1) or 1) for h in c.habilidades
        if h.get("cuando") == cuando and h.get("accion") == "botar" and not h.get("opcional")
        and (h.get("objetivo") or {}).get("quien", "oponente") in ("ambos", "propio")
    )
    if not n:
        return False
    queda = len(p.j(yo).mazo) - n
    # UUOX T21: si ya estaba al alcance del rival, botar 1 más no cambia nada (Medjay ataca).
    return queda <= 2 or queda <= _alcance_rival(p, yo) < len(p.j(yo).mazo)


def _bota_al_atacar(p, c: Instancia) -> int:
    """Cuánto bota al rival este Aliado solo por atacar (Mandoble de Seth)."""
    fuentes = [c] + [a for a in p.e.portadas if a.portador == c.uid]
    return sum(
        int(h.get("cantidad", 1)) for x in fuentes for h in x.habilidades
        if h.get("cuando") == "al_atacar" and h.get("accion") == "botar"
        and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente"
    )


def _bota_seguro_al_atacar(p, c: Instancia) -> int:
    """Lo que el rival bota sí o sí cuando este Aliado ataca, aunque yo
    también bote (Ramsés IX: cada jugador bota 1)."""
    fuentes = [c] + [a for a in p.e.portadas if a.portador == c.uid]
    return sum(
        int(h.get("cantidad", 1)) for x in fuentes for h in x.habilidades
        if h.get("cuando") == "al_atacar" and h.get("accion") == "botar"
        and (h.get("objetivo") or {}).get("quien", "oponente") in ("oponente", "ambos")
    )


def _bota_al_danar(p, c: Instancia) -> int:
    """Lo que el rival bota además del daño cuando este Aliado lo daña."""
    fuentes = [c] + [a for a in p.e.portadas if a.portador == c.uid]
    return sum(
        int(h.get("cantidad", 1) or 1) for x in fuentes for h in x.habilidades
        if h.get("cuando") == "al_hacer_dano" and h.get("accion") == "botar"
        and (h.get("objetivo") or {}).get("quien", "oponente") in ("oponente", "ambos")
    )


def _remato_el_proximo_turno(p, yo) -> bool:
    """Mis Aliados en mesa alcanzan para botarle el castillo al rival
    atacando (fuerza más lo que botan al atacar)."""
    total = sum(max(0, hab.fuerza(p, a)) + _bota_seguro_al_atacar(p, a) for a in p.j(yo).aliados)
    return 0 < len(p.j(1 - yo).mazo) <= total


def _rebaja_disponible(p, yo) -> int:
    """Cuánta fuerza puedo quitarle a un atacante en la Guerra de Talismanes
    (Toro Apis en la Reserva)."""
    mejor = 0
    for c in p.j(yo).reserva:
        for h in c.habilidades:
            if (
                h.get("accion") == "modificarFuerza" and h.get("cuando") == "activada"
                and int(h.get("valor", 0)) < 0 and (h.get("objetivo") or {}).get("quien") == "oponente"
                and int((h.get("costo") or {}).get("oros", 0)) <= p.j(yo).oro_disponible
            ):
                mejor = max(mejor, -int(h.get("valor", 0)))
    return mejor


def _decisivo(p, t: Instancia, cambio: int) -> bool:
    """¿Cambiarle `cambio` de fuerza a este combatiente da vuelta su pelea?"""
    for a in p.atacantes:
        b = p.bloqueos.get(a.uid)
        if b is None or not a.en_juego or not b.en_juego:
            continue
        fa, fb = hab.fuerza(p, a), hab.fuerza(p, b)

        def muertes(x, y):  # (muere el atacante, muere el bloqueador)
            return (y >= x, x >= y)

        if t is a and muertes(fa, fb) != muertes(fa + cambio, fb):
            return True
        if t is b and muertes(fa, fb) != muertes(fa, fb + cambio):
            return True
    return False


def _combatientes(p) -> set[int]:
    """Quienes siguen peleando: un bloqueador cuyo atacante ya salió (Djedefhor
    devuelto a la mano) no está en combate (#39)."""
    vivos = [a for a in p.atacantes if a.en_juego]
    out = {a.uid for a in vivos}
    for a in vivos:
        b = p.bloqueos.get(a.uid)
        if b is not None and b.en_juego:
            out.add(b.uid)
    return out


def _remocion_sin_buen_objetivo(p, yo, inst: Instancia) -> bool:
    """Su "al entrar" remueve, pero no hay nada que valga la pena sacar."""
    tiene = any(
        h.get("cuando") == "al_jugar" and h.get("accion") in _REMOCION
        and (h.get("objetivo") or {}).get("quien") == "oponente"
        for h in inst.habilidades
    )
    return tiene and _valor_remocion_al_entrar(p, yo, inst) <= 4.5 and len(p.j(yo).mazo) > 15 \
        and not _robo_que_deja(inst)


def _usos_de_mi_destierro(p, yo) -> list[dict]:
    """Objetivos de mis cartas que juegan o recuperan desde mi Destierro (Rea)."""
    jug = p.j(yo)
    out = []
    for c in jug.mazo + jug.mano + jug.cementerio + list(p.e.instancias_en_juego(yo)):
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("accion") in ("jugarDesde", "ponerEnJuego", "subirMano", "barajar", "buscar") \
                    and obj.get("quien") == "propio" and "destierro" in hab.zonas_de(obj, ""):
                out.append(obj)
    return out


def _robo_que_deja(inst: Instancia) -> int:
    """FqvR #1: Focea queda en juego y en la Guerra se destruye para robar 2:
    vale por la remoción y por esas cartas."""
    if inst.tipo not in (Tipo.TOTEM, Tipo.ALIADO):
        return 0
    return max([0] + [int(h.get("cantidad", 1) or 1) for h in inst.habilidades
                      if h.get("cuando") == "activada" and h.get("accion") == "robar"
                      and (h.get("objetivo") or {}).get("quien", "propio") == "propio"])


def _valor_con_armas(p, c: Instancia) -> float:
    """Una carta y las Armas que porta (se van con ella)."""
    return _valor_carta(p, c) + sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == c.uid)


def _valor_vivo(p, c: Instancia) -> float:
    """Lo que un Aliado sigue aportando en la mesa: su fuerza y las
    habilidades que seguirá usando. Jentakus I ya gastó la suya al entrar."""
    if c.tipo != Tipo.ALIADO:
        return c.carta.coste * 0.5
    # Lo que dispara al morir no se pierde al morir (Djedefhor baraja igual).
    # Un "al entrar" que dura mientras está en juego (Cleopatra) sí sigue.
    # tuK8 #4: un motor que se activa cada turno sin destruirse (Idmon) vale
    # más que un Aliado del mismo tamaño que ya usó su "al entrar".
    sigue = sum(
        (3 if h.get("duracion") == "mientras_en_juego" else 2 if _habilidad_repetible(h) else 1) for h in c.habilidades
        if (h.get("cuando") not in ("al_jugar", "al_salir_del_juego", None) or h.get("duracion") == "mientras_en_juego")
        and h.get("accion") not in hab.PROPIEDADES and h.get("accion") != "errante"
    )
    armas = sum(
        1 for a in p.e.portadas if a.portador == c.uid for h in a.habilidades
        if h.get("cuando") in ("al_atacar", "al_hacer_dano", "al_bloquear", "activada")
    )
    return max(0, hab.fuerza(p, c)) + 1.5 * (sigue + armas)


def _habilidad_repetible(h: dict) -> bool:
    costo = h.get("costo") or {}
    return h.get("cuando") == "activada" and not costo.get("destruirEstaCarta") \
        and not costo.get("desterrarEstaCarta") and h.get("accion") not in hab.PROPIEDADES


def _costo_oro(p, yo) -> float:
    """Cuánto me cuesta perder un Oro ahora: al comienzo, con pocos, mucho."""
    oros = len(p.j(yo).reserva) + len(p.j(yo).pagado)
    return 6.0 if oros <= 4 else 4.5 if oros <= 6 else 3.0


def _impacto_quitar(p, yo, t: Instancia) -> float:
    """Cuánto cambia la partida sacar a `t` de la mesa ahora (Jeroglíficos):
    daño que evito o dejo pasar, el Aliado mío que salvo, el tiempo que pierde
    el rival en volver a jugarla y si era una carta mía robada. Resta si al
    salir le da algo al rival (Werin se busca un Talismán)."""
    v = 2.0 * _fuerza_que_aporta(p, t) if t.controlador != yo else 0.0
    if t.tipo == Tipo.ALIADO and t.uid in _combatientes(p):
        peso_mio = 2.0 if len(p.j(yo).mazo) <= 15 else 1.0
        peso_suyo = 2.0 if len(p.j(1 - yo).mazo) <= 15 else 1.0
        for a in p.atacantes:
            b = p.bloqueos.get(a.uid)
            if a is t:  # me ataca
                if b is None or not b.en_juego:
                    v += hab.fuerza(p, t) * peso_mio  # daño que evito
                elif hab.fuerza(p, b) < hab.fuerza(p, t):
                    v += _valor_vivo(p, b)  # salvo a mi bloqueador, que moría solo
                # #34: si mueren los dos, sacar su atacante solo lo salva a él.
            elif b is t:  # bloquea a mi atacante
                fa, ft = hab.fuerza(p, a), hab.fuerza(p, t)
                if fa > ft and not hab.tiene_prop(p, t, "indestructible"):
                    # Muere igual (Werin ante Nephre-Ka con el Escudo): el
                    # exceso ya pasa, sacarlo solo suma lo que frenaba y le
                    # salva la carta al rival (salvo que su castillo esté bajo).
                    v += max(0, ft) * peso_suyo - (_valor_vivo(p, t) if peso_suyo == 1 else 0)
                else:
                    v += fa * peso_suyo  # daño que dejo pasar
                    if ft > fa:
                        v += _valor_vivo(p, a)  # salvo a mi atacante (y él no moría)
    v += t.carta.coste * 0.5  # tiene que volver a pagarla
    if t.controlador != yo and t.en_juego and _motor_activable(p, t) and _motor_con_combustible(p, t):
        v += 8.0  # #4 0VzQ: Nuh trae un Arma gratis cada turno (más que Pili con la Lanza)
    if t.controlador != yo and t.tipo == Tipo.ALIADO and p.e.activo == yo and p.e.fase == "vigilia":
        # #15 0VzQ: por ganar, sacar un bloqueador abre paso; el que está en la
        # Línea de Ataque no bloquea este turno.
        mi_ataque = sum(max(0, hab.fuerza(p, a)) for a in p.j(yo).aliados if _puede_atacar(p, a))
        if mi_ataque >= len(p.j(1 - yo).mazo):
            if t.zona == Zona.DEFENSA and not hab.tiene_estado(p, t, "no_puede_bloquear"):
                v += 10.0
            elif t.zona == Zona.ATAQUE:
                v -= 4.0
    if t.zona == Zona.CEMENTERIO and t.controlador != yo and _se_juega_del_cementerio(t):
        # Escarabeo al Escudo Miliciano: desde ahí arma a Djoser al bloquear.
        v += 4.0 + t.carta.coste * 0.5
    if t.zona == Zona.CEMENTERIO and t.controlador != yo and _pieza_clave(t):
        v += 3.0  # Neferite anulada: desterrarla para que no vuelva (Montuhopet, Bennu)
    # #121: si porta Armas, se van con él (Montuhopet con el Escudo Miliciano).
    v += sum(a.carta.coste * 0.5 + 1 for a in p.e.portadas if a.portador == t.uid)
    if t.dueno == yo and t.controlador != yo:
        v += 1.5 * _valor_vivo(p, t)  # #38: recupero mi Ramsés II
    # Sacar a Haquika me devuelve lo que me robó (mientras esté en juego).
    v += sum(1.5 * _valor_vivo(p, x) for x in p.e.instancias_en_juego(t.controlador)
             if x.dueno == yo and x.control and x.control.get("fuente") == t.uid)
    if _gana_al_morir(t) or any(x.get("cuando") == "al_salir_del_juego" for x in t.habilidades):
        v -= 3.0
    return v


def _impacto_bloqueador(p, yo, t: Instancia, fuente: Instancia | None = None) -> float:
    """Qer-Her en mi Vigilia, antes de atacar: sacar al bloqueador (Montuhopet
    con el Escudo Miliciano) deja pasar a mi atacante y no baraja nada."""
    if not (
        t.tipo == Tipo.ALIADO and p.e.activo == yo and p.e.fase == "vigilia" and t.controlador != yo
        and t in p.j(t.controlador).defensa and not hab.tiene_estado(p, t, "no_puede_bloquear")
    ):
        return 0.0
    ft = hab.fuerza(p, t)
    # Qer-Her se destruye para usarse: no cuenta como atacante.
    mios = [a for a in p.j(yo).aliados if a is not fuente and a.listo and _puede_atacar(p, a) and hab.fuerza(p, a) > 0]
    frena = [a for a in mios if hab.fuerza(p, a) <= ft]
    if not frena:
        return 0.0
    peso_suyo = 2.0 if len(p.j(1 - yo).mazo) <= 15 else 1.0
    a = max(frena, key=lambda x: hab.fuerza(p, x))
    return hab.fuerza(p, a) * peso_suyo + (_valor_vivo(p, a) if hab.fuerza(p, a) < ft else 0)


def _fuerza_temporal_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Cambiar la fuerza por un rato solo sirve si cambia un combate."""
    if (h.get("duracion") or "instantaneo") in _DURACIONES_PERMANENTES or h.get("cuando") == "continua":
        return True
    obj = h.get("objetivo") or {}
    if obj.get("quien") == "esta_carta":
        return True
    fijar_cero = h.get("modoFuerza") == "fijar" and int(h.get("valor", 0) or 0) == 0
    sube = int(h.get("valor", 0)) >= 0 and not fijar_cero
    if not p.atacantes:
        # #3 Zrfq: un Talismán (Forma de Lince) se guarda para la Guerra: sorpresa.
        if fuente.tipo == Tipo.TALISMAN:
            return False
        # Sin combate: solo subir a los propios antes de atacar en tu Vigilia, y
        # a uno que ataque este turno (#5/#8: no al Medjay recién jugado).
        return sube and p.e.fase == "vigilia" and p.e.activo == yo and (h.get("duracion") or "") != "instantaneo" \
            and any(t.controlador == yo and _ataca_este_turno(p, t) for t in hab.candidatos_validos(p, yo, fuente, h))
    combatientes = _combatientes(p)
    cands = hab.candidatos_validos(p, yo, fuente, h)
    cambio = int(h.get("valor", 0))
    bloqueados = {a for a, b in p.bloqueos.items() if b is not None and b.en_juego}

    def sirve(t):
        if t.uid not in combatientes or (t.controlador == yo) != sube:
            return False
        if sube and t in p.atacantes and t.uid not in bloqueados:
            # #3 Zrfq: Forma de Lince en un atacante libre: más daño (y roba la copia).
            # #3 EZMt: el Merodeador también, ya en la Guerra de Talismanes.
            return True
        if _decisivo(p, t, -hab.fuerza(p, t) if fijar_cero else cambio):
            return True  # #120: cambia quién muere
        if sube and t in p.atacantes and t.uid in bloqueados:
            b = p.bloqueos.get(t.uid)
            if b is not None and hab.fuerza(p, t) + cambio > hab.fuerza(p, b):
                return True  # I4Sl2 #3: el exceso pasa al castillo (La Ilíada en Liontari contra Haquika)
        # Un atacante sin bloquear: −1 solo ahorra 1 de daño; vale si apura.
        return not sube and t.uid not in bloqueados and _en_peligro(p, yo)

    return any(sirve(t) for t in cands)


def _perder_habilidad_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    return bool(_objetivos_perder_habilidad(p, yo, fuente, h))


def _objetivos_perder_habilidad(p, yo, fuente: Instancia, h: dict, objetivos=None) -> list:
    """A quién vale la pena quitarle la habilidad ahora. Una Restricción,
    solo si me restringe algo que uso (Nudo de Isis impide barajar: sirve si
    tengo cartas que barajan)."""
    obj = h.get("objetivo") or {}
    propia = obj.get("quien") == "esta_carta"
    if objetivos is None:
        objetivos = [fuente] if propia else hab.candidatos_validos(p, yo, fuente, h)
    if not objetivos:
        return []
    jug = p.j(yo)
    # #15/#71: solo cuenta lo que voy a usar ya (en juego o jugable este
    # turno desde la mano), no lo que algún día robaré.
    # Ib-Mut ya en la Reserva no vuelve a barajar: su habilidad era al entrar.
    # En juego cuentan las que se activan o disparan en mi combate; en la
    # mano, las de cartas que puedo jugar ahora.
    # #111: lo que baraja al atacar o al hacer daño (Escudo Celestial) solo
    # cuenta si de verdad ataco este turno (no con Flechas de Lava a la vista).
    ataco = p.e.activo == yo and not (_cancelador_revelado(p, 1 - yo) and not _puedo_anular(p, yo))
    combate = {"al_atacar", "al_hacer_dano", "al_ser_bloqueado"}
    acciones = {
        x.get("accion") for c in p.e.instancias_en_juego(yo) for x in c.habilidades
        if x.get("cuando") == "activada" or (ataco and x.get("cuando") in combate)
    } | {
        x.get("accion")
        for c in jug.mano
        if (c.tipo == Tipo.ORO and not jug.oro_jugado and p.e.activo == yo)
        or (c.tipo != Tipo.ORO and p.puede_pagar(yo, c))
        for x in c.habilidades
        # De la mano, solo lo que baraja al jugarse o activarse ahora: un
        # Escudo Celestial guardado no va a barajar este turno.
        if x.get("cuando") in ("al_jugar", "activada")
    }
    # Voy a atacar en este turno con algún Aliado listo.
    atacare = ataco and p.e.fase == "vigilia" and any(
        a.listo and _puede_atacar(p, a) and hab.fuerza(p, a) > 0 for a in jug.aliados
    ) and not (_MAZO_LENTO_PASIVO and _mazo_lento(p, yo) and not _partida_controlada(p, yo))  # #5 c0p0
    out = []
    for t in objetivos:
        if t.controlador == yo and not propia:
            continue
        if any(x.get("accion") == "restriccion" and x.get("modo") == "jugar_tipo"
               and (x.get("objetivo") or {}).get("quien") in ("ambos", "cualquiera")
               for x in t.habilidades) and any(
                   c.tipo == Tipo.TALISMAN and p.puede_pagar(1 - yo, c) for c in p.j(1 - yo).mano
               ):
            continue  # quitar esta restricción también habilita Talismanes rivales
        # Sin contar la habilidad que uso para quitársela (usaQuien), ni las de
        # "al entrar" que ya usó (Kawit ya buscó su Oro), ni las que solo lo
        # protegen (Inmunidad de Werin: no tengo nada que apuntarle).
        habs = [
            x for x in t.carta.habilidades
            if x.get("accion") not in hab.PROPIEDADES and x.get("accion") not in ("inmunidad", "errante")
            and x.get("usaQuien") not in ("oponente", "ambos")
            and not (t.en_juego and x.get("cuando") in ("al_jugar", None))
        ]
        # #87: en combate, al bloqueador indestructible que muere sin ella
        # (Haquika bloqueando a mi Aliado más fuerte).
        if not propia and any(
            p.bloqueos.get(a.uid) is t and hab.tiene_prop(p, t, "indestructible") and hab.fuerza(p, a) >= hab.fuerza(p, t)
            for a in p.atacantes
        ):
            out.append(t)
            continue
        # EZMt: el Merodeador atacando, bloqueado por mi Aliado que lo iguala o
        # le gana: sin habilidad no se sube la fuerza desterrando del Cementerio.
        if not propia and t in p.atacantes and (p.bloqueos.get(t.uid) or None) is not None \
                and p.bloqueos[t.uid].controlador == yo \
                and hab.fuerza(p, p.bloqueos[t.uid]) >= hab.fuerza(p, t) and any(
                    x.get("cuando") == "activada" and x.get("accion") == "modificarFuerza"
                    and int(x.get("valor", 0) or 0) > 0 and hab.puede_pagar_costo(p, t.controlador, t, x)
                    for x in t.habilidades):
            out.append(t)
            continue
        # Combo: Adiós Belleza a Werin y después lo saco. Sin Inmunidad,
        # Neferite o Nephre-Ka ya lo alcanzan; y sin habilidad, al salir del
        # juego (también con Akhet) no busca su Talismán.
        if not propia and t.tipo == Tipo.ALIADO:
            remociones = _remociones_a_mano(p, yo, pagando=_oros_que_cuesta_quitar(p, yo, fuente, h))
            bloqueadas = [r for r in remociones if hab.inmune(p, t, r)]
            al_salir = any(x.get("cuando") == "al_salir_del_juego" for x in habs)
            # #6 ZOlJ: Ptolomeo II se previene del Dragón de Magma: Carnwennan primero.
            previene = any(x.get("accion") == "prevenir" for x in t.carta.habilidades)
            if bloqueadas or ((al_salir or previene) and remociones):
                out.append(t)
                continue
        if not propia and not _remociones_a_mano(p, yo):
            # #6 UUOX: Corona de Arturo (Oros indestructibles) solo molesta si tengo con qué destruir.
            habs = [x for x in habs if not (x.get("accion") == "otorgarPropiedad"
                                            and x.get("modo") in ("indestructible", "indesterrable"))]
        if not habs:
            continue
        if propia or all(x.get("accion") == "restriccion" for x in habs):
            if any((x.get("modo") or "").split("_")[0] in acciones for x in habs):
                out.append(t)  # Nudo de Isis me impide barajar lo que voy a barajar
            continue
        if t.tipo == Tipo.ORO and not p.atacantes and all(x.get("cuando") == "activada" for x in t.carta.habilidades):
            # #99 Un Oro que se activa (Papiros) solo molesta en combate; pero
            # si voy a atacar, Jeroglíficos me devolvería el atacante a la mano.
            if atacare and any(
                x.get("accion") in ("subirMano", "destruir", "desterrar") and (x.get("objetivo") or {}).get("quien") == "oponente"
                and (x.get("objetivo") or {}).get("zona", "en_juego") == "en_juego"  # Escarabeo destierra del Cementerio: no
                for x in t.carta.habilidades
            ):
                out.append(t)
            elif any(x.get("accion") in ("prevenir", "anular", "redirigir") for x in t.carta.habilidades) \
                    and _remociones_a_mano(p, yo, pagando=0):
                out.append(t)  # Amkh prevendría la Focea que le voy a tirar a Haquika
            continue
        sigue = {"continua", "propia_entra", "propia_sale", "al_atacar", "al_bloquear", "al_hacer_dano",
                 "al_ser_bloqueado", "al_inicio_fase"}
        if not propia and p.e.activo == yo and (
            t.zona == Zona.ATAQUE or not t.listo or hab.tiene_estado(p, t, "no_puede_bloquear")
        ):
            # #4 EZMt: los Guerreros Egipcios en la línea de ataque no bloquean
            # este turno: su habilidad al bloquear no importa.
            sigue = sigue - {"al_bloquear"}
        if not propia and p.e.activo != yo and p.atacantes:
            # En el turno rival, ya declarado el ataque, lo de "al atacar" ya se
            # aplicó (el +2 de los Egipcios): quitarle la habilidad no lo deshace.
            sigue = sigue - {"al_atacar"}
        if not propia and h.get("duracion") == "hasta_fase_final":
            # #7 ZOlJ: hasta mi Fase Final, Ramsés IX no ataca: su habilidad no molesta.
            sigue -= {"al_atacar", "al_hacer_dano", "al_ser_bloqueado"} if p.e.activo == yo else {"al_bloquear"}
            if p.e.activo == yo and not atacare:
                sigue -= {"al_bloquear"}  # #9 UUOX: Guerreros Egipcios solo molesta si lo ataco
            if p.e.activo == yo:
                # Guerrero Escorpión: su robo y la Furia que da son de su turno.
                habs = [x for x in habs if x.get("turno") != "propio"
                        and not (x.get("accion") == "otorgarPropiedad" and x.get("modo") == "furia")]
        if any(x.get("cuando") in sigue and x.get("accion") != "restriccion" for x in habs):
            out.append(t)
        # Qer-Her: solo habilidades que paga para usar; mejor guardarla
    return out


def _oros_que_cuesta_quitar(p, yo, fuente, h: dict) -> int:
    """Oros que dejo de tener por quitar la habilidad: el coste del Talismán,
    o el Oro sin pagar que se destierra (Carnwennan)."""
    if fuente is None:
        return 0
    if not fuente.en_juego:
        return p.coste_de(yo, fuente)
    if fuente.tipo == Tipo.ORO and (h.get("costo") or {}).get("desterrarEstaCarta") and fuente in p.j(yo).reserva:
        return 1
    return 0


def _remociones_a_mano(p, yo, *, pagando: int = 0) -> list:
    """Cartas con las que puedo sacar ahora un Aliado rival: activadas en mi
    mesa (Neferite) o cartas de la mano que alcanzo a pagar después de
    `pagando` Oros (Nephre-Ka, Akhet)."""
    jug = p.j(yo)
    sacar = ("destruir", "desterrar", "mover", "subirMano")

    def remueve(x):
        obj = x.get("objetivo") or {}
        return x.get("accion") in sacar and obj.get("quien") == "oponente" and "Aliado" in (obj.get("tipos") or ["Aliado"])

    out = []
    for c in p.e.instancias_en_juego(yo):
        if any(x.get("cuando") == "activada" and remueve(x) for x in c.habilidades):
            out.append(c)
    for c in jug.mano:
        if c.tipo != Tipo.ORO and p.coste_de(yo, c) <= jug.oro_disponible - pagando and any(
            x.get("cuando") in ("al_jugar", None) and remueve(x) for x in c.habilidades
        ):
            out.append(c)
    return out


def _arma_gratis_disponible(p, yo) -> bool:
    """Tengo en mesa o en la mano un Aliado que juega cualquier Arma gratis
    desde el Mazo o el Cementerio (Nuh)."""
    # Simulación yI09 T4: Rey Arturo en la mano con 1 Oro (le faltan varios
    # turnos) frenaba a Yvain de buscar Galatine. De la mano solo cuenta lo que
    # pago este turno o el próximo.
    en_mano = [x for x in p.j(yo).mano if p.coste_de(yo, x) <= p.j(yo).oro_disponible + 1]
    for x in p.e.instancias_en_juego(yo) + en_mano:
        if x is None or x.tipo == Tipo.ORO:
            continue
        for h in x.carta.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("accion") == "jugarDesde" and (h.get("modo") or "sin_pagar") == "sin_pagar" \
                    and obj.get("quien", "propio") == "propio" and "Arma" in (obj.get("tipos") or []) \
                    and set(hab.zonas_de(obj, "mano")) & {"cementerio", "mazo"}:
                return True
    return False


def _buscar_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """No buscar a la mano algo que ya se juega desde donde está (Qer-Her), ni
    un Arma si Nuh me la trae gratis."""
    if h.get("zonaDestino", "mano") != "mano":
        return True
    cands = hab.candidatos_validos(p, yo, fuente, h)
    if cands and _arma_gratis_disponible(p, yo):
        cands = [c for c in cands if c.tipo != Tipo.ARMA]
    return any(not (_se_juega_desde(c) & {_zona_de(c)}) and not hab.prohibido(p, "jugar_tipo", yo, c)
               for c in cands) if cands else False


def _zona_de(c: Instancia) -> str:
    return {Zona.MAZO: "mazo", Zona.CEMENTERIO: "cementerio", Zona.DESTIERRO: "destierro", Zona.MANO: "mano"}.get(
        c.zona, "en_juego"
    )


def _masiva_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Qadesh: destruir todo solo si el rival pierde bastante más que yo y
    puedo rearmarme (Aliados en mano) o él tiene muchos más Aliados."""
    cands = hab.candidatos_validos(p, yo, fuente, h)
    mios = [c for c in cands if c.controlador == yo]
    suyos = [c for c in cands if c.controlador != yo]
    if not suyos:
        return False
    ventaja = sum(_valor_carta(p, c) for c in suyos) - sum(_valor_carta(p, c) for c in mios)
    if "Aliado" not in ((h.get("objetivo") or {}).get("tipos") or ["Aliado"]):
        return ventaja >= 3  # #166 Quemar los Templos: revienta sus Armas
    rearme = any(c.tipo == Tipo.ALIADO for c in p.j(yo).mano if c is not fuente)
    return ventaja >= 6 and (rearme or len(suyos) - len(mios) >= 2)


def _valor_de_rejugar(p, yo, c: Instancia) -> float:
    """Cuánto gana un Aliado propio al volver a la mano y jugarse de nuevo
    (Nephre-Ka con algo que destruir). Sin habilidad al entrar, solo pierde
    tiempo y Oros."""
    # Amyrteos: al salir del juego (también a la mano) acelera un Oro.
    salida = 6.0 if _gana_al_morir(c) else 0.0
    # tuK8 #6 (Epicuro): lo invertido este turno (Doce Pruebas) y sus Armas se
    # pierden; un motor ya usado (Idmon) se vuelve a activar si se rejuega.
    perdido = 8.0 * any(m.turno == p.e.turno and m.valor > 0 for m in c.mods) \
        + sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == c.uid)
    motor = 4.0 * any(_habilidad_repetible(h) and hab.usos(p, yo, c, h, k) > 0 for k, h in enumerate(c.habilidades)) \
        if p.puede_pagar(yo, c) else 0.0
    salida += motor - perdido
    if not any(h.get("cuando") == "al_jugar" for h in c.habilidades):
        return salida - c.carta.coste * 0.5
    return salida + _valor_remocion_al_entrar(p, yo, c) + 1.0 - c.carta.coste * 0.5


def _valor_rebote(p, yo, inst: Instancia) -> float:
    """Montuhopet II: lo que gana subiendo el mejor Aliado propio (#43, #134:
    subir a Amyrteos acelera un Oro y se vuelve a jugar)."""
    mejor = 0.0
    for h in inst.habilidades:
        if _rebote_propio(h):
            cands = hab.candidatos_validos(p, yo, inst, h)
            mejor = max([mejor] + [2.0 * _valor_de_rejugar(p, yo, c) for c in cands])
    return mejor


def _rebote_propio(h: dict) -> bool:
    obj = h.get("objetivo") or {}
    return h.get("cuando") == "al_jugar" and h.get("accion") == "subirMano" and obj.get("quien") == "propio"         and "en_juego" in hab.zonas_de(obj) and not h.get("opcional")


def _aliado_conviene(p, yo, inst: Instancia) -> bool:
    """Pili: un Aliado débil cuya habilidad al entrar no tendría objetivo se
    guarda, salvo que el castillo esté en peligro. Montuhopet II: si obliga a
    subir un Aliado propio, solo se juega si hay uno que gane al rejugarse."""
    for h in inst.habilidades:
        if _rebote_propio(h):
            cands = hab.candidatos_validos(p, yo, inst, h)
            if cands and max(_valor_de_rejugar(p, yo, c) for c in cands) <= 0:
                return False  # ni en peligro: devolver un Aliado útil nunca ayuda
            if not cands and len(p.j(yo).mazo) > 15:
                return False  # #89: sin nada que subir, se guarda para el combo
    if len(p.j(yo).mazo) <= 15:
        return True
    if _COMETA_ESPERA and not _en_peligro(p, yo) and any(
            h.get("cuando") == "al_jugar" and h.get("accion") == "perderHabilidad"
            and (h.get("objetivo") or {}).get("quien") == "oponente" for h in inst.habilidades) \
            and not any((_anular_siempre(p, a) or _valor_vivo(p, a) > 5)
                        and not any(x.get("accion") == "ganarControl" for x in a.habilidades)
                        for a in p.j(1 - yo).aliados if not _neutralizado(p, a)):
        # Héctor 2026-11-12 (19965): Draco Cometa se guarda para quitarle la
        # habilidad al Demoledor cuando entre (a la Haquika no: no devuelve el Aliado).
        return False
    habs = [h for h in inst.habilidades if h.get("cuando") == "al_jugar" and hab._necesita_objetivo(h)]
    remocion = [
        h for h in habs
        if h.get("accion") in _REMOCION and (h.get("objetivo") or {}).get("quien") == "oponente"
    ]
    if remocion and _valor_remocion_al_entrar(p, yo, inst) <= 0:
        # #11: Nephre-Ka sin Cementerio para pagar entra sin efecto: se guarda,
        # salvo que haga falta mesa o sirva para alimentar a Ay (robar 2).
        # Para armar mesa, mejor otro Aliado que no gaste su habilidad (Amyrteos).
        otro = any(
            c is not inst and c.tipo == Tipo.ALIADO and p.puede_pagar(yo, c)
            and not any(x.get("cuando") == "al_jugar" and x.get("accion") in _REMOCION for x in c.habilidades)
            for c in p.j(yo).mano
        )
        sin_mesa = not p.j(yo).aliados and not otro and (p.j(1 - yo).aliados or len(p.j(yo).mazo) <= 15)
        para_ay = any(_es_salida(c) for c in p.j(yo).aliados + p.j(yo).mano if c is not inst)
        if not (sin_mesa or para_ay):
            return False
    if not habs or inst.carta.fuerza >= inst.carta.coste:
        return True
    return any(hab.candidatos_validos(p, yo, inst, h) for h in habs)


_REMOCION = {"destruir", "desterrar", "subirMano", "mover", "ganarControl"}


def _refuerzo_desde_cementerio(p, quien: int) -> int:
    mejor = 0
    oros = p.j(quien).oro_disponible
    for c in p.j(quien).cementerio:
        if c.tipo != Tipo.ARMA:
            continue
        for h in c.habilidades:
            if h.get("accion") != "jugarDesde" or h.get("cuando") != "activada":
                continue
            if hab.zona_activacion(h) != "cementerio" or int((h.get("costo") or {}).get("oros", 0)) > oros:
                continue
            bono = sum(
                int(x.get("valor", 0)) for x in c.habilidades
                if x.get("accion") == "modificarFuerza" and x.get("cuando") == "continua"
            )
            mejor = max(mejor, bono)
    return mejor


def _refuerzo_activable(p, quien: int, bloqueadores) -> int:
    """I4Sl2 #1: lo que el rival le puede sumar a un bloqueador en la Guerra
    de Talismanes con algo ya en juego (La Ilíada: +2 a un Titán, botando 1)."""
    mejor = 0
    for s in hab.fuentes_activables(p, quien):
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "modificarFuerza" or h.get("cuando") != "activada":
                continue
            valor = int(h.get("valor", 0) or 0)
            if valor <= 0 or h.get("modoFuerza", "sumar") != "sumar" or not hab._en_zona_activacion(s, h):
                continue
            limite = int(h.get("limitePorTurno", 0) or 0)
            if limite and s.usos_turno.get(k, 0) >= limite:
                continue
            if not hab.puede_pagar_costo(p, quien, s, h):
                continue
            obj = h.get("objetivo") or {}
            if obj.get("quien") == "esta_carta":
                if any(hab._esta_carta(p, s) is b for b in bloqueadores):
                    mejor = max(mejor, valor)
            elif any(hab.coincide(p, b, {**obj, "quien": None}) for b in bloqueadores):
                mejor = max(mejor, valor)
    return mejor


def _botar_de(p, yo, j) -> int:
    """Cuántas cartas hace botar al rival esta jugada (0 si no bota)."""
    if j.tipo == "activar":
        habs = [j.carta.habilidades[j.habilidad]]
    elif j.carta is not None and j.carta.tipo == Tipo.TALISMAN:
        habs = [h for h in j.carta.habilidades if h.get("cuando") in ("al_jugar", None)]
    else:
        return 0
    total = 0
    for h in habs:
        if h.get("accion") == "botar" and (h.get("objetivo") or {}).get("quien", "oponente") in ("oponente", "ambos"):
            total += hab.cantidad(p, yo, h, [], lado=1 - yo)
    return total


def _se_rejuega_del_cementerio(c: Instancia) -> bool:
    """Jinetes de Fuego: se puede jugar desde el Cementerio (y desde la mano
    va al Cementerio, así que se juega dos veces)."""
    return any(
        hab.es_permiso_jugar(h) and "cementerio" in hab.zonas_de(h.get("objetivo") or {}, "cementerio")
        for h in c.habilidades
    )


def _botar_posible(p, yo) -> int:
    """Todo lo que puedo hacer botar al rival este turno con los Oros que
    tengo: Talismanes, Armas que botan al atacar en un Aliado listo
    (Mandoble de Seth) y Oros que botan (Papiros de Lahun)."""
    jug = p.j(yo)
    oros = jug.oro_disponible
    listos = [a for a in jug.aliados if a.listo and not hab.tiene_estado(p, a, "no_puede_atacar")]
    items = []  # (bota, gasta)
    for c in jug.mano:
        if c.tipo == Tipo.TALISMAN:
            b = sum(
                hab.cantidad(p, yo, h, [], lado=1 - yo) for h in c.habilidades
                if h.get("accion") == "botar" and h.get("cuando") in ("al_jugar", None)
                and (h.get("objetivo") or {}).get("quien", "oponente") == "oponente"
            )
            if b:
                items.append((b, p.coste_de(yo, c)))
                if _se_rejuega_del_cementerio(c):
                    items.append((b, p.coste_de(yo, c)))  # Jinetes de Fuego: de la mano y otra vez del Cementerio
        elif c.tipo == Tipo.ARMA and listos:
            b = sum(
                int(h.get("cantidad", 1)) for h in c.habilidades
                if h.get("cuando") == "al_atacar" and h.get("accion") == "botar"
            )
            if b:
                items.append((b, p.coste_de(yo, c)))
    for c in jug.cementerio:
        # #139: Jinetes de Fuego se juega desde el Cementerio.
        if c.tipo == Tipo.TALISMAN and _se_rejuega_del_cementerio(c):
            b = sum(
                hab.cantidad(p, yo, h, [], lado=1 - yo) for h in c.habilidades
                if h.get("accion") == "botar" and h.get("cuando") in ("al_jugar", None)
            )
            if b:
                items.append((b, p.coste_de(yo, c)))
    for c in jug.reserva:
        for h in c.habilidades:
            if h.get("cuando") == "activada" and h.get("accion") == "botar":
                costo = h.get("costo") or {}
                items.append((int(h.get("cantidad", 1)), int(costo.get("oros", 0)) + (1 if costo.get("pagarEstaCarta") else 0)))
    total = sum(_bota_al_atacar(p, a) for a in listos)
    # #137 / #139: el daño de combate también suma (el exceso pasa aunque
    # bloqueen).
    total += _dano_estimado(p, yo, listos)
    for b, g in sorted(items, key=lambda x: (-x[0], x[1])):
        if g <= oros:
            total += b
            oros -= g
    return total


def _dano_estimado(p, yo, listos) -> int:
    """Daño de combate que hago este turno. En combate, el real; si no, con
    el rival bloqueando a mis atacantes más fuertes con sus mejores Aliados."""
    if p.atacantes and p.e.activo == yo:
        total = 0
        for a in p.atacantes:
            if not a.en_juego:
                continue
            b = p.bloqueos.get(a.uid)
            fa = max(0, hab.fuerza(p, a))
            total += fa if b is None or not b.en_juego else max(0, fa - hab.fuerza(p, b))
        return total
    atacan = sorted((max(0, hab.fuerza(p, a)) for a in listos), reverse=True)
    bloquean = sorted(
        (max(0, hab.fuerza(p, b)) for b in p.j(1 - yo).defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")),
        reverse=True,
    )
    total = 0
    for k, fa in enumerate(atacan):
        total += fa - min(fa, bloquean[k]) if k < len(bloquean) else fa
    return total


def _remate_en_marcha(p, yo) -> bool:
    return p.e.activo == yo and _botar_posible(p, yo) >= len(p.j(1 - yo).mazo)


def _me_bota(p, yo, j) -> int:
    """Cuánto de mi castillo bota esta jugada (Grandes Faraones nos bota a
    los dos, y a mí 1 más con pocos Faraones)."""
    # Tocador del rival: si mi botar no lo deja fuera, me devuelve lo mismo.
    espejo = 0
    bota = _botar_de(p, yo, j)
    if bota and _devuelvo_lo_botado(p, 1 - yo) and bota < len(p.j(1 - yo).mazo):
        espejo = bota
    if j.tipo != "activar":
        return espejo
    h = j.carta.habilidades[j.habilidad]
    n = espejo
    for e in [h] + [x for x in h.get("luego") or [] if isinstance(x, dict)]:
        if e.get("accion") == "botar" and (e.get("objetivo") or {}).get("quien") in ("ambos", "propio"):
            n += int(e.get("cantidad", 1) or 1)
    return n + int((h.get("costo") or {}).get("botar", 0) or 0)


def _remate(p, yo, jugadas):
    """Si sumando lo que bota cada jugada disponible (con los Oros que hay)
    el rival se queda sin castillo, empieza por la que más bota."""
    rival = len(p.j(1 - yo).mazo)
    oros = p.j(yo).oro_disponible

    def bota(j):
        # Un Arma que bota al atacar cuenta si va en un Aliado propio listo.
        if j.tipo == "jugar" and j.carta.tipo == Tipo.ARMA and j.portador is not None:
            if j.portador.controlador == yo and j.portador.listo:
                return sum(
                    int(h.get("cantidad", 1)) for h in j.carta.habilidades
                    if h.get("cuando") == "al_atacar" and h.get("accion") == "botar"
                )
            return 0
        if (j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO and p.e.activo == yo
                and hab.tiene_prop(p, j.carta, "furia") and hab.tiene_prop(p, j.carta, "imbloqueable")
                and not _cancelador_revelado(p, 1 - yo)):
            return max(0, j.carta.carta.fuerza)  # #14 0VzQ: Dario III entra y pega 4 seguro
        return _botar_de(p, yo, j)

    botadoras = sorted(
        ((bota(j), _oros_que_gasta(p, yo, j), j) for j in jugadas
         if j.tipo != "pasar" and _me_bota(p, yo, j) < len(p.j(yo).mazo)),
        key=lambda x: (-x[0], x[1]),
    )
    if _remate_en_marcha(p, yo):
        # Lo que bota recién al atacar o en la Guerra (Papiros) también suma.
        return next((j for b, _, j in botadoras if b > 0), None)
    total, usadas = 0, set()
    for bota, gasta, j in botadoras:
        if bota <= 0 or gasta > oros or id(j.carta) in usadas:
            continue
        total += bota
        oros -= gasta
        usadas.add(id(j.carta))
    if total < rival or total <= 0:
        return None  # sin castillo rival (pierde al robar) no hay nada que rematar
    return next((j for bota, _, j in botadoras if bota > 0), None)


def _alimenta_remocion(p, yo, n: int) -> float:
    """Botarle n cartas al rival le llena el Cementerio: Neferite I paga su
    destierro desterrando de ahí según el coste del objetivo. ¿Cuánto vale el
    mejor Aliado mío que pasaría a quedar a su alcance (Haquika, Demoledor)?"""
    if n <= 0:
        return 0.0
    cem = len(p.j(1 - yo).cementerio)
    mios = [x for x in p.e.instancias_en_juego(yo) if x.tipo != Tipo.ORO]
    perdida = 0.0
    for c in p.e.instancias_en_juego(1 - yo):
        for h in c.habilidades:
            if (
                h.get("cuando") != "activada" or h.get("accion") not in ("destruir", "desterrar")
                or (h.get("costo") or {}).get("desterrarCementerioSegun") != "coste_objetivo"
            ):
                continue
            antes = [x for x in mios if x.carta.coste <= cem and hab.coincide(p, x, h.get("objetivo") or {})]
            despues = [x for x in mios if x.carta.coste <= cem + n and hab.coincide(p, x, h.get("objetivo") or {})]
            v0 = max((_valor_carta(p, x) for x in antes), default=0.0)
            v1 = max((_valor_carta(p, x) for x in despues), default=0.0)
            perdida = max(perdida, v1 - v0)
    return perdida


def _es_letal(p, yo, j) -> bool:
    """¿La jugada deja al rival sin Mazo Castillo?"""
    if j.tipo == "activar":
        habs = [j.carta.habilidades[j.habilidad]]
    elif j.carta is not None and j.carta.tipo == Tipo.TALISMAN:
        habs = [h for h in j.carta.habilidades if h.get("cuando") in ("al_jugar", None)]
    else:
        return False
    rival = len(p.j(1 - yo).mazo)
    for h in habs:
        if h.get("accion") == "botar" and (h.get("objetivo") or {}).get("quien", "oponente") in ("oponente", "ambos"):
            if hab.cantidad(p, yo, h, [], lado=1 - yo) >= rival:
                return True
    return False


def _letal_por_refuerzo(p, yo, carta: Instancia) -> bool:
    """Furia Irracional: +2 e imbloqueable puede cerrar el ataque ya armado.

    La estimación es deliberadamente de Vigilia: suma la mesa que puede atacar,
    el bono de la carta y el botar garantizado al atacar. Si alcanza el
    castillo rival, esa carta debe ir antes que una activación de valor menor.
    """
    bonos = [int(h.get("valor", 0) or 0) for h in carta.habilidades
             if h.get("accion") == "modificarFuerza" and int(h.get("valor", 0) or 0) > 0]
    if not bonos or p.e.activo != yo or p.e.fase != "vigilia":
        return False
    ataque = sum(
        max(0, hab.fuerza(p, a)) + _bota_seguro_al_atacar(p, a)
        for a in p.j(yo).aliados if _puede_atacar(p, a)
    )
    return ataque + max(bonos) >= len(p.j(1 - yo).mazo)


def _recupera_al_bloquear(p, b: Instancia) -> bool:
    """Escudo Miliciano: al bloquear, el portador baraja cartas del Cementerio."""
    fuentes = [b] + [a for a in p.e.portadas if a.portador == b.uid]
    return any(
        h.get("cuando") == "al_bloquear" and h.get("accion") == "barajar"
        for x in fuentes for h in x.habilidades
    )


def _es_salida(c: Instancia) -> bool:
    """Ay: se activa sacrificando otro Aliado propio."""
    return any(
        h.get("cuando") == "activada"
        and ((h.get("costo") or {}).get("desterrarAliados") or (h.get("costo") or {}).get("destruirAliados"))
        for h in c.habilidades
    )


def _hay_salida(p, yo, inst: Instancia) -> bool:
    """¿Tengo cómo sacar del juego a este Aliado con provecho? Ay en juego
    (desterrar un Aliado para robar) o Montuhopet en la mano (subirlo)."""
    for c in list(p.e.instancias_en_juego(yo)):
        for h in c.habilidades:
            costo = h.get("costo") or {}
            if h.get("cuando") == "activada" and (costo.get("desterrarAliados") or costo.get("destruirAliados")):
                return True
    return any(_rebote_propio(h) for c in p.j(yo).mano if c is not inst for h in c.habilidades)


def _muere_en_este_combate(p, t: Instancia) -> bool:
    """El Aliado está en el combate en curso y su rival lo mata."""
    for a in getattr(p, "atacantes", []) or []:
        b = p.bloqueos.get(a.uid)
        if b is None:
            continue
        if a is t and hab.fuerza(p, b) >= hab.fuerza(p, a):
            return True
        if b is t and hab.fuerza(p, a) >= hab.fuerza(p, b):
            return True
    return False


def _vale_un_talisman(p, yo, c: Instancia) -> bool:
    """Héctor 2026-11-12: un Talismán de remoción (Bola de Fuego) no se gasta
    en un Aliado chico que ya usó su "al entrar" (Kawit sin Arma), ni en uno
    que al salir le da algo al rival (Werin busca un Talismán) salvo que sea
    grande o lleve Arma."""
    if c.tipo != Tipo.ALIADO:
        return True
    if _CORRECCIONES_19965 and _sostiene_anulacion(p, yo, c):
        return False  # Héctor: la Bola al Cometa robado le devuelve la habilidad al Demoledor
    armado = any(a.portador == c.uid for a in p.e.portadas)
    if armado:
        return True
    if _gana_al_morir(c) and hab.fuerza(p, c) < 4:
        return False
    return _valor_vivo(p, c) > 3
def _gana_al_morir(c: Instancia) -> bool:
    """Amyrteos: al salir del juego te da algo (un Oro, una carta)."""
    return any(
        h.get("cuando") == "al_salir_del_juego"
        and h.get("accion") in ("ponerEnJuego", "buscar", "robar", "generarOro")
        and (h.get("objetivo") or {}).get("quien", "propio") == "propio"
        for h in c.habilidades
    )


def _oro_defiende(c: Instancia) -> bool:
    """Oro que me defiende de un ataque: Codex Arturicus (daño a 0),
    Jeroglíficos (sube un atacante a la mano), Toro Apis (−1 a un atacante)."""
    return any(
        x.get("cuando") == "activada" and (
            x.get("accion") in ("cancelarAtaque", "reducirDano")
            or (x.get("accion") in ("subirMano", "destruir", "desterrar")
                and (x.get("objetivo") or {}).get("quien") == "oponente")
            or (x.get("accion") == "modificarFuerza" and int(x.get("valor", 0) or 0) < 0)
        )
        for x in c.habilidades
    )


def _rival_agro(p, yo) -> bool:
    """El rival me presiona en la mesa: más fuerza que yo, o 5 o más."""
    fuerza = lambda q: sum(max(0, hab.fuerza(p, a)) for a in p.j(q).aliados)  # noqa: E731
    return fuerza(1 - yo) >= 5 or fuerza(1 - yo) > fuerza(yo)


def _defensivo(c: Instancia | None) -> bool:
    """Talismán que se juega cuando te atacan (Flechas de Lava)."""
    return c is not None and c.tipo == Tipo.TALISMAN and any(
        h.get("accion") in ("cancelarAtaque", "reducirDano") or h.get("fase") == "declaracion_ataque"
        for h in c.habilidades
    )


_UMBRAL_CANCELADOR = 0.10
_UMBRAL_CANCELADOR_LETAL = 0.35


def _cancela_y_bota(carta) -> bool:
    """Flechas de Lava: cancela el ataque y luego el atacante bota."""
    return carta.tipo == Tipo.TALISMAN and any(
        h.get("accion") == "cancelarAtaque"
        and any(x.get("accion") == "botar" for x in (h.get("luego") or []))
        for h in carta.habilidades
    )


def _prob_cancelador_con_bote(p, yo) -> float:
    """Probabilidad de que el rival tenga en la mano (y pueda pagar) un
    talismán que cancela el ataque y me hace botar (según `creencias`)."""
    from . import creencias

    oro = p.j(1 - yo).oro_disponible
    if oro <= 0:
        return 0.0
    return creencias.prob_en_mano(p, yo, lambda c: _cancela_y_bota(c) and (c.coste or 0) <= oro)


def _anulador(c: Instancia | None) -> bool:
    return c is not None and c.tipo == Tipo.TALISMAN and any(h.get("accion") == "anular" for h in c.habilidades)


def _letal_conjunto(p, yo, candidatos, libres, rebaja, su_castillo) -> list:
    """Atacantes que ganan la partida ahora aunque el rival bloquee a los más
    fuertes con todos sus bloqueadores. Vacío si no hay letal."""
    atacan = [c for c in candidatos if hab.fuerza(p, c) > 0]
    if not atacan:
        return []
    bloqueables = [c for c in atacan if not hab.tiene_prop(p, c, "imbloqueable")]
    seguros = [c for c in atacan if c not in bloqueables]
    # El rival bloquea a los más fuertes que pueda; pasan los demás.
    resto = sorted(max(0, hab.fuerza(p, c) - rebaja) for c in bloqueables)
    pasan = resto[:max(0, len(resto) - len(libres))]
    dano = sum(pasan) + sum(max(0, hab.fuerza(p, c) - rebaja) for c in seguros)
    dano += sum(_bota_seguro_al_atacar(p, c) for c in atacan)
    return atacan if dano >= su_castillo else []


def _en_peligro(p, yo) -> bool:
    """El rival puede botarme el castillo atacando en su próximo turno."""
    amenaza = sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados)
    return amenaza >= len(p.j(yo).mazo)


def _oros_a_reservar(p, yo) -> int:
    """En tu Vigilia, si el rival puede atacarte fuerte y tienes un Talismán
    defensivo en la mano, guarda los Oros para pagarlo."""
    if p.e.fase != "vigilia" or p.e.activo != yo:
        return 0
    rival = p.j(1 - yo)
    amenaza = sum(max(0, hab.fuerza(p, a)) for a in rival.aliados)
    if amenaza < 4 and len(p.j(yo).mazo) > amenaza:
        return 0
    costes = [p.coste_de(yo, c) for c in p.j(yo).mano if _defensivo(c)]
    costes = [c for c in costes if c <= p.j(yo).oro_disponible]
    return max(costes, default=0)


def _cancelador_revelado(p, quien: int) -> Instancia | None:
    """Talismán que cancela ataques (Flechas de Lava) que `quien` tiene a la
    vista en la mano (lo buscó) y puede pagar."""
    for c in p.j(quien).mano:
        if getattr(c, "revelada", False) and _defensivo(c) and p.coste_de(quien, c) <= p.j(quien).oro_disponible:
            return c
    return None


def _anuladores(p, yo, objetivo: Instancia | None = None) -> list:
    return [
        c for c in p.j(yo).mano
        if c.tipo == Tipo.TALISMAN and any(
            h.get("accion") == "anular" and (objetivo is None or hab.coincide(p, objetivo, h.get("objetivo") or {}))
            for h in c.habilidades
        )
    ]


def _puedo_anular(p, yo) -> bool:
    """¿Tengo con qué anular el cancelador revelado del rival (Gran Guardián)?"""
    amenaza = _cancelador_revelado(p, 1 - yo)
    return any(p.coste_de(yo, c) <= p.j(yo).oro_disponible for c in _anuladores(p, yo, amenaza))


def _reserva_para_responder(p, yo) -> int:
    """#51: con Resplandor de Heka en la mano, guardo sus Oros para el
    turno del rival en vez de gastarlos en algo flojo."""
    if p.e.fase != "vigilia" or p.e.activo != yo:
        return 0
    costes = [
        p.coste_de(yo, c) for c in p.j(yo).mano
        if c.tipo == Tipo.TALISMAN and any(
            h.get("cuando") == "oponente_juega" and h.get("accion") not in ("anular", "redirigir", "otra")
            for h in c.habilidades
        )
    ]
    costes = [c for c in costes if c <= p.j(yo).oro_disponible]
    return max(costes, default=0)


def _reserva_para_anular(p, yo) -> int:
    """#55: si el rival tiene en la mano una amenaza revelada (buscó a Ramsés
    II) y yo tengo con qué anularla (Abismo), guardo los Oros para eso."""
    if p.e.fase != "vigilia" or p.e.activo != yo:
        return 0
    amenaza = any(getattr(c, "revelada", False) and c.carta.coste >= 4 for c in p.j(1 - yo).mano)
    # #121: también si voy a atacar y el rival tiene a la vista Flechas de Lava.
    atacare = any(a.listo for a in p.j(yo).aliados)
    if not amenaza and not (atacare and _cancelador_revelado(p, 1 - yo)):
        return 0
    costes = [
        p.coste_de(yo, c) for c in p.j(yo).mano
        if c.tipo == Tipo.TALISMAN and any(h.get("accion") == "anular" for h in c.habilidades)
    ]
    costes = [c for c in costes if c <= p.j(yo).oro_disponible]
    return max(costes, default=0)


def _oros_que_gasta(p, yo, j) -> int:
    if j.tipo == "activar":
        h = j.carta.habilidades[j.habilidad]
        c = h.get("costo") or {}
        return int(c.get("oros", 0)) + (1 if c.get("pagarEstaCarta") else 0)
    if j.tipo in ("jugar",):
        return p.coste_de(yo, j.carta)
    return 0


def _remocion_que_se_sacrifica_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Perseo: un Aliado que se sacrifica para sacar una carta rival solo lo
    hace si esa carta vale más que él (Haquika sí; Kawit no)."""
    costo = h.get("costo") or {}
    if fuente.tipo != Tipo.ALIADO or not (costo.get("destruirEstaCarta") or costo.get("desterrarEstaCarta")):
        return True
    if h.get("accion") not in ("destruir", "desterrar", "barajar", "subirMano", "mover") \
            or (h.get("objetivo") or {}).get("quien") != "oponente":
        return True
    cands = hab.candidatos_validos(p, yo, fuente, h)
    return any(_impacto_quitar(p, yo, t) + (_valor_vivo(p, t) if t.en_juego else 0) >= _valor_vivo(p, fuente)
               for t in cands)


def _valor_robo_al_jugar(p, yo, inst: Instancia) -> float:
    """Nacimiento de Pegaso: robar al jugarse vale más con la mano corta."""
    n = 0
    for h in inst.habilidades:
        if h.get("cuando") not in ("al_jugar", None):
            continue
        for e in [h] + [x for x in h.get("luego") or [] if isinstance(x, dict)]:
            if e.get("accion") == "robar" and (e.get("objetivo") or {}).get("quien", "propio") == "propio":
                n += int(e.get("cantidad", 1) or 1)
    if inst.tipo == Tipo.ALIADO:
        return 0.0  # un Aliado ya vale por su cuerpo (Djedefhor)
    return n * (3.0 if len(p.j(yo).mano) <= 3 else 1.2)


def _recupero_al_quitar(p, yo, t: Instancia) -> float:
    """Haquika tiene robado un Aliado mío: si sale del juego, vuelve a mí (el
    rival lo pierde y yo lo gano: cuenta doble)."""
    return sum(3.0 * _valor_vivo(p, x) for x in p.e.instancias_en_juego(1 - yo)
               if x.control and x.control.get("fuente") == t.uid and x.control.get("original") == yo)


def _valor_remocion_activada(p, yo, fuente: Instancia, h: dict) -> float:
    """I4Sl2 #2/#4: una remoción activada (Tártaro) vale lo que saca, como la
    de una carta al entrar (antes, un 3 fijo): desterrar a Haquika además me
    devuelve el Aliado que me robó."""
    obj = h.get("objetivo") or {}
    if h.get("accion") not in _REMOCION or obj.get("quien") not in ("oponente", "cualquiera"):
        return 0.0
    if "en_juego" not in hab.zonas_de(obj):
        return 0.0
    cands = [c for c in hab.candidatos_validos(p, yo, fuente, h) if c.controlador != yo]
    vuelve = h.get("accion") == "subirMano" or (
        h.get("accion") == "mover" and h.get("zonaDestino") in ("mazo_tope", "mano"))
    mejor = 0.0
    for c in cands:
        v = (1.5 * (0.5 if vuelve else 1.0) * _valor_vivo(p, c)
             + sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == c.uid)
             + _recupero_al_quitar(p, yo, c) - (6 if _gana_al_morir(c) else 0)
             # Indestructible (Haquika): desterrarlo es la única respuesta.
             + (4.0 if h.get("accion") != "destruir" and hab.tiene_prop(p, c, "indestructible") else 0))
        mejor = max(mejor, v)
    oros = int((h.get("costo") or {}).get("oros", 0) or 0)
    return mejor - 0.5 * oros if mejor else 0.0


def _valor_remocion_al_entrar(p, yo, inst: Instancia) -> float:
    """Nephre-Ka: lo que vale la mejor carta rival que saca al entrar."""
    mejor = 0.0
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        # #80: Neferite I destierra activándola en el mismo turno, sin pagar Oros.
        # Qer-Her no: para usarla se destruye a sí misma, no es "al entrar".
        costo = h.get("costo") or {}
        activada_ya = h.get("cuando") == "activada" and not costo.get("oros")             and not costo.get("destruirEstaCarta") and not costo.get("desterrarEstaCarta")
        if (h.get("cuando") != "al_jugar" and not activada_ya) or h.get("accion") not in _REMOCION \
                or obj.get("quien") not in ("oponente", "cualquiera"):
            continue
        coste_obj = obj.get("coste") or {}
        if (h.get("cuando") == "al_jugar" and inst.tipo == Tipo.ALIADO and not inst.en_juego
                and coste_obj.get("segun") in ("aliados_raza", "aliados_arquetipo")):  # Artabano se cuenta
            # La habilidad se resuelve después de entrar: el propio Aliado cuenta.
            zona = inst.zona
            try:
                inst.zona = Zona.DEFENSA
                p.j(yo).defensa.append(inst)
                cands = hab.candidatos_validos(p, yo, inst, h)
            finally:
                p.j(yo).defensa.remove(inst)
                inst.zona = zona
        else:
            cands = hab.candidatos_validos(p, yo, inst, h)
        if obj.get("quien") == "cualquiera":
            cands = [c for c in cands if c.controlador != yo]  # #5 0VzQ: Abismo y Akhet del rival
        if (h.get("costo") or {}).get("desterrarCementerioSegun") == "coste_objetivo":
            tope = len(p.j(yo).cementerio)
            cands = [c for c in cands if c.tipo != Tipo.ORO and c.carta.coste <= tope]
        # Robarlo (Haquika) vale más que sacarlo: además lo uso yo.
        if h.get("accion") == "ganarControl":
            valor = max([0.0] + [1.5 * _valor_vivo(p, c) for c in cands])
        else:
            # #35: lo que sigue aportando en la mesa (Nephre-Ka ya usó su
            # habilidad: sacarlo vale poco); #121: con sus Armas; #22: sacar a
            # Amyrteos le regala un Oro al rival.
            def libera(c):  # #63: sacar a Cleopatra devuelve las habilidades a los míos
                if any(x.get("accion") == "perderHabilidad" and x.get("duracion") == "mientras_en_juego"
                       for x in c.habilidades):
                    return 1.5 * sum(1 for a in p.j(yo).aliados if a.sin_habilidad_hasta is not None)
                return 0.0

            # tuK8 #2: al tope del Mazo (Focea) o a la Mano solo lo retrasa:
            # el rival lo vuelve a jugar y repite su "al entrar" (Yvain busca
            # otra Espada). Las Armas que porta sí se pierden.
            vuelve = h.get("accion") == "subirMano" or (
                h.get("accion") == "mover" and h.get("zonaDestino") in ("mazo_tope", "mano"))
            valor = max([0.0] + [
                1.5 * ((0.5 if vuelve else 1.0) * _valor_vivo(p, c)
                       + sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == c.uid))
                - (3 if vuelve and any(x.get("cuando") == "al_jugar" for x in c.habilidades) else 0)
                - (6 if _gana_al_morir(c) else 0) + libera(c)
                for c in cands
            ])
        # #18: si el rival tiene en la mano una amenaza revelada (buscó a
        # Ramsés II) bastante peor que lo que hay ahora, conviene guardarla.
        amenaza = max(
            [0.0] + [1.5 * _valor_vivo(p, c) for c in p.j(1 - yo).mano
                     if getattr(c, "revelada", False) and _tipo_ok(c, h)]
        )
        if amenaza >= valor + 4:
            valor = -amenaza / 2
        mejor = valor if mejor == 0.0 else max(mejor, valor)
    return mejor


def _motor_con_combustible(p, t: Instancia) -> bool:
    """Nuh solo amenaza si le quedan Armas que traer (Mazo o Cementerio)."""
    for h in t.habilidades:
        if h.get("cuando") != "activada" or h.get("accion") not in ("jugarDesde", "buscar", "ponerEnJuego"):
            continue
        obj = h.get("objetivo") or {}
        zonas = [z for z in hab.zonas_de(obj, "mazo") if z in ("mazo", "cementerio", "mano", "destierro")]
        jug = p.j(t.controlador)
        lista = {"mazo": jug.mazo, "cementerio": jug.cementerio, "mano": jug.mano, "destierro": jug.destierro}
        if any(hab.coincide(p, c, obj) for z in zonas for c in lista[z]):
            return True
    return not any(h.get("accion") in ("jugarDesde", "buscar", "ponerEnJuego") for h in t.habilidades)


def _necesito_robar(p, yo, fuente: Instancia) -> bool:
    """¿Me hacen falta cartas ahora? Poca mano, o nada que jugar con lo que
    tengo (ni un Oro para el próximo turno)."""
    mano = [c for c in p.j(yo).mano if c is not fuente]
    if len(mano) <= 2:
        return True
    jugable = any(c.tipo != Tipo.ORO and p.puede_pagar(yo, c) for c in mano)
    oro = any(c.tipo == Tipo.ORO for c in mano)
    return not jugable and not oro


def _sacrificio_de_aliados_conviene(p, yo, fuente: Instancia, h: dict) -> bool:
    """Ay: desterrar un Aliado propio para robar solo si el que se va vale
    menos que lo que se gana (y no es uno con efecto mientras está en juego,
    como Cleopatra VII)."""
    c = h.get("costo") or {}
    n = int(c.get("desterrarAliados", 0)) + int(c.get("destruirAliados", 0))
    if not n:
        return True
    otros = [a for a in p.j(yo).aliados if a is not fuente]
    if len(otros) < n:
        return False
    if h.get("accion") == "robar" and not _necesito_robar(p, yo, fuente):
        return False  # #1 0VzQ: con jugadas en la mano, desterrar un Aliado (que sigue pegando) sobra
    for a in sorted(otros, key=lambda x: _valor_carta(p, x))[:n]:
        if _pieza_clave(a):
            return False  # Neferite (aunque Resplandor la dejara sin habilidad) no se paga por robar
        if any((x.get("duracion") == "mientras_en_juego" or x.get("cuando") == "continua")
               and x.get("accion") not in hab.PROPIEDADES for x in a.habilidades):
            return False
        ganancia = 2.5 * int(h.get("cantidad", 1)) + 1 if h.get("accion") == "robar" else 4.0
        if _valor_carta(p, a) > ganancia:
            return False
    return True


class Heuristico:
    """Reglas de prioridad simples: juega lo más caro que pueda, ataca cuando
    no pierde el intercambio y bloquea para salvar castillo o ganar cartas."""

    nombre = "heuristico"

    def __init__(self, seed: int | None = None):
        self.rng = random.Random(seed)

    # Mulligan: ≥ 2 Oros y algo útil en el turno 1 (un Aliado o Tótem barato,
    # o una respuesta para la jugada del rival). Un Talismán que en el turno 1
    # no tendría a qué afectar (Luz del Saber sin Cementerio) no cuenta.
    def quedarse_mano(self, p, yo):
        mano = p.j(yo).mano
        if len(mano) <= 6:
            return True  # bajar a 5 cuesta más que una mano floja
        # smWj #2: dos Dragones (Errante: solo uno en juego) cuentan como 1 Oro.
        errantes = set()
        oros = 0
        for c in mano:
            if c.tipo != Tipo.ORO:
                continue
            if hab.tiene_prop(p, c, "errante"):
                if c.nombre in errantes:
                    continue
                errantes.add(c.nombre)
            oros += 1
        # Un acelerador que pago en el turno 1 con el Oro inicial cuenta como
        # otro Oro: Kawit busca uno; Amyrteos con Ay en la mano, al desterrarse,
        # pone uno en juego (así me mantengo en curva).
        if any(
            c.tipo == Tipo.ALIADO and c.carta.coste <= 1 + oros and (
                any(h.get("accion") == "buscar" and "Oro" in ((h.get("objetivo") or {}).get("tipos") or [])
                    for h in c.habilidades if h.get("cuando") in ("al_jugar", None))
                or (_gana_al_morir(c) and any(_es_salida(x) for x in mano if x is not c))
            )
            for c in mano
        ):
            oros += 1
        if len(mano) == 7:
            return oros >= 2 and any(c.tipo != Tipo.ORO and c.carta.coste <= 3 for c in mano)
        if _mazo_lento(p, yo) and _MULLIGAN_LENTO_V2:
            # Dragón: casi todo cuesta 3 o más; el turno 1 no importa. Bastan 2
            # Oros y algo que hacer: Vínculo (roba), una respuesta (Capa,
            # Toque, Fe, Bola, Desleal) o algo barato que bajar. Jugando primero
            # hace falta algo que bajar temprano; segundo, las respuestas bastan.
            if not 2 <= oros <= 5:
                return False
            vinculo = any(_vinculo(h) for c in mano for h in c.habilidades)
            baratas = any(c.tipo in (Tipo.ALIADO, Tipo.TOTEM) and c.carta.coste <= 3 for c in mano)
            respuesta = any(c.tipo == Tipo.TALISMAN and c.carta.coste <= 3 and (
                _defensivo(c) or _anulador(c) or any(
                    h.get("cuando") == "oponente_juega" or (
                        h.get("accion") in _REMOCION | {"barajar"}
                        and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera", "disparadora"))
                    for h in c.habilidades)) for c in mano)
            primero = p.e.activo == yo
            return vinculo or baratas or (respuesta and not primero) or (respuesta and oros >= 3)
        if _mazo_lento(p, yo) and 3 <= oros <= 5 and any(
            c.tipo in (Tipo.ALIADO, Tipo.TOTEM) and c.carta.coste <= 3 for c in mano
        ):
            # Dragón: mazo de control con muchas cartas caras. Con 3 a 5 Oros y
            # algo que bajar temprano se queda; un mulligan le cuesta más que a un agro.
            return True
        # #2: 3 Oros y al menos 2 cartas para bajar a la mesa en los turnos 2-3
        # (Akhet, Haquika, Nuh) sirve; #1: con un solo Aliado (Pili) y el resto
        # situacional (Luz del Saber, Flechas, el Mandoble), no.
        baratas = sum(1 for c in mano if c.tipo in (Tipo.ALIADO, Tipo.TOTEM) and c.carta.coste <= 3)
        return (oros >= 2 and any(_util_en_turno_1(c) for c in mano)) or (3 <= oros <= 5 and baratas >= 2)

    def elegir_jugada(self, p, yo, jugadas):
        jugadas = [
            j for j in jugadas
            if not (j.tipo == "jugar" and j.carta.tipo != Tipo.ORO and _se_bota_de_mas(p, yo, j.carta, "al_jugar"))
            and not (j.tipo == "jugar" and _sin_objetivo_al_entrar(p, yo, j.carta))
            and not (j.tipo == "jugar" and _sacrificio_sin_combo(p, yo, j.carta))
        ]  # Kamose con el castillo corto me manda al Cementerio a mí también
        if p.e.fase == "guerra_talismanes" and p.e.activo != yo:
            # Lanza Divina: "una vez por turno" también vale en la Guerra del
            # turno rival; gratis y bota 2: se usa siempre.
            for j in jugadas:
                h = j.carta.habilidades[j.habilidad] if j.tipo == "activar" else {}
                if h.get("accion") == "botar" and (h.get("objetivo") or {}).get("quien") == "oponente" \
                        and hab._costo_gratis(h) and int(h.get("limitePorTurno", 0) or 0) >= 1:
                    return j
        oros = [j for j in jugadas if j.tipo == "oro"]
        if oros:
            # Primero los Oros con habilidad (dan algo mientras están en reserva);
            # #40: con la mano corta, el que roba (Biblioteca Eterna).
            corta = len(p.j(yo).mano) <= 3
            # Con 6+ Oros y sobrando para lo que tengo, la Biblioteca se baja y
            # se cambia ya por 2 cartas (busco Armas en vez de otro Oro).
            en_juego = len(p.j(yo).reserva) + len(p.j(yo).pagado)
            sobran = en_juego + 1 >= 6 and _por_gastar(p, yo) <= p.j(yo).oro_disponible

            def valor_oro(j):
                if getattr(self, "oro_etb", _ORO_ETB_INUTIL) and len({x.carta.nombre for x in oros}) > 1 \
                        and _entrada_de_oro_inutil(p, yo, j.carta):
                    return -5  # su "al entrar" no hace nada hoy: se guarda para cuando sirva
                roba = any(h.get("accion") == "robar" for h in j.carta.habilidades)
                generador = max(
                    [0] + [int(h.get("valor", 0) or 0) for h in j.carta.habilidades
                           if h.get("accion") == "generarOro"]
                )
                def puede_pagar_con_generador(carta):
                    return any(
                        h.get("accion") == "generarOro"
                        and (not (h.get("soloParaTipos") or [])
                             or carta.tipo.value in (h.get("soloParaTipos") or []))
                        and (not h.get("soloParaRaza")
                             or h.get("soloParaRaza") in (carta.raza or ""))
                        and carta.carta.coste >= int(h.get("soloParaCosteMin", 0) or 0)
                        for h in j.carta.habilidades
                    )
                if generador and any(
                    c.tipo != Tipo.ORO and c.carta.coste >= 4
                    and puede_pagar_con_generador(c)
                    and p.coste_de(yo, c) <= p.j(yo).oro_disponible + generador
                    for c in p.j(yo).mano
                ):
                    # Dragones: genera justo los recursos para bajar el
                    # Aliado caro (por ejemplo Killgharrah) este mismo turno.
                    return 90
                if _ESTRELLA_BUSCA and _busca_oro_defensivo(p, yo, j.carta):
                    return 95  # Héctor 19965 T6: Estrella primero, a ver si sale el Codex
                if any(_vinculo(h) for h in j.carta.habilidades) and p.j(yo).oro_disponible >= 1:
                    # Vínculo transforma el Oro en recursos este mismo turno;
                    # se juega antes que un Oro reactivo como Carnwennan.
                    return 75
                if en_juego <= 2 and any(_vinculo(h) for h in j.carta.habilidades)                         and p.j(yo).oro_disponible >= 1:
                    return 100  # turno 1: Vínculo del Aullido se juega y se activa
                if any(h.get("accion") == "restriccion" and h.get("modo") == "desterrar_cementerio"
                       for h in j.carta.habilidades) and _cementerio_rival_sirve(p, yo) and not any(
                           any(h.get("modo") == "desterrar_cementerio" for h in x.habilidades)
                           for x in p.j(yo).reserva):
                    # Cinturón de Lady Ann contra el Faraón: en la Reserva frena
                    # Jinetes desde el Cementerio, Nephre-Ka, Neferite y Merodeador.
                    # No hace falta el primero: en los turnos medios, cuando su
                    # Cementerio ya tiene con qué.
                    return 80
                if any(h.get("accion") == "perderHabilidad" and h.get("cuando") == "activada"
                       and any(_pieza_clave(t) and t.controlador != yo
                               for t in hab.candidatos_validos(p, yo, j.carta, h))
                       for h in j.carta.habilidades):
                    return 85  # ZsfY #5: el Diente de la Bestia para el Apophis
                if not sobran and _corona_sirve_ya(p, yo, j.carta):
                    return 50  # #2 ZOlJ: la Corona primero, lo antes posible (T10: con Oros de sobra, Biblioteca)
                # La Ilíada: el Oro que bonifica cada turno va primero.
                repetible = sum(1 for h in j.carta.habilidades if _habilidad_repetible(h)
                                and int(h.get("limitePorTurno", 0) or 0) >= 1)
                return len(j.carta.habilidades) + (3 if roba and (corta or sobran) else 0) + 3 * repetible \
                    + _bonus_oro_entrada(p, yo, j.carta)

            return max(oros, key=valor_oro)
        restos = [r for r in p.j(yo).oros_restringidos if r[0] > 0]
        if _USAR_GENERADOS and restos and p.e.fase == "vigilia":
            # Oros generados (Dragones) que solo pagan ciertas cartas: se
            # pierden en la Fase Final. Se usan en la carta más cara que pagan.
            usa = [j for j in jugadas if j.tipo == "jugar" and j.carta.tipo != Tipo.ORO
                   and any(hab.paga_restringido(j.carta, r) for r in restos)]
            if usa:
                return max(usa, key=lambda j: (p.coste_de(yo, j.carta), _valor_carta(p, j.carta)))
        roba = [
            j for j in jugadas
            if j.tipo == "activar" and j.carta.habilidades[j.habilidad].get("accion") == "robar"
            and not (j.carta.habilidades[j.habilidad].get("costo") or {}).get("oros")
            and self._vale_la_pena(p, yo, j)
        ]
        if roba:
            # #71: robar primero y después decidir. Antes el robo que no cuesta
            # un Oro (Akhet) que la Biblioteca Eterna: con lo robado quizás ya
            # no hace falta desterrarla.
            return min(roba, key=lambda j: j.carta.tipo == Tipo.ORO)
        generadores = [
            j for j in jugadas
            if j.tipo == "activar" and j.carta.habilidades[j.habilidad].get("accion") == "generarOro"
            and any(
                c.tipo == Tipo.ALIADO
                and c.carta.coste >= int(j.carta.habilidades[j.habilidad].get("soloParaCosteMin", 0) or 0)
                # smWj #1: Dragones se paga a sí mismo: 2 Oros (uno Dragones) dan 3, no 4.
                and p.coste_de(yo, c) <= p.j(yo).oro_disponible + int(
                    j.carta.habilidades[j.habilidad].get("valor", 0) or 0
                ) - (1 if (j.carta.habilidades[j.habilidad].get("costo") or {}).get("pagarEstaCarta") else 0)
                for c in p.j(yo).mano
            )
            and self._vale_la_pena(p, yo, j)
        ]
        if generadores:
            return generadores[0]
        letal = [
            j for j in jugadas
            if j.tipo != "pasar" and _es_letal(p, yo, j) and _me_bota(p, yo, j) < len(p.j(yo).mazo)
        ]  # Grandes Faraones con 1 y 1: me boto yo primero
        if letal:
            return letal[0]  # #155: Papiros de Lahun bota 3 y gana; nada más importa
        remate = _remate(p, yo, jugadas)
        if remate is not None:
            return remate  # #131: Jinetes de Fuego + Papiros de Lahun
        for j in jugadas:
            # #122: Ramsés II con Furia gana atacando, lo bloqueen o no.
            if (
                j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO and hab.tiene_prop(p, j.carta, "furia")
                and _letal_al_atacar(p, yo, j.carta) and not _cancelador_revelado(p, 1 - yo)
            ):
                return j
        mejores = [j for j in jugadas if j.tipo != "pasar" and self._vale_la_pena(p, yo, j)]
        if p.e.fase == "guerra_talismanes" and p.e.activo != yo and len(p.atacantes) >= 2:
            # i4b3 #1: Bola de Fuego a uno y Toque de Pérsival al otro limpian
            # la mesa; el Desleal solo saca a uno. Primero la más barata si
            # alcanza para dos.
            remos = sorted([j for j in mejores if j.tipo == "jugar" and j.carta.tipo == Tipo.TALISMAN
                            and any(h.get("accion") in _REMOCION | {"barajar"}
                                    and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
                                    for h in j.carta.habilidades)],
                           key=lambda j: p.coste_de(yo, j.carta))
            if len(remos) >= 2 and p.coste_de(yo, remos[0].carta) + p.coste_de(yo, remos[1].carta) \
                    <= p.j(yo).oro_disponible:
                return remos[0]
        habilitador = self._habilita_remocion_por_raza(p, yo, mejores)
        if habilitador is not None:
            return habilitador  # FtbJ #3: Rey Minos antes que Ganimedes (mata a Sir Gaheris)
        restringidos = [r for r in p.j(yo).oros_restringidos if r[0] > 0]
        if restringidos:
            # m8ii #4: ya generé con Dragones: primero lo que usa esos Oros
            # (el Dragón de coste 4+), antes que gastar los normales en otra cosa.
            usan = [j for j in mejores if j.tipo == "jugar" and j.carta.tipo != Tipo.ORO
                    and any(hab.paga_restringido(j.carta, r) for r in restringidos)]
            if usan:
                return max(usan, key=lambda j: self._puntaje(p, yo, j))
        # #4 c0p0: Alquimista primero si después igual alcanza para lo demás:
        # el Oro que trae entra a la Reserva y se usa este mismo turno.
        for r in mejores:
            if (r.tipo == "jugar" and r.carta.tipo == Tipo.TALISMAN
                    and _ramp_de_oro(r.carta) and _ramp_temprano(p, yo)
                    and not _combo_draig_lady_listo(p, yo)):
                quedan = p.j(yo).oro_disponible - p.coste_de(yo, r.carta) + 1
                if any(j is not r and j.tipo == "jugar" and j.carta.tipo != Tipo.ORO
                       and p.coste_de(yo, j.carta) <= quedan for j in mejores):
                    return r
        reactiva = _reserva_reactiva(p, yo) if _RESERVA_REACTIVA else 0
        reserva = _oros_a_reservar(p, yo) + _reserva_para_anular(p, yo) + _reserva_para_responder(p, yo)
        reserva = min(max(reserva, reactiva), p.j(yo).oro_disponible)
        # Con la mesa vacía y el castillo sano, primero me desarrollo: no paso
        # turnos enteros solo para tener Flechas de Lava y Resplandor listos.
        desarrollar = not p.j(yo).aliados and len(p.j(yo).mazo) > 15 and not reactiva
        if reserva:
            # #90: guarda Oros para Flechas de Lava si el rival amenaza.
            # qSMg #1: guardando para Toque + Bola, solo algo excelente los gasta.
            umbral = 20 if reactiva else 12

            def remocion_talisman(j):
                return j.tipo == "jugar" and j.carta.tipo == Tipo.TALISMAN and any(
                    h.get("accion") in _REMOCION for h in j.carta.habilidades)

            def cabe_con_lo_reservado(j):
                # i4b3 #2 / 1uF1 #1: la Bola (2) se usa ya si deja 1 para el Toque;
                # el Desleal (3) no, porque se lleva lo de Toque + Bola.
                # UBsS #1: si el rival va a atacar con 2 o más (tiene la Corona),
                # todo se guarda para su Guerra de Talismanes.
                if _atacantes_esperados(p, yo) >= 2:
                    return False
                sin_esta = _reserva_reactiva(p, yo, salvo=j.carta)
                return _oros_que_gasta(p, yo, j) + sin_esta <= p.j(yo).oro_disponible

            mejores = [
                j for j in mejores
                if _defensivo(j.carta) or _anulador(j.carta)
                or (desarrollar and j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO and self._puntaje(p, yo, j) >= 6.5)
                or _oros_que_gasta(p, yo, j) <= p.j(yo).oro_disponible - reserva
                or (reactiva and remocion_talisman(j) and cabe_con_lo_reservado(j))
                # UBsS #3: Lady que destierra a 2 Guerreros vale más que guardar.
                or (j.tipo == "jugar" and _saca_varios(p, yo, j.carta))
                # 1uF1 #2: Alquimista acerca a La Llama Fría y a Lady: no se frena.
                or (reactiva and j.tipo == "jugar" and _ramp_de_oro(j.carta) and _juntando_oros(p, yo))
                or (self._puntaje(p, yo, j) >= umbral and not (reactiva and remocion_talisman(j)))
            ]
        if getattr(self, "gestion_mano", _GESTION_MANO) and mejores:
            mejores = [j for j in mejores if not self._guardar_para_la_mano(p, yo, j)]
        if not mejores:
            return next(j for j in jugadas if j.tipo == "pasar")
        return max(mejores, key=lambda j: self._puntaje(p, yo, j) + _bonus_carnada(p, yo, j))

    def _guardar_para_la_mano(self, p, yo, j) -> bool:
        """Gestión de mano: en mi Vigilia, un Aliado/Tótem/Arma que me deja con
        menos de `_MANO_MIN` cartas se guarda si la mesa ya está bien (tengo
        al menos 2 Aliados y no menos que el rival), no estoy en peligro, el
        rival no está por caer y la jugada no es excelente ni roba cartas."""
        if j.tipo != "jugar" or j.carta is None or p.e.fase != "vigilia" or p.e.activo != yo:
            return False
        c = j.carta
        if c.tipo not in (Tipo.ALIADO, Tipo.TOTEM, Tipo.ARMA) or c.zona != Zona.MANO:
            return False
        mio, suyo = p.j(yo), p.j(1 - yo)
        minimo = getattr(self, "mano_min", _MANO_MIN)
        if len(mio.mano) - 1 >= minimo:
            return False
        if len(mio.aliados) < max(getattr(self, "mano_mesa_min", _MANO_MESA_MIN), len(suyo.aliados)) \
                or _en_peligro(p, yo):
            return False
        fuerza = sum(max(0, hab.fuerza(p, a)) for a in mio.aliados)
        if len(suyo.mazo) <= 2 * fuerza:
            return False  # cerrando la partida: la presión vale más que la mano
        if _roba(c) or _pieza_clave(c):
            return False
        return self._puntaje(p, yo, j) < getattr(self, "mano_umbral", _MANO_UMBRAL)

    def _habilita_remocion_por_raza(self, p, yo, mejores):
        """FtbJ #3: Ganimedes destruye una carta de coste ≤ mis Héroes. Si con un
        Héroe más (Rey Minos) alcanza un objetivo que si no, no, y me alcanzan
        los Oros para los dos, primero bajo al que habilita."""
        if any(j.tipo == "activar" and j.carta.habilidades[j.habilidad].get("accion") == "mirarTope"
               and j.carta.habilidades[j.habilidad].get("zonaDestino") == "en_juego" for j in mejores):
            return None  # FtbJ #1: Idmon va antes que todo
        jugar = [j for j in mejores if j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO and not j.carta.en_juego]
        for k in jugar:
            for h in k.carta.habilidades:
                cmp = ((h.get("objetivo") or {}).get("coste") or {})
                if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in _REMOCION \
                        or cmp.get("segun") != "aliados_raza":
                    continue
                raza = cmp.get("raza") or ""
                ahora = sum(1 for a in p.j(yo).aliados if raza in (a.raza or "")) + 1  # cuenta a sí mismo
                rivales = [t for t in p.e.instancias_en_juego(1 - yo) if t.tipo != Tipo.ORO]

                def valor(t):
                    return _peligro(p, t) + t.carta.coste if t.tipo == Tipo.ALIADO else _valor_carta(p, t)

                mejor_ahora = max([valor(t) for t in rivales if t.carta.coste <= ahora], default=0)
                mejor_mas = max([valor(t) for t in rivales if t.carta.coste <= ahora + 1], default=0)
                if mejor_mas <= mejor_ahora:
                    continue  # un Héroe más no le da un objetivo mejor (la Espada ya alcanza)
                for e in sorted(jugar, key=lambda x: p.coste_de(yo, x.carta)):
                    if e is k or raza not in (e.carta.raza or ""):
                        continue
                    if p.coste_de(yo, e.carta) + p.coste_de(yo, k.carta) <= p.j(yo).oro_disponible:
                        return e
        return None

    def _vale_la_pena(self, p, yo, j) -> bool:
        if j.tipo == "activar":
            h = j.carta.habilidades[j.habilidad]
            if h.get("accion") == "barajar" and (h.get("objetivo") or {}).get("quien") == "propio" \
                    and "cementerio" in hab.zonas_de(h.get("objetivo") or {}) \
                    and (h.get("costo") or {}).get("desterrarEstaCarta"):
                # Milano Rojo: no se pierde para barajar dos cartas cuando la
                # mesa rival no amenaza. Se reserva como extensión de castillo.
                return _en_peligro(p, yo) or len(p.j(yo).mazo) <= 8
            if _cultista(h):
                return _cultista_tiene_mano(p, yo)
            if (h.get("objetivo") or {}).get("nombrarCarta") and _nombra_en_mazo_rival(j.carta):
                # FtbJ #6: Orfeo se usa en mi turno y en la Guerra cuando me atacan.
                return any(v[0] > 0 for v in _copias_posibles_en_mazo(p, yo).values())
            if j.carta.nombre.casefold() == "jeroglificos" and h.get("accion") == "subirMano" \
                    and p.atacantes:
                # Si puedo intercambiar bloqueando al atacante, no gasto el
                # JeroglÃ­fico: con rival de mano corta vale mÃ¡s reciclar una
                # carta propia que devolverle el Aliado a la mano.
                for atacante in p.atacantes:
                    if any(hab.fuerza(p, b) == hab.fuerza(p, atacante)
                           for b in p.j(yo).defensa):
                        return False
            if h.get("accion") == "jugarDesde" and (h.get("costo") or {}).get("desterrarEstaCarta") and any(
                e.get("momento") == "fase_final" and e.get("accion") == "desterrar" for e in h.get("luego") or []
            ) and (any(r.zona == Zona.MANO for r in _remociones_a_mano(p, yo))
                   or not any(_amenaza_en_mesa(p, a) for a in p.j(1 - yo).aliados)):
                # #4 UUOX: el Aliado traído se destierra en la Fase Final: no se gasta
                # para sacar un Nephre-Ka de 2 que ya no hace nada, ni si el Magma de la mano alcanza.
                return False
            if h.get("accion") == "convertirEnAliado":
                return _bloquearia_con(p, yo, int(h.get("valor", 0) or 0))  # #3 d8bV: Mercaderes
            if _CARNWENNAN_TURNO and h.get("accion") == "perderHabilidad" and j.carta.tipo == Tipo.ORO \
                    and h.get("duracion") == "hasta_fase_final" and p.e.activo == yo:
                # Héctor 2026-11-12: Carnwennan dura hasta MI Fase Final. En mi
                # Vigilia, quitarle la habilidad al Demoledor no sirve: ataca en
                # el turno del rival. En mi turno solo vale contra un defensor
                # que frenaría mi ataque (indestructible, aura, Arma en defensa).
                objs = [t for t in hab.candidatos_validos(p, yo, j.carta, h) if t.controlador != yo]
                mios = [a for a in p.j(yo).aliados if _puede_atacar(p, a) and hab.fuerza(p, a) > 0]
                def frena_mi_ataque(t):
                    if t.tipo == Tipo.ARMA:
                        portador = next((a for a in p.j(1 - yo).aliados if a.uid == t.portador), None)
                        return portador is not None and portador.zona == Zona.DEFENSA and any(
                            x.get("cuando") == "continua" and x.get("accion") == "modificarFuerza" for x in t.habilidades)
                    if any(x.get("accion") == "ganarControl" for x in t.habilidades):
                        return False  # Haquika: sin habilidad, si muere no devuelve lo robado
                    return t.tipo == Tipo.ALIADO and t.zona == Zona.DEFENSA and (
                        hab.tiene_prop(p, t, "indestructible") or any(
                            x.get("cuando") in ("al_bloquear", "al_ser_bloqueado") or (
                                x.get("cuando") == "continua" and x.get("accion") == "modificarFuerza")
                            for x in t.habilidades))
                # Demoledor encarece mis Talismanes en 2: sin habilidad, la Bola
                # le cuesta 2 este turno (Carnwennan + Bola en el mismo turno).
                quedan = p.j(yo).oro_disponible - (1 if j.carta in p.j(yo).reserva else 0)
                abarata = [t for t in objs if any(x.get("accion") == "encarecer" for x in t.habilidades) and any(
                    c.tipo == Tipo.TALISMAN and _remocion_al_entrar(c) and c.carta.coste <= quedan
                    and p.coste_de(yo, c) > quedan for c in p.j(yo).mano)]
                # Héctor: Carnwennan apaga lo continuo y lo que el rival usaría
                # en mi turno: Qer-Her que se destruye para subirme un Aliado,
                # Werin que va a salir (no busca Talismán), Marco Antonio que no
                # me deja jugar Talismanes.
                grandes = [c for c in list(p.j(yo).aliados) + [x for x in p.j(yo).mano if p.puede_pagar(yo, x)]
                           if c.tipo == Tipo.ALIADO and c.carta.coste >= 5]

                def me_saca_algo(t):
                    return t.tipo == Tipo.ALIADO and grandes and any(
                        x.get("cuando") == "activada" and x.get("accion") in (_REMOCION | {"subirMano"})
                        and (x.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
                        and hab.puede_pagar_costo(p, 1 - yo, t, x) for x in t.habilidades)

                def lo_saco_ya(t):
                    return _gana_al_morir(t) and any(
                        c.tipo != Tipo.ORO and _remocion_al_entrar(c) and c.carta.coste <= quedan
                        and any(t in hab.candidatos_validos(p, yo, c, x) for x in _remocion_al_entrar(c))
                        for c in p.j(yo).mano)

                def me_restringe(t):
                    tipos = {c.tipo.value for c in p.j(yo).mano if c.tipo != Tipo.ORO and c.carta.coste <= quedan}
                    return any(x.get("cuando") == "continua" and x.get("accion") in ("restriccion", "prohibir", "impedirJugar")
                               and (not (x.get("objetivo") or {}).get("tipos")
                                    or tipos & set((x.get("objetivo") or {}).get("tipos") or []))
                               for x in t.habilidades)
                def haquika_armada(t):
                    # Héctor: Haquika con Mandoble que me pega cada turno:
                    # Carnwennan le quita lo indestructible y la Bola la destruye
                    # (si tengo Desleal, mejor el Desleal: recupero mi Aliado).
                    if not any(x.get("accion") == "ganarControl" for x in t.habilidades):
                        return False
                    if not any(a.portador == t.uid for a in p.e.portadas):
                        return False
                    if any(c.tipo != Tipo.ORO and p.puede_pagar(yo, c) and any(
                            x.get("accion") in ("desterrar", "ganarControl") and (x.get("objetivo") or {}).get("quien") == "oponente"
                            for x in c.habilidades) for c in p.j(yo).mano):
                        return False
                    return any(c.tipo != Tipo.ORO and c.carta.coste <= quedan and any(
                        x.get("accion") == "destruir" and (x.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
                        for x in c.habilidades) for c in p.j(yo).mano)
                prioridad = ([t for t in objs if haquika_armada(t)] + [t for t in objs if lo_saco_ya(t)] + [t for t in objs if me_saca_algo(t)] + abarata
                             + [t for t in objs if me_restringe(t)]
                             + ([t for t in objs if frena_mi_ataque(t)] if mios else []))
                if not prioridad:
                    return False
                p._carnwennan_objetivo = (p.e.turno, prioridad[0].uid)
            if h.get("accion") == "perderHabilidad" and j.carta.tipo == Tipo.ORO \
                    and (h.get("costo") or {}).get("desterrarEstaCarta") and not _en_peligro(p, yo):
                # Héctor 2026-11-12: Carnwennan es clave; solo contra lo que más
                # pesa (Haquika, Demoledor, Nuh) o un Arma, no en cualquier cosa.
                # Nunca a Haquika (al perder la habilidad, si muere no vuelve mi
                # Aliado); sí a un Werin que va a morir en combate, con Oros de sobra,
                # para que no busque su Talismán.
                objs = [t for t in hab.candidatos_validos(p, yo, j.carta, h) if t.controlador != yo]
                oros = hab.oros_en_juego(p, yo)

                def sirve(t):
                    if any(x.get("accion") == "ganarControl" for x in t.carta.habilidades):
                        # Héctor: solo la Haquika armada que me ataca y que bloqueo
                        # con uno más fuerte (sin habilidad, muere en el combate).
                        bloq = getattr(p, "bloqueos", {}) or {}
                        b = bloq.get(t.uid)
                        return _CARNWENNAN_TURNO and t in p.atacantes and b is not None \
                            and any(a.portador == t.uid for a in p.e.portadas) \
                            and hab.fuerza(p, b) >= hab.fuerza(p, t)
                    if _CORRECCIONES_2 and t.tipo == Tipo.ARMA and not any(
                            a.uid == t.portador for a in p.atacantes):
                        return False  # Héctor (2376 T17): un Arma solo si su portador me ataca ahora
                    if _anular_siempre(p, t) or t.tipo == Tipo.ARMA:
                        return t in _objetivos_perder_habilidad(p, yo, j.carta, h, [t])
                    return _gana_al_morir(t) and oros >= 6 and _muere_en_este_combate(p, t)
                if not any(sirve(t) for t in objs):
                    return False
            costo = h.get("costo") or {}
            if j.carta.tipo == Tipo.ORO and j.carta in p.j(yo).reserva \
                    and any(costo.get(k) for k in ("barajarEstaCarta", "destruirEstaCarta", "desterrarEstaCarta")) \
                    and h.get("accion") == "desterrar" and "cementerio" in hab.zonas_de(h.get("objetivo") or {}, ""):
                # rqHs #1: Trono Dorado no se gasta un Oro por desterrar un Sir
                # Gaheris que no hace nada ahí. Sirve para (según el usuario):
                return _trono_conviene(p, yo, j.carta)
            if j.carta.tipo == Tipo.ORO and (h.get("costo") or {}).get("desterrarEstaCarta") and _juntando_oros(p, yo):
                if _aliado_temporal(h) and not any(
                        _saca_una_amenaza(p, yo, c) and any(
                            (_pieza_clave(a) or hab.fuerza(p, a) >= 4) for a in p.j(1 - yo).aliados)
                        for c in self._utiles_jugar_desde(p, yo, j.carta, h)):
                    return False
            if _rescate_lady(h):
                return _rescate_conviene(p, yo, j.carta, h)  # Draig Ifanc + Lady Calvaur
            if (h.get("accion") == "modificarFuerza" and int(h.get("valor", 0) or 0) > 0
                    and p.e.fase == "vigilia" and p.e.activo == yo
                    and h.get("duracion", "hasta_fase_final") == "hasta_fase_final"
                    and (h.get("fase") in (None, "cualquiera") or "guerra" in str(h.get("fase")))):
                return False  # #3 EZMt: Merodeador, mejor en la Guerra de Talismanes, ya vistos los bloqueos
            if _genera_restringido_inutil(p, yo, h):
                return False  # #7/#8 c0p0: Dragones sin un Dragón caro que pagar
            if _generar_oro_inutil(p, yo, h):
                return False
            if j.carta.nombre.casefold() == "trono dorado" and h.get("accion") == "desterrar":
                objetivos = hab.candidatos_validos(p, yo, j.carta, h)
                if not any(_valor_carta(p, c) >= 5 or _pieza_clave(c)
                           or _se_juega_del_cementerio(c) for c in objetivos):
                    return False
            if h.get("accion") == "generarOro" and h.get("soloParaCosteMin"):
                # #1 EZMt: Dragones solo si el Dragón caro que paga es mi mejor
                # jugada; si no, el Nival contra un solo Aliado le gana a Draco Cometa.
                from .motor import Jugada

                minimo = int(h.get("soloParaCosteMin", 0) or 0)
                # Los caros todavía no se pagan (falta generar): cuento los que
                # alcanzan después de pagar Dragones y que tienen algo que hacer.
                tras = p.j(yo).oro_disponible - 1 + int(h.get("valor", 0) or 0)
                caros = [c for c in p.j(yo).mano if c.tipo == Tipo.ALIADO and c.carta.coste >= minimo
                         and (h.get("soloParaRaza") or "") in (c.raza or "") and p.coste_de(yo, c) <= tras
                         and not _sin_objetivo_al_entrar(p, yo, c)]
                otros = [c for c in p.j(yo).mano if c.tipo != Tipo.ORO and c not in caros
                         and p.puede_pagar(yo, c) and self._vale_la_pena(p, yo, Jugada("jugar", c))]
                if not caros:
                    return False
                if otros and max(self._puntaje(p, yo, Jugada("jugar", c)) for c in otros) > \
                        max(self._puntaje(p, yo, Jugada("jugar", c)) for c in caros):
                    return False
            if h.get("grupoLimite") and h.get("accion") == "barajar" and _otra_opcion_mejor(p, yo, j.carta, h):
                return False  # #4 d8bV: Gaspar baraja 2 Dragones antes que 1 carta
            costo_h = h.get("costo") or {}
            if costo_h.get("desterrarCementerio") and h.get("accion") == "modificarFuerza":
                # qSMg #2: el Merodeador no destierra la Furia Irracional (se juega
                # del Cementerio) salvo que ese +1 me dé la partida.
                n = int(costo_h["desterrarCementerio"])
                libres = [c for c in p.j(yo).cementerio if c is not j.carta and not _vale_en_cementerio(c)]
                if len(libres) < n:
                    dano = sum(max(0, hab.fuerza(p, a)) for a in p.atacantes
                               if a.controlador == yo and p.bloqueos.get(a.uid) is None)
                    if dano + int(h.get("valor", 0) or 0) < len(p.j(1 - yo).mazo):
                        return False
            if (h.get("accion") == "desterrar" and costo_h.get("desterrarCementerio")
                    and (h.get("objetivo") or {}).get("quien") == "oponente"
                    and "cementerio" in hab.zonas_de(h.get("objetivo") or {})):
                propios = p.j(yo).cementerio
                if j.carta.nombre.casefold() == "escarabeo" and sum(
                    1 for c in propios if c.nombre.casefold() == "qer-her"
                ) > len(propios) - int(costo_h["desterrarCementerio"]):
                    return False  # nunca gastar Qer-Her para activar Escarabeo
                cands = hab.candidatos_validos(p, yo, j.carta, h)
                amenazas = [c for c in cands if _se_juega_del_cementerio(c) or _pieza_clave(c)]
                if not amenazas or (propios and all(_se_juega_del_cementerio(c) for c in propios)):
                    return False
            if (h.get("accion") == "buscar" and (h.get("costo") or {}).get("fondoMazoEstaCarta")
                    and p.e.fase == "vigilia" and not _en_peligro(p, yo)
                    and len(p.j(yo).mazo) - 1 > _alcance_rival(p, yo) + 1):
                disponibles = p.j(yo).oro_disponible - int((h.get("costo") or {}).get("oros", 0))
                opciones = hab.candidatos_validos(p, yo, j.carta, h)
                jugable = any(p.coste_de(yo, c) <= disponibles and (
                    c.tipo != Tipo.ARMA or any(hab.portador_valido(p, c, a, yo) for a in p.j(yo).aliados)
                ) for c in opciones)
                if opciones and all(c.tipo == Tipo.ARMA for c in opciones) and not jugable:
                    return False  # buscar un Arma solo si se puede usar este turno
            if (h.get("accion") == "buscar" and (h.get("costo") or {}).get("fondoMazoEstaCarta")
                    and p.e.fase == "vigilia" and p.e.activo == yo and not _en_peligro(p, yo)):
                objetivos = hab.candidatos_validos(p, yo, j.carta, h)
                if objetivos and all(x.tipo == Tipo.ARMA and x.zona == Zona.CEMENTERIO for x in objetivos):
                    for aliado in p.j(yo).mano:
                        if aliado.tipo != Tipo.ALIADO or p.coste_de(yo, aliado) > p.j(yo).oro_disponible:
                            continue
                        if any(x.get("accion") == "jugarDesde" and x.get("cuando") == "activada"
                               and x.get("modo") == "sin_pagar" and not (x.get("costo") or {})
                               and "cementerio" in hab.zonas_de(x.get("objetivo") or {})
                               and "Arma" in ((x.get("objetivo") or {}).get("tipos") or [])
                               for x in aliado.habilidades):
                            return False  # preservar el Oro si ese Aliado puede recuperar el Arma gratis
            if h.get("accion") in ("otra", "mirar"):
                return False
            if _robo_suicida(p, yo, h):
                return False  # Biblioteca Eterna con 4 cartas en el castillo
            if _robo_obliga_a_descartar(p, yo, h):
                return False  # Ay con la mano llena: roba para tirar cartas
            if _costo_suicida(p, yo, j.carta, h):
                return False  # Nudo de Isis pagando botar 3 con 3 cartas
            if p.e.fase == "guerra_talismanes" and not self._guerra_conviene(p, yo, [h]):
                return False
            if _ya_vigente(p, yo, j.carta, h):
                return False  # #104 Ramsés II: ya es indestructible
            if h.get("accion") == "otorgarPropiedad" and (h.get("objetivo") or {}).get("quien") == "esta_carta"                     and j.carta.tipo == Tipo.ALIADO and _se_lo_llevan(p, yo, j.carta, h.get("modo")):
                return False  # Ramsés II: Indestructible no lo salva del Qer-Her que lo sube a la mano
            if _candado_tocador(p, yo, j):
                return True  # Papiros con Tocador: si me bota, pierde él
            costo = h.get("costo") or {}
            if costo.get("fondoMazoEstaCarta") and len(p.j(yo).mazo) - 1 <= _alcance_rival(p, yo) + 1:
                # Riton Aqueménida: al fondo de mi mazo suma 1 al castillo.
                return bool(hab.candidatos_validos(p, yo, j.carta, h)) or h.get("accion") not in ("buscar",)
            if not _sacrificio_de_oro_conviene(p, yo, j.carta, h):
                return False  # #13 Jeroglíficos
            if not _sacrificio_de_aliados_conviene(p, yo, j.carta, h):
                return False  # Ay desterrando a Cleopatra VII
            if not _remocion_que_se_sacrifica_conviene(p, yo, j.carta, h):
                return False  # Perseo no se gasta en Kawit
            n = int((h.get("costo") or {}).get("barajarMano") or 0)
            if n:
                # Piedra Roseta es opcional: solo si tengo algo que sobre en la
                # mano (no el Akhet que saca a Cleopatra).
                mano = [c for c in p.j(yo).mano if c is not j.carta]
                peores = self.elegir_descartes(p, yo, mano, n)
                if len(peores) < n or max(self._valor_descarte(p, yo, c) for c in peores) > 4.5:
                    return False
            return self._objetivo_util(p, yo, j.carta, h)
        inst = j.carta
        if inst.tipo == Tipo.TALISMAN:
            habs = [
                h for h in inst.habilidades
                if h.get("accion") not in ("otra", "anular") and not hab.es_permiso_jugar(h)
            ]
            if not habs:
                return False  # sin habilidad programada: no gasta oro en nada
            if p.e.fase == "guerra_talismanes" and not self._guerra_conviene(p, yo, habs):
                return False
            # Jinetes de Fuego con Neferite rival sin Cementerio: botarle le
            # da con qué desterrar a mi Haquika o mi Demoledor.
            n = _botar_de(p, yo, j)
            if n and not _es_letal(p, yo, j) and _alimenta_remocion(p, yo, n) > 0.8 * n + 2:
                return False
            return all(self._objetivo_util(p, yo, inst, h, pagando=p.coste_de(yo, inst)) for h in habs)
        if inst.tipo == Tipo.ALIADO and not _aliado_conviene(p, yo, inst):
            return False  # #11 Pili: se guarda para cuando su habilidad sirva
        if inst.tipo == Tipo.ALIADO and hab.tiene_prop(p, inst, "errante") and any(
            a.nombre == inst.nombre for a in p.j(yo).aliados
        ):
            return False  # Killgharrah: no reemplaza una copia viva por otra.
        menos = _me_adelgaza(inst)
        if menos and len(p.j(yo).mazo) - menos - 1 <= _alcance_rival(p, yo):
            return False  # Kawit con 4 cartas y Papiros + Ay del rival a la vista
        if inst.tipo == Tipo.TOTEM and _remocion_sin_buen_objetivo(p, yo, inst):
            return False  # #22: Akhet se guarda para algo más valioso que Amyrteos
        if _VETO_ATAQUE_SIMETRICO and _veto_ataque_me_perjudica(p, yo, inst):
            return False  # Tebas: no se baja si frena más mis ataques que los del rival
        if _anulacion_a_la_vista(p, yo, inst) and len(p.j(yo).mazo) > 15 and _hay_carnada(p, yo, inst):
            return False  # #29/#115: primero la carnada (menos importante); esta, después
        if _NO_ALIMENTAR_ABISMO and inst.tipo == Tipo.ALIADO and _anulacion_a_la_vista(p, yo, inst) \
                and len(p.j(yo).mazo) > 8 and (
                    inst.carta.coste >= 5 or any(_habilidad_repetible(h) for h in inst.habilidades)) \
                and any(c is not inst and c.tipo != Tipo.ORO and p.puede_pagar(yo, c) for c in p.j(yo).mano):
            # Héctor 2026-11-12 (partida 19965): Vouivre (5) entró contra un
            # Abismo a la vista y se perdió; con Draig Ifanc + Bola al Demoledor
            # tenía bloqueador y le bajaba el ataque. Lo caro espera la carnada.
            return False
        djoser = inst.tipo == Tipo.ARMA and p.e.activo == yo and _valor_arma_que_entra(p, yo) > 0
        if inst.tipo == Tipo.ARMA and _solo_recupera(inst) and len(p.j(yo).mazo) > 15 and not djoser:
            # #43: Escudo Celestial se guarda para cuando haga falta barajar,
            # salvo que vaya en un atacante que pega seguro (Ramsés II
            # indestructible) con Cementerio que barajar.
            pega = j.portador is not None and j.portador.controlador == yo and j.portador.listo                 and _puede_atacar(p, j.portador) and hab.fuerza(p, j.portador) >= 4
            if not (pega and len(p.j(yo).cementerio) >= 3 and p.e.activo == yo):
                return False
        if inst.tipo == Tipo.ARMA and j.portador is not None and j.portador.controlador == yo                 and p.e.activo == yo and _se_lo_llevan(p, yo, j.portador) and not djoser:
            return False  # el Escudo se iría al Cementerio cuando el Qer-Her suba a Ramsés
        if inst.tipo == Tipo.ARMA:
            # Arma que perjudica a su portador (fuerza negativa): al Aliado
            # oponente más fuerte. Si no, al Aliado propio más fuerte.
            perjudica = any(
                h.get("accion") == "modificarFuerza" and int(h.get("valor", 0)) < 0 for h in inst.habilidades
            )
            lado = p.j(1 - yo) if perjudica else p.j(yo)
            candidatos = [a for a in lado.aliados if hab.portador_valido(p, inst, a, yo)]
            if not perjudica and _rinde_al_atacar(inst):
                candidatos = [a for a in candidatos if _puede_atacar(p, a)]  # #24: Ay es Guardián
            # #94: en lo propio, primero uno que pueda atacar este turno.
            clave = (lambda a: hab.fuerza(p, a)) if perjudica else (
                lambda a: (a.listo, hab.fuerza(p, a) + _bono_por_arma(a)))  # #11 0VzQ: Djoser gana 2 por Arma
            return bool(candidatos) and j.portador is max(candidatos, key=clave)
        return True

    def _guerra_conviene(self, p, yo, habs) -> bool:
        """En Guerra de Talismanes solo juega lo que afecta el combate."""
        defiende = yo != p.e.activo
        for h in habs:
            accion = h.get("accion")
            if accion in ("destruir", "desterrar", "subirMano", "modificarFuerza", "barajar", "ganarControl", "mover"):
                return True
            if defiende and accion in ("cancelarAtaque", "reducirDano", "restringirCombate"):
                return True
            if accion == "robar" and h.get("fase") == "guerra_talismanes":
                # Focea mejora la selección de cartas incluso con una mano amplia.
                # El control de robo suicida se aplica antes de llegar aquí.
                return True
        return False

    def _objetivo_util(self, p, yo, fuente, h, *, pagando: int = 0) -> bool:
        """¿El efecto haría algo que valga la pena ahora? `pagando`: Oros que
        se gastan antes de resolverlo (el coste del Talismán que lo trae)."""
        accion = h.get("accion")
        obj = h.get("objetivo") or {}
        quien = obj.get("quien", "oponente")
        if accion in _DANINO:
            # No usar removal sobre lo propio, salvo que sea su intención.
            if quien == "propio" and accion not in ("barajar", "subirMano"):
                return False
            if accion in ("botar", "descartar") and quien == "propio":
                return False
        if accion == "botar" and quien == "ambos":
            # Grandes Faraones: botamos los dos. Solo si lo deja fuera, o si
            # me sobra castillo y voy bastante adelante.
            n = hab.cantidad(p, yo, h, [], lado=1 - yo)
            mio, suyo = len(p.j(yo).mazo), len(p.j(1 - yo).mazo)
            # Lo que yo boto: lo mismo, más el "luego" que me bota a mí.
            extra = sum(int(e.get("cantidad", 1)) for e in h.get("luego") or []
                        if e.get("accion") == "botar" and (e.get("objetivo") or {}).get("quien") == "propio")
            if mio <= n + extra:
                return False  # me botaría el castillo a mí también
            return suyo <= n or (mio - n > 15 and mio >= suyo + 5)
        if accion == "jugarDesde":
            return self._jugar_desde_conviene(p, yo, fuente, h, pagando)  # #3, #89, #40
        if accion == "modificarFuerza" and not _fuerza_temporal_conviene(p, yo, fuente, h):
            return False  # #152 Toro Apis
        if accion == "restringirCombate" and h.get("modo") == "puede_atacar_este_turno":
            # #47 Ramsés II ya ataca al entrar (Furia); #33 Ay es Guardián y no
            # ataca; #128 Nephre-Ka se iba a desterrar con Ay.
            cands = hab.candidatos_validos(p, yo, fuente, h)
            return any(_atacara_si_puede(p, yo, c) for c in cands)
        if accion == "perderHabilidad" and not _perder_habilidad_conviene(p, yo, fuente, h):
            return False  # #58 Nudo de Isis
        if accion == "buscar" and not _buscar_conviene(p, yo, fuente, h):
            return False  # #135 Rito de Aton
        if accion in ("destruir", "desterrar") and quien == "cualquiera" and obj.get("seleccion") == "todos":
            return _masiva_conviene(p, yo, fuente, h)  # #57 Qadesh
        if accion in _REMOCION and quien == "oponente" and hab._necesita_objetivo(h):
            cands = [c for c in hab.candidatos_validos(p, yo, fuente, h) if not _neutralizado(p, c)]  # #55
            costo = h.get("costo") or {}
            if fuente.tipo == Tipo.ALIADO and fuente.en_juego and (
                costo.get("destruirEstaCarta") or costo.get("desterrarEstaCarta")
            ):
                # Qer-Her se destruye para usarla: el objetivo tiene que valer más.
                return any(
                    _impacto_quitar(p, yo, c) + _impacto_bloqueador(p, yo, c, fuente) > _valor_vivo(p, fuente)
                    for c in cands
                )
            if fuente.tipo == Tipo.TALISMAN and len(cands) and not _en_peligro(p, yo) and not p.atacantes:
                return any(_vale_un_talisman(p, yo, c) for c in cands)
            return bool(cands)
        if accion in _REMOCION and quien == "cualquiera" and fuente.tipo == Tipo.TALISMAN \
                and hab._necesita_objetivo(h) and not _en_peligro(p, yo) and not p.atacantes:
            # Bola de Fuego: solo si hay un objetivo rival que valga el Talismán.
            suyos = [c for c in hab.candidatos_validos(p, yo, fuente, h)
                     if c.controlador != yo and not _neutralizado(p, c)]
            if _BOLA_ESPERA and p.e.activo == yo:
                # Héctor 2026-11-12: en mi turno la Bola solo va a un motor
                # (Haquika, Nuh, Demoledor) o a un Aliado armado; el resto
                # espera la Guerra de Talismanes del rival (responde a lo que baje).
                suyos = [c for c in suyos if _anular_siempre(p, c)
                         or any(a.portador == c.uid for a in p.e.portadas)]
            return any(_vale_un_talisman(p, yo, c) for c in suyos)
        if hab._necesita_objetivo(h):
            return bool(hab.candidatos_validos(p, yo, fuente, h))
        return True

    def _utiles_jugar_desde(self, p, yo, fuente, h, pagando: int = 0) -> list:
        gratis = (h.get("modo") or "sin_pagar") == "sin_pagar"
        oros = hab.oro_para(p, yo, fuente) - pagando
        utiles = []
        for c in hab._candidatos_jugar(p, yo, fuente, h):
            if not gratis and p.coste_de(yo, c) > oros:
                continue
            if _aliado_temporal(h) and not _saca_una_amenaza(p, yo, c):
                continue  # Cruz Templaria: Gaspar se destierra al final y no hizo nada
            if gratis and fuente.tipo == Tipo.TALISMAN and fuente.carta.coste >= 4 \
                    and "mazo" in hab.zonas_de(h.get("objetivo") or {}, "") \
                    and c.carta.coste <= fuente.carta.coste and not _combo_al_entrar(p, yo, c):
                # UBsS #2: La Llama Fría (5) trae Lady o Killgharrah, o Vouivre si
                # baraja 2 Aliados rivales; Draig Ifanc no paga lo que cuesta.
                continue
            if _aliado_temporal(h) and any(x.nombre == c.nombre and p.puede_pagar(yo, x) for x in p.j(yo).mano):
                continue  # #11 c0p0: Lady está en la mano y se paga: se juega de ahí y se queda
            if _aliado_temporal(h) and any(
                x.nombre == c.nombre and any(_rescate_lady(r) and _rescate_conviene(p, yo, x, r) for r in x.habilidades)
                for x in p.j(yo).cementerio
            ):
                continue  # #4 3W4d: mejor el combo (Draig muere, rampea y Lady vuelve a la mano para quedarse)
            if c.tipo == Tipo.TALISMAN:
                habs = [x for x in c.habilidades if x.get("accion") not in ("otra", "anular")]
                # Otro "jugar desde" (una segunda Luz del Saber) no cuenta:
                # evaluarlo volvería a esta misma pregunta sin fin.
                if any(x.get("accion") == "jugarDesde" for x in habs) or not all(
                    self._objetivo_util(p, yo, c, x) for x in habs
                ):
                    continue
            utiles.append(c)
        return utiles

    def _jugar_desde_conviene(self, p, yo, fuente, h, pagando: int) -> bool:
        """Luz del Saber / Nuh: solo si hay algo que valga la pena jugar."""
        gratis = (h.get("modo") or "sin_pagar") == "sin_pagar"
        utiles = self._utiles_jugar_desde(p, yo, fuente, h, pagando)
        if not utiles:
            return False
        if gratis and fuente.tipo == Tipo.TALISMAN and fuente.carta.coste >= 4 \
                and "mazo" in hab.zonas_de(h.get("objetivo") or {}, ""):
            # UBsS #2: La Llama Fría (5) es para Lady o Killgharrah: traer a
            # Draig Ifanc no paga lo que cuesta.
            if max(c.carta.coste for c in utiles) <= fuente.carta.coste:
                return False
        if gratis and (h.get("objetivo") or {}).get("quien") != "esta_carta":
            # #40 Nuh: jugar gratis se guarda para una carta cara (el Mandoble)
            # si la hay en esas zonas; una barata solo si urge recuperarse.
            if max(c.carta.coste for c in utiles) >= 2:
                return True
            # También cuenta una cara en la mano: conviene barajarla y jugarla
            # gratis después.
            caras = [x for x in _en_zonas(p, yo, h) + p.j(yo).mano if x.carta.coste >= 2 and _tipo_ok(x, h)]
            urge = len(p.j(yo).mazo) <= 12 and any(_recupera(c) for c in utiles)
            return urge or not caras
        return True

    def _valor_jugar_desde(self, p, yo, fuente, pagando: int = 0) -> float | None:
        """#37/#64: Luz del Saber vale lo que vale la mejor carta que trae."""
        from .motor import Jugada

        mejor = None
        for h in fuente.habilidades:
            if h.get("accion") != "jugarDesde":
                continue
            for c in self._utiles_jugar_desde(p, yo, fuente, h, pagando):
                v = self._puntaje(p, yo, Jugada("jugar", c))
                mejor = v if mejor is None else max(mejor, v)
        return mejor

    def _puntaje(self, p, yo, j) -> float:
        if _COMBO_IFANC_LADY and j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO \
                and j.carta.nombre.casefold() in ("draig ifanc", "draco putrido") \
                and any(c.nombre.casefold() == "lady calvaur" for c in p.j(yo).cementerio) \
                and p.e.activo == yo:
            # Héctor 2026-11-12 (partida 19965, T6): Ifanc + Lady del Cementerio:
            # roba, Lady vuelve a la mano y el Ifanc trae un Oro (Codex). Si el
            # rival lo anula con Abismo, se lo quemé con una carta barata.
            return max(20.0, self._puntaje_base(p, yo, j))
        base = self._puntaje_base(p, yo, j)
        if _CORRECCIONES_2 and j.tipo == "jugar":
            base += _castigo_barrida_propia(p, yo, j.carta)
        if _CORRECCIONES_19965 and j.tipo == "jugar" and p.e.activo == yo:
            base += _ajuste_remocion_hector(p, yo, j.carta, base)
        return base

    def _puntaje_base(self, p, yo, j) -> float:
        if j.tipo == "activar":
            h = j.carta.habilidades[j.habilidad]
            if j.carta.nombre.casefold() == "anand" and h.get("accion") == "botar":
                # Antes de atacar con Aine, Anand presiona ambos castillos y
                # convierte Oro/Aliado botado en robo o reciclaje.
                if any(a.nombre.casefold() == "aine" and _puede_atacar(p, a) for a in p.j(yo).aliados):
                    return 18.0
            if j.carta.nombre.casefold() == "lady calvaur" and j.carta.zona == Zona.CEMENTERIO \
                    and h.get("accion") == "destruir":
                # Lady vuelve a la mano al sacrificar un Dragón. Ifanc además
                # acelera un Oro al salir; Pútrido transforma el sacrificio en
                # una remoción. Es una secuencia, no un simple "destruir mío".
                objetivos = hab.candidatos_validos(p, yo, j.carta, h)
                if not objetivos:
                    return 0.0
                valor = 16.0
                for a in objetivos:
                    if a.nombre.casefold() == "draig ifanc" and any(c.tipo == Tipo.ORO for c in p.j(yo).mazo):
                        valor = max(valor, 25.0)
                    if a.nombre.casefold() == "draco putrido" and any(
                        x.tipo == Tipo.ALIADO and x.carta.coste <= 4 for x in p.j(1 - yo).aliados
                    ):
                        valor = max(valor, 24.0)
                return valor
            if h.get("accion") == "buscar" and _en_peligro(p, yo) and any(
                _defensivo(c) for c in hab.candidatos_validos(p, yo, j.carta, h)
            ):
                return 30.0  # #85: sobrevivir primero
            if h.get("accion") == "jugarDesde":
                return self._valor_jugar_desde(p, yo, j.carta) or 3.0
            if h.get("accion") == "mirarTope" and h.get("zonaDestino") == "en_juego":
                return 28.0  # FtbJ #1: Idmon primero: un Héroe gratis y decido con lo que sale
            if h.get("accion") == "perderHabilidad" and any(
                x.get("accion") == "restriccion" and x.get("modo") == "barajar_cementerio"
                for x in j.carta.habilidades
            ) and any(
                x.get("accion") == "barajar" and "cementerio" in hab.zonas_de(x.get("objetivo") or {})
                for c in p.j(yo).mano + p.e.instancias_en_juego(yo) for x in c.habilidades
            ):
                return 32.0
            if h.get("accion") == "perderHabilidad" and any(
                t.tipo == Tipo.ORO and any(x.get("accion") in ("prevenir", "anular", "redirigir") for x in t.carta.habilidades)
                for t in _objetivos_perder_habilidad(p, yo, j.carta, h)
            ):
                return 15.0  # Figuras Negras a Amkh antes de la Focea
            if h.get("accion") == "perderHabilidad" and any(
                t.tipo == Tipo.ALIADO and any(x.get("accion") == "prevenir" for x in t.carta.habilidades)
                for t in _objetivos_perder_habilidad(p, yo, j.carta, h)
            ):
                # #6 ZOlJ: Carnwennan a Ptolomeo II antes que el Dragón de Magma que lo destruye.
                from .motor import Jugada
                remos = [r for r in _remociones_a_mano(p, yo, pagando=_oros_que_cuesta_quitar(p, yo, j.carta, h))
                         if r.zona == Zona.MANO]
                return max([15.0] + [self._puntaje(p, yo, Jugada("jugar", r)) + 1 for r in remos])
            if _candado_tocador(p, yo, j):
                return 25.0  # Papiros con Tocador: primero el candado
            if (h.get("costo") or {}).get("fondoMazoEstaCarta") and len(p.j(yo).mazo) - 1 <= _alcance_rival(p, yo) + 1:
                return 24.0  # Riton Aqueménida: +1 al castillo antes que gastar en otra cosa
            if _REMOCION_ACTIVADA:
                v = _valor_remocion_activada(p, yo, j.carta, h)
                if v > 3.0:
                    return v
            return 3.0
        inst = j.carta
        if inst.tipo == Tipo.TALISMAN and _letal_por_refuerzo(p, yo, inst):
            return 40.0  # Furia Irracional: el ataque que sigue es letal.
        if inst.tipo == Tipo.TALISMAN and any(
            h.get("accion") == "jugarDesde" and h.get("cuando") in ("al_jugar", None) and not hab.es_permiso_jugar(h)
            for h in inst.habilidades
        ):
            v = self._valor_jugar_desde(p, yo, inst, pagando=p.coste_de(yo, inst))
            if v is not None:
                return v - 0.5  # un poco menos: además gasta la Luz del Saber
        base = inst.carta.coste * 2.0 + _valor_remocion_al_entrar(p, yo, inst) + _valor_rebote(p, yo, inst)
        base += _valor_robo_al_jugar(p, yo, inst)  # Nacimiento de Pegaso
        if inst.tipo == Tipo.ARMA and j.portador is not None:
            base += _valor_defensivo_arma(p, yo, inst, j.portador)  # #80 Escudo Miliciano
            if j.portador.controlador == yo:
                base += 3.0 * _bono_por_arma(j.portador)  # #11 0VzQ: el Escudo en Djoser pega mucho más
        base += _valor_motor_de_entradas(p, yo, inst)  # #101 Ptolomeo III primero
        if inst.tipo == Tipo.ARMA:
            base += _valor_arma_que_entra(p, yo)  # Djoser destruye al entrar un Arma
        base += _valor_masiva(p, yo, inst)  # Quemar los Templos: las Armas de Djoser
        if inst.tipo == Tipo.ALIADO and _relevo_sin_objetivo(p, yo, inst):
            base -= inst.carta.coste  # Bennu sin Aliado en el Cementerio: mejor Werin
        if inst.tipo == Tipo.ALIADO and _gana_al_morir(inst):
            # Combo Amyrteos + Montuhopet II: primero Amyrteos, después
            # Montuhopet lo sube (acelera un Oro) y se vuelve a jugar.
            rebote = [c for c in p.j(yo).mano if c is not inst and any(_rebote_propio(h) for h in c.habilidades)]
            if rebote and p.j(yo).oro_disponible >= p.coste_de(yo, inst) + min(p.coste_de(yo, c) for c in rebote):
                base += 8.0
        if any(
            h.get("cuando") == "al_jugar" and h.get("accion") == "buscar"
            and "Oro" in ((h.get("objetivo") or {}).get("tipos") or []) for h in inst.habilidades
        ):
            oros_en_juego = len(p.j(yo).reserva) + len(p.j(yo).pagado)
            if oros_en_juego <= 4:
                base += 4.0  # acelerar al comienzo, sin imponer la jugada
            if (oros_en_juego in (4, 5) and not any(c.tipo == Tipo.ORO for c in p.j(yo).mano)
                    and any(c.tipo == Tipo.ORO for c in p.j(yo).mazo)):
                base += 4.0  # valorar el próximo Oro frente a otras opciones
        if inst.tipo == Tipo.ALIADO:
            disponibles = p.j(yo).oro_disponible - p.coste_de(yo, inst)
            for h in inst.habilidades:
                obj = h.get("objetivo") or {}
                if h.get("cuando") == "al_jugar" and h.get("accion") == "subirMano" and obj.get("quien") == "propio" and "cementerio" in hab.zonas_de(obj):
                    recuperables = hab.candidatos_validos(p, yo, inst, h)
                    base += max([0.0] + [_valor_remocion_al_entrar(p, yo, c) for c in recuperables
                                         if c.tipo == Tipo.ALIADO and p.coste_de(yo, c) <= disponibles])
        if inst.tipo == Tipo.ALIADO and _gana_al_morir(inst) and _hay_salida(p, yo, inst):
            base += 7.0  # #13: Amyrteos + Ay (roba 2 y acelera un Oro)
        if inst.tipo == Tipo.ALIADO and _es_salida(inst) and any(_gana_al_morir(a) for a in p.j(yo).aliados):
            base += 7.0  # #26: Ay con Amyrteos ya en mesa
        if inst.tipo == Tipo.ALIADO:
            base += inst.carta.fuerza + (2 if hab.tiene_prop(p, inst, "furia") else 0)
            if inst.nombre.casefold() == "idmon el adivino" and not inst.en_juego:
                base += 8.0  # alto techo: puede jugar gratis el Héroe superior
            if inst.nombre.casefold() == "saladino" and not inst.en_juego:
                # El Oro de Saladino habilita inmediatamente Yvain/Persival y
                # mantiene la curva de Caballeros; no se cambia por un 2/2.
                base += 9.0 if len(p.j(yo).reserva) + len(p.j(yo).pagado) <= 5 else 3.0
            if inst.nombre.casefold() == "sir persival" and any(
                    a.nombre.casefold() == "teseo de atenas" for a in p.j(1 - yo).aliados):
                base += 12.0  # Teseo ataca al entrar y destruye al hacer daño.
            if inst.nombre.casefold() == "cathach" and len(p.j(yo).mazo) <= 8 \
                    and len(p.j(yo).cementerio) >= 2:
                base += 15.0  # recuperación inmediata de castillo bajo presión
            if not inst.en_juego and any(h.get("cuando") == "continua" and h.get("accion") == "modificarFuerza"
                                         for h in inst.habilidades):
                zona = inst.zona
                try:
                    inst.zona = Zona.DEFENSA
                    p.j(yo).defensa.append(inst)
                    base += 2 * _fuerza_que_aporta(p, inst)
                finally:
                    p.j(yo).defensa.remove(inst)
                    inst.zona = zona
            for h in inst.habilidades:
                obj = h.get("objetivo") or {}
                v = int(h.get("valor", 0) or 0)
                if h.get("cuando") == "continua" and h.get("accion") == "modificarFuerza" and v < 0 \
                        and obj.get("quien") == "oponente" and hab.condicion_ok(p, yo, h):
                    # #10 UUOX: Cathach baja 1 a cada Aliado rival (y mata a los de 1).
                    for a in p.j(1 - yo).aliados:
                        f = max(0, hab.fuerza(p, a))
                        base += 2 * min(-v, f)  # i4b3 #3: con fuerza 0 no muere
                if h.get("cuando") == "al_jugar" and h.get("accion") == "barajar" and obj.get("quien") == "propio" \
                        and "cementerio" in hab.zonas_de(obj) and (_rival_agro(p, yo) or _en_peligro(p, yo)):
                    # Contra agro, barajarse cartas del Cementerio alarga el castillo.
                    base += 1.5 * min(int(h.get("cantidad", 1) or 1), len(p.j(yo).cementerio))
            if not p.j(yo).aliados and p.j(1 - yo).aliados:
                if any(c is not inst and c.carta.id == inst.carta.id and
                       p.coste_de(yo, inst) + p.coste_de(yo, c) <= p.j(yo).oro_disponible
                       for c in p.j(yo).mano):
                    base += 3.0  # dos Aliados alcanzables ayudan a recuperar la mesa
            # Un Aliado de la raza puede habilitar una remoción en la misma
            # Vigilia (Marco Antonio seguido de Ganimedes).
            if inst.raza and not inst.en_juego:
                for siguiente in p.j(yo).mano:
                    if siguiente is inst or siguiente.tipo != Tipo.ALIADO or siguiente.raza != inst.raza:
                        continue
                    if p.coste_de(yo, inst) + p.coste_de(yo, siguiente) > p.j(yo).oro_disponible:
                        continue
                    if not any((h.get("objetivo") or {}).get("coste", {}).get("segun") == "aliados_raza"
                               and h.get("accion") in _REMOCION and h.get("cuando") == "al_jugar"
                               for h in siguiente.habilidades):
                        continue
                    antes = _valor_remocion_al_entrar(p, yo, siguiente)
                    zona = inst.zona
                    try:
                        inst.zona = Zona.DEFENSA
                        p.j(yo).defensa.append(inst)
                        despues = _valor_remocion_al_entrar(p, yo, siguiente)
                    finally:
                        p.j(yo).defensa.remove(inst)
                        inst.zona = zona
                    base += max(0, despues - antes)
                    break
            if inst.carta.coste >= 4 and _se_lo_llevan(p, yo, inst) and not any(
                h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION
                and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
                for h in inst.habilidades
            ):
                # Qer-Her a la vista: 4 Oros que vuelven a la mano. kFaZ: no a Lady,
                # que ya desterró 2 al entrar (y si la devuelven, se juega de nuevo).
                base -= 2.0 * inst.carta.coste
        if _pieza_clave(inst) and not any(a.carta.nombre == inst.carta.nombre for a in p.j(yo).aliados) \
                and _nombrar_raza_sirve(p, yo, inst):
            # Armar el candado Ptolomeo II + Neferite I + Cleopatra VII antes
            # que un Arma; cada pieza que ya está suma a la siguiente.
            base += 6.0 + 2.0 * sum(1 for a in p.j(yo).aliados if _pieza_clave(a))
        if getattr(inst, "jugar_ya_turno", None) == p.e.turno and not inst.en_juego:
            base += 30.0  # Lady Calvaur recién vuelta sacrificando otro Dragón: va ya
        if inst.tipo == Tipo.ALIADO and _gana_al_morir(inst) and inst.raza == "Dragón" and any(
            _rescate_lady(h) for c in p.j(yo).cementerio for h in c.habilidades
        ):
            # Draig Ifanc con Lady en el Cementerio: entra, muere, rampea un Oro
            # y vuelve Lady. Es LA jugada temprana (ideal en el turno 2) hasta
            # poder pagar a Lady (7 Oros o 5 + Dragones); después pesa menos.
            # Pero si el rival pega fuerte y tengo con qué frenarlo (Bola de
            # Fuego, Gozosa, Desleal), primero se frena el agro.
            if _frenar_agro_primero(p, yo, inst):
                pass  # primero la Bola de Fuego / Gozosa / Desleal
            elif _capacidad_lady(p, yo):
                base += 4.0
            else:
                base += 15.0
        if inst.tipo == Tipo.ALIADO and not inst.en_juego:
            if inst.nombre.casefold() == "vouivre" and _combo_al_entrar(p, yo, inst):
                # Convierte un aliado propio en dos rivales fuera y permanece
                # como tutor de Dragones cada Vigilia.
                base += 16.0
            suyos, mios = _victimas_barrida(p, yo, inst)
            barre = any(h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION
                        and (h.get("objetivo") or {}).get("seleccion") == "todos" for h in inst.habilidades)
            if barre:
                # #1/#3 3W4d: Dragón Nival vale por lo que barre: contra 3 es la
                # jugada; contra uno solo (o ninguno: dZ3A, el Ptolemaico tiene 3) se guarda.
                base += 4.0 * suyos - 4.0 * mios - (18.0 if suyos <= 1 else 0.0)
        if inst.tipo == Tipo.ALIADO and not inst.en_juego and _cultista_tiene_mano(p, yo) and any(
            _cultista(h) for h in inst.habilidades
        ):
            # dZ3A: Cultistas le saca un Aliado de la mano (mira y baraja): con
            # la mesa rival vacía, esa es la jugada antes que Draco Cometa.
            # Contra agro, hasta la última carta puede ser el Aliado que lo
            # mantiene jugando (Amosis I y otros motores). Se prioriza salvo
            # que haya una remoción necesaria para sobrevivir a su mesa.
            base += 8.0 + (5.0 if _rival_agro(p, yo) else 0.0)
            if not p.j(1 - yo).aliados:
                base += 3.0
            if _rival_agro(p, yo) and _frenar_agro_primero(p, yo, inst):
                base -= 14.0
        if inst.tipo == Tipo.ALIADO and p.j(1 - yo).aliados and any(
            h.get("cuando") in ("al_jugar", None) and h.get("accion") == "perderHabilidad"
            and any(e.get("modo") == "no_puede_atacar" for e in h.get("luego") or [])
            and hab.condicion_ok(p, yo, h) for h in inst.habilidades
        ):
            base += 5.0  # Draco Cometa: deja a un Aliado rival sin atacar ni bloquear (casi una remoción)
        if inst.tipo == Tipo.TALISMAN and _remocion_clave(p, yo, inst):
            base += 8.0  # #1/#2 c0p0: Desleal a Neferite I
        if inst.tipo == Tipo.TALISMAN and _ramp_de_oro(inst):
            quedan = p.j(yo).oro_disponible - p.coste_de(yo, inst) + 1
            if (_ramp_temprano(p, yo) and any(
                    c is not inst and c.tipo != Tipo.ORO and p.coste_de(yo, c) <= quedan
                    for c in p.j(yo).mano)):
                base += 6.0  # #4 c0p0: Alquimista primero y después lo demás con el Oro que trae
        if inst.tipo == Tipo.TALISMAN and _descarte_rival(inst):
            # Cruzada de los Niños: vale por lo que de verdad descarta; si le deja
            # la mano vacía, más. Si Cultistas está listo, primero él (elige al
            # Aliado que baraja) y después la Cruzada descarta al azar el resto.
            mano_rival = len(p.j(1 - yo).mano)
            n = min(_descarte_rival(inst), mano_rival)
            base += 3.0 * n + (2.0 if 0 < n == mano_rival else 0.0)
            if any(_cultista(h) and h.get("cuando") == "activada" for c in p.e.instancias_en_juego(yo)
                   for h in c.habilidades) and any(c.tipo == Tipo.ALIADO for c in p.j(1 - yo).mano):
                base -= 6.0
        if inst.tipo == Tipo.TALISMAN and _ramp_de_oro(inst) and _rival_agro(p, yo) and any(
            _oro_defiende(c) and not any(x.nombre == c.nombre for x in p.e.instancias_en_juego(yo))
            for c in p.j(yo).mazo
        ):
            base += 4.0  # Alquimista contra agro: se trae el Codex Arturicus
        if inst.tipo == Tipo.TALISMAN:
            # Combo: Adiós Belleza a Werin va antes que el Nephre-Ka que lo saca.
            for x in inst.habilidades:
                if x.get("accion") == "perderHabilidad" and x.get("cuando") in ("al_jugar", None):
                    habilita = [
                        t for t in _objetivos_perder_habilidad(p, yo, inst, x)
                        if t.tipo == Tipo.ALIADO and t.controlador != yo
                        and _remociones_a_mano(p, yo, pagando=p.coste_de(yo, inst))
                    ]
                    if habilita:
                        base += 4.0 + max(_valor_carta(p, t) for t in habilita)
        if inst.tipo == Tipo.TALISMAN and p.e.fase == "vigilia":
            base -= 1.0  # guarda talismanes de combate para la guerra
        return base + self.rng.random() * 0.1

    def elegir_atacantes(self, p, yo, candidatos):
        rival = p.j(1 - yo)
        candidatos = [
            c for c in candidatos
            if not _se_bota_de_mas(p, yo, c, "al_atacar")
            or _letal_al_atacar(p, yo, c)
            # UUOX: tras gastar mejoras (p. ej. dos del Merodeador) el
            # Medjay debe atacar. Se conserva el límite de no botar el último
            # castillo propio.
            or (_potenciado_este_turno(p, c) and len(p.j(yo).mazo) > 1)
        ]  # Guerrero Medjay / Ramsés IX botan también mi castillo
        candidatos = [
            c for c in candidatos
            if not (c.nombre.casefold() == "orcos" and any(
                a.nombre.casefold() == "niamh" and hab.fuerza(p, a) >= hab.fuerza(p, c)
                for a in rival.aliados
            ))
        ]  # Niamh bloquea Imbloqueables: Orcos no llega a hacer daño ni robar.
        letales = list(candidatos)  # antes de guardar defensores: el letal gana igual
        candidatos = [c for c in candidatos if not _ultimo_defensor(p, yo, c) and not _mejor_en_casa(p, yo, c)]
        libres = sorted(
            [b for b in rival.defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")],
            key=lambda b: hab.fuerza(p, b), reverse=True,
        )
        rebaja = _rebaja_disponible(p, 1 - yo)  # #67: el Toro Apis del rival
        refuerzo = max(_refuerzo_desde_cementerio(p, 1 - yo),  # #124: Escudo Miliciano
                       _refuerzo_activable(p, 1 - yo, libres) if _REFUERZO_ACTIVABLE else 0)  # I4Sl2 #1: La Ilíada
        mi_castillo, su_castillo = len(p.j(yo).mazo), len(rival.mazo)
        # Auditoría 2026-11-12 (Killgharrah, Artabano): Flechas de Lava cancela
        # el ataque y me hace botar la fuerza de mi mayor Aliado; con el robo
        # final eso me deja sin castillo. Si el rival puede tenerla, no ataco.
        bote = max((hab.fuerza(p, a) for a in p.j(yo).aliados), default=0)
        if _FLECHAS_HECTOR:
            # Héctor 2026-11-12: Flechas cuesta 3; asusta solo si con ella y el
            # resto de su daño directo (Jinetes, Papiros) me deja sin castillo
            # y no tengo cómo anularla (Fe Sin Límite con Oro).
            anulo = any(_anulador(c) and p.coste_de(yo, c) <= p.j(yo).oro_disponible for c in p.j(yo).mano)
            amenaza = bote + _quemado_rival(p, yo)
            if anulo or p.j(1 - yo).oro_disponible < 3:
                amenaza = -1
        else:
            amenaza = bote
        if amenaza >= mi_castillo - 1:
            riesgo = _prob_cancelador_con_bote(p, yo)
            if riesgo >= _UMBRAL_CANCELADOR:
                candidatos = []
                if riesgo >= _UMBRAL_CANCELADOR_LETAL:
                    letales = []
        agresivo = su_castillo <= 12 or su_castillo < mi_castillo - 8
        if su_castillo > 12:
            # El candado (Ptolomeo II, Neferite, Cleopatra) no ataca si un bloqueador lo puede matar (o lo
            # exponen a Jeroglíficos y Toro Apis en el combate).
            candidatos = [
                c for c in candidatos
                if not _pieza_clave(c) or all(hab.fuerza(p, b) + refuerzo < hab.fuerza(p, c) for b in libres)
            ]
            candidatos = [c for c in candidatos if not (
                any(h.get("cuando") == "continua" and h.get("accion") in ("modificarFuerza", "restriccion")
                    for h in c.habilidades)
                and not hab.tiene_prop(p, c, "imbloqueable")
                and not hab.tiene_prop(p, c, "indestructible")
                and any(hab.fuerza(p, b) + refuerzo >= hab.fuerza(p, c) - rebaja
                        and _valor_vivo(p, c) > _valor_vivo(p, b) for b in libres)
            )]
        if _cancelador_revelado(p, 1 - yo) and not _puedo_anular(p, yo):
            # Héctor 2026-11-12: si las Flechas no me matan y tengo letal, ataco
            # igual (si las usa, los atacantes vuelven a defensa). Atacar sin
            # letal solo para quemarla rindió −0,6 pts (botar duele).
            if _FLECHAS_QUEMAR and amenaza < mi_castillo - 1:
                letal = _letal_conjunto(p, yo, letales, libres, rebaja, su_castillo)
                if letal:
                    return letal
            return []  # #121: me cancela el ataque con Flechas de Lava y me hace botar
        # Auditoría 2026-11-12: con daño letal entre todos, se ataca aunque
        # esté en peligro o sea un mazo lento (antes se quedaban a bloquear y
        # el filtro de abajo ya no veía el letal).
        letal = _letal_conjunto(p, yo, letales, libres, rebaja, su_castillo)
        if letal:
            return letal
        if _NO_ATACAR_EN_PELIGRO and _en_peligro(p, yo) and not any(_letal_al_atacar(p, yo, c) for c in candidatos):
            # PYDO #7: el rival me gana atacando el próximo turno: los Aliados
            # se quedan a bloquear (salvo los que no pueden bloquear igual).
            candidatos = [c for c in candidatos if hab.tiene_estado(p, c, "no_puede_bloquear")]
        atacan = [c for c in candidatos if hab.fuerza(p, c) > 0]
        if len(atacan) > len(libres):
            # #1 d8bV: no alcanza a bloquearlos a todos. Bloquea a los más
            # fuertes; lo que pasa más lo que botan al atacar (Ramsés IX) gana.
            pasan = sorted(max(0, hab.fuerza(p, c) - rebaja) for c in atacan)[:len(atacan) - len(libres)]
            if sum(pasan) + sum(_bota_seguro_al_atacar(p, c) for c in atacan) >= su_castillo:
                return atacan
        # 2026-11-12: desactivado (_MAZO_LENTO_PASIVO). Dragón dejaba pasar 572
        # turnos con la mesa rival vacía en 300 partidas contra Sacerdote;
        # atacando sube de 16% a 24% y la media contra el meta +1,7 pts.
        if _MAZO_LENTO_PASIVO and _mazo_lento(p, yo) and (not _partida_controlada(p, yo) or (
                _rival_usa_cementerio(p, 1 - yo)
                and su_castillo > 2 * sum(max(0, hab.fuerza(p, c)) for c in candidatos))):
            # Dragón (control): no ataca hasta tener la partida controlada,
            # salvo que el ataque gane; los Aliados se quedan bloqueando.
            # #5 EZMt: el daño le llena el Cementerio al Faraón (Nephre-Ka,
            # Jinetes de Fuego): solo se ataca para cerrar la partida.
            return [c for c in candidatos if _letal_al_atacar(p, yo, c)]
        if not libres:
            return [c for c in candidatos if hab.fuerza(p, c) > 0]
        out = []
        # Demoledor de Amon: se lleva al bloqueador que obliga (#39) y solo
        # ataca si gana esa pelea (#113: contra Ay con Escudo Miliciano muere).
        for c in candidatos:
            if not _obliga_a_bloquear(c) or hab.fuerza(p, c) <= 0:
                continue
            if not libres:
                out.append(c)  # #69: sin bloqueadores, el Demoledor también ataca
                continue
            forzado = max(libres, key=lambda b: _prioridad_obligar(p, b))
            anterior = forzado.sin_habilidad_hasta
            efectos = [e for h in c.habilidades if h.get("accion") == "obligarBloqueo"
                       for e in h.get("luego") or []]
            try:
                if any(e.get("accion") == "perderHabilidad" for e in efectos) and not hab.inmune(p, forzado, c):
                    forzado.sin_habilidad_hasta = "hasta_fase_final"
                fuerza_forzado = hab.fuerza(p, forzado)
            finally:
                forzado.sin_habilidad_hasta = anterior
            reduccion = sum(-min(0, int(e.get("valor", 0) or 0)) for e in efectos
                            if e.get("accion") == "modificarFuerza" and e.get("modoFuerza", "sumar") == "sumar")
            if hab.fuerza(p, c) - rebaja > fuerza_forzado - reduccion + refuerzo:
                out.append(c)
                libres.remove(forzado)
        resto = [c for c in candidatos if c not in out and not _obliga_a_bloquear(c)]
        for c in sorted(resto, key=lambda x: hab.fuerza(p, x), reverse=True):
            f = hab.fuerza(p, c) - rebaja + _bono_al_atacar(c)
            if hab.fuerza(p, c) <= 0:
                continue
            if (
                hab.tiene_prop(p, c, "imbloqueable") or _gana_al_morir(c) or _bota_al_atacar(p, c) or not libres
                or _letal_al_atacar(p, yo, c)
            ):
                out.append(c)  # pasa, gana al morir o bota igual al atacar (Mandoble)
                continue
            if hab.tiene_prop(p, c, "indestructible") and not _lo_necesito_para_defender(p, yo, c):
                # Ramsés II: no arriesga nada. Pero Haquika (2) contra un
                # bloqueador que no muere no gana nada y deja de defender.
                if all(hab.fuerza(p, b) + refuerzo < f for b in libres) or _rinde_al_atacar(c) or any(
                    x.get("cuando") == "al_ser_bloqueado" for x in c.habilidades
                ):
                    out.append(c)
                continue
            mejor = libres[0]
            fm = hab.fuerza(p, mejor) + refuerzo
            parejo = f == fm and not hab.tiene_prop(p, mejor, "indestructible")
            if f > fm or (parejo and _valor_vivo(p, c) <= _valor_vivo(p, mejor)):
                out.append(c)  # gana, o cambia uno que no vale más que el bloqueador (#103 Cleopatra no)
            elif agresivo and sum(1 for x in out if not _obliga_a_bloquear(x)
                                  and not hab.tiene_prop(p, x, "imbloqueable")) >= len(libres):
                out.append(c)  # #166: con más atacantes que bloqueadores, alguno pasa
        # #135: si me sobran al menos 2 atacantes por sobre sus bloqueadores,
        # ataco con todos: los que no bloquee pasan.
        disponibles = [c for c in candidatos if hab.fuerza(p, c) > 0]
        if libres and refuerzo:
            # #8 0VzQ: con el Escudo Miliciano en su Cementerio, el mejor
            # bloqueador pega más; no se manda a morir a uno que vale más que él.
            fm = hab.fuerza(p, libres[0]) + refuerzo
            disponibles = [
                c for c in disponibles
                if c in out or hab.tiene_prop(p, c, "imbloqueable")
                or hab.fuerza(p, c) - rebaja > fm or _valor_vivo(p, c) <= _valor_vivo(p, libres[0])
            ]
        bloqueadores_totales = sum(1 for b in rival.defensa if not hab.tiene_estado(p, b, "no_puede_bloquear"))
        # Mercaderes y equivalentes pueden convertirse durante la declaraciÃ³n;
        # cuentan como un bloqueo real antes de decidir regalar atacantes.
        convertibles = sum(
            1 for c in rival.reserva
            if any(h.get("accion") == "convertirEnAliado" for h in c.habilidades)
        )
        if libres and not agresivo:
            # tuK8 #4: aunque sobren atacantes, el rival bloquea al que le
            # conviene: no se regala uno que muere y vale más que el bloqueador
            # (Idmon contra Melisende). Cerrando la partida, sí.
            disponibles = [
                c for c in disponibles
                if c in out or hab.tiene_prop(p, c, "imbloqueable") or _letal_al_atacar(p, yo, c)
                or not any(hab.fuerza(p, b) + refuerzo >= hab.fuerza(p, c) - rebaja
                           and _valor_vivo(p, c) > _valor_vivo(p, b) for b in libres)
            ]
        if len(disponibles) >= bloqueadores_totales + 2 + convertibles \
                and not _cancelador_revelado(p, 1 - yo):
            return disponibles
        return out

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        castillo = len(p.j(yo).mazo)
        total = sum(hab.fuerza(p, a) for a in atacantes)
        # Auditoría 2026-11-12: el daño real supera la fuerza declarada (lo que
        # botan al atacar o al dañar, y lo que el rival sube en la Guerra de
        # Talismanes con sus Oros libres). Sin contarlo no se bloqueaba el
        # ataque que mataba.
        extra = sum(_bota_seguro_al_atacar(p, a) + _bota_al_danar(p, a) for a in atacantes)
        margen = 3 + min(3, p.j(1 - yo).oro_disponible)
        apurado = total + extra >= castillo - margen or (castillo <= 10 and total > 0)
        if apurado and any(
            x.get("accion") == "reducirDano" and (x.get("modo") or "dano_a_cero") == "dano_a_cero"
            and x.get("cuando") == "activada" for c in p.e.instancias_en_juego(yo) + p.j(yo).pagado
            for x in c.habilidades
        ):
            apurado = False  # #12 c0p0: el Codex deja el daño en 0; no se pierden bloqueadores
        if _OP("NB") and not apurado and _vouivre_espera(p, yo):
            return {}  # Héctor: guardo mi Aliado y los suyos para barajarlos con Vouivre
        libres = sorted((b for b in bloqueadores if hab.fuerza(p, b) > 0), key=lambda b: hab.fuerza(p, b))

        def arriesga(b):
            # Ptolomeo II se cuida: solo bloquea si mata y sobrevive con margen
            # (un Toro Apis no lo da vuelta), salvo apurado. #12 c0p0: Cathach
            # también (su −1 a los rivales vale más que un Merodeador).
            aura = any(h.get("cuando") == "continua" and h.get("accion") == "modificarFuerza"
                       and int(h.get("valor", 0) or 0) < 0 for h in b.habilidades)
            # 1uF1 #3: Draco Cometa mantiene a Amosis I sin habilidad mientras
            # siga en juego: si muere bloqueando, Amosis la recupera.
            candado = any(
                t.sin_habilidad_fuente == b.uid
                or any(e.get("fuente") == b.uid and e.get("duracion") == "mientras_en_juego" for e in t.estados)
                for t in p.e.instancias_en_juego(1 - yo)
            )
            if _CORRECCIONES_2 and aura and not (_pieza_clave(b) or candado):
                return False  # Héctor (97465 T11): Cathach bloquea a la Kawit y la mata
            return (_pieza_clave(b) or aura or candado) and not apurado
        out = {}
        rebaja = _rebaja_disponible(p, yo)  # #49: Toro Apis −1 al que bloqueo
        # Primero el que gana algo si me hace daño (Jentakus con Escudo
        # Celestial baraja tantas como daño): bloquearlo le niega eso.
        def gana_al_danar(a):
            fuentes = [a] + [x for x in p.e.portadas if x.portador == a.uid]
            return any(h.get("cuando") == "al_hacer_dano" for x in fuentes for h in x.habilidades)

        for atk in sorted(atacantes, key=lambda a: (gana_al_danar(a), _valor_vivo(p, a)), reverse=True):
            fa = hab.fuerza(p, atk) - rebaja
            if atk.sin_habilidad_hasta is None:
                for h in atk.habilidades:
                    # MscU #2: Laegerie duplica su fuerza si la bloquean.
                    if h.get("cuando") == "al_ser_bloqueado" and h.get("accion") == "modificarFuerza" \
                            and (h.get("objetivo") or {}).get("quien") == "esta_carta":
                        fa = 2 * fa if h.get("modoFuerza") == "duplicar" else fa + int(h.get("valor", 0) or 0)
            if _castigo_si_lo_bloquean(p, atk) > 0 and not _bloqueo_con_tocador_conviene(p, yo, atk) and not any(
                hab.fuerza(p, b) > fa and not hab.tiene_prop(p, atk, "indestructible") for b in libres
            ):
                continue  # #91: bloquear a Ramsés II hace botar 6 además del daño (salvo con Tocador)
            atras = castillo < len(p.j(1 - yo).mazo) - 8
            recupera = any(_recupera_al_bloquear(p, b) for b in libres)
            if _gana_al_morir(atk) and not apurado and not atras and not recupera:
                continue  # Amyrteos: matarlo le da un Oro; mejor recibir su daño
            # 1) Bloqueador que sobrevive y mata (el más débil que alcance).
            mata = [b for b in libres if hab.fuerza(p, b) > fa + (1 if arriesga(b) else 0)]
            # #81: Amyrteos bloquea con gusto: frena daño y al morir acelera un Oro.
            # Héctor 2026-11-12: con Lady en el Cementerio, Draig Ifanc se guarda
            # para destruirlo con ella (vuelve Lady a la mano), no para bloquear.
            lady_cem = any(any(_rescate_lady(x) for x in c.habilidades) for c in p.j(yo).cementerio)
            ganan = [b for b in libres if _gana_al_morir(b) and not arriesga(b)
                     and not (lady_cem and "Dragón" in (b.raza or ""))]
            if not mata and ganan and _castigo_si_lo_bloquean(p, atk) == 0:
                b = ganan[0]
                out[atk.uid] = b
                libres.remove(b)
                continue
            # 2) Un indestructible no se pierde: bloquear siempre reduce el daño
            # (Haquika ante Jentakus).
            duros = [b for b in libres if hab.tiene_prop(p, b, "indestructible") and hab.fuerza(p, b) > 0 and not arriesga(b)]
            if mata:
                b = mata[0]
            elif duros:
                b = max(duros, key=lambda x: hab.fuerza(p, x))
            else:
                # 2) Intercambio parejo si el atacante vale más.
                iguales = [
                    b for b in libres
                    if hab.fuerza(p, b) == fa and _valor_carta(p, b) <= _valor_carta(p, atk) and not arriesga(b)
                ]
                if iguales and not apurado and _remato_el_proximo_turno(p, yo):
                    continue  # #2 d8bV: Ramsés IX gana atacando el próximo turno; no se cambia
                if iguales:
                    b = iguales[0]
                elif apurado and libres:
                    b = libres[-1]  # 3) Salvar castillo con el más fuerte
                else:
                    continue
            out[atk.uid] = b
            libres.remove(b)
        return out

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        accion = h.get("accion")
        fuente_contexto = getattr(p, "ctx_fuente_habilidad", None)
        marca = getattr(p, "_carnwennan_objetivo", None)
        if accion == "perderHabilidad" and marca and marca[0] == p.e.turno and h.get("duracion") == "hasta_fase_final":
            elegido = [c for c in candidatos if c.uid == marca[1]]
            if elegido:
                p._carnwennan_objetivo = None
                return elegido[:n]
        if accion == "mover" and h.get("zonaDestino") in ("cementerio", "destierro")                 and candidatos and all(c.controlador == yo and c.zona == Zona.MANO for c in candidatos):
            # PYDO #1: Dionisio Zagreo descarta a Gea (vuelve sola desde el
            # Cementerio); Anhur destierra lo que menos vale.
            if h.get("zonaDestino") == "destierro":
                return sorted(candidatos, key=lambda c: (_vale_en_cementerio(c),
                                                         self._valor_descarte(p, yo, c)))[:n]
            return sorted(candidatos, key=lambda c: self._valor_descarte(p, yo, c))[:n]
        if accion == "mover" and h.get("zonaDestino") == "mazo_tope" and p.e.activo == yo \
                and p.e.fase == "vigilia" and all(c.controlador != yo for c in candidatos):
            # FqvR #1: Focea saca al bloqueador para que mi Aliado ataque (y en
            # esa Guerra Focea roba 2); un Tótem lo vuelve a jugar igual.
            mios = [a for a in p.j(yo).aliados if _puede_atacar(p, a) and hab.fuerza(p, a) > 0]
            bloqueadores = [c for c in candidatos if c.zona == Zona.DEFENSA
                            and not hab.tiene_estado(p, c, "no_puede_bloquear")]
            castigan = [c for c in candidatos if c in _castigadores(p, yo)]
            if castigan:
                return castigan[:n]  # PYDO #4: el Apophis primero
            if mios and bloqueadores:
                return sorted(bloqueadores, key=lambda c: -hab.fuerza(p, c))[:n]
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "anillos de badbury" \
                and accion == "barajar":
            # Niamh es la respuesta que neutraliza Orcos; quitarla libera el
            # ataque Imbloqueable antes que devolver un simple +1 de fuerza.
            # P3Cy T6: elegía el de más valor aunque fuera propio (mi Anand en
            # vez del Tom Thumb rival). Primero siempre lo del rival.
            return sorted(candidatos, key=lambda c: (c.controlador == yo, c.nombre.casefold() != "niamh",
                                                     -_valor_vivo(p, c)))[:n]
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "epicuro de samos" \
                and accion == "subirMano":
            # Epicuro vuelve Ganimedes a la mano para repetir su remoción;
            # Teseo ya hizo su daño/entrada y no genera el mismo ciclo.
            return sorted(candidatos, key=lambda c: (
                c is fuente_contexto, c.nombre.casefold() != "ganimedes", c.carta.coste
            ))[:n]
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "ganimedes" \
                and accion == "destruir":
            # Si el arma está portada, sacar al Aliado retira también el arma
            # y evita que vuelva a aprovecharse con otra criatura.
            portadores = {c.portador for c in candidatos if c.tipo == Tipo.ARMA and c.portador}
            sin_armas_portadas = [c for c in candidatos if not (c.tipo == Tipo.ARMA and c.portador in portadores)]
            if sin_armas_portadas:
                candidatos = sin_armas_portadas
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "teseo de atenas" \
                and accion == "destruir":
            # Erec recicla carta(s) al atacar; una vez que Persival ya entró,
            # es un motor más valioso que otro Persival sin efecto pendiente.
            return sorted(candidatos, key=lambda c: (c.nombre.casefold() != "sir erec", -_valor_vivo(p, c)))[:n]
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "orestes" \
                and accion == "buscar":
            # Con Teseo ya listo en mano, Alejandro convierte la b\u00fasqueda en
            # presi\u00f3n de mesa al robar un Aliado rival.
            tengo_teseo = any(c.nombre.casefold() == "teseo de atenas" for c in p.j(yo).mano)
            if tengo_teseo and p.j(1 - yo).aliados:
                return sorted(candidatos, key=lambda c: (
                    c.nombre.casefold() != "alejandro magno", -_valor_carta(p, c)
                ))[:n]
        # Cartas propias que ya se juegan desde donde están (Qer-Her en el
        # Cementerio): no conviene barajarlas, desterrarlas ni buscarlas.
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "haquika" \
                and accion == "ganarControl":
            return sorted(candidatos, key=lambda c: (
                c.nombre.casefold() != "nephre-ka", -_valor_vivo(p, c)
            ))[:n]
        if fuente_contexto is not None and fuente_contexto.nombre.casefold() == "atenas" \
                and accion == "buscar":
            oros = [c for c in candidatos if c.tipo == Tipo.ORO]
            if oros:
                return sorted(oros, key=lambda c: -_valor_carta(p, c))[:n]
        def ya_jugable(c):
            return c.controlador == yo and (
                _zona_de(c) in _se_juega_desde(c) or _recupera_desde_cementerio(c)
            )

        if accion == "perderHabilidad" and any(
            e.get("accion") == "restringirCombate" and e.get("modo") == "no_puede_atacar" for e in h.get("luego") or []
        ):
            # Draco Cometa: al que más daño me hace (Ramsés II: 6 de fuerza y
            # bloquearlo bota 6), que además deja de atacar y de bloquear.
            def dano(c):
                return (max(0, hab.fuerza(p, c)) + _castigo_si_lo_bloquean(p, c) + _amenaza_botar(c)
                        + (3 if hab.tiene_prop(p, c, "imbloqueable") else 0))
            rivales = [c for c in candidatos if c.controlador != yo and not _inhabilitado(p, c)] or \
                [c for c in candidatos if c.controlador != yo]
            return sorted(rivales or candidatos, key=lambda c: -dano(c))[:n]
        if accion == "perderHabilidad" and (h.get("objetivo") or {}).get("quien") != "esta_carta":
            # El mismo criterio que decidió jugarla (Adiós Belleza a Jeroglíficos).
            candidatos = _objetivos_perder_habilidad(p, yo, None, h, objetivos=candidatos) or candidatos

        fuente = getattr(p, "ctx_fuente_habilidad", None)
        if accion == "buscar" and fuente is not None and fuente.nombre.casefold() == "vouivre":
            sin_copia = [c for c in candidatos if not any(x.nombre == c.nombre for x in p.j(yo).mano)]
            if sin_copia:
                candidatos = sin_copia
            return sorted(candidatos, key=lambda c: -_valor_busqueda_vouivre(p, yo, c))[:n]
        if fuente is not None and fuente.nombre.casefold() == "lady calvaur" \
                and fuente.zona == Zona.CEMENTERIO and accion == "destruir":
            # Lady + Ifanc: Oro gratis; Lady + Pútrido: destierro del rival.
            def combo_lady(c):
                if c.nombre.casefold() == "draig ifanc" and any(x.tipo == Tipo.ORO for x in p.j(yo).mazo):
                    return 30
                if c.nombre.casefold() == "draco putrido" and any(
                    x.tipo == Tipo.ALIADO and x.carta.coste <= 4 for x in p.j(1 - yo).aliados
                ):
                    return 29
                return _valor_vivo(p, c)
            return sorted(candidatos, key=combo_lady, reverse=True)[:n]

        if accion == "barajar" and (h.get("objetivo") or {}).get("quien") in ("propio", None):
            fuera = [c for c in candidatos if not c.en_juego]
            fuente = getattr(p, "ctx_fuente_habilidad", None)
            if fuera and "cementerio" in hab.zonas_de(h.get("objetivo") or {}) and not (
                fuente is not None and h.get("grupoLimite")
            ):
                # Cathach/Killgharrah: primero soporte, Talismán, Oro o una
                # pieza que vuelve a barajar; Lady se conserva para recuperarla
                # sacrificando un Dragón desde el Cementerio. m8ii: salvo que
                # tenga La Llama Fría: ahí Lady vuelve al mazo para traerla.
                tutor = _tutor_en_mano(p, yo)
                return sorted(
                    fuera,
                    key=lambda c: (
                        -tutor(c),
                        not (c.nombre.casefold() == "gaspar" and any(
                            a.nombre.casefold() == "vouivre" for a in p.j(yo).aliados
                        )),
                        ya_jugable(c), _recupera_desde_cementerio(c), not _reciclable_prioritario(c),
                        -_valor_carta(p, c),
                    ),
                )[:n]
            if not fuera and candidatos:
                # #7 Zrfq: Vouivre: el que menos pierdo (Draig Ifanc además rampea).
                return sorted(candidatos, key=lambda c: (c is getattr(p, "ctx_fuente_habilidad", None),
                                                         _valor_vivo(p, c) - (4 if _gana_al_morir(c) else 0)))[:n]
            if fuera or h.get("opcional") or h.get("cantidadSegun"):
                # "Tantas como": si no alcanzan, se barajan las que hay.
                # #4 d8bV: con Gaspar, la carta suelta no es un Aliado (esos van de a 2).
                fuente = getattr(p, "ctx_fuente_habilidad", None)
                otra = [x.get("objetivo") or {} for x in (fuente.habilidades if fuente is not None else ())
                        if h.get("grupoLimite") and x.get("grupoLimite") == h.get("grupoLimite")
                        and x.get("cantidad") != h.get("cantidad")]
                # m8ii: con La Llama Fría en la mano, primero vuelve al mazo lo
                # que ella traería y no está ahí (las Lady del Cementerio).
                tutor = _tutor_en_mano(p, yo)
                # mBp5 #2: corto de Oros, primero un Oro (y contra agro, una remoción).
                corto = _faltan_oros(p, yo)
                agro = _mazo_agresivo(p, 1 - yo)

                def recurso(c):
                    if not corto:
                        return 0
                    if c.tipo == Tipo.ORO:
                        return 2
                    return 1 if agro and c.tipo == Tipo.TALISMAN and any(
                        x.get("accion") in _REMOCION for x in c.habilidades) else 0

                def util(c):
                    # mBp5: Gaspar baraja Dragones que remueven o barajan al entrar
                    # (Cathach, Draco Cometa, Magma); los baratos primero.
                    if c.tipo != Tipo.ALIADO:
                        return 0
                    hace = any(x.get("cuando") in ("al_jugar", None) and x.get("accion") in
                               _REMOCION | {"barajar", "perderHabilidad"} for x in c.habilidades)
                    return (2 if c.carta.coste <= 4 else 1) if hace else 0

                vouivre = any(x.nombre.casefold() == "vouivre" for x in p.j(yo).aliados)
                cult_mano = any(any(_cultista(x) for x in m.habilidades) for m in p.j(yo).mano)

                def bucle(c):
                    # Héctor: Gaspar baraja al Cultista para que Vouivre lo traiga.
                    return _OP("GC") and vouivre and not cult_mano and len(p.j(1 - yo).mano) >= 2 \
                        and any(_cultista(x) for x in c.habilidades)

                return sorted(fuera, key=lambda c: (ya_jugable(c), not bucle(c), any(hab.coincide(p, c, o) for o in otra),
                                                    -recurso(c), -(tutor(c)), -util(c), -_valor_carta(p, c)))[:n]
        if accion == "obligarBloqueo":
            return sorted(candidatos, key=lambda c: _prioridad_obligar(p, c), reverse=True)[:n]
        if _rescate_lady(h):
            lady = next((c for c in p.j(yo).cementerio if any(x is h or x == h for x in c.habilidades)), None)
            v = _victima_rescate(p, yo, candidatos, la_juego_ya=_lady_se_juega_ya(p, yo, lady), lady=lady)
            if v is not None and lady is not None and not _sale_con_premio(p, yo, v):
                lady.jugar_ya_turno = p.e.turno  # sacrifiqué otro Dragón: Lady se juega ahora
            if v is not None:
                return [v]  # Lady Calvaur destruye a Draig Ifanc o Draco Pútrido, nunca a otro
        if _es_sacrificio(h):
            # Vouivre: baraja otro Aliado mío, nunca a sí misma.
            fuente = getattr(p, "ctx_fuente_habilidad", None)
            otros = [c for c in candidatos if c is not fuente]
            return sorted(otros or candidatos, key=lambda c: _valor_vivo(p, c) - (4 if _gana_al_morir(c) else 0))[:n]
        if accion in ("destruir", "desterrar", "barajar") and candidatos and not p.atacantes \
                and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera") \
                and all(c.controlador != yo and c.en_juego and c.tipo == Tipo.ALIADO
                        and c.zona != Zona.ATAQUE for c in candidatos):
            # #6 EZMt: Lady destierra al Merodeador y a los Egipcios, no a los
            # Nephre-Ka que ya gastaron su habilidad.
            return sorted(candidatos, key=lambda c: -_peligro(p, c))[:n]
        if accion in ("barajar", "descartar", "desterrar") and candidatos \
                and all(c.controlador != yo and c.zona == Zona.MANO for c in candidatos):
            # #1 UUOX: Cultistas baraja de la mano rival a Ramsés IX, el que remata botando.
            return sorted(candidatos, key=lambda c: -(_valor_carta(p, c) + 3 * _amenaza_botar(c)
                                                      + 3 * _genera_recursos(c) + _peligro_en_mano(p, c)))[:n]
        if candidatos and all(c.controlador == yo and c.zona == Zona.MANO for c in candidatos)                 and accion in ("mover", "descartar", "desterrar"):
            # Anhur / Dionisio: de la mano va lo que menos sirve, mejor si cumple
            # el filtro del "luego" (un Eterno roba 2 más).
            filtros = [e.get("filtroAfectada") or {} for e in h.get("luego") or [] if e.get("relacion") == "si_afectada_cumple"]
            return sorted(candidatos, key=lambda c: (not any(hab.coincide(p, c, f) for f in filtros),
                                                     self._valor_descarte(p, yo, c)))[:n]
        if accion == "restringirCombate" and h.get("modo") in ("no_puede_atacar", "no_puede_bloquear"):
            # Lanza de Osiris: lo que más le quita al rival (ataque y bloqueo).
            return sorted(candidatos, key=lambda c: (
                c.controlador == yo, -_valor_restringir(p, c, h), -hab.fuerza(p, c)))[:n]
        if accion == "repartir":
            # La Odisea: lo mejor a la mano; al Cementerio lo que se juega desde
            # ahí (o lo segundo mejor); al Destierro lo que menos vale.
            destino = h.get("zonaDestino")
            usos = _usos_de_mi_destierro(p, yo)

            def al_destierro(c):
                return any(hab.coincide(p, c, {**o, "quien": None}) for o in usos)
            if destino == "destierro" and any(al_destierro(c) for c in candidatos):
                return sorted(candidatos, key=lambda c: (not al_destierro(c), -_valor_carta(p, c)))[:n]
            if destino == "cementerio":
                # fKRi #5: la Leucrota va al Destierro (Rea la juega), no al Cementerio.
                return sorted(candidatos, key=lambda c: (not _vale_en_cementerio(c), al_destierro(c),
                                                         -_valor_carta(p, c)))[:n]
            if destino == "mano" and len(candidatos) >= 3:
                # ZsfY #2: Rea va al Destierro (la otra Rea en mano la juega
                # gratis) y el Homunculus al Cementerio: a la mano, la Caja.
                otros = [c for c in candidatos if not al_destierro(c) and not _vale_en_cementerio(c)]
                if otros:
                    return sorted(otros, key=lambda c: -self._valor_conservar(p, yo, c))[:n]
            orden = sorted(candidatos, key=lambda c: -self._valor_conservar(p, yo, c))
            return (orden[-n:] if destino == "destierro" else orden[:n])
        if accion == "mirarTope":
            if _TOPE_SIN_REPETIDOS:
                # Héctor 2026-11-12 (19965 T8): Dragones es errante y ya tengo
                # uno en mesa: mejor el Cinturón. Bajo presión, el Codex.
                def tope(c):
                    v = _valor_carta(p, c)
                    if hab.tiene_prop(p, c, "errante") and any(
                            x.nombre == c.nombre for x in p.e.instancias_en_juego(yo)):
                        v -= 100
                    if c.tipo == Tipo.ORO and _oro_defiende(c) and _en_peligro(p, yo):
                        v += 50
                    return v
                return sorted(candidatos, key=lambda c: -tope(c))[:n]
            return sorted(candidatos, key=lambda c: -_valor_carta(p, c))[:n]  # Tadg: la mejor
        if accion == "elegir":
            # Amergin: el Druida de más fuerza (el rival bota tanto como ella).
            return sorted(candidatos, key=lambda c: -(hab.fuerza(p, c) if c.en_juego else c.carta.fuerza))[:n]
        if accion == "ganarControl":
            return sorted(candidatos, key=lambda c: -_valor_robar(p, yo, c))[:n]
        if accion == "buscar" and (h.get("costo") or {}):
            permitidos = [c for c in candidatos if not hab.prohibido(p, "jugar_tipo", yo, c)]
            candidatos = permitidos or candidatos
        if accion == "modificarFuerza" and p.atacantes:
            # #49: primero a quien el cambio le da vuelta su pelea (Jentakus
            # bloqueado por Djedefhor), después el resto de los combatientes.
            cambio = int(h.get("valor", 0))
            enemigo = cambio < 0
            pelean = _combatientes(p)
            return sorted(
                candidatos,
                key=lambda c: (
                    (c.controlador == yo) == enemigo, not _decisivo(p, c, cambio), c.uid not in pelean,
                    -_valor_carta(p, c),
                ),
            )[:n]
        if accion == "buscar" and all(c.tipo == Tipo.ALIADO for c in candidatos):
            # #19: Jentakus no busca siempre a Ramsés: lo que arma combo con la
            # mesa (Ay si tengo Amyrteos; Amyrteos si tengo Ay) y nada que el
            # rival anule a la vista.
            return sorted(candidatos, key=lambda c: -_valor_para_el_plan(p, yo, c))[:n]
        if accion == "jugarDesde" and candidatos and all(c.tipo == Tipo.ARMA for c in candidatos):
            corto = len(p.j(yo).mazo) <= 12

            def arma(c):
                baraja = any(x.get("accion") == "barajar" for x in c.habilidades)
                bota = any(x.get("accion") == "botar" for x in c.habilidades)
                return (baraja if corto else bota), c.carta.coste

            return sorted(candidatos, key=arma, reverse=True)[:n]
        if accion == "jugarDesde":
            from .motor import Jugada

            # #77: la que más rinde al jugarse ahora (Haquika sobre Djedefhor).
            if _aliado_temporal(h):
                # Cruz Templaria: el Aliado se destierra en la Fase Final; vale
                # solo por lo que hace al entrar (Magma, Nival, Lady Calvaur).
                candidatos = [c for c in candidatos if _saca_una_amenaza(p, yo, c)] or candidatos
            def ataca_ya(c):
                # Xerxes en mi Vigilia: lo que entra y ataca este turno suma su fuerza.
                fuente_j = getattr(p, "ctx_fuente_habilidad", None)
                if p.e.activo != yo or p.e.fase != "vigilia" or c.tipo != Tipo.ALIADO                         or fuente_j is None or fuente_j.tipo != Tipo.ALIADO:
                    return 0.0  # solo un Aliado que entra y trae otro (Xerxes); no La Llama Fría
                furia = hab.tiene_prop(p, c, "furia") or any(
                    h.get("cuando") == "al_jugar" and h.get("modo") == "puede_atacar_este_turno"
                    and hab.condicion_ok(p, yo, h) for h in c.habilidades) or any(
                    h.get("cuando") == "continua" and h.get("modo") == "puede_atacar_este_turno"
                    for a in p.e.instancias_en_juego(yo) for h in a.habilidades)
                return 1.5 * c.carta.fuerza if furia else 0.0
            return sorted(candidatos, key=lambda c: -(self._puntaje(p, yo, Jugada("jugar", c)) + ataca_ya(c)))[:n]
        if accion == "restringirCombate" and h.get("modo") in ("no_puede_atacar", "no_puede_bloquear"):
            def amenaza(c):
                if c.tipo != Tipo.ALIADO:
                    return _valor_carta(p, c)
                dano = any(x.get("cuando") == "al_hacer_dano" for x in c.habilidades)
                return (_valor_carta(p, c) + (4 if hab.tiene_prop(p, c, "imbloqueable") else 0)
                        + (3 if dano else 0))
            return sorted(candidatos, key=lambda c: (c.controlador == yo, -amenaza(c)))[:n]
        if accion == "subirMano" and all(c.controlador == yo for c in candidatos) \
                and h.get("cuando") in ("al_jugar", "activada"):
            # Montuhopet II / Epicuro: se sube el que más gana al volver a jugarse.
            return sorted(candidatos, key=lambda c: -_valor_de_rejugar(p, yo, c))[:n]
        if accion == "ponerEnJuego" and all(c.tipo == Tipo.ORO for c in candidatos):
            corto = len(p.j(1 - yo).mazo) <= 15
            # Perdiendo la mesa, un Oro que me defiende (Jeroglíficos sube a la
            # mano a un atacante) antes que uno que bota.
            fuerza = lambda q: sum(max(0, hab.fuerza(p, a)) for a in p.j(q).aliados)  # noqa: E731
            perdiendo = fuerza(1 - yo) > fuerza(yo)
            defiende = _oro_defiende

            ya = {x.nombre for x in p.j(yo).reserva + p.j(yo).pagado}

            def oro_util(c):  # #129: con el rival corto, un Papiros que bota
                bota = sum(int(x.get("cantidad", 1)) for x in c.habilidades if x.get("accion") == "botar")
                util = sum(1 for x in c.habilidades if x.get("accion") != "errante")
                # fKRi #2: el Aceite de Oliva trae La Ilíada (bonifica cada turno).
                cada_turno = 0 if c.nombre in ya else 4 * sum(
                    1 for x in c.habilidades if _habilidad_repetible(x) and int(x.get("limitePorTurno", 0) or 0) >= 1)
                return bota * (2 if corto else 0.5) + util + (4 if perdiendo and defiende(c) else 0) + cada_turno

            return sorted(candidatos, key=lambda c: -oro_util(c))[:n]
        if accion == "buscar" and candidatos and all(c.tipo == Tipo.ORO for c in candidatos):
            clave = [c for c in candidatos if _oro_que_acelera_ataques(c)
                     and not any(x.nombre == c.nombre for x in p.j(yo).reserva + p.j(yo).pagado + p.j(yo).mano)]
            if clave:
                return clave[:n]  # #1 Zrfq: la Corona Faraónica es la llave del Faraón guerrero
            if h.get("zonaDestino") == "reserva_oro" and _oros_indestructibles(p, yo):
                # #2 3W4d: con la Corona de Arturo en juego, Mercaderes bloquea
                # cada turno sin morir.
                merc = [c for c in candidatos if any(x.get("accion") == "convertirEnAliado" for x in c.habilidades)]
                if merc:
                    return merc[:n]
            fuente_buscar = getattr(p, "ctx_fuente_habilidad", None)
            if h.get("zonaDestino") == "reserva_oro" and fuente_buscar is not None \
                    and fuente_buscar.tipo == Tipo.TALISMAN and _juntando_oros(p, yo) \
                    and len(p.j(yo).mazo) > 20 and not _en_peligro(p, yo):
                # 1uF1 #2: Alquimista juntando Oros trae Estrella de Belén (al
                # entrar busca otro Oro): así llego a 5 para La Llama Fría y Lady.
                cavan = [c for c in candidatos if any(
                    x.get("cuando") in ("al_jugar", None) and x.get("accion") in ("mirarTope", "buscar")
                    and "Oro" in ((x.get("objetivo") or {}).get("tipos") or []) for x in c.habilidades)]
                if cavan:
                    return cavan[:n]
            if h.get("zonaDestino") == "reserva_oro" and (_rival_agro(p, yo) or _mazo_agresivo(p, 1 - yo)):
                # ZOlJ / #2 3W4d: contra agro (en mesa o por su mazo), Draig
                # Ifanc se trae el Codex Arturicus (daño a 0).
                defensa = [c for c in candidatos if _oro_defiende(c)
                           and not any(x.nombre == c.nombre for x in p.e.instancias_en_juego(yo))]
                if defensa:
                    return sorted(defensa, key=lambda c: not any(
                        x.get("accion") in ("reducirDano", "cancelarAtaque") for x in c.habilidades))[:n]
        if accion == "buscar" and candidatos and any(c.tipo == Tipo.ORO for c in candidatos) \
                and not all(c.tipo == Tipo.ORO for c in candidatos):
            # fKRi #3: Atenas busca La Ilíada antes que Ave de Hera.
            ya = {x.nombre for x in p.j(yo).reserva + p.j(yo).pagado + p.j(yo).mano}
            clave = [c for c in candidatos if c.tipo == Tipo.ORO and c.nombre not in ya and any(
                _habilidad_repetible(x) and int(x.get("limitePorTurno", 0) or 0) >= 1 for x in c.habilidades)]
            if clave:
                return clave[:n]
        if accion == "buscar" and candidatos and all(c.tipo == Tipo.ORO for c in candidatos):
            # ZsfY #1: Luz de Prometeo en el Titán trae La Ilíada (+2 cada turno).
            en_juego = {x.nombre for x in p.j(yo).reserva + p.j(yo).pagado + p.j(yo).mano}

            def repetible(c):  # La Ilíada (una vez por turno) > Piedra Roseta > Rito de Aton (se destierra)
                return sum(2 if int(x.get("limitePorTurno", 0) or 0) >= 1 else 1
                           for x in c.habilidades if _habilidad_repetible(x))
            return sorted(candidatos, key=lambda c: (c.nombre in en_juego, -repetible(c)))[:n]
        if accion in _BENEFICIO_PROPIO or (accion == "modificarFuerza" and int(h.get("valor", 0)) >= 0):
            peligro = accion == "buscar" and _en_peligro(p, yo)

            def bota(c):  # #87: Jinetes de Fuego o Mercado Egipcio, que hacen daño
                return accion == "buscar" and c.tipo == Tipo.TALISMAN and any(
                    x.get("accion") == "botar" for x in c.habilidades
                )

            def gana(c):  # #126: Mercado Egipcio con 6 Oros ante un castillo de 1
                return accion == "buscar" and c.tipo == Tipo.TALISMAN and sum(
                    hab.cantidad(p, yo, x, [], lado=1 - yo) for x in c.habilidades
                    if x.get("accion") == "botar" and x.get("cuando") in ("al_jugar", None)
                ) >= len(p.j(1 - yo).mazo)

            sin_combate = accion == "modificarFuerza" and not p.atacantes
            orden = sorted(
                candidatos,
                key=lambda c: (
                    c.controlador != yo, sin_combate and not _ataca_este_turno(p, c),  # #8 Zrfq
                    not gana(c), not (peligro and _defensivo(c)), not bota(c), ya_jugable(c),
                    -_motor_de_cartas(c), -_valor_carta(p, c),
                ),
            )
        else:
            # #4 0VzQ / #121: el Arma se va con su portador; sacar el Arma sola
            # le deja el Aliado (y Nuh la vuelve a traer).
            uids = {c.uid for c in candidatos}
            sin_armas = [c for c in candidatos if not (c.tipo == Tipo.ARMA and c.portador in uids)]
            candidatos = sin_armas or candidatos
            # En combate, primero lo que de verdad cambia la batalla (#18).
            combatientes = _combatientes(p)

            # El de mayor impacto en la partida ahora (combate, Aliado salvado,
            # carta mía recuperada…), no el más caro.
            orden = sorted(
                candidatos,
                key=lambda c: (
                    c.controlador == yo, ya_jugable(c),
                    # Héctor 2026-11-12: Bola de Fuego no a Kawit sin Arma ni a Werin.
                    fuente_contexto is not None and fuente_contexto.tipo == Tipo.TALISMAN
                    and accion in ("destruir", "desterrar") and not _vale_un_talisman(p, yo, c),
                    # Guardia Gozosa (quita la habilidad y destruye) a Haquika: el
                    # Aliado que robó no vuelve. Mejor otro objetivo.
                    accion == "perderHabilidad" and c.controlador != yo and any(
                        x.get("accion") == "ganarControl" for x in c.carta.habilidades),
                    # Lady, Bola, Magma: primero lo que da recursos o daño cada turno
                    # (Haquika, Demoledor, Nuh), salvo un combate que cambiar ya.
                    not (accion in ("destruir", "desterrar") and c.controlador != yo
                         and c.uid not in combatientes and _anular_siempre(p, c)),
                    # Lady Calvaur vuelve desde el Cementerio; si hay otro
                    # objetivo útil, no regalarle esa recuperación al rival.
                    accion in ("destruir", "desterrar") and _recupera_desde_cementerio(c),
                    # Ganimedes: mi Constantino robado vuelve si saco a Haquika;
                    # destruirlo es perderlo.
                    accion in ("destruir", "desterrar") and c.dueno == yo and c.controlador != yo,
                    -_impacto_quitar(p, yo, c), -_valor_carta(p, c),
                ),
            )
        return orden[:n]

    def elegir_descartes(self, p, yo, mano, n):
        oros_mano = sum(1 for c in mano if c.tipo == Tipo.ORO)
        return sorted(mano, key=lambda c: self._valor_descarte(p, yo, c, oros_mano))[:n]

    def elegir_destierro_costo(self, p, yo, fuente, disponibles, n):
        if fuente.nombre.casefold() == "escarabeo":
            disponibles = [c for c in disponibles if c.nombre.casefold() != "qer-her"]
            prioritarios = [c for c in disponibles if _recupera_desde_cementerio(c)
                            or c.nombre.casefold() == "vouivre"]
            if prioritarios:
                return sorted(prioritarios, key=lambda c: -_valor_carta(p, c))[:n]
        usos_destierro = _usos_de_mi_destierro(p, yo)
        if usos_destierro and all(c.zona == Zona.CEMENTERIO for c in disponibles):
            # FqvR #4: Rea juega gratis desde el Destierro un Titán u Olímpico:
            # el Homunculus destierra esos Aliados (el mejor primero), después
            # otros Aliados, y guarda Oros y soporte.
            def sirve(c):
                return any(hab.coincide(p, c, {**o, "quien": None}) for o in usos_destierro)
            return sorted(disponibles, key=lambda c: (
                _vale_en_cementerio(c), not sirve(c),
                {Tipo.ALIADO: 0, Tipo.TALISMAN: 1, Tipo.ARMA: 2, Tipo.TOTEM: 3}.get(c.tipo, 4),
                -_valor_carta(p, c) if sirve(c) else _valor_carta(p, c)))[:n]
        # qSMg #2: del Cementerio se destierra primero lo que no se juega ni se
        # recupera desde ahí (la Furia Irracional y Jinetes se quedan).
        return sorted(disponibles, key=lambda c: (_vale_en_cementerio(c), _valor_carta(p, c)))[:n]

    def _valor_descarte(self, p, yo, c, oros_mano=None) -> float:
        v = self._valor_descarte_base(p, yo, c, oros_mano)
        if c.en_juego:
            return v
        rival_mesa = _CORRECCIONES_19965 and any(not _neutralizado(p, a) for a in p.j(1 - yo).aliados)
        remo = c.tipo != Tipo.ORO and (_remocion_al_entrar(c) or any(
            h.get("accion") == "cancelarHabilidad" for h in c.habilidades))
        if rival_mesa and remo:
            v += 6.0  # Héctor: Gozosa y Desafiar a Arturo no se tiran con mesa rival
        elif _CORRECCIONES_2 and remo:
            v += 4.0  # Héctor (2376 T1/T3): la Bola contra estos mazos se guarda
        if _CORRECCIONES_2 and any(_rescate_lady(h) for h in c.habilidades) and not p.puede_pagar(yo, c) \
                and any(x.nombre.casefold() in ("draig ifanc", "draco putrido")
                        for x in list(p.j(yo).mano) + list(p.j(yo).aliados) if x is not c):
            v = min(v, 0.5)  # Héctor (97465 T4/T8): con Ifanc, Lady al Cementerio arma el combo
        return v

    def _valor_descarte_base(self, p, yo, c, oros_mano=None) -> float:
        fuente = getattr(p, "ctx_fuente_habilidad", None)
        if fuente is not None and fuente.nombre.casefold() == "ramsés ii":
            if c.nombre.casefold() == "nephre-ka":
                return -3.0
            if c.nombre.casefold() == "forma de lince" and len(p.j(yo).mano) <= 4:
                return 20.0
        if c.nombre.casefold() == "lady calvaur" and p.puede_pagar(yo, c):
            return 100.0  # se puede bajar ahora: no se descarta por exceso de mano
        if c.nombre.casefold() == "idmon el adivino":
            return 24.0  # motor de alto techo: no se pierde por exceso de mano
        if hab.tiene_prop(p, c, "errante") and any(
            x is not c and x.nombre == c.nombre for x in p.j(yo).mano
        ):
            return -2.0  # una segunda copia no se juega con la primera en mano
        if c.tipo == Tipo.ORO:
            # Sobran Oros cuando ya hay muchos en juego.
            if oros_mano is None:
                oros_mano = sum(1 for x in p.j(yo).mano if x.tipo == Tipo.ORO)
            oros_juego = len(p.j(yo).reserva) + len(p.j(yo).pagado)
            if oros_mano <= 1 and oros_juego < 7 and not _remate_en_marcha(p, yo):
                return 12.0  # FtbJ #2: el único Oro para el próximo turno se guarda
            if oros_mano <= 3 and oros_juego + oros_mano <= 6 and not _remate_en_marcha(p, yo):
                return 10.0  # tuK8 #1: con 2 Oros en juego, los 3 de la mano hacen falta
            if oros_mano > 3:
                # Solo sobran con más de 3 Oros en la mano. Aun así, su
                # habilidad sigue sirviendo (Papiros de Lahun bota 3): vale
                # más que un Escudo Miliciano que vuelve.
                return 1.5 * sum(1 for h in c.habilidades if h.get("accion") != "errante")
            return 5
        if any(_rescate_lady(h) for h in c.habilidades) and _capacidad_lady(p, yo, extra=1):
            return 25.0  # #2 EZMt: ya alcanzo a pagar a Lady (o el próximo turno): se guarda en la mano
        if _descarte_gratis(p, yo, c):
            return 0.5  # Escudo Miliciano: descartarlo casi no cuesta, se juega desde ahí
        if any(hab.zona_activacion(h) == "cementerio" for h in c.habilidades):
            return 1.0  # lKff #2 / PYDO #1: Homunculus y Gea se barajan desde el Cementerio
        if c.en_juego and _pieza_clave(c):
            return 50.0  # pagar un costo con el candado (Neferite, Ptolomeo II): último recurso
        if c.en_juego and c.tipo == Tipo.ALIADO and any(
                h.get("cuando") == "al_salir_del_juego" and h.get("accion") in ("buscar", "robar")
                and (h.get("objetivo") or {}).get("quien", "propio") == "propio" for h in c.habilidades):
            return 0.5  # Ay destierra a Roxana: al salir busca un Oro
        # Lo que haría ahora: Akhet con Cleopatra en la mesa rival vale
        # mucho; Quemar los Templos sin Armas que quemar, poco.
        v = _valor_carta(p, c) + max(0.0, _valor_remocion_al_entrar(p, yo, c))
        if any(x is not c and x.carta.id == c.carta.id for x in p.j(yo).mano):
            v -= 3.0  # conservar variedad y un Oro para el próximo turno
        habs = [h for h in c.habilidades if h.get("cuando") in ("al_jugar", None) and hab._necesita_objetivo(h)]
        if c.tipo != Tipo.ALIADO and habs and not any(hab.candidatos_validos(p, yo, c, h) for h in habs):
            # Sin objetivo ahora: una remoción (Akhet) lo tendrá cuando el rival
            # juegue algo; lo demás sí pierde valor.
            # mBp5 #1: Bola de Fuego ("una carta en juego", de cualquiera) también
            # es una remoción; contra un mazo agro vale todavía más guardarla.
            quita_al_rival = all(
                (h.get("objetivo") or {}).get("quien") == "oponente"
                or ((h.get("objetivo") or {}).get("quien") == "cualquiera"
                    and "Aliado" in ((h.get("objetivo") or {}).get("tipos") or []))
                for h in habs
            )
            v += 1.0 if quita_al_rival else -3.0  # una remoción barata vale guardarla
            if quita_al_rival and _mazo_agresivo(p, 1 - yo) and any(h.get("accion") in _REMOCION for h in habs):
                v += 3.0
        elif c.tipo == Tipo.ALIADO and any(
                h.get("cuando") == "al_jugar" and h.get("accion") in _REMOCION
                and (h.get("objetivo") or {}).get("quien") == "oponente" for h in habs) \
                and _valor_remocion_al_entrar(p, yo, c) <= 0:
            v += 3.0  # tuK8 #1: Ganimedes sin blanco aún lo tendrá; no se bota por exceso
        v += _valor_a_futuro(p, yo, c)
        return v

    def _valor_conservar(self, p, yo, c) -> float:
        """Qué tan bueno es tener esta carta en la mano. Una remoción al entrar
        (Focea) vale según los Aliados del mazo rival (Haquika del Sacerdote)."""
        v = self._valor_descarte(p, yo, c)
        if any(x.get("cuando") in ("al_jugar", None) and x.get("accion") in ("destruir", "desterrar", "subirMano", "mover", "barajar")
               and (x.get("objetivo") or {}).get("quien") == "oponente" for x in c.habilidades):
            rival = p.j(1 - yo)
            v += 0.8 * max((_valor_carta(p, a) for a in rival.mazo + rival.mano + rival.aliados if a.tipo == Tipo.ALIADO),
                           default=0)
        return v

    def tope_o_fondo(self, p, yo, cartas):
        """Nacimiento de Pegaso: las dejo arriba (y las robo) si sirven."""
        if not cartas:
            return "mazo_tope"
        promedio = sum(_valor_carta(p, c) for c in cartas) / len(cartas)
        return "mazo_tope" if promedio >= 4 else "mazo_fondo"

    def elegir_portador(self, p, yo, arma, portadores):
        """Escudo Miliciano desde el Cementerio en el turno rival: al Aliado
        que va a bloquear (el que atacó el turno anterior no bloquea)."""
        if p.e.activo != yo:
            bloquean = [
                a for a in portadores
                if a.controlador == yo and a in p.j(yo).defensa and not hab.tiene_estado(p, a, "no_puede_bloquear")
            ]
            # Las piezas del candado no bloquean: el Escudo va al que sí lo hará.
            bloquean = [a for a in bloquean if not _pieza_clave(a)] or bloquean
            if bloquean:
                return max(bloquean, key=lambda a: (_valor_defensivo_arma(p, yo, arma, a), hab.fuerza(p, a)))
        elif p.e.fase == "vigilia":
            # En mi Vigilia, el Arma va a un Aliado que ataca este turno (Mandoble
            # en Kawit, no en el Nuh que recién entra; además le quita foco a Nuh).
            atacan = [a for a in portadores if a.controlador == yo and a.listo and _puede_atacar(p, a)]
            if atacan:
                portadores = atacan
        return self.elegir_objetivos(p, yo, portadores, 1, {"accion": "modificarFuerza", "valor": 1})[0]

    def prevenir_conviene(self, p, yo, fuente, h, t, efecto):
        """Ptolomeo II: no paga (botar 3) por un Aliado que muere igual en este
        combate; si el efecto lo sube a la mano, hasta lo salva."""
        if t.tipo == Tipo.ALIADO and _muere_en_combate(p, t):
            return False
        if h.get("modo") == "barajar_mazo":
            # Amkh se destruye: vale la pena por lo que pesa en la mesa.
            return t.tipo != Tipo.ORO and (t.carta.coste >= 3 or _valor_carta(p, t) >= 4)
        return self.usar_opcional(p, yo, fuente, h)

    def preferir_alternativo(self, p, yo, fuente, h):
        """#120: Ramsés II: con la mano corta, pagar 1 Oro antes que descartar
        (las cartas en la mano son recursos)."""
        alt = h.get("costoAlternativo") or {}
        principal = h.get("costo") or {}
        if principal.get("descartar") and alt.get("oros") and not alt.get("descartar"):
            if any(_descarte_gratis(p, yo, c) for c in p.j(yo).mano if c is not fuente):
                return False  # Ramsés II: descarto el Escudo Miliciano, que vuelve desde el Cementerio
            return len(p.j(yo).mano) <= 4 and p.j(yo).oro_disponible >= int(alt["oros"])
        if principal.get("botar") and alt.get("oros") and not alt.get("botar"):
            # Ptolomeo II: 1 Oro antes que botar 3 (el castillo es la vida).
            return p.j(yo).oro_disponible >= int(alt["oros"]) and not _remate_en_marcha(p, yo)
        return False

    def usar_opcional(self, p, yo, fuente, h):
        c = h.get("costo") or {}
        if fuente.nombre.casefold() == "sir erec" and h.get("grupoElegir") == "erec":
            caballeros = [x for x in p.j(yo).cementerio if x.tipo == Tipo.ALIADO and x.raza == "Caballero"]
            # "una carta o dos Caballeros": si están los dos, el reciclaje
            # doble es el plan; la primera opción no debe cerrarlo.
            return (int(h.get("cantidad", 1) or 1) >= 2) if len(caballeros) >= 2 else True
        if fuente.nombre.casefold() == "focea" and h.get("accion") == "robar" \
                and p.e.fase == "guerra_talismanes":
            return True  # convierte daño/combate en dos cartas y filtrado de mano
        if h.get("accion") == "robar" and fuente.tipo == Tipo.ORO and any(
                (x.get("costo") or {}).get("barajarEstaCarta") for x in fuente.habilidades):
            return True  # FqvR #5: Trono Dorado se barajó primero: el robo deja el castillo igual
        if _robo_suicida(p, yo, h) or _robo_obliga_a_descartar(p, yo, h):
            return False
        if _vinculo(h) and _VINCULO_FRENA and _vinculo_frena(p, yo):
            return False  # bajar el Aliado vale más que robar 2 y descartar 1
        if _vinculo(h) and not _robo_suicida(p, yo, h):
            return True  # turno 1 y después: Vínculo filtra la mano
        if (c.get("oros") or c.get("pagarEstaCarta")) and _remate_en_marcha(p, yo):
            return False  # #136: los Oros van al remate (Mandoble + Papiros)
        if c.get("botar") and int(c["botar"]) >= len(p.j(yo).mazo) - 2:
            return False  # no se mata a sí mismo
        if h.get("accion") == "reducirDano" and fuente.tipo == Tipo.ORO and (c.get("desterrarEstaCarta") or c.get("destruirEstaCarta")):
            # #8 UUOX: el Codex (un solo uso) se guarda para un daño crítico.
            dano, castillo = int(h.get("_dano", 0) or 0), len(p.j(yo).mazo)
            # 3W4d: quedar fuera del alcance del rival en su próximo turno:
            # Papiros + Jinetes de Fuego (con 6 Oros, 9 sin atacar) más su mesa.
            rango = _quemado_rival(p, yo) + sum(max(0, hab.fuerza(p, a)) for a in p.j(1 - yo).aliados)
            if _juntando_oros(p, yo):
                return dano >= castillo or castillo - dano <= max(5, rango)  # el Oro vale más que unas cartas
            if _CODEX_MINIMO and dano <= 2 and dano < castillo:
                return False  # un solo uso: se guarda para un golpe que importe
            return dano >= castillo or castillo - dano <= max(8, rango) or dano >= 10
        if h.get("grupoElegir") and h.get("accion") == "descartar"                 and (h.get("objetivo") or {}).get("quien") == "propio":
            # Sonriente: "descarta una carta o bota 3": descartar si sobra mano.
            return len(p.j(yo).mano) >= 2 or len(p.j(yo).mazo) <= 8
        if _es_sacrificio(h):
            # #7 Zrfq: Vouivre baraja a Draig Ifanc y 2 Aliados rivales; #5 UUOX: nunca a sí misma.
            return _sacrificio_que_remueve(p, yo, fuente, h)
        if _cultista(h):
            return _cultista_tiene_mano(p, yo)
        if h.get("grupoElegir") and h.get("accion") == "modificarFuerza" \
                and (h.get("objetivo") or {}).get("quien") == "esta_carta":
            # m8ii #1: Guerrero Bereber: +2 a otro Guerrero, salvo que sea el
            # único o que el +1 lo salve (un bloqueador rival de su misma fuerza).
            otras = [x for x in fuente.habilidades if x is not h and x.get("grupoElegir") == h.get("grupoElegir")
                     and [c for c in hab.candidatos_validos(p, yo, fuente, x) if c is not fuente]]
            if otras:
                f = hab.fuerza(p, fuente)
                bloqueadores = [b for b in p.j(1 - yo).defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")]
                atacantes = len(p.atacantes) or sum(1 for a in p.j(yo).aliados if a.zona == Zona.ATAQUE)
                if atacantes > len(bloqueadores):
                    return False  # i4b3 #4: 7 atacantes y 1 bloqueador: +2 a los Egipcios
                return any(hab.fuerza(p, b) == f for b in p.j(1 - yo).defensa
                           if not hab.tiene_estado(p, b, "no_puede_bloquear"))
        if _rescate_lady(h):
            return _rescate_conviene(p, yo, fuente, h)
        if h.get("accion") == "mostrar" and any(
            e.get("accion") == "barajar" and "cementerio" in hab.zonas_de(e.get("objetivo") or {})
            for e in h.get("luego") or []
        ):
            return bool(p.j(yo).cementerio)  # #1 ZOlJ: Látigo y Bastón sin nada que barajar no muestra
        if c.get("destruirEstaCarta") and h.get("accion") != "prevenir" and fuente.tipo == Tipo.ALIADO:
            return False  # no sacrifica un Aliado por un efecto menor
        return self._objetivo_util(p, yo, fuente, h)

    def responder(self, p, yo, carta, opciones):
        """#57 / #82: Resplandor de Heka contra lo que importa en la mesa
        (Haquika que me roba un Aliado, Djedefhor que roba 2 con poca mano)."""
        # Resplandor además me da una carta: responde con menos que una
        # anulación, pero solo contra el impacto de entrada. Una habilidad
        # futura (Werin al salir) no justifica perderlo antes de Haquika.
        if _motor_activable(p, carta):
            return 0  # Nuh: le quito para siempre un Arma gratis por turno
        for k, (_, h) in enumerate(opciones):
            if h.get("accion") in ("barajar", "destruir", "desterrar", "subirMano") \
                    and (h.get("objetivo") or {}).get("quien") == "disparadora":
                # #10 c0p0: la Capa saca la carta entera: vale contra el Medjay.
                return k if _amenaza_que_entra(p, carta) else None
        if _importancia(p, carta.controlador, carta, solo_al_jugar=True) < _UMBRAL_ANULAR - 1:
            return None
        return 0

    def elegir_carta(self, p, yo, nombres):
        """Nombrar una carta (Sir Bedivere, Takelot): el Aliado rival que vi en
        su mano o, si no, el que más copias tiene entre su mano y su mazo."""
        rival = p.j(1 - yo)
        # Bedivere corta la amenaza que el HÃ©roe puede bajar: no desperdicia
        # el nombre en un Oro como Ave de Hera.
        for prioridad in ("teseo de atenas", "alejandro magno"):
            halladas = [n for n in nombres if n.casefold() == prioridad]
            if halladas:
                return halladas[0]
        vistos = [c.nombre for c in rival.mano if getattr(c, "revelada", False) and c.tipo == Tipo.ALIADO]
        cuenta = {}
        for c in rival.mano + rival.mazo + rival.aliados:
            if c.tipo == Tipo.ALIADO and c.nombre in nombres:
                cuenta[c.nombre] = cuenta.get(c.nombre, 0) + 1 + _valor_carta(p, c) / 10
        for n in vistos:
            if n in nombres:
                return n
        return max(cuenta, key=cuenta.get) if cuenta else self.rng.choice(nombres) if hasattr(self, "rng") else nombres[0]

    def elegir_opcion(self, p, yo, fuente, opciones):
        """Nuada: "debes destruir uno de tus Aliados o botar 3". Con castillo
        sano se bota; corto, se entrega el Aliado que menos vale."""
        def costo(x):
            quien = (x.get("objetivo") or {}).get("quien")
            # Loch Lein: la elige quien la sufre ("tu oponente debe elegir").
            victima = quien == "oponente" and fuente.controlador != yo
            if x.get("accion") == "botar" and (quien == "propio" or victima):
                n = int(x.get("cantidad", 1) or 1)
                return 99 if len(p.j(yo).mazo) - n <= max(2, _alcance_rival(p, yo)) else n * 1.2
            if x.get("accion") == "descartar" and victima:
                return 98 if not p.j(yo).mano else 2.5  # sin mano no es una opción posible
            if x.get("accion") in ("destruir", "desterrar") and (x.get("objetivo") or {}).get("quien") == "propio":
                cands = [c for c in hab.candidatos_validos(p, yo, fuente, x) if c is not fuente] or                     hab.candidatos_validos(p, yo, fuente, x)
                return min((_valor_vivo(p, c) for c in cands), default=99)
            return 5.0
        return min(range(len(opciones)), key=lambda k: costo(opciones[k]))

    def cancelar_habilidad(self, p, yo, fuente, h, opciones):
        """#2 ZiXU: Siete contra Tebas contra lo que me saca cartas (Djoser
        destruye, Akhet, Ramsés IX bota) o le da mucho al rival (roba 2,
        Escudo Miliciano baraja su Cementerio)."""
        accion = h.get("accion")
        obj = h.get("objetivo") or {}
        rival = 1 - yo
        n = int(h.get("cantidad", 1) or 1)
        vale = False
        if accion in _REMOCION | {"barajar", "perderHabilidad", "restringirCombate"} \
                and obj.get("quien") in ("oponente", "cualquiera", "ambos") \
                and "en_juego" in hab.zonas_de(obj):
            vale = any(c.controlador == yo for c in hab.candidatos_validos(p, rival, fuente, h))
        elif accion in ("botar", "descartar") and obj.get("quien") in ("oponente", "ambos"):
            vale = n >= 2 or len(p.j(yo).mazo) <= 10
        elif accion in ("robar", "buscar", "jugarDesde", "ponerEnJuego", "generarOro") \
                and obj.get("quien", "propio") == "propio":
            vale = n >= 2 or accion in ("jugarDesde", "ponerEnJuego")
        elif accion == "barajar" and obj.get("quien") == "propio" and "cementerio" in hab.zonas_de(obj):
            vale = n >= 2  # Escudo Miliciano: le devuelve 2 cartas al castillo
        elif accion == "modificarFuerza" and int(h.get("valor", 0) or 0) >= 2 and p.atacantes:
            vale = True  # cambia un combate
        if not vale and sum(int(e.get("cantidad", 1) or 1) for e in h.get("luego") or []
                            if e.get("accion") == "robar") >= 2:
            vale = True  # ZsfY #3: Anhur roba 1 + 2 más
        solo_carn = all(o[1].get("accion") == "perderHabilidad" for o in opciones)
        if any(o[1].get("accion") == "perderHabilidad" for o in opciones):
            # Carnwennan es clave (Héctor): solo contra lo que cambia la partida.
            clave = accion in ("obligarBloqueo", "ganarControl") or (
                accion in ("botar", "descartar") and obj.get("quien") in ("oponente", "ambos") and n >= 3) or (
                accion in _REMOCION and any(c.controlador == yo and _valor_vivo(p, c) >= 4
                                            for c in hab.candidatos_validos(p, rival, fuente, h)))
            if solo_carn and not clave:
                return None
            if clave:
                vale = True
                if solo_carn:
                    return 0
        if not vale:
            return None
        opciones_ok = [k for k in range(len(opciones)) if opciones[k][1].get("accion") != "perderHabilidad"]
        if opciones_ok:
            return min(opciones_ok, key=lambda k: (opciones[k][0].zona != Zona.MANO, opciones[k][0].carta.coste))
        # Primero un Talismán de la mano; una carta en juego (Flidais) se pierde.
        return min(range(len(opciones)), key=lambda k: (opciones[k][0].zona != Zona.MANO, opciones[k][0].carta.coste))

    def anular(self, p, yo, carta, opciones):
        barata = min(range(len(opciones)), key=lambda k: opciones[k][0].carta.coste)
        rival = p.j(carta.controlador)
        # #2 0VzQ: Nuh, Haquika, Demoledor no pasan. #10: Kawit / Djedefhor
        # cuando el rival anda corto de cartas o no bajó Oro este turno.
        forzada = _anular_siempre(p, carta) or (_acelera_al_entrar(carta) and (
            len(rival.mano) <= 3
            or (not rival.oro_jugado and len(rival.mano) <= 5 and p.e.activo == carta.controlador)
        )) or (
            # #7 / #11 UUOX: Fe Sin Límite a la Forma de Lince cuando su
            # atacante libre hará daño: se corta el robo que le permitiría al
            # rival dejar de tener una mano corta.
            _lince_puede_robar(p, carta) and len(rival.mano) <= 3
        )
        # Por la importancia de la carta en la partida, no por su coste: una
        # que roba pesa más si quien la juega tiene poca mano.
        importancia = _importancia(p, carta.controlador, carta)
        if importancia < _UMBRAL_ANULAR and not forzada:
            return None
        # Si una respuesta de la mano ya corta el efecto de entrada, se guarda
        # la anulación dura. Resplandor de Heka además roba una carta: contra
        # Kawit y Haquika es mejor dejar que entre sin resolver su habilidad
        # que mandar la carta completa al Cementerio con Gran Guardián.
        respuestas = []
        for t in p.j(yo).mano:
            if t.tipo != Tipo.TALISMAN or not p.puede_pagar(yo, t):
                continue
            for h in t.habilidades:
                if h.get("cuando") == "oponente_juega" and h.get("accion") not in ("anular", "redirigir", "otra"):
                    if hab._responde_a(h, carta):
                        respuestas.append((t, h))
                    break
        if respuestas and self.responder(p, yo, carta, respuestas) is not None:
            return None
        if _lo_previene_ptolomeo(p, yo, carta):
            return None  # Ptolomeo II previene; el Gran Guardián se guarda
        if forzada:
            return barata
        # Con una sola anulación, se guarda si el rival tiene a la vista algo
        # peor que esta carta (lo buscó y lo vimos).
        peor = max(
            (_importancia(p, carta.controlador, c) for c in p.j(carta.controlador).mano
             if getattr(c, "revelada", False) and c is not carta),
            default=0,
        )
        if len(opciones) == 1 and peor > importancia:
            return None
        return min(range(len(opciones)), key=lambda k: opciones[k][0].carta.coste)


def _redirigir_heuristico(p, yo, objetivo, opciones):
    """Redirige a una carta del rival (la más valiosa); si solo hay propias,
    a una claramente menos valiosa que la original."""
    rivales = [k for k, c in enumerate(opciones) if c.controlador != yo]
    if rivales:
        return max(rivales, key=lambda k: _valor_carta(p, opciones[k]))
    propias = [k for k, c in enumerate(opciones) if _valor_carta(p, c) < _valor_carta(p, objetivo) - 1]
    return min(propias, key=lambda k: _valor_carta(p, opciones[k])) if propias else None


def _elegir_raza_heuristico(p, yo, razas, h):
    """Nombra la raza con más Aliados del rival (en juego y en su mazo),
    descontando los míos: el efecto también me afecta a mí."""
    cuenta = _cuenta_razas(p, yo, razas)
    # Si toda raza presente me daña más que al rival, nombro una que no está.
    return max(razas, key=lambda r: cuenta[r] if r != hab.OTRA_RAZA else 0.5)


def _cuenta_razas(p, yo, razas) -> dict:
    cuenta = {r: 0 for r in razas}
    for quien, signo in ((1 - yo, 1), (yo, -1)):
        j = p.j(quien)
        for x in j.defensa + j.ataque + j.mano + j.mazo:
            if x.tipo == Tipo.ALIADO and x.carta.raza in cuenta:
                cuenta[x.carta.raza] += signo * (3 if x.en_juego else 1)
    return cuenta


def _nombrar_raza_sirve(p, yo, c: Instancia) -> bool:
    """Cleopatra VII en mis manos: ¿hay una raza que pueda nombrar (no
    excluida) que dañe más al rival que a mí? Sin eso es solo un cuerpo."""
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if not obj.get("nombrarRaza"):
            continue
        excluidas = {r.lower() for r in obj.get("excluirRazas") or []}
        razas = list({
            x.carta.raza for j in p.e.jugadores for x in j.mazo + j.mano + j.defensa + j.ataque
            if x is not c and x.tipo == Tipo.ALIADO and x.carta.raza and x.carta.raza.lower() not in excluidas
        })
        return not razas or any(v > 0 for v in _cuenta_razas(p, yo, razas).values())
    return True


def _elegir_carta_heuristico(p, yo, nombres):
    """Prioriza habilidades vigentes y su efecto real sobre la mesa."""
    fuente = getattr(p, "ctx_fuente_habilidad", None)
    if fuente is not None and _nombra_en_mazo_rival(fuente):
        # FtbJ #4: Orfeo destierra la copia del Mazo rival: nunca una Única que
        # ya está en mesa (Rey Arturo); lo que más vale y aún puede estar ahí.
        posibles = _copias_posibles_en_mazo(p, yo)
        ok = [n for n in nombres if posibles.get(n, (0, 0))[0] > 0]
        if ok:
            return max(ok, key=lambda n: posibles[n][0] * posibles[n][1])
    if fuente is not None and _nombra_en_mano_rival(fuente):
        # tuK8 #5: Sir Bedivere baja un Aliado de la mano rival. Con información
        # pública: el que vi en su mano y aún no jugó; si no, el que más copias
        # le pueden quedar. Nunca una Única que ya está en mesa (Marco Antonio).
        rival = p.j(1 - yo)
        aliados = {c.nombre for c in rival.mazo + rival.mano + rival.cementerio + rival.destierro
                   + list(p.e.instancias_en_juego(1 - yo)) if c.tipo == Tipo.ALIADO}
        vistos = [c for c in rival.mano if getattr(c, "revelada", False) and c.nombre in aliados and c.nombre in nombres]
        if vistos:
            return max(vistos, key=lambda c: _valor_carta(p, c)).nombre
        posibles = _copias_posibles_en_mazo(p, yo)
        ok = [n for n in nombres if n in aliados and posibles.get(n, (0, 0))[0] > 0]
        if ok:
            return max(ok, key=lambda n: posibles[n][0] * posibles[n][1])
    rival = p.j(1 - yo)
    puntaje = {n: 0.0 for n in nombres}
    for x in rival.defensa + rival.ataque + rival.apoyo + rival.reserva:
        if x.nombre not in puntaje or not x.habilidades:
            continue
        utiles = sum(1 for h in x.habilidades if h.get("cuando") not in ("al_jugar", None))
        antes = sum(hab.fuerza(p, a) for a in rival.aliados)
        anterior = x.sin_habilidad_hasta
        try:
            x.sin_habilidad_hasta = "hasta_fase_final"
            perdida = antes - sum(hab.fuerza(p, a) for a in rival.aliados)
        finally:
            x.sin_habilidad_hasta = anterior
        puntaje[x.nombre] += utiles * 3 + max(0, perdida) * 2
    for x in rival.mano + rival.mazo:
        if x.nombre in puntaje:
            puntaje[x.nombre] += 0.15 * sum(1 for h in x.carta.habilidades if h.get("cuando") not in ("al_jugar", None))
    return max(nombres, key=lambda n: puntaje[n])


Heuristico.elegir_carta = lambda self, p, yo, nombres: _elegir_carta_heuristico(p, yo, nombres)
Heuristico.elegir_raza = lambda self, p, yo, razas, h: _elegir_raza_heuristico(p, yo, razas, h)
Heuristico.redirigir = lambda self, p, yo, objetivo, opciones: _redirigir_heuristico(p, yo, objetivo, opciones)


JUGADORES = {"aleatorio": Aleatorio, "heuristico": Heuristico}


_puntaje_base = Heuristico._puntaje


_RESPUESTAS = {"anular", "cancelarHabilidad", "cancelarAtaque", "redirigir"}


def _costo_respuesta_en_mano(p, yo, salvo) -> int | None:
    """La respuesta barata (≤2) más económica que tengo en la mano (Siete
    contra Tebas, Fe Sin Límite), para guardarle los Oros."""
    # Las anulaciones tienen su propio criterio (guardar ante una amenaza
    # revelada); aquí, las que cancelan habilidades o ataques del rival, y solo
    # si el rival tiene en mesa habilidades que se activan o disparan.
    rival_tiene = any(h.get("cuando") not in ("continua", None)
                      for x in p.e.instancias_en_juego(1 - yo) for h in x.habilidades)
    if not rival_tiene:
        return None
    costes = [
        p.coste_de(yo, c) for c in p.j(yo).mano
        if c is not salvo and c.tipo == Tipo.TALISMAN and p.coste_de(yo, c) <= 2 and any(
            h.get("accion") in (_RESPUESTAS - {"anular"}) for h in c.habilidades)
    ]
    return min(costes) if costes else None


def _puntaje_con_robo(self, p, yo, j):
    v = _puntaje_base(self, p, yo, j)
    if _GUARDAR_PARA_RESPUESTA and p.e.fase == "vigilia" and p.e.activo == yo and j.tipo in ("jugar", "activar"):
        # I4Sl2 #4: no gastar el último Oro que necesita mi respuesta de la mano
        # (Siete contra Tebas) si antes alcanzaba: entre jugadas parecidas, la
        # que me deja responder.
        costo = _costo_respuesta_en_mano(p, yo, j.carta)
        gasta = _oros_que_gasta(p, yo, j)
        disponible = p.j(yo).oro_disponible
        if costo is not None and disponible >= costo and disponible - gasta < costo:
            # Algo menor (robar 1 con Escila) no vale perder la respuesta.
            v = v - 2.5 if v >= 12 else min(v, 0.5)
    if j.tipo == "activar":
        h = j.carta.habilidades[j.habilidad]
        costo = h.get("costo") or {}
        if costo.get("desterrarCementerio") and _alimenta_mi_destierro(p, yo):
            v = max(v, 25.0)  # ZsfY #4: Homunculus primero destierra la Rea que juega la otra Rea
        if h.get("accion") == "perderHabilidad" and (h.get("objetivo") or {}).get("quien") == "oponente" \
                and any(_pieza_clave(t) for t in hab.candidatos_validos(p, yo, j.carta, h)):
            v = max(v, 40.0)  # ZsfY #5: Diente al Apophis antes de jugar el resto del turno
    if j.tipo == "jugar" and j.carta.tipo == Tipo.TOTEM:
        v += 1.0 * _robo_que_deja(j.carta)  # FqvR #1: Focea queda y roba 2 en la Guerra
    if j.tipo == "jugar" and j.carta.tipo == Tipo.TALISMAN and _remocion_unica(p, yo, j.carta)             and _valor_remocion_al_entrar(p, yo, j.carta) < 12 and len(p.j(1 - yo).mazo) > 15:
        v -= 3.0  # FqvR #1: la Expulsión (Única) se guarda para algo más grande que Duphon
    if j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO and _remocion_que_crece(p, yo, j.carta):
        v -= 10.0  # Pato Killer: primero los Guerreros, Artabano al final alcanza más
    if j.tipo == "jugar" and j.carta.tipo == Tipo.ALIADO:
        c = j.carta
        for h in c.habilidades:
            if h.get("cuando") != "al_jugar":
                continue
            obj = h.get("objetivo") or {}
            if h.get("accion") == "mostrar" and obj.get("zona") == "mano" and any(
                    x is not c and hab.coincide(p, x, {**obj, "quien": None}) for x in p.j(yo).mano):
                v += 2.0  # MscU #1: Roxana primero (muestra a Ay y roba); Ay la destierra después
            elif h.get("accion") == "mostrar" and obj.get("zona") == "mano" and h.get("luego"):
                if _salida_que_rinde(p, yo, c):
                    v += 2.0  # con Ay en mesa: se baja, Ay la destierra para robar y ella busca un Oro
                else:
                    v -= 2.5  # sin otro Faraón que mostrar, Roxana se guarda hasta tener uno
            elif h.get("accion") == "mirarTope" and h.get("zonaDestino") == "mano":
                v += 1.0  # fKRi #4: Rhiannon genera recursos en mano
            elif h.get("opcional") and h.get("accion") in ("barajar", "buscar", "jugarDesde") \
                    and hab._necesita_objetivo(h) and not hab.candidatos_validos(p, yo, c, h):
                v -= 1.5  # fKRi #1: Caturix sin nada que barajar es un 2/3 sin más
    if j.tipo == "jugar" and j.carta.tipo != Tipo.ORO:
        # PYDO #4: contra Apophis cada carta que no es Oro me bota 3: primero
        # se lo saca de la mesa (Focea, Expulsión) y no se siguen bajando Aliados.
        castigo = _castigo_por_jugar(p, yo)
        v -= 2.0 * castigo
        if castigo and _quita_al_castigador(p, yo, j.carta):
            v += 5.0 * castigo
    return v


def _salida_que_rinde(p, yo, c: Instancia) -> bool:
    """`c` gana algo al salir del juego (Roxana busca un Oro) y tengo en mesa
    quien la saca como costo este turno (Ay: destierra un Aliado para robar)."""
    if not any(h.get("cuando") == "al_salir_del_juego" for h in c.habilidades):
        return False
    return any(
        h.get("cuando") == "activada" and any(k in (h.get("costo") or {}) for k in ("desterrarAliados", "destruirAliados"))
        and not any(hab.usos(p, yo, a, h, k) for k in [a.habilidades.index(h)])
        for a in p.j(yo).aliados for h in a.habilidades)


def _remocion_que_crece(p, yo, c: Instancia) -> bool:
    """Artabano: su alcance depende de cuántos Guerreros controlo. Si con los
    que todavía puedo bajar este turno llega a un Aliado rival más caro y
    valioso, se juega al final."""
    jug = p.j(yo)
    for h in c.habilidades:
        comp = (h.get("objetivo") or {}).get("coste") or {}
        if h.get("cuando") != "al_jugar" or comp.get("segun") not in ("aliados_raza", "aliados_arquetipo"):
            continue
        filtro = {"quien": None, "raza": comp.get("raza", ""), "arquetipo": comp.get("arquetipo", ""), "tipos": ["Aliado"]}
        ahora = 1 + sum(1 for a in jug.aliados if hab.coincide(p, a, filtro))
        quedan = jug.oro_disponible - p.coste_de(yo, c)
        extra = 0
        for x in sorted((x for x in jug.mano if x is not c and x.tipo == Tipo.ALIADO and hab.coincide(p, x, filtro)),
                        key=lambda x: p.coste_de(yo, x)):
            if p.coste_de(yo, x) <= quedan:
                quedan -= p.coste_de(yo, x)
                extra += 1
        if not extra:
            continue
        rival = [a for a in p.j(1 - yo).aliados if a.tipo == Tipo.ALIADO]
        mejor_ahora = max([_valor_vivo(p, a) for a in rival if a.carta.coste <= ahora], default=0)
        mejor_luego = max([_valor_vivo(p, a) for a in rival if a.carta.coste <= ahora + extra], default=0)
        if mejor_luego > mejor_ahora + 1:
            return True
    return False


def _castigadores(p, yo) -> list:
    return [s for s in p.e.instancias_en_juego(1 - yo) if s.sin_habilidad_hasta is None and any(
        h.get("cuando") == "oponente_juega" and h.get("accion") == "botar" for h in s.habilidades)]


def _quita_al_castigador(p, yo, c: Instancia) -> bool:
    """Esta carta al entrar puede sacar o anular al Apophis."""
    objetivos = set(id(s) for s in _castigadores(p, yo))
    return bool(objetivos) and any(
        h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION | {"mover", "perderHabilidad"}
        and any(id(t) in objetivos for t in hab.candidatos_validos(p, yo, c, h))
        for h in c.habilidades)


def _castigo_por_jugar(p, yo) -> int:
    """Cartas que boto por jugar una carta que no es Oro (Apophis)."""
    n = 0
    for s in p.e.instancias_en_juego(1 - yo):
        if s.sin_habilidad_hasta is not None:
            continue
        for h in s.habilidades:
            if h.get("cuando") == "oponente_juega" and h.get("accion") == "botar":
                n += int(h.get("cantidad", 1) or 1)
    return n


def _alimenta_mi_destierro(p, yo) -> bool:
    """Hay en mi Cementerio un Aliado que Rea (en juego o pagable en la mano)
    juega gratis desde el Destierro este mismo turno."""
    jug = p.j(yo)
    usuarios = [c for c in list(p.e.instancias_en_juego(yo)) + [c for c in jug.mano if p.puede_pagar(yo, c)]
                if any(h.get("accion") in ("jugarDesde", "ponerEnJuego")
                       and "destierro" in hab.zonas_de(h.get("objetivo") or {}, "")
                       and (h.get("objetivo") or {}).get("quien") == "propio" for h in c.habilidades)]
    if not usuarios:
        return False
    objs = [h.get("objetivo") or {} for c in usuarios for h in c.habilidades
            if "destierro" in hab.zonas_de(h.get("objetivo") or {}, "")]
    return any(any(hab.coincide(p, c, {**o, "quien": None}) for o in objs) for c in jug.cementerio
               if c.tipo == Tipo.ALIADO)


def _remocion_unica(p, yo, c: Instancia) -> bool:
    """Remoción de la que el mazo tiene una sola copia (Expulsión de Titanes)."""
    if not any(h.get("cuando") in ("al_jugar", None) and h.get("accion") in _REMOCION
               and (h.get("objetivo") or {}).get("quien") == "oponente" for h in c.habilidades):
        return False
    jug = p.j(yo)
    todas = jug.mazo + jug.mano + jug.cementerio + jug.destierro + list(p.e.instancias_en_juego(yo))
    return sum(1 for x in todas if x.nombre == c.nombre) <= 1


Heuristico._puntaje = _puntaje_con_robo


def _cambio_de_castillo(habs) -> int:
    """Cartas que una habilidad (y sus "luego") suma (+) o quita (−) a mi
    Mazo Castillo: barajar del Cementerio suma, robar o botar resta."""
    neto = 0
    for h in habs:
        obj = h.get("objetivo") or {}
        n = int(h.get("cantidad") or 1)
        if obj.get("quien") not in (None, "propio"):
            pass
        elif h.get("accion") == "barajar" and obj.get("zona") == "cementerio":
            neto += n
        elif h.get("accion") == "robar":
            neto -= n
        elif h.get("accion") == "botar" and obj.get("quien") == "propio":
            neto -= n
        neto -= int((h.get("costo") or {}).get("botar") or 0)
        neto += _cambio_de_castillo(h.get("luego") or [])
    return neto


def _a_rango_de_cancelador(p, yo) -> bool:
    """Flechas de Lava me dejaría sin castillo (bota la fuerza de mi mayor
    Aliado, más el robo final) y el rival puede tenerla."""
    bote = max((hab.fuerza(p, a) for a in p.j(yo).aliados), default=0)
    return bote > 0 and bote >= len(p.j(yo).mazo) - 1 \
        and _prob_cancelador_con_bote(p, yo) >= _UMBRAL_CANCELADOR


_puntaje_sin_rango = Heuristico._puntaje


def _puntaje_rango_flechas(self, p, yo, j):
    """Héctor 2026-11-12: a rango de Flechas de Lava, todo el esfuerzo en salir
    de rango (barajar al Mazo Castillo) y no robar por gusto."""
    v = _puntaje_sin_rango(self, p, yo, j)
    if j.tipo not in ("jugar", "activar", "oro") or j.carta is None or p.e.activo != yo:
        return v
    habs = [j.carta.habilidades[j.habilidad]] if j.tipo == "activar" else [
        h for h in j.carta.habilidades if h.get("cuando") == "al_jugar"]
    neto = _cambio_de_castillo(habs)
    if neto and _a_rango_de_cancelador(p, yo):
        v += 6.0 * neto
    return v


Heuristico._puntaje = _puntaje_rango_flechas

_vale_la_pena_base = Heuristico._vale_la_pena


def _vale_la_pena_guardando_respuesta(self, p, yo, j):
    """I4Sl2 #4: algo menor (robar 1 con Escila) no se hace si me deja sin los
    Oros de la respuesta que tengo en la mano (Siete contra Tebas)."""
    if _GUARDAR_PARA_RESPUESTA and p.e.fase == "vigilia" and p.e.activo == yo and j.tipo in ("jugar", "activar"):
        costo = _costo_respuesta_en_mano(p, yo, j.carta)
        disponible = p.j(yo).oro_disponible
        if costo is not None and disponible >= costo and disponible - _oros_que_gasta(p, yo, j) < costo \
                and self._puntaje(p, yo, j) < 12:
            return False
    return _vale_la_pena_base(self, p, yo, j)


Heuristico._vale_la_pena = _vale_la_pena_guardando_respuesta


def _remocion_sin_blanco(p, yo, c) -> bool:
    """Reporte qx6H T3: Anillos de Badbury con la mesa rival vacía gasta su
    barajar de entrada en nada; mejor bajar un Aliado y guardarlo."""
    if c.tipo not in (Tipo.TOTEM, Tipo.TALISMAN):
        return False
    habs = [h for h in c.habilidades if h.get("cuando") == "al_jugar"
            and h.get("accion") in (_REMOCION | {"barajar"})
            and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
            and "en_juego" in hab.zonas_de(h.get("objetivo") or {})]
    return bool(habs) and not any(
        x.controlador != yo for h in habs for x in hab.candidatos_validos(p, yo, c, h))


_vale_la_pena_previo_blanco = Heuristico._vale_la_pena


def _vale_la_pena_con_blanco(self, p, yo, j):
    if _LECCIONES_QX6 and j.tipo == "jugar" and j.carta is not None             and p.e.activo == yo and _remocion_sin_blanco(p, yo, j.carta):
        return False
    return _vale_la_pena_previo_blanco(self, p, yo, j)


Heuristico._vale_la_pena = _vale_la_pena_con_blanco


def _nombrar_tipo(self, p, yo, fuente, tipos):
    """Afrodita: nombra el tipo que más hay en mi castillo (conozco mi mazo,
    no su orden), pesando el coste: acertar un Aliado caro rinde más."""
    peso = {t: sum(1 + 0.25 * (c.carta.coste or 0) for c in p.j(yo).mazo if c.tipo.value == t) for t in tipos}
    return max(tipos, key=lambda t: peso[t])


Heuristico.nombrar_tipo = _nombrar_tipo

_usar_opcional_base = Heuristico.usar_opcional


def _usar_opcional_sin_danarme(self, p, yo, fuente, h):
    """hkp2r #1: "puedes barajar una carta en juego" (Anillos de Badbury) no se
    usa si solo puede caer en cartas propias."""
    obj = h.get("objetivo") or {}
    if h.get("accion") in (_DANINO - {"botar", "descartar"}) and obj.get("quien") == "cualquiera" \
            and obj.get("seleccion", "elige") == "elige" and "en_juego" in hab.zonas_de(obj):
        cands = hab.candidatos_validos(p, yo, fuente, h)
        if cands and all(c.controlador == yo for c in cands):
            return False
    return _usar_opcional_base(self, p, yo, fuente, h)


Heuristico.usar_opcional = _usar_opcional_sin_danarme

_elegir_jugada_sin_trono = Heuristico.elegir_jugada


def _elegir_jugada_marcando_trono(self, p, yo, jugadas):
    """Anota el turno en que se usó un Trono Dorado (uno por turno, I4Sl2 #6)."""
    j = _elegir_jugada_sin_trono(self, p, yo, jugadas)
    if j is not None and j.tipo == "activar" and j.carta.tipo == Tipo.ORO:
        h = j.carta.habilidades[j.habilidad]
        if (h.get("costo") or {}).get("barajarEstaCarta") and h.get("accion") == "desterrar":
            p.__dict__.setdefault("trono_usado", {})[yo] = p.e.turno
    return j


Heuristico.elegir_jugada = _elegir_jugada_marcando_trono


_elegir_objetivos_sin_cementerio = Heuristico.elegir_objetivos


def _elegir_objetivos_cementerio_rival(self, p, yo, candidatos, n, h):
    """I4Sl2 #5: al desterrar del Cementerio rival, primero lo que juega o
    recicla desde ahí (el otro Homunculus), luego lo que más vale."""
    if h.get("accion") == "desterrar" and candidatos and all(
            c.zona == Zona.CEMENTERIO and c.dueno != yo for c in candidatos):
        return sorted(candidatos, key=lambda c: (not _vale_en_cementerio(c), not _pieza_clave(c),
                                                 -_valor_carta(p, c)))[:n]
    return _elegir_objetivos_sin_cementerio(self, p, yo, candidatos, n, h)


Heuristico.elegir_objetivos = _elegir_objetivos_cementerio_rival



# Opcional: ataques (y bloqueos, experimental) decididos por simulación con la
# mano rival estimada. Si busqueda_ataques se importa primero, se registra solo.
import sys as _sys  # noqa: E402

if f"{__package__}.busqueda_ataques" not in _sys.modules:
    from .busqueda_ataques import BuscadorAtaques, BuscadorCompleto  # noqa: E402,F401


# Héctor 2026-11-12: "jugar las cartas útiles que tengas en mano, a menos que
# estés guardando respuestas; ser lo más eficiente posible con los Oros".
# Si la heurística pasa la Vigilia con un Aliado pagable, lo juega (el más
# caro que deje los Oros reservados para responder).
_elegir_jugada_base = Heuristico.elegir_jugada


def _elegir_jugada_eficiente(self, p, yo, jugadas):
    j = _elegir_jugada_base(self, p, yo, jugadas)
    if j.tipo != "pasar" or p.e.fase != "vigilia" or p.e.activo != yo:
        return j
    reserva = _oros_a_reservar(p, yo) + _reserva_para_anular(p, yo) + _reserva_para_responder(p, yo)
    oro = p.j(yo).oro_disponible
    aliados = [x for x in jugadas if x.tipo == "jugar" and x.carta.tipo == Tipo.ALIADO
               and oro - p.coste_de(yo, x.carta) >= reserva]
    if not aliados:
        return j
    return max(aliados, key=lambda x: p.coste_de(yo, x.carta))


Heuristico.elegir_jugada = _elegir_jugada_eficiente


_elegir_jugada_previa_c2 = Heuristico.elegir_jugada


def _elegir_jugada_sin_generar_de_mas(self, p, yo, jugadas, *a, **k):
    """Héctor (97465 T6): Dragones generó 2 Oros y después se jugó la Bola.
    El generador restringido solo se activa si lo mejor que sigue es algo que
    paga (un Dragón de coste 4+)."""
    pend = getattr(self, "_gen_pendiente", None)
    if _CORRECCIONES_2 and pend and pend[0] == (p.e.turno, yo):
        # Ya generé para un Dragón caro: ahora lo juego (no la Bola).
        cal = [x for x in jugadas if x.tipo == "jugar" and x.carta.uid in pend[1]]
        if cal:
            self._gen_pendiente = None
            try:
                return max(cal, key=lambda x: self._puntaje(p, yo, x))
            except Exception:
                return cal[0]
    j = _elegir_jugada_previa_c2(self, p, yo, jugadas, *a, **k)
    if not _CORRECCIONES_2 or j is None or j.tipo != "activar":
        return j
    h = j.carta.habilidades[j.habilidad]
    if h.get("accion") != "generarOro" or not (h.get("soloParaTipos") or h.get("soloParaRaza") or h.get("soloParaCosteMin")):
        return j
    minimo = int(h.get("soloParaCosteMin", 0) or 0)
    raza = h.get("soloParaRaza") or ""
    disp = p.j(yo).oro_disponible - 1 + int(h.get("valor", 0) or 0)

    def califica(c):
        return c.tipo == Tipo.ALIADO and (not raza or raza in (c.raza or "")) and c.carta.coste >= minimo \
            and p.coste_de(yo, c) <= disp
    try:
        mejor_con = max((self._puntaje(p, yo, x) for x in jugadas if x.tipo == "jugar" and califica(x.carta)), default=None)
        otras = [x for x in jugadas if x is not j and x.tipo == "jugar" and not califica(x.carta)
                 and _vale_jugar_ya(self, p, yo, x)]
        mejor_sin = max(otras, key=lambda x: self._puntaje(p, yo, x), default=None)
    except Exception:
        return j
    if mejor_sin is not None and (mejor_con is None or self._puntaje(p, yo, mejor_sin) > mejor_con):
        return mejor_sin
    self._gen_pendiente = ((p.e.turno, yo), {x.carta.uid for x in jugadas if x.tipo == "jugar" and califica(x.carta)})
    return j


def _vale_jugar_ya(self, p, yo, x) -> bool:
    try:
        return self._vale_la_pena(p, yo, x)
    except Exception:
        return False


Heuristico.elegir_jugada = _elegir_jugada_sin_generar_de_mas


# ── Jugar según lo que pide la partida (Desafiante Control, zJg0U8 y Fv8DTu) ──
# La misma carta no vale siempre lo mismo: con la mesa rival más fuerte se
# busca y se juega removal; con el castillo corto, reciclaje; con la mesa
# tranquila, un motor de robo (Anand, Avalon) antes que un golpe que me bota.
_PLAN_SEGUN_NECESIDAD = True


def _fuerza_mesa(p, quien) -> int:
    return sum(max(0, hab.fuerza(p, a)) for a in p.j(quien).aliados)


def _me_superan(p, yo) -> bool:
    return _fuerza_mesa(p, 1 - yo) > _fuerza_mesa(p, yo)


def _castillo_corto(p, yo) -> int:
    """0 sano; 1 corto (≤ 15 o dos golpes del rival); 2 crítico (≤ 8 o un golpe)."""
    n, golpe = len(p.j(yo).mazo), max(_alcance_rival(p, yo), 3)
    if n <= 8 or n <= golpe + 2:
        return 2
    return 1 if n <= 15 or n <= 2 * golpe else 0


def _remocion_encadenada(p, yo, c: Instancia) -> float:
    """Aine: "puedes mostrar un Desafiante de tu Mano para desterrar": el
    removal va en el "luego" de un costo al entrar. Vale el mejor objetivo,
    si se puede pagar el costo (hay otra carta que mostrar o descartar)."""
    mejor = 0.0
    for h in c.habilidades:
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") not in ("mostrar", "descartar", "botar"):
            continue
        if (h.get("objetivo") or {}).get("quien") == "propio" and h.get("accion") in ("mostrar", "descartar") \
                and not any(x is not c and hab.coincide(p, x, {**(h.get("objetivo") or {}), "quien": None})
                            for x in p.j(yo).mano):
            continue
        for e in h.get("luego") or []:
            obj = e.get("objetivo") or {}
            if e.get("accion") not in _REMOCION or obj.get("quien") not in ("oponente", "cualquiera"):
                continue
            for t in hab.candidatos_validos(p, yo, c, e):
                if t.controlador != yo:
                    mejor = max(mejor, 1.5 * _valor_vivo(p, t)
                                + sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == t.uid))
    return mejor


def _remocion_que_aporta(p, yo, c: Instancia, *, activadas_solo: bool = False) -> float:
    """Lo que saca del rival: al entrar (directo o encadenado) o activándola
    (Cerridwen se destruye para desterrar: se descuenta su cuerpo)."""
    v = 0.0 if activadas_solo else max(_valor_remocion_al_entrar(p, yo, c), _remocion_encadenada(p, yo, c))
    for h in c.habilidades:
        if h.get("cuando") != "activada" or h.get("zonaActivacion"):
            continue
        r = _valor_remocion_activada(p, yo, c, h)
        if r and (h.get("costo") or {}).get("destruirEstaCarta"):
            r -= 1.5 * c.carta.fuerza
        v = max(v, r)
    return max(0.0, v)


def _reciclaje_que_aporta(p, yo, c: Instancia) -> int:
    """Caturix / Moy-Mell: cuántas cartas de mi Cementerio vuelven al mazo."""
    n = 0
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("accion") != "barajar" or obj.get("quien") not in ("propio", None) \
                or "cementerio" not in hab.zonas_de(obj, "") or h.get("zonaActivacion") == "cementerio":
            continue
        filtro = {**obj, "quien": None}
        hay = sum(1 for x in p.j(yo).cementerio if hab.coincide(p, x, filtro))
        n = max(n, min(int(h.get("cantidad", 1) or 1), hay))
    return n


def _motor_de_robo(c: Instancia) -> bool:
    """Roba turno a turno activándose (Anand, Avalon, Tuatha De Danaan)."""
    for h in c.habilidades:
        if h.get("cuando") != "activada" or h.get("zonaActivacion"):
            continue
        costo = h.get("costo") or {}
        if any(v for k, v in costo.items() if k != "oros"):
            continue  # Ay destierra un Aliado mío para robar: no es un motor gratis
        if h.get("accion") == "robar" or any(e.get("accion") == "robar" for e in h.get("luego") or []):
            return True
    return False


def _valor_necesidad(p, yo, c: Instancia) -> float:
    """Cuánto me sirve esta carta por lo que pide la partida ahora."""
    presion, corto = _me_superan(p, yo), _castillo_corto(p, yo)
    v = _remocion_que_aporta(p, yo, c) * (1.0 if presion else 0.4)
    if corto:
        v += _reciclaje_que_aporta(p, yo, c) * (1.5 if corto == 2 else 0.8)
    if _motor_de_robo(c) and corto < 2:
        v += 1.0 if presion else 3.0
    return v


def _castigo_golpe_que_me_bota(p, yo, c: Instancia) -> float:
    """Nuada: "cuando hace daño, destruyes un Aliado tuyo o botas 3". Cada
    golpe me cuesta cartas: sin presión, no es mejor que un motor."""
    n = 0
    for h in c.habilidades:
        if h.get("cuando") == "al_hacer_dano" and h.get("accion") == "botar" \
                and (h.get("objetivo") or {}).get("quien") == "propio":
            n = max(n, int(h.get("cantidad", 1) or 1))
    if not n:
        return 0.0
    return n * (0.8 + 0.6 * _castillo_corto(p, yo))


def _valor_tutor(self, p, yo, c: Instancia) -> float:
    """Beleth: lo que vale lo mejor que puede buscar ahora (menos el descarte)."""
    mejor = None
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") != "buscar" \
                or "mazo" not in hab.zonas_de(obj, ""):
            continue
        filtro = {**obj, "quien": None}
        cands = [x for x in p.j(yo).mazo if hab.coincide(p, x, filtro)]
        if not cands:
            continue
        v = max(_valor_necesidad(p, yo, x) - (3.0 if any(m.nombre == x.nombre for m in p.j(yo).mano) else 0.0)
                for x in cands)
        if (h.get("costo") or {}).get("descartar"):
            resto = [x for x in p.j(yo).mano if x is not c]
            if not resto:
                continue
            v -= 0.3 * min(self._valor_descarte(p, yo, x) for x in resto)
        mejor = v if mejor is None else max(mejor, v)
    return mejor or 0.0


_puntaje_previo_necesidad = Heuristico._puntaje


def _barajar_rival_que_aporta(p, yo, c: Instancia) -> float:
    """Anillos de Badbury (desafío 4n5oe T7: barajó a Teseo, fuerza 6): mandar
    al mazo una carta rival en juego es removal. Vale algo menos que
    destruirla: vuelve a su castillo (+1) y la puede robar de nuevo."""
    mejor = 0.0
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") != "barajar" \
                or "en_juego" not in hab.zonas_de(obj, "") or obj.get("quien") not in ("oponente", "cualquiera"):
            continue
        for t in hab.candidatos_validos(p, yo, c, h):
            if t.controlador == yo or t.tipo == Tipo.ORO:
                continue
            armas = sum(_valor_carta(p, a) for a in p.e.portadas if a.portador == t.uid)
            mejor = max(mejor, 1.5 * _valor_vivo(p, t) + armas - 1.0)
    return mejor


def _puntaje_segun_necesidad(self, p, yo, j):
    v = _puntaje_previo_necesidad(self, p, yo, j)
    if _PLAN_SEGUN_NECESIDAD and j.tipo == "jugar" and j.carta is not None and j.carta.zona == Zona.MANO \
            and p.e.activo == yo and p.e.fase == "vigilia":
        v += _barajar_rival_que_aporta(p, yo, j.carta) * (1.0 if _me_superan(p, yo) else 0.4)
    if not _PLAN_SEGUN_NECESIDAD or j.tipo != "jugar" or j.carta is None or j.carta.zona != Zona.MANO \
            or j.carta.tipo not in (Tipo.ALIADO, Tipo.TOTEM) or p.e.activo != yo or p.e.fase != "vigilia":
        return v  # (La Llama Fría puntúa cartas del Cementerio como si se jugaran: eso no)
    c = j.carta
    presion, corto = _me_superan(p, yo), _castillo_corto(p, yo)
    # Lo que la base no cuenta: removal activado o encadenado, reciclaje y motor.
    extra = _remocion_que_aporta(p, yo, c, activadas_solo=True) + _remocion_encadenada(p, yo, c)
    v += extra * (0.6 if presion else 0.2)
    if corto:
        v += _reciclaje_que_aporta(p, yo, c) * (1.2 if corto == 2 else 0.5)
    if _motor_de_robo(c) and corto < 2:
        v += 1.0 if presion else 3.0
    # Con el castillo crítico o la mesa perdida, buscar la pieza justa pesa más
    # que un cuerpo más (G1 T11: Beleth por Caturix antes que Aine).
    v += (1.0 if corto == 2 or presion else 0.6) * max(0.0, _valor_tutor(self, p, yo, c))
    v -= _castigo_golpe_que_me_bota(p, yo, c)
    v += _valor_cavar(p, yo, c)
    return v


Heuristico._puntaje = _puntaje_segun_necesidad


def _valor_cavar(p, yo, c: Instancia) -> float:
    """Rhiannon (desafío 2026-11-14, T1: Rhiannon antes que Niamh): mirar el
    tope y tomar cartas vale por lo que se espera tomar (según lo que queda
    en el mazo, sin mirar el orden), más con la mesa tranquila; lo que se
    descarta al Cementerio cuesta castillo, más cuanto más corto está."""
    if not _PLAN_SEGUN_NECESIDAD:
        return 0.0
    mazo = p.j(yo).mazo
    mejor = None
    for h in c.habilidades:
        if h.get("cuando") not in ("al_jugar", None) or h.get("accion") != "mirarTope" \
                or (h.get("zonaDestino") or "mano") != "mano" or not mazo:
            continue
        n = min(int(h.get("cantidad", 1) or 1), len(mazo))
        tomar = int(h.get("valor") or 0)
        filtro = {**(h.get("objetivo") or {}), "quien": None, "zona": None}
        frac = sum(1 for x in mazo if hab.coincide(p, x, filtro)) / len(mazo)
        esperadas = min(tomar, n * frac) if tomar > 1 else 1 - (1 - frac) ** n
        # El castillo es la vida: las n miradas salen del mazo (a la mano o al
        # Cementerio); si el resto vuelve al mazo, solo las que se toman.
        salen = n if h.get("restoA") == "cementerio" else esperadas
        v = esperadas * (2.0 if not _me_superan(p, yo) else 1.0) \
            - 0.4 * salen * (1 + _castillo_corto(p, yo))
        mejor = v if mejor is None else max(mejor, v)
    return mejor or 0.0


def _bonus_oro_entrada(p, yo, carta: Instancia) -> float:
    """Ceangal An Fhanaigh (desafío 2026-11-14, T3): un Oro cuyo "al entrar"
    saca algo que vale la pena hoy va antes que uno que rinde más adelante
    (Joya Amatista); el bonus crece con lo que vale el objetivo."""
    if not _PLAN_SEGUN_NECESIDAD:
        return 0.0
    mejor = 0.0
    for h in carta.habilidades:
        if h.get("cuando") != "al_jugar" or h.get("accion") not in _REMOCION:
            continue
        obj = h.get("objetivo") or {}
        oro = p.j(yo).oro_disponible
        paga = (h.get("costo") or {}).get("orosSegun") == "coste_objetivo"
        for x in p.e.instancias_en_juego(1 - yo):
            if x.tipo == Tipo.ORO or not hab.coincide(p, x, {**obj, "quien": None}):
                continue
            if paga and x.carta.coste > oro:
                continue
            v = _valor_vivo(p, x)
            if v >= 2.0:
                mejor = max(mejor, 1.0 + 0.5 * v)
    return mejor


def _botar_con_premio(h: dict) -> bool:
    """Anand: botamos 1 cada uno y, si cae Oro o Aliado, robo o reciclo."""
    return h.get("accion") == "botar" and (h.get("objetivo") or {}).get("quien") == "ambos" and any(
        e.get("relacion") == "si_afectada_cumple" and e.get("accion") in ("robar", "barajar")
        for e in h.get("luego") or [])


_objetivo_util_previo_nec = Heuristico._objetivo_util


def _objetivo_util_segun_necesidad(self, p, yo, fuente, h, *, pagando: int = 0) -> bool:
    if _PLAN_SEGUN_NECESIDAD and h.get("relacion") and h.get("accion") in _REMOCION \
            and hab._necesita_objetivo(h):
        # Magia Amatista: el "luego" de una carta ya pagada es gratis; si
        # alcanza a un Aliado rival, se usa (no es "gastar un Talismán").
        return any(c.controlador != yo for c in hab.candidatos_validos(p, yo, fuente, h))
    if _PLAN_SEGUN_NECESIDAD and _botar_con_premio(h):
        # No es Grandes Faraones (ventaja de 15): bota poco y devuelve una carta.
        n = hab.cantidad(p, yo, h, [], lado=1 - yo)
        return n <= 2 and len(p.j(yo).mazo) - n > max(3, _alcance_rival(p, yo))
    return _objetivo_util_previo_nec(self, p, yo, fuente, h, pagando=pagando)


Heuristico._objetivo_util = _objetivo_util_segun_necesidad


_elegir_opcion_previo_nec = Heuristico.elegir_opcion


def _elegir_opcion_segun_necesidad(self, p, yo, fuente, opciones):
    if _PLAN_SEGUN_NECESIDAD:
        acciones = [o.get("accion") for o in opciones]
        if set(acciones) == {"destruir", "botar"} and not _castillo_corto(p, yo)                 and all((o.get("objetivo") or {}).get("quien") == "propio" for o in opciones):
            return acciones.index("botar")  # Nuada con castillo sano: 3 cartas valen menos que un Aliado
        if set(acciones) == {"robar", "barajar"}:
            # Anand: con el castillo corto vuelve una carta al mazo; si no, robo.
            return acciones.index("barajar" if _castillo_corto(p, yo) and p.j(yo).cementerio else "robar")
        validas = [k for k, o in enumerate(opciones)
                   if not (o.get("accion") in ("destruir", "desterrar")
                           and (o.get("objetivo") or {}).get("quien") == "propio"
                           and not [c for c in hab.candidatos_validos(p, yo, fuente, o) if c is not fuente])]
        if validas and len(validas) < len(opciones):
            # Nuada no se destruye a sí misma: sin otro Aliado, bota 3.
            sub = _elegir_opcion_previo_nec(self, p, yo, fuente, [opciones[k] for k in validas])
            return validas[sub]
    return _elegir_opcion_previo_nec(self, p, yo, fuente, opciones)


Heuristico.elegir_opcion = _elegir_opcion_segun_necesidad


_sacrificio_de_oro_previo_nec = _sacrificio_de_oro_conviene


def _sacrificio_de_oro_conviene(p, yo, fuente, h) -> bool:  # noqa: F811
    """Salmón del Saber: desterrar un Oro para que un atacante no haga daño
    solo si el golpe importa (como el Codex), no por 5 con 39 en el mazo."""
    if _PLAN_SEGUN_NECESIDAD and h.get("accion") == "reducirDano" and fuente.tipo == Tipo.ORO \
            and p.atacantes and p.e.activo != yo:
        bloqueados = set(getattr(p, "bloqueos", {}) or {})
        dano = max((max(0, hab.fuerza(p, a)) for a in p.atacantes if a.uid not in bloqueados), default=0)
        castillo = len(p.j(yo).mazo)
        rango = _quemado_rival(p, yo) + _fuerza_mesa(p, 1 - yo)
        return dano >= castillo or castillo - dano <= max(8, rango) or dano >= 10
    obj = h.get("objetivo") or {}
    if _PLAN_SEGUN_NECESIDAD and h.get("accion") == "buscar" and fuente.tipo == Tipo.ORO             and "cementerio" in hab.zonas_de(obj, "") and obj.get("quien") in ("propio", None):
        # Linaje Celta: reventarlo trae lo que la partida pide (Caturix con el
        # castillo crítico, removal si me superan), no cualquier Aliado.
        cands = hab.candidatos_validos(p, yo, fuente, h)
        if any(_valor_necesidad(p, yo, c) >= 4.0 for c in cands):
            return True
    return _sacrificio_de_oro_previo_nec(p, yo, fuente, h)


_usar_opcional_previo_nec = Heuristico.usar_opcional


def _usar_opcional_segun_necesidad(self, p, yo, fuente, h):
    if _PLAN_SEGUN_NECESIDAD and h.get("accion") in ("mostrar", "descartar", "botar") \
            and (h.get("objetivo") or {}).get("quien") == "propio" and h.get("luego") \
            and all(x.get("relacion") == "si_se_cumplio" for x in h["luego"]) \
            and all(x.get("accion") in _REMOCION for x in h["luego"]) \
            and not any(t.controlador != yo for x in h["luego"] for t in hab.candidatos_validos(p, yo, fuente, x)):
        # Aine sin objetivo (Ériu es Indesterrable): no se muestra la mano gratis.
        return False
    return _usar_opcional_previo_nec(self, p, yo, fuente, h)


Heuristico.usar_opcional = _usar_opcional_segun_necesidad


def _removals_con_limite(p, yo, fuente):
    """Mis otras remociones con límite (Cerridwen: coste 2 o menos), en mesa o
    en la mano: (carta, habilidad)."""
    for c in list(p.j(yo).mano) + [a for a in p.j(yo).aliados]:
        if c is fuente or (c.zona == Zona.MANO and c.tipo != Tipo.ALIADO):
            continue
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            if h.get("accion") not in ("destruir", "desterrar") or obj.get("quien") != "oponente" \
                    or not (obj.get("coste") or obj.get("fuerza")) or "en_juego" not in hab.zonas_de(obj):
                continue
            if h.get("cuando") == "activada" or (c.zona == Zona.MANO and h.get("cuando") in ("al_jugar", None)):
                yield c, h


def _otro_removal_lo_cubre(p, yo, fuente, t: Instancia) -> bool:
    return any(hab.coincide(p, t, {**(h.get("objetivo") or {}), "quien": None})
               for _, h in _removals_con_limite(p, yo, fuente))


def _pega_en_mesa(p, a: Instancia) -> float:
    """Su fuerza más lo que suma a sus compañeros mientras está (Godofredo)."""
    v = float(max(0, hab.fuerza(p, a)))
    for h in a.habilidades:
        if h.get("cuando") == "continua" and h.get("accion") == "modificarFuerza" \
                and (h.get("objetivo") or {}).get("quien") == "propio" and (h.get("modoFuerza") or "sumar") == "sumar":
            filtro = {**(h.get("objetivo") or {}), "quien": None}
            v += float(h.get("valor", 0) or 0) * sum(
                1 for x in p.j(a.controlador).aliados if x is not a and hab.coincide(p, x, filtro))
    return v


def _ganancia_de_repartir(p, yo, fuente, t: Instancia, alt: Instancia) -> float:
    """Cuánto gano si este removal va a `alt` y el otro (con límite) saca a `t`,
    frente a sacar a `t` ahora. No es una regla fija: depende de si el otro se
    puede usar hoy, de lo que cuesta usarlo (Cerridwen se destruye), de qué
    otro objetivo tendría igual y de si el castillo aguanta un turno de `t`."""
    mejor = None
    for c, h in _removals_con_limite(p, yo, fuente):
        filtro = {**(h.get("objetivo") or {}), "quien": None}
        if not hab.coincide(p, t, filtro):
            continue
        # Cerridwen está para gastarse así: su cuerpo pesa, pero no como un Aliado entero.
        cuerpo = 0.5 * max(0, hab.fuerza(p, c)) if (h.get("costo") or {}).get("destruirEstaCarta") else 0.0
        # Lo que ese removal sacaría igual si `t` se va ahora (no se pierde nada si no hay otro).
        otro = max((_valor_vivo(p, u) for u in p.e.instancias_en_juego(1 - yo)
                    if u is not t and u is not alt and hab.coincide(p, u, filtro)), default=0.0)
        g = _valor_vivo(p, alt) - cuerpo - max(0.0, otro - cuerpo)
        hoy = c.zona != Zona.MANO or p.puede_pagar(yo, c)
        if not hoy:
            # Un turno del rival con `t` en vez de con `alt`: lo que pega de más
            # (Godofredo además sube a sus Caballeros) pesa más con el castillo corto.
            extra = _pega_en_mesa(p, t) - _pega_en_mesa(p, alt)
            g -= max(0.0, extra) * (1.0 + _castillo_corto(p, yo))
        mejor = g if mejor is None else max(mejor, g)
    return mejor if mejor is not None else float("-inf")


_elegir_objetivos_previo_nec = Heuristico.elegir_objetivos


def _elegir_objetivos_segun_necesidad(self, p, yo, candidatos, n, h):
    elegidos = _elegir_objetivos_previo_nec(self, p, yo, candidatos, n, h)
    obj = h.get("objetivo") or {}
    if not _PLAN_SEGUN_NECESIDAD or n != 1 or len(elegidos) != 1 or h.get("accion") not in ("destruir", "desterrar") \
            or obj.get("quien") != "oponente" or obj.get("coste") or p.e.activo != yo:
        return elegidos
    fuente = getattr(p, "ctx_fuente_habilidad", None)
    t = elegidos[0]
    if t.controlador == yo or not _otro_removal_lo_cubre(p, yo, fuente, t):
        return elegidos
    # G1 T9: Aine a Persival y Cerridwen a Godofredo, solo si repartir rinde.
    otros = [(c, _ganancia_de_repartir(p, yo, fuente, t, c)) for c in candidatos
             if c.controlador != yo and c.tipo == Tipo.ALIADO and c is not t
             and not _otro_removal_lo_cubre(p, yo, fuente, c)]
    otros = [(c, g) for c, g in otros if g > 0.5]
    return [max(otros, key=lambda x: x[1])[0]] if otros else elegidos


Heuristico.elegir_objetivos = _elegir_objetivos_segun_necesidad


_valor_para_el_plan_previo = _valor_para_el_plan


def _valor_para_el_plan(p, yo, c: Instancia) -> float:  # noqa: F811
    """Beleth / Linaje Celta: además del plan de mesa, lo que la partida pide
    (removal si me superan, Caturix con el castillo corto, robo si hay calma)."""
    v = _valor_para_el_plan_previo(p, yo, c)
    if not _PLAN_SEGUN_NECESIDAD:
        return v
    v += 1.5 * _valor_necesidad(p, yo, c) - _castigo_golpe_que_me_bota(p, yo, c)
    if any(m.nombre == c.nombre for m in p.j(yo).mano):
        v -= 3.0  # ya tengo una en la mano
    return v


# ── Sidhes del Bosque: jugar bajo mi control un Aliado del Mazo rival ────────
# Veo su Mazo Castillo: la mejor es la que más rinde aquí (lo que hace por mí
# en esta partida) más lo que le quito (su carta clave ya no la va a robar).
def _robo_al_rival(h: dict) -> bool:
    obj = h.get("objetivo") or {}
    return h.get("accion") == "jugarDesde" and obj.get("quien") == "oponente" and "mazo" in hab.zonas_de(obj, "")


def _lo_que_le_quito(p, yo, c: Instancia) -> float:
    """Cuánto pierde el rival sin esa carta: su cuerpo y habilidades y, si
    potencia a su raza (Rey Arturo, Godofredo), cuántos de los suyos suben."""
    v = _valor_vivo(p, c) + 0.5 * c.carta.coste
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("cuando") == "continua" and obj.get("quien") == "propio" and obj.get("seleccion") == "todos":
            filtro = {**obj, "quien": None}
            v += 1.5 * sum(1 for a in p.j(1 - yo).aliados if hab.coincide(p, a, filtro))
    return v


def _valor_robo_al_rival(self, p, yo, c: Instancia) -> float:
    from .motor import Jugada

    return self._puntaje(p, yo, Jugada("jugar", c)) + _valor_necesidad(p, yo, c) + 0.5 * _lo_que_le_quito(p, yo, c)


def _candidatos_robo(p, yo, fuente, h) -> list[Instancia]:
    return [c for c in hab._candidatos_jugar(p, yo, fuente, h) if c.tipo == Tipo.ALIADO]


_utiles_jugar_desde_previo = Heuristico._utiles_jugar_desde


def _utiles_jugar_desde_robo(self, p, yo, fuente, h, pagando: int = 0):
    if _PLAN_SEGUN_NECESIDAD and _robo_al_rival(h):
        # La regla de La Llama Fría (traer algo más caro que ella) es para
        # mi mazo; aquí además le quito la carta al rival.
        return _candidatos_robo(p, yo, fuente, h)
    return _utiles_jugar_desde_previo(self, p, yo, fuente, h, pagando)


Heuristico._utiles_jugar_desde = _utiles_jugar_desde_robo

_jugar_desde_conviene_previo = Heuristico._jugar_desde_conviene


def _jugar_desde_conviene_robo(self, p, yo, fuente, h, pagando: int):
    if _PLAN_SEGUN_NECESIDAD and _robo_al_rival(h):
        cands = _candidatos_robo(p, yo, fuente, h)
        # Vale si lo que traigo rinde lo que cuesta el Talismán: un Aliado de
        # su coste o una pieza clave (removal, motor, el que potencia su raza).
        return any(_valor_robo_al_rival(self, p, yo, c) >= _UMBRAL_ROBO * max(1, fuente.carta.coste)
                   for c in cands)
    return _jugar_desde_conviene_previo(self, p, yo, fuente, h, pagando)


_UMBRAL_ROBO = 2.0
Heuristico._jugar_desde_conviene = _jugar_desde_conviene_robo

_valor_jugar_desde_previo = Heuristico._valor_jugar_desde


def _valor_jugar_desde_robo(self, p, yo, fuente, pagando: int = 0):
    if _PLAN_SEGUN_NECESIDAD:
        robos = [h for h in fuente.habilidades if _robo_al_rival(h)]
        if robos:
            vals = [_valor_robo_al_rival(self, p, yo, c) for h in robos for c in _candidatos_robo(p, yo, fuente, h)]
            return max(vals) if vals else None
    return _valor_jugar_desde_previo(self, p, yo, fuente, pagando)


Heuristico._valor_jugar_desde = _valor_jugar_desde_robo

_elegir_objetivos_previo_robo = Heuristico.elegir_objetivos


def _elegir_objetivos_robo(self, p, yo, candidatos, n, h):
    if _PLAN_SEGUN_NECESIDAD and _robo_al_rival(h) and candidatos:
        return sorted(candidatos, key=lambda c: -_valor_robo_al_rival(self, p, yo, c))[:n]
    return _elegir_objetivos_previo_robo(self, p, yo, candidatos, n, h)


Heuristico.elegir_objetivos = _elegir_objetivos_robo


def _elegir_mirar_tope(self, p, yo, fuente, vistas, modos):
    """Rhiannon: con las cartas a la vista, el modo que más aporta ahora (un
    Oro/Arma o los Aliados Desafiante), según lo que pide la partida."""
    mejor = (0, [], float("-inf"))
    for k, (elegibles, maximo) in enumerate(modos):
        if not elegibles or not maximo:
            continue
        picks = self.elegir_objetivos(p, yo, elegibles, min(maximo, len(elegibles)), {"accion": "mirarTope"})
        v = sum(_valor_carta(p, c) + _valor_necesidad(p, yo, c) for c in picks)
        if v > mejor[2]:
            mejor = (k, picks, v)
    return mejor[0], mejor[1]


Heuristico.elegir_mirar_tope = _elegir_mirar_tope



# ── Lecciones de 7 desafíos (2026-11-14), verificadas con 40 simulaciones ───
_LECCIONES_7 = True


def _remocion_al_jugar_sin_blanco(p, yo, c) -> bool:
    """Ganimedes (FeCs T6) con la mesa rival vacía: su "destruye al entrar" se
    pierde. Un Aliado cuyo cuerpo no destaca (fuerza ≤ coste) se guarda."""
    if c.tipo != Tipo.ALIADO or (c.carta.fuerza or 0) > (c.carta.coste or 0):
        return False
    # cuZm T3: Aine destierra en el "luego" (después de mostrar un Desafiante).
    entrada = [h for h in c.habilidades if h.get("cuando") == "al_jugar"]
    entrada += [e for h in entrada for e in h.get("luego") or [] if isinstance(e, dict)]
    habs = [h for h in entrada
            if h.get("accion") in (_REMOCION | {"barajar"})
            and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
            and "en_juego" in hab.zonas_de(h.get("objetivo") or {})]
    # Solo con la mesa rival vacía de esos tipos (Nephre-Ka sin Cementerio
    # para pagar igual se juega si el rival tiene Aliados: hace mesa).
    tipos = {t for h in habs for t in ((h.get("objetivo") or {}).get("tipos") or [])}
    return bool(habs) and not any(not tipos or x.tipo.value in tipos for x in p.e.instancias_en_juego(1 - yo)
                                  if x.tipo != Tipo.ORO)


_PREMIOS = {"robar", "buscar", "generarOro", "ponerEnJuego", "mirarTope", "jugarDesde"}


def _premio_al_salir(c) -> bool:
    """Draig Ifanc (busca un Oro al morir), Renpet (mira 2 y toma 1 al
    salir): sacarlo del juego le da algo a su dueño."""
    return any(h.get("cuando") in ("al_salir_del_juego", "al_ser_destruido", "al_morir")
               and h.get("accion") in _PREMIOS
               and (h.get("objetivo") or {}).get("quien", "propio") == "propio"
               for h in c.habilidades)


def _remocion_que_regala(p, yo, c) -> bool:
    """4NtK T3: Eter devolviendo a Renpet al tope le regalaba dos cartas (al
    salir y al volver a entrar). Si todo blanco rival premia al salir, no."""
    habs = [h for h in c.habilidades if h.get("cuando") == "al_jugar"
            and h.get("accion") in (_REMOCION | {"barajar"})
            and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera")
            and "en_juego" in hab.zonas_de(h.get("objetivo") or {})]
    blancos = [x for h in habs for x in hab.candidatos_validos(p, yo, c, h) if x.controlador != yo]
    return bool(blancos) and all(_premio_al_salir(x) for x in blancos)


_vale_la_pena_previo_7 = Heuristico._vale_la_pena


def _sin_par_igual(p, yo, c) -> bool:
    """vg1J T5: Ataque Fulminante baraja DOS Aliados rivales del mismo coste
    (o fuerza). Con un solo Aliado rival no hace nada: se perdían 4 Oros."""
    habs = [h for h in c.habilidades if h.get("cuando") == "al_jugar"
            and (h.get("objetivo") or {}).get("mismoValor") in ("coste", "fuerza")]
    if not habs:
        return False
    for h in habs:
        n = max(1, int(h.get("cantidad", 1) or 1))
        modo = h["objetivo"]["mismoValor"]
        grupos: dict[int, int] = {}
        for x in hab.candidatos_validos(p, yo, c, h):
            if x.controlador != yo:
                v = x.carta.coste if modo == "coste" else hab.fuerza(p, x)
                grupos[v] = grupos.get(v, 0) + 1
        if any(k >= n for k in grupos.values()):
            return False
    return True


def _achica_atacante(p, yo, j) -> bool:
    """tmi4 T9: Diente de la Bestia en la Guerra del rival, cuando me atacan:
    un atacante pierde su habilidad y 2 de fuerza (57% vs 25%)."""
    if j.tipo != "activar" or p.e.fase != "guerra_talismanes" or p.e.activo == yo or not p.atacantes:
        return False
    h = j.carta.habilidades[j.habilidad]
    efectos = [h] + [e for e in h.get("luego") or [] if isinstance(e, dict)]
    baja = any(e.get("accion") == "modificarFuerza" and int(e.get("valor") or 0) < 0 for e in efectos)
    if not baja or (h.get("objetivo") or {}).get("quien") != "oponente":
        return False
    return any(a in hab.candidatos_validos(p, yo, j.carta, h) for a in p.atacantes) \
        and len(p.j(yo).mazo) <= 20


def _vale_la_pena_7(self, p, yo, j):
    if _LECCIONES_7 and _achica_atacante(p, yo, j):
        return True
    if _LECCIONES_7 and j.tipo == "jugar" and j.carta is not None and _sin_par_igual(p, yo, j.carta):
        return False
    if _LECCIONES_7 and j.tipo == "jugar" and j.carta is not None and j.carta.tipo == Tipo.TALISMAN \
            and p.coste_de(yo, j.carta) == 0 and any(
                h.get("cuando") == "al_jugar" and h.get("accion") == "buscar"
                and (h.get("zonaDestino") or "mano") == "mano" and hab.candidatos_validos(p, yo, j.carta, h)
                for h in j.carta.habilidades):
        return True  # z7to T8: Aton (coste 0, busca un Oro) es una carta gratis: 1 turno vs 3,2
    if _LECCIONES_7 and j.tipo == "jugar" and j.carta is not None and p.e.activo == yo \
            and (_remocion_al_jugar_sin_blanco(p, yo, j.carta) or _remocion_que_regala(p, yo, j.carta)):
        return False
    if _LECCIONES_7 and j.tipo == "activar" and p.e.fase == "guerra_talismanes" and p.atacantes:
        h = j.carta.habilidades[j.habilidad]
        if h.get("accion") == "perderHabilidad" and h.get("duracion") == "hasta_fase_final":
            # 5R9h T5: Carnwennan al Draig Ifanc que bloquea y muere: sin
            # habilidad no busca el Oro que le dio la Lady Calvaur (42% → 75%).
            por_uid = {a.uid: a for a in p.atacantes}
            cands = set(map(id, hab.candidatos_validos(p, yo, j.carta, h)))
            for atk_uid, b in (p.bloqueos or {}).items():
                atk = por_uid.get(atk_uid)
                if atk is not None and b.controlador != yo and id(b) in cands and _premio_al_salir(b) \
                        and hab.fuerza(p, atk) >= hab.fuerza(p, b):
                    p._carnwennan_objetivo = (p.e.turno, b.uid)
                    return True
    if _LECCIONES_7 and _abre_paso_al_ataque(p, yo, j):
        return True
    return _vale_la_pena_previo_7(self, p, yo, j)


def _abre_paso_al_ataque(p, yo, j) -> bool:
    """ZTSY T9: Bola de Fuego en mi Vigilia al único bloqueador rival (Bran):
    todos mis atacantes pasan. Excepción a "la Bola espera la Guerra rival"."""
    if j.tipo != "jugar" or j.carta is None or j.carta.tipo != Tipo.TALISMAN             or p.e.fase != "vigilia" or p.e.activo != yo:
        return False
    habs = [h for h in j.carta.habilidades if h.get("cuando") == "al_jugar"
            and h.get("accion") in _REMOCION and "en_juego" in hab.zonas_de(h.get("objetivo") or {})]
    if not habs:
        return False
    bloqueadores = [b for b in p.j(1 - yo).defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")]
    mios = [a for a in p.j(yo).aliados if _puede_atacar(p, a) and hab.fuerza(p, a) > 0]
    if len(bloqueadores) != 1 or len(mios) < 2:
        return False
    blanco = bloqueadores[0]
    return any(blanco in hab.candidatos_validos(p, yo, j.carta, h) for h in habs)         and p.coste_de(yo, j.carta) <= p.j(yo).oro_disponible


Heuristico._vale_la_pena = _vale_la_pena_7


_usar_opcional_previo_7 = Heuristico.usar_opcional


def _usar_opcional_7(self, p, yo, fuente, h):
    """4NtK T3: Eter puede (no debe) devolver a Renpet; si todo blanco rival
    premia al salir, el efecto no se usa y Eter queda como cuerpo."""
    obj = (h or {}).get("objetivo") or {}
    if _LECCIONES_7 and (h or {}).get("cuando") == "al_jugar" \
            and (h or {}).get("accion") in (_REMOCION | {"barajar"}) \
            and obj.get("quien") in ("oponente", "cualquiera") and "en_juego" in hab.zonas_de(obj):
        blancos = [x for x in hab.candidatos_validos(p, yo, fuente, h) if x.controlador != yo]
        if blancos and all(_premio_al_salir(x) for x in blancos):
            return False
    return _usar_opcional_previo_7(self, p, yo, fuente, h)


Heuristico.usar_opcional = _usar_opcional_7


def _mejor_busqueda(p, yo, j) -> float:
    """Valor de lo mejor que trae a la mano un "buscar" (Rito de Atón)."""
    h = j.carta.habilidades[j.habilidad]
    if h.get("accion") != "buscar" or (h.get("zonaDestino") or "mano") != "mano":
        return 0.0
    cands = [c for c in hab.candidatos_validos(p, yo, j.carta, h) if c.controlador == yo]
    return max((_valor_carta(p, c) + _valor_necesidad(p, yo, c) for c in cands), default=0.0)


_UMBRAL_BUSQUEDA = 8.0  # una respuesta a la amenaza (Neferite contra Rey Arturo)

_elegir_jugada_previo_7 = Heuristico.elegir_jugada


def _oro_de_remocion_sin_blanco(p, yo, c) -> bool:
    """cuZm T3: Ceangal An Fhanaigh destruye al entrar; con la mesa rival
    vacía se pierde. Mejor bajar otro Oro (Carmix) y guardarlo (92% vs 58%)."""
    entrada = [h for h in c.habilidades if h.get("cuando") == "al_jugar"]
    if c.tipo != Tipo.ORO or not entrada:
        return False
    if not all(h.get("accion") in _REMOCION and "en_juego" in hab.zonas_de(h.get("objetivo") or {})
               and (h.get("objetivo") or {}).get("quien") in ("oponente", "cualquiera") for h in entrada):
        return False
    return not any(x.tipo != Tipo.ORO for x in p.e.instancias_en_juego(1 - yo))


def _motor_de_robo(c) -> bool:
    """Bruja Anís: un Aliado que roba solo cada turno (Fase Final o activado)."""
    return c.tipo == Tipo.ALIADO and any(
        h.get("accion") == "robar" and (h.get("cuando") == "al_inicio_fase"
                                        or (h.get("cuando") == "activada" and not (h.get("costo") or {})))
        for h in c.habilidades)


def _elegir_jugada_7(self, p, yo, jugadas):
    elegida = _elegir_jugada_previo_7(self, p, yo, jugadas)
    if _LECCIONES_7 and elegida.tipo == "pasar" and p.e.fase == "vigilia" and p.e.activo == yo \
            and p.e.turno <= 4 and not p.j(1 - yo).aliados:
        # P3Cy T1: guardaba Oros para la Capa de Invisibilidad con el rival
        # sin mesa y pasaba; Bruja Anís en T1 roba cada turno (45% → 82%).
        motores = [j for j in jugadas if j.tipo == "jugar" and j.carta is not None and _motor_de_robo(j.carta)
                   and hab.condicion_ok(p, yo, next(h for h in j.carta.habilidades if h.get("accion") == "robar"))
                   is not None and self._vale_la_pena(p, yo, j)]
        if motores:
            return max(motores, key=lambda j: self._puntaje(p, yo, j))
    if _LECCIONES_7 and elegida.tipo == "oro" and _oro_de_remocion_sin_blanco(p, yo, elegida.carta):
        otros = [j for j in jugadas if j.tipo == "oro" and not _oro_de_remocion_sin_blanco(p, yo, j.carta)]
        if otros:
            return _elegir_jugada_previo_7(self, p, yo, [j for j in jugadas if j not in
                                                         [x for x in jugadas if x.tipo == "oro" and x not in otros]])
    if _LECCIONES_7 and p.e.fase == "vigilia" and p.e.activo == yo and elegida.tipo == "activar"             and elegida.carta.habilidades[elegida.habilidad].get("accion") == "robar":
        # kZYc T7: robar gratis primero (Biblioteca) se adelantaba a buscar la
        # respuesta en el Cementerio (Rito de Atón trae a Neferite).
        busquedas = [(j, _mejor_busqueda(p, yo, j)) for j in jugadas if j.tipo == "activar"]
        busquedas = [(j, v) for j, v in busquedas if v >= _UMBRAL_BUSQUEDA and self._vale_la_pena(p, yo, j)]
        if busquedas:
            return max(busquedas, key=lambda x: x[1])[0]
    return elegida


Heuristico.elegir_jugada = _elegir_jugada_7


def _bonus_lecciones_7(p, yo, j) -> float:
    if j.tipo != "jugar" or j.carta is None or j.carta.tipo != Tipo.ALIADO or j.carta.zona != Zona.MANO:
        return 0.0  # solo lo que se juega ahora (no al valorar el Cementerio)
    c, rival, v = j.carta, p.j(1 - yo), 0.0
    if _en_peligro(p, yo) or (len(p.j(yo).mazo) <= 12 and len(rival.aliados) > len(p.j(yo).aliados)):
        # lj65 T8: bajo presión, Perseo (se destierra para barajar un Aliado
        # rival) vale el removal que trae, no solo su cuerpo (33% vs 3%).
        for h in c.habilidades:
            obj = h.get("objetivo") or {}
            costo = h.get("costo") or {}
            if h.get("cuando") == "activada" and h.get("accion") in (_REMOCION | {"barajar"}) \
                    and (costo.get("desterrarEstaCarta") or costo.get("destruirEstaCarta")) \
                    and obj.get("quien") == "oponente" and "en_juego" in hab.zonas_de(obj):
                blancos = sorted((_valor_vivo(p, a) for a in rival.aliados if hab.coincide(p, a, obj)), reverse=True)
                copias = sum(1 for x in p.j(yo).mano if x.nombre == c.nombre)  # cada copia saca uno
                v += 1.5 * sum(blancos[:copias])
                break
    for h in c.habilidades:
        obj = h.get("objetivo") or {}
        if h.get("accion") == "ponerEnJuego" and obj.get("nombrarCarta") and obj.get("zona") == "mano" \
                and obj.get("quien") == "oponente":
            # HIM0 T7 Sir Bedivere: nombra un Aliado de la mano rival y se lo
            # queda. Sin saber qué tiene es una moneda al aire (Héctor: la
            # Guardia Gozosa es removal seguro); con un Aliado ya visto en su
            # mano, es un robo casi seguro y se repite cada turno.
            vistos = [x for x in rival.mano if getattr(x, "revelada", False) and x.tipo == Tipo.ALIADO]
            pozo = [x for x in rival.mano + rival.mazo if x.tipo == Tipo.ALIADO]
            if vistos:
                v += 2.0 * max(_valor_carta(p, x) for x in vistos)
            elif pozo and rival.mano:
                cuenta = {}
                for x in pozo:
                    cuenta[x.nombre] = cuenta.get(x.nombre, 0) + 1
                nombre, n = max(cuenta.items(), key=lambda kv: kv[1])
                total = len(rival.mano) + len(rival.mazo)
                acierto = 1 - (1 - n / total) ** len(rival.mano)
                media = sum(_valor_carta(p, x) for x in pozo if x.nombre == nombre) / n
                v += 0.5 * acierto * media
        if h.get("cuando") == "propia_entra" and "Arma" in (h.get("disparoTipos") or []) \
                and h.get("accion") in _REMOCION and rival.aliados:
            # tInn T5 Djoser: con un Arma en la mano, destruye un Aliado rival
            # al equiparla. Héctor: vale contra un rival agro que me supera en
            # mesa (hay que limpiarla rápido); si no, Ptolomeo II protege mejor.
            suyos = sum(max(0, hab.fuerza(p, a)) for a in rival.aliados)
            mios = sum(max(0, hab.fuerza(p, a)) for a in p.j(yo).aliados)
            if any(x.tipo == Tipo.ARMA for x in p.j(yo).mano) and suyos >= mios:
                v += 0.8 * max(_valor_vivo(p, a) for a in rival.aliados)
    if hab.tiene_prop(p, c, "furia") and not any(
            not hab.tiene_estado(p, b, "no_puede_bloquear") for b in rival.defensa):
        # FeCs T8 Teseo: Furia contra una mesa sin bloqueadores pega ya.
        # Héctor: si el rival tiene Oros para responder (Red de Plata,
        # Flechas), el golpe no es seguro: vale la mitad.
        v += (0.6 if p.j(1 - yo).oro_disponible == 0 else 0.3) * (c.carta.fuerza or 0)
    return v


def _bonus_buff_de_raza(p, yo, j) -> float:
    """vg1J T3: Panteón (+2 a mis Aliados si controlo un Olímpico) valía 6,1
    porque aún no había Olímpico en mesa (62% vs 90%). Cuenta los Aliados que
    tengo y los de esa raza que puedo bajar pronto."""
    if j.tipo != "jugar" or j.carta is None or j.carta.tipo != Tipo.TOTEM or j.carta.zona != Zona.MANO:
        return 0.0
    v = 0.0
    for h in j.carta.habilidades:
        cond = h.get("condicion") or {}
        if h.get("cuando") != "continua" or h.get("accion") != "modificarFuerza" \
                or (h.get("objetivo") or {}).get("quien") != "propio" or cond.get("tipo") != "aliados_raza":
            continue
        raza = cond.get("raza", "")
        if any(hab._raza_ok(a, raza) for a in p.j(yo).aliados):
            continue  # la condición ya se cumple: el puntaje base lo cuenta
        pronto = [c for c in p.j(yo).mano if c.tipo == Tipo.ALIADO and hab._raza_ok(c, raza)
                  and p.coste_de(yo, c) <= p.j(yo).oro_disponible + 1]
        if pronto:
            v += int(h.get("valor") or 0) * min(3, len(p.j(yo).aliados) + len(pronto))
    return v


def _bonus_habilita_furia(p, yo, j) -> float:
    """Simulación yI09 T7: Tótem de la Serpiente antes que Gronw Pebyr. Con un
    Tótem en mesa, Gronw entra con Furia e Imbloqueable y pega ese turno (fuerza
    2 +1 por Tótem +1 del buff). Vale el golpe inmediato si alcanza para los dos."""
    if j.tipo != "jugar" or j.carta is None or j.carta.tipo != Tipo.TOTEM or j.carta.zona != Zona.MANO:
        return 0.0
    if any(x.tipo == Tipo.TOTEM for x in p.j(yo).apoyo):
        return 0.0  # ya tengo Tótem: la Furia ya está habilitada
    quedan = p.j(yo).oro_disponible - p.coste_de(yo, j.carta)
    mejor = 0.0
    for c in p.j(yo).mano:
        if c is j.carta or c.tipo != Tipo.ALIADO or p.coste_de(yo, c) > quedan:
            continue
        cond = [h for h in c.habilidades if h.get("accion") in ("furia", "imbloqueable")
                and (h.get("condicion") or {}).get("tipo") == "totems_propios"]
        if not any(h.get("accion") == "furia" for h in cond):
            continue
        fuerza = (c.carta.fuerza or 0) + sum(1 for h in c.habilidades if h.get("valorPorCada") == "totem_en_juego")
        fuerza += sum(int(h.get("valor") or 0) for h in j.carta.habilidades
                      if h.get("accion") == "modificarFuerza" and h.get("cuando") == "continua"
                      and hab._raza_ok(c, (h.get("objetivo") or {}).get("raza", "")))
        golpe = fuerza * (1.0 if any(h.get("accion") == "imbloqueable" for h in cond) else 0.6)
        mejor = max(mejor, golpe)
    return mejor


_puntaje_previo_7 = Heuristico._puntaje


def _puntaje_7(self, p, yo, j):
    base = _puntaje_previo_7(self, p, yo, j)
    if not _LECCIONES_7:
        return base
    v = base + _bonus_lecciones_7(p, yo, j) + _bonus_habilita_furia(p, yo, j) + _bonus_buff_de_raza(p, yo, j)
    if j.tipo == "jugar" and j.carta is not None and j.carta.tipo == Tipo.TOTEM \
            and any(x.nombre == j.carta.nombre for x in p.j(yo).apoyo) \
            and any(h.get("accion") == "robar" and h.get("cuando") not in ("activada", "continua")
                    for h in j.carta.habilidades):
        # ezWO T8: la segunda copia de País Sin Luz dobla un robo que ya
        # tengo; robé 5 y descarté a Oillipheist por exceso de mano.
        v -= 0.5 * base
    return v


Heuristico._puntaje = _puntaje_7


def _cementerio_protegido(p, yo) -> bool:
    """Cinturón de Lady Ann en mi Reserva: nadie destierra de los Cementerios."""
    return any(h.get("accion") == "restriccion" and h.get("modo") == "desterrar_cementerio"
               for x in p.j(yo).reserva for h in x.habilidades)


_elegir_objetivos_previo_7 = Heuristico.elegir_objetivos


def _elegir_objetivos_7(self, p, yo, candidatos, n, h):
    obj = (h or {}).get("objetivo") or {}
    if _LECCIONES_7 and (h or {}).get("accion") == "barajar" and obj.get("quien") == "propio"             and candidatos and all(c.controlador == yo and c.zona == Zona.CEMENTERIO for c in candidatos)             and _rival_destierra_cementerio(p, yo) and not _cementerio_protegido(p, yo):
        # Héctor: con Escarabeo rival a la vista y sin Cinturón de Lady Ann,
        # barajar en el castillo salva del destierro lo más valioso del
        # Cementerio (Lady Calvaur antes que otra copia de Killgharrah).
        return sorted(candidatos, key=lambda c: -_valor_carta(p, c))[:n]
    return _elegir_objetivos_previo_7(self, p, yo, candidatos, n, h)


Heuristico.elegir_objetivos = _elegir_objetivos_7


_elegir_atacantes_previo_7 = Heuristico.elegir_atacantes


def _elegir_atacantes_7(self, p, yo, candidatos):
    """kZYc T6: Erec y Persival atacaron juntos y la mesa quedó sin quien
    bloquee el contraataque (38%; solo Erec, 82%). Si el rival me devuelve más
    atacantes de los que me quedan para bloquear y el ataque no es letal, el
    más débil que puede frenar a uno de sus Aliados se queda en casa."""
    out = _elegir_atacantes_previo_7(self, p, yo, candidatos)
    if not _LECCIONES_7 or len(out) < 2:
        return out
    rival = p.j(1 - yo)
    suyos = [a for a in rival.aliados if hab.fuerza(p, a) > 0]
    quedan = [a for a in p.j(yo).defensa if a not in out]
    if len(suyos) <= len(quedan) or sum(max(0, hab.fuerza(p, c)) for c in out) >= len(rival.mazo):
        return out
    # Auditoría 15-11 (uX2m T5, z7to T8): solo si el contraataque duele (≥20%
    # del castillo) y el que se queda frena al atacante rival más fuerte; si
    # no, guardarlo solo resta daño (Fergus contra 5 de daño; un Beleth de 2).
    if sum(max(0, hab.fuerza(p, a)) for a in suyos) < 0.2 * len(p.j(yo).mazo):
        return out
    fuerte = max(hab.fuerza(p, a) for a in suyos)
    frenan = [c for c in out if hab.fuerza(p, c) > fuerte and not hab.tiene_prop(p, c, "imbloqueable")
              and not _obliga_a_bloquear(c)]  # el Demoledor ataca para obligar
    if not frenan:
        return out
    casa = min(frenan, key=lambda c: hab.fuerza(p, c))
    return [c for c in out if c is not casa]


Heuristico.elegir_atacantes = _elegir_atacantes_7

# Opcional: Vigilia (con "pasar") + ataques por simulación: jugador "busqueda_vigilia".
if f"{__package__}.busqueda_vigilia" not in _sys.modules:
    from .busqueda_vigilia import BuscadorVigilia  # noqa: E402,F401
