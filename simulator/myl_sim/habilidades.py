"""Ejecución de habilidades parametrizadas (formato de card_habilidad.dart).

Cada habilidad es un dict con: accion, cuando, fase, turno, condicion, costo,
objetivo, cantidad, valor, modoFuerza, zonaDestino, duracion, opcional,
limitePorTurno. Un valor desconocido nunca rompe la partida: se ignora.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from .modelo import Instancia, ModFuerza, Tipo, Zona

if TYPE_CHECKING:  # pragma: no cover
    from .motor import Partida

PROPIEDADES = {"imbloqueable", "indestructible", "indesterrable", "noAnulable", "furia"}
UNA_COPIA_EN_JUEGO = re.compile(r"s[óo]lo puedes tener (?:un|una|1)\b[^.]*en juego", re.I)

# Fases en que una habilidad "cualquiera" se puede activar o un Talismán jugar.
VENTANAS_LIBRES = {"vigilia", "guerra_talismanes"}

_ZONAS_EN_JUEGO = {
    "linea_defensa": [Zona.DEFENSA],
    "linea_ataque": [Zona.ATAQUE],
    "linea_apoyo": [Zona.APOYO],
    "reserva_oro": [Zona.RESERVA],
    "oro_pagado": [Zona.PAGADO],
    "en_juego": [Zona.DEFENSA, Zona.ATAQUE, Zona.APOYO, Zona.RESERVA, Zona.PAGADO],
}
_ZONAS_FUERA = {
    "mano": Zona.MANO,
    "mazo": Zona.MAZO,
    "cementerio": Zona.CEMENTERIO,
    "destierro": Zona.DESTIERRO,
}


def tiene_prop(p: "Partida", inst: Instancia, accion: str) -> bool:
    """¿La carta tiene esta propiedad ahora? Respeta su turno y condición
    (p. ej. "no puede ser anulada si controlas 2 o más Aliados")."""
    def activa(h: dict, quien: int) -> bool:
        return h.get("accion") == accion and turno_ok(p, quien, h) and condicion_ok(p, quien, h)

    if any(e.get("modo") == f"prop:{accion}" for e in inst.estados):
        return True
    if accion == "guardian" and any(e.get("modo") == "sin_guardian" for e in inst.estados):
        return False  # Osiris le quitó "no puede ser declarado atacante"
    # Julio César: "tus demás Aliados son imbloqueables" (continua de otra carta).
    for s, h in _continuas(p, "otorgarPropiedad"):
        obj = h.get("objetivo") or {}
        if (h.get("modo") or "indestructible") != accion or obj.get("quien") == "esta_carta":
            continue
        if inst.controlador in _lados(s.controlador, obj.get("quien", "propio")) \
                and (coincide(p, inst, obj) or _oro_convertido_coincide(p, inst, obj)) \
                and not _excluida(s, inst, obj) and inst.en_juego:
            return True

    for h in inst.habilidades:
        if not activa(h, inst.controlador):
            continue
        # En un Arma, la propiedad puede ser de su portador, no del Arma.
        if inst.tipo == Tipo.ARMA and _aplica_a_portador(h):
            continue
        return True
    if inst.tipo == Tipo.ALIADO:
        for arma in p.e.portadas:
            if arma.portador == inst.uid and any(
                activa(h, arma.controlador) and _aplica_a_portador(h)
                and _raza_ok(inst, h.get("portadorRaza") or "") for h in arma.habilidades
            ):
                return True
    return False


def _oro_convertido_coincide(p: "Partida", inst: Instancia, obj: dict) -> bool:
    """Mercaderes vuelto Aliado sigue siendo un Oro: la Corona de Arturo
    ("los Oros son indestructibles") también lo cubre en la Línea de Defensa."""
    if inst.carta.tipo != Tipo.ORO or inst.tipo == Tipo.ORO or "Oro" not in (obj.get("tipos") or []):
        return False
    return coincide(p, inst, {**obj, "tipos": [], "zona": "en_juego", "zonas": []})


_PROPIEDADES_DE_ALIADO = {"imbloqueable", "furia", "guardian", "retador", "sinLimiteArmas"}


def _aplica_a_portador(h: dict) -> bool:
    """Propiedad de Arma: ¿es de su portador? (por defecto, las de Aliado)."""
    quien = (h.get("objetivo") or {}).get("quien")
    if quien in ("esta_carta", "el_arma"):
        return quien == "esta_carta"
    return h.get("accion") in _PROPIEDADES_DE_ALIADO


# ── Comparaciones, condiciones y filtros ──────────────────────────────────────
def cumple(op: str, a: int, b: int) -> bool:
    return {
        ">=": a >= b,
        "<=": a <= b,
        "==": a == b,
        ">": a > b,
        "<": a < b,
    }.get(op, False)


def _lados(i: int, quien: str) -> list[int]:
    return {"propio": [i], "oponente": [1 - i], "cualquiera": [i, 1 - i], "ambos": [i, 1 - i]}.get(
        quien, [1 - i]
    )


def condicion_ok(p: "Partida", i: int, h: dict) -> bool:
    c = h.get("condicion") or {}
    tipo = c.get("tipo", "ninguna")
    if tipo == "ninguna":
        return True
    fuente = getattr(p, "ctx_fuente_habilidad", None)
    if fuente is not None and tipo in ("esta_carta_ataco", "esta_carta_no_ataco"):
        fuente = _esta_carta(p, fuente) or fuente  # Casco de Hades: el que ataca es el portador
    if tipo == "esta_carta_ataco":
        return fuente is not None and fuente.uid in getattr(p, "ataco_este_turno", set())
    if tipo == "esta_carta_no_ataco":  # Conn: "en respuesta a que no sea declarado atacante"
        return fuente is not None and fuente.uid not in getattr(p, "ataco_este_turno", set())
    if tipo == "aliados_atacaron":
        return cumple(c.get("op", ">="), len(p.ataco_este_turno_inst(i)), int(c.get("valor", 1)))
    if tipo == "oponente_activo":  # Aaru: el rival declaró el ataque de este turno.
        return p.e.activo == 1 - i
    if tipo == "controla_nombre":
        nombre = str(c.get("nombre") or "").casefold()
        return bool(nombre) and any(
            x.nombre.casefold() == nombre for x in p.e.instancias_en_juego(i)
        )
    if tipo == "aliados_destruidos_turno":
        return cumple(c.get("op", ">="), p.aliados_destruidos_turno, int(c.get("valor", 1)))
    if tipo == "carta_cementerio_nombre":
        nombre = str(c.get("nombre") or "").casefold()
        return bool(nombre) and cumple(
            c.get("op", ">="),
            sum(1 for x in p.j(i).cementerio if x.nombre.casefold() == nombre and x is not fuente),
            int(c.get("valor", 1)),
        )
    if tipo == "carta_cementerio_arquetipo":
        arquetipo = str(c.get("arquetipo") or "")
        return bool(arquetipo) and cumple(
            c.get("op", ">="),
            sum(1 for x in p.j(i).cementerio if _arquetipo_ok(x, arquetipo) and x is not fuente),
            int(c.get("valor", 1)),
        )
    if tipo == "aliados_fuerza_min":
        minimo = int(c.get("fuerzaMin", 0))
        return cumple(c.get("op", ">="),
                      sum(1 for x in p.j(i).aliados if fuerza(p, x) >= minimo),
                      int(c.get("valor", 1)))
    if tipo == "descarto_este_turno":
        return cumple(c.get("op", ">="), p.descartadas_turno[i], int(c.get("valor", 1)))
    if tipo == "cartas_arquetipo_en_juego":
        arquetipo = str(c.get("arquetipo") or "")
        return bool(arquetipo) and cumple(
            c.get("op", ">="),
            sum(1 for x in p.e.instancias_en_juego(i) if _arquetipo_ok(x, arquetipo)),
            int(c.get("valor", 1)),
        )
    if tipo == "oros_cementerio":
        return cumple(c.get("op", ">="),
                      sum(1 for x in p.j(i).cementerio if x.tipo == Tipo.ORO),
                      int(c.get("valor", 1)))
    if tipo == "bloquea_imbloqueable":  # Niamh
        return fuente is not None and any(
            b is fuente and tiene_prop(p, a, "imbloqueable") for a in p.atacantes for u, b in p.bloqueos.items()
            if u == a.uid)
    especiales = {
        # Sir Dinadan: "si este Aliado porta una o más Armas".
        "porta_armas": lambda: sum(1 for a in p.e.portadas if fuente is not None and a.portador == fuente.uid),
        # Eros: "si entra en juego en tu primer turno".
        "primer_turno": lambda: 1 if p.e.turno <= 2 else 0,
        # Reina Merrow: "si hizo daño al Mazo Castillo oponente" (este turno).
        "hizo_dano": lambda: 1 if fuente is not None and fuente.uid in p.dano_hecho else 0,
        # Caldero de Corff: Aliados de la raza en tu Línea de Ataque.
        "atacantes_raza": lambda: sum(1 for a in p.j(i).ataque if _raza_ok(a, c.get("raza", ""))),
        # Mut: "si tienes más cartas en el destierro que tu oponente" (> 0).
        "destierro_vs_oponente": lambda: len(p.j(i).destierro) - len(p.j(1 - i).destierro),
        # Osorkhon / Serpiente Roja / Martillo de Hefestos (su portador): 1 si
        # esta carta está en la línea indicada ("linea_ataque" / "linea_defensa").
        "esta_carta_en_linea": lambda: 1 if fuente is not None and (_esta_carta(p, fuente) or fuente).zona == {
            "linea_ataque": Zona.ATAQUE, "linea_defensa": Zona.DEFENSA}.get(c.get("zona", "linea_defensa")) else 0,
        # Neftis: "si es el único Aliado declarado bloqueador".
        "unico_bloqueador": lambda: 1 if fuente is not None and len(p.bloqueos) == 1
        and any(b is fuente for b in p.bloqueos.values()) else 0,
        # León de Nemea: "si en tu Cementerio tienes 3 o más Aliados de raza Titán".
        "cementerio_raza": lambda: sum(1 for x in p.j(i).cementerio
                                       if x.tipo == Tipo.ALIADO and _raza_ok(x, c.get("raza", ""))),
        # Atalanta la Amazona: "si controlas 1 o más Armas" (portadas por quien sea).
        "armas_propias": lambda: armas_propias(p, i),
    }
    if tipo in especiales:
        return cumple(c.get("op", ">="), especiales[tipo](), int(c.get("valor", 1)))
    yo, rival = p.j(i), p.j(1 - i)
    valor = {
        "aliados_propios": len(yo.aliados),
        "aliados_oponente": len(rival.aliados),
        "oros_reserva": len(yo.reserva),
        "cartas_mano": len(yo.mano),
        "cartas_mazo": len(yo.mazo),
        "cartas_cementerio": len(yo.cementerio),
        # "Si controlas un Aliado Faraón" se mira sin contar al que está
        # entrando y dispara la habilidad (Corona Faraónica con Jentakus I).
        "aliados_raza": sum(
            1 for a in yo.aliados
            if _raza_ok(a, c.get("raza", "")) and a is not getattr(p, "ctx_disparadora", None)
        ),
        "oros_en_juego": oros_en_juego(p, i),
        "oros_vs_oponente": oros_en_juego(p, i) - oros_en_juego(p, 1 - i),
    }.get(tipo)
    entrando = getattr(p, "ctx_disparadora", None)
    if tipo == "aliados_arquetipo":  # Averix / Guerrero Escorpión.
        # En disparos de fase no hay ``ctx_disparadora``: la fuente debe
        # excluirse igual, pues Escorpión pide *otro* Guerrero en mesa.
        # ``incluyeFuente``: cuenta a todos, también a esta carta (Minotauro
        # del Hades: "si controlas otro Minotauro" = 2 o más contándolo; así
        # no depende de qué habilidad se esté resolviendo en ese momento).
        todos = bool(c.get("incluyeFuente"))
        valor = sum(
            1 for a in yo.aliados
            if _arquetipo_ok(a, c.get("arquetipo", "")) and (todos or (a is not entrando and a is not fuente))
        )
    elif tipo == "aliados_no_raza":  # Menhir: "si todos tus Aliados son Defensor" (== 0)
        valor = sum(1 for a in yo.aliados if not _raza_ok(a, c.get("raza", "")))
    elif tipo == "aliados_misma_raza":  # Morir de Pie: "2 o más Aliados de una misma raza"
        cuenta: dict[str, int] = {}
        for a in yo.aliados:
            if a.raza:
                cuenta[a.raza.lower()] = cuenta.get(a.raza.lower(), 0) + 1
        valor = max(cuenta.values(), default=0)
    elif tipo == "aliados_vs_oponente":  # Orestes: "menos Aliados que tu oponente" (< 0)
        valor = len([a for a in yo.aliados if a is not entrando]) - len(rival.aliados)
    elif tipo == "mano_arquetipo":  # Marmita Druida: "mostrar una carta Druida"
        valor = sum(1 for x in yo.mano if _arquetipo_ok(x, c.get("arquetipo", "")))
    elif tipo == "mano_raza":  # Roxana: mostrar un Aliado Faraón de la mano.
        valor = sum(1 for x in yo.mano if _raza_ok(x, c.get("raza", "")))
    elif tipo == "atacantes_arquetipo":  # Guerrero Escorpión: "si Aliados Guerrero fueron declarados atacantes"
        valor = sum(
            1 for a in p.ataco_este_turno_inst(i) if _arquetipo_ok(a, c.get("arquetipo", ""))
        )
    elif tipo == "aliados_coste":  # Mago Merlín: Aliados de coste 3 o más.
        coste = c.get("coste") or {}
        valor = sum(
            1 for a in yo.aliados
            if cumple(coste.get("op", ">="), a.carta.coste, int(coste.get("valor", 0)))
        )
    elif tipo == "totems_propios":
        valor = sum(1 for x in p.e.instancias_en_juego(i) if x.tipo == Tipo.TOTEM)
    if valor is None:
        return True  # condición desconocida: no bloquea
    return cumple(c.get("op", ">="), valor, int(c.get("valor", 1)))


def _sigue_indestructible(p: "Partida", x: Instancia, h: dict) -> bool:
    """Indestructible aún después de perder la habilidad (Artabano)."""
    if not h.get("antesPerderHabilidad") or x.sin_habilidad_hasta is not None:
        return tiene_prop(p, x, "indestructible")
    anterior = x.sin_habilidad_hasta
    try:
        x.sin_habilidad_hasta = "hasta_fase_final"
        return tiene_prop(p, x, "indestructible")
    finally:
        x.sin_habilidad_hasta = anterior


def turno_ok(p: "Partida", i: int, h: dict) -> bool:
    turno = h.get("turno", "cualquiera")
    activo = p.e.activo == i
    return turno == "cualquiera" or (turno == "propio") == activo


def mostrar_a(p: "Partida", i: int, titulo: str, cartas: list) -> None:
    """La persona ve estas cartas en ese momento (la mano rival con Sir
    Bedivere o Cultistas) sin que queden descubiertas después."""
    ver = getattr(p.decide(i), "ver_cartas", None)
    if ver is not None and cartas:
        ver(p, i, titulo, list(cartas))


_MUESTRA_MAZO = re.compile(r"(mostrar|muestra)\s+(?:las?\s+)?(?:\w+\s+){0,2}cartas?\s+"
                           r"(?:de\s+la\s+parte\s+superior\s+)?de\s+(?:tu|su)\s+mazo")


def _dice_mostrar(fuente: Instancia) -> bool:
    """El texto dice que las cartas del Mazo se muestran (Estrella de Belén,
    Tom Thumb). Desafío LyCy: Látigo y Bastón "muestra un Guerrero de tu Mano"
    pero solo *mira* la primera del Mazo: esa la ve solo quien la juega."""
    return bool(_MUESTRA_MAZO.search((fuente.carta.texto or "").casefold()))


def mostrar_mano_rival(p: "Partida", i: int, fuente: Instancia) -> None:
    """Una sola vez por resolución: la persona ve la mano rival completa."""
    clave = (p.e.turno, fuente.uid)  # Cultistas: mirar y luego barajar, una vez
    if getattr(p, "_mano_mostrada", None) == clave:
        return
    p._mano_mostrada = clave
    mano = p.j(1 - i).mano
    mostrar_a(p, i, f"{fuente.nombre}: la mano del rival", mano)
    p.anotar(f"{fuente.nombre}: la mano de J{1 - i} es " + privado(i, ", ".join(x.nombre for x in mano) or "(vacía)"))


_MARCA_PRIVADA = __import__("re").compile(r"⟪J\d\|(.*?)⟫")


def sin_marcas(texto: str) -> str:
    """Narración completa (simulaciones, repetición al final): sin las marcas
    de privado, con el texto a la vista."""
    return _MARCA_PRIVADA.sub(lambda m: m.group(1), texto)


def privado(i: int, texto: str) -> str:
    """Texto que solo ve el jugador i (el Desafío IA lo oculta al otro)."""
    return f"⟪J{i}|{texto}⟫"


def fase_ok(p: "Partida", h: dict, fase: str | None = None) -> bool:
    actual = fase or p.e.fase
    if h.get("fases"):  # Escudo Miliciano: en la Declaración de Ataque o de Bloqueo
        return actual in h["fases"]
    f = h.get("fase", "cualquiera")
    if f == "cualquiera":
        return True
    return f == actual


def _raza_ok(inst: Instancia, raza: str) -> bool:
    return not raza or raza.lower() in inst.raza.lower()


def _arquetipo_ok(inst: Instancia, arquetipo: str) -> bool:
    """Arquetipo (Druida, Goblin, Minotauro…): va en el nombre, no en la raza."""
    if not arquetipo:
        return True
    a = arquetipo.lower()
    if len(a) <= 3:
        # "Sir" es un título: palabra completa (Osiris y Siroco no son Aliados Sir).
        return a in re.findall(r"\w+", inst.nombre.lower()) \
            or a in re.findall(r"\w+", (inst.arquetipo_extra or "").lower())
    return a in inst.nombre.lower() or a in (inst.arquetipo_extra or "").lower()  # Acólitos de Drácula


def coincide(p: "Partida", inst: Instancia, obj: dict) -> bool:
    """¿La carta cumple tipos / coste / fuerza / raza del objetivo?"""
    if obj.get("filtroSoloAliados") and inst.tipo != Tipo.ALIADO and (obj.get("raza") or obj.get("arquetipo")):
        # Caturix: "Oros y/o Aliados de raza Desafiante": la raza filtra solo
        # a los Aliados (simulación eTOU T14: los Oros nunca se barajaban).
        obj = {**obj, "raza": "", "arquetipo": ""}
    tipos = obj.get("tipos") or []
    if tipos and inst.tipo.value not in tipos:
        return False
    if inst.tipo.value in (obj.get("excluirTipos") or []):
        return False
    coste = obj.get("coste")
    if coste:
        if inst.tipo == Tipo.ORO or not cumple(coste.get("op", "<="), inst.carta.coste, int(coste.get("valor", 0))):
            return False
    if inst.tipo == Tipo.ORO and any(k in obj for k in ("costeMin", "costeMax", "costeExacto")):
        return False
    if obj.get("costeMin") is not None and inst.carta.coste < int(obj["costeMin"]):
        return False
    if obj.get("costeMax") is not None and inst.carta.coste > int(obj["costeMax"]):
        return False
    if obj.get("costeExacto") is not None and inst.carta.coste != int(obj["costeExacto"]):
        return False
    f = obj.get("fuerza")
    if f:
        if inst.tipo != Tipo.ALIADO or not cumple(f.get("op", "<="), fuerza(p, inst) if inst.en_juego else inst.carta.fuerza, int(f.get("valor", 0))):
            return False
    if obj.get("fuerzaMin") is not None or obj.get("fuerzaMax") is not None:
        if inst.tipo != Tipo.ALIADO:
            return False
        valor = fuerza(p, inst) if inst.en_juego else inst.carta.fuerza
        if obj.get("fuerzaMin") is not None and valor < int(obj["fuerzaMin"]):
            return False
        if obj.get("fuerzaMax") is not None and valor > int(obj["fuerzaMax"]):
            return False
    if obj.get("conArma") and not any(a.portador == inst.uid for a in p.e.portadas):
        return False
    if obj.get("conModificadorFuerza") and fuerza(p, inst) == inst.carta.fuerza:
        return False
    if obj.get("mismoNombreEnJuego") and not any(
        x.nombre == inst.nombre for x in p.e.instancias_en_juego(inst.controlador)
    ):
        return False
    if obj.get("sinHabilidad") and inst.habilidades:
        return False
    if obj.get("nombre") and inst.nombre != obj["nombre"]:
        return False
    nombres = obj.get("nombres") or []
    if nombres and inst.nombre not in nombres:
        return False
    if obj.get("combate") and not _en_combate(p, inst):
        return False
    if obj.get("noPuedeAtacar") and not (tiene_prop(p, inst, "guardian") or tiene_estado(p, inst, "no_puede_atacar")):
        return False  # Cegar el Mal: "un Aliado en juego que no pueda ser declarado atacante"
    if obj.get("jugadaSinPagar") and not getattr(inst, "jugada_sin_pagar", False):
        return False  # Sheut: "anula una carta jugada sin pagar su coste"
    if obj.get("soloRespuesta") and not es_respuesta(inst):
        return False  # Micenas: cartas de anulación o en respuesta
    if not _arquetipo_ok(inst, obj.get("arquetipo", "")):
        return False
    return _raza_ok(inst, obj.get("raza", ""))


_ACCIONES_RESPUESTA = {"anular", "cancelarHabilidad", "cancelarAtaque", "redirigir"}
_CUANDO_RESPUESTA = {"oponente_juega", "habilidad_oponente", "afectada_por_oponente"}


def es_respuesta(inst: Instancia) -> bool:
    """Carta de anulación o que se juega en respuesta (Micenas)."""
    return any(h.get("accion") in _ACCIONES_RESPUESTA or h.get("cuando") in _CUANDO_RESPUESTA
               for h in inst.carta.habilidades)


def _en_combate(p: "Partida", inst: Instancia) -> bool:
    """Toque de Pérsival: Aliado declarado atacante o bloqueador este turno."""
    return inst.uid in p.ataco_este_turno or any(b is inst for b in p.bloqueos.values())


def _esta_carta(p: "Partida", fuente: Instancia) -> Instancia | None:
    """En un Arma portada, "esta carta" es su portador."""
    if fuente.tipo == Tipo.ARMA and fuente.zona == Zona.PORTADA:
        return _instancia_por_uid(p, fuente.portador)
    return fuente


def _instancia_por_uid(p: "Partida", uid: int | None) -> Instancia | None:
    if uid is None:
        return None
    for inst in p.e.instancias_en_juego():
        if inst.uid == uid:
            return inst
    return None


def candidatos(p: "Partida", i: int, fuente: Instancia, h: dict, *, zona: str | None = None) -> list[Instancia]:
    obj = h.get("objetivo") or {}
    quien = obj.get("quien", "oponente")
    if quien == "bloqueador_portador":
        portador = _esta_carta(p, fuente)
        bloqueador = p.bloqueos.get(portador.uid) if portador is not None else None
        return [bloqueador] if bloqueador is not None and bloqueador.en_juego else []
    if quien == "esta_fuente":
        # Una habilidad de un Arma suele apuntar a su portador mediante
        # ``esta_carta``. Algunos efectos (Carro Real) deben mover el Arma
        # misma, por lo que se distingue explícitamente la fuente impresa.
        return [fuente]
    if quien == "esta_carta":
        x = _esta_carta(p, fuente)
        return [x] if x is not None else []
    if quien == "disparadora":
        x = getattr(p, "ctx_disparadora", None)
        return [x] if x is not None else []
    zonas = [zona] if zona else zonas_de(obj)
    out: list[Instancia] = []
    for lado in _lados(i, quien):
        jug = p.j(lado)
        for zona in zonas:
            if zona in _ZONAS_EN_JUEGO:
                for z in _ZONAS_EN_JUEGO[zona]:
                    out += [x for x in jug.lista(z) if x not in out]
                if zona == "en_juego":
                    out += [a for a in p.e.portadas if a.controlador == lado and a not in out]
            elif zona in _ZONAS_FUERA:
                out += [x for x in jug.lista(_ZONAS_FUERA[zona]) if x not in out]
    if h.get("cuando") == "al_jugar" and h.get("accion") == "subirMano" and quien == "propio":
        # Montuhopet II: "al entrar, sube un Aliado tuyo" no se elige a sí misma.
        out = [x for x in out if x is not fuente]
    costo = h.get("costo") or {}
    if costo.get("destruirEstaCarta") or costo.get("desterrarEstaCarta"):
        # #2 UUOX: Guardia Gozosa se destruye para barajar: no se baraja a sí misma.
        out = [x for x in out if x is not fuente]
    if h.get("cuando") == "al_jugar" and h.get("accion") in ("barajar", "destruir", "desterrar") \
            and quien == "propio" and any(e.get("relacion") == "si_se_cumplio" for e in h.get("luego") or []):
        # Desafío 5VXY T18: Vouivre "baraja un Aliado que controles para
        # barajar 2 oponentes": el que se paga es otro, no ella misma.
        out = [x for x in out if x is not fuente]
    if fuente.tipo == Tipo.TALISMAN:
        # Simulación yI09 T3: Desafiar a Arturo se barajaba a sí mismo. Un
        # Talismán va al Cementerio recién al terminar de resolverse.
        out = [x for x in out if x is not fuente]
    return out


# fu7V (Conchobar): 14 cartas del catálogo dicen "defensa"/"ataque" en vez de
# "linea_defensa"/"linea_ataque" y no encontraban ningún objetivo.
_ALIAS_ZONA = {"defensa": "linea_defensa", "ataque": "linea_ataque", "apoyo": "linea_apoyo"}


def zonas_de(obj: dict, defecto: str = "en_juego") -> list[str]:
    zonas = obj.get("zonas") or []
    return [_ALIAS_ZONA.get(z, z) for z in (zonas or [obj.get("zona", defecto)])]


def _con_raza_nombrada(fuente: Instancia, obj: dict) -> dict:
    if obj.get("nombrarRaza"):
        obj = {**obj, "raza": fuente.nombrado or "\u0000sin-nombrar"}
    if obj.get("nombrarCarta"):
        obj = {**obj, "nombre": fuente.nombrado_carta or "\u0000sin-nombrar"}
    return obj


def _excluida(fuente: Instancia, x: Instancia, obj: dict) -> bool:
    """"Tus demás Aliados", "que no sea Amergin": esta carta y sus copias."""
    return (bool(obj.get("excluirFuente")) and x is fuente) or (
        bool(obj.get("excluirEstaCarta")) and (x is fuente or x.nombre == fuente.nombre)
    )


def _comparacion_dinamica(p: "Partida", i: int, obj: dict, fuente: Instancia | None = None) -> dict:
    """Ganimedes: "coste igual o menor a la cantidad de Aliados Héroe que
    controles": el valor de la comparación se calcula ahora."""
    for campo in ("coste", "fuerza"):
        comp = obj.get(campo)
        if isinstance(comp, dict) and comp.get("segun") == "aliados_raza":
            n = sum(1 for a in p.j(i).aliados if _raza_ok(a, comp.get("raza", "")))
            obj = {**obj, campo: {**comp, "valor": n}}
        elif isinstance(comp, dict) and comp.get("segun") == "coste_afectada":
            # Castillo de Drácula: "de coste igual o menor a la carta desterrada".
            previas = getattr(p, "ctx_previas", None) or []
            n = max((x.carta.coste for x in previas if x.tipo != Tipo.ORO), default=0)
            obj = {**obj, campo: {**comp, "valor": n}}
        elif isinstance(comp, dict) and comp.get("segun") == "coste_pagado":
            # Plutón: "de igual o menor coste" que el Aliado destruido para pagar.
            if getattr(p, "ctx_costo_fuente", None) is fuente:
                n = getattr(p, "ctx_costo_coste", 0)
            else:  # aún sin pagar (la IA decide si usarla): el mejor Aliado que podría destruir
                n = max((a.carta.coste for a in p.j(i).aliados if a is not fuente), default=0)
            obj = {**obj, campo: {**comp, "valor": n}}
        elif isinstance(comp, dict) and comp.get("segun") == "aliados_arquetipo":
            n = sum(1 for a in p.j(i).aliados if _arquetipo_ok(a, comp.get("arquetipo", "")))
            obj = {**obj, campo: {**comp, "valor": n}}
        elif isinstance(comp, dict) and comp.get("segun") == "totems_propios":
            n = sum(1 for x in p.e.instancias_en_juego(i) if x.tipo == Tipo.TOTEM)
            obj = {**obj, campo: {**comp, "valor": n}}
        elif isinstance(comp, dict) and comp.get("segun") == "armas_propias":
            # Sir Bleoberis: "de coste igual o menor a la cantidad de Armas que controles".
            obj = {**obj, campo: {**comp, "valor": armas_propias(p, i)}}
        elif isinstance(comp, dict) and comp.get("segun") == "coste_disparadora":
            # Jared el Mago: "de coste igual o menor al Talismán jugado".
            x = getattr(p, "ctx_disparadora", None)
            n = x.carta.coste if x is not None and x.tipo != Tipo.ORO else -1
            obj = {**obj, campo: {**comp, "valor": n}}
    return obj


def armas_propias(p: "Partida", i: int) -> int:
    """Armas que controla el jugador (las porte un Aliado suyo o del rival)."""
    return sum(1 for x in p.e.instancias_en_juego(i) if x.tipo == Tipo.ARMA)


def candidatos_validos(p: "Partida", i: int, fuente: Instancia, h: dict, **kw) -> list[Instancia]:
    obj = _comparacion_dinamica(p, i, _con_raza_nombrada(fuente, h.get("objetivo") or {}), fuente)
    if obj.get("mismoNombre"):
        obj = {**obj, "nombre": fuente.nombre}  # Ceilican Seelie: una copia de este Aliado
    # Si la carta aún no se juega (sigue en la mano), su coste también sale
    # del mismo oro que el recargo (Demoledor de Amon).
    # Solo si se está jugando: Werin subido a la mano por Jeroglíficos dispara
    # su "al salir del juego" desde la mano y no paga nada.
    jugandose = fuente in p.j(i).mano and h.get("cuando") in ("al_jugar", None)
    disponible = p.j(i).oro_disponible - (p.coste_de(i, fuente) if jugandose else 0)
    out = [
        x
        for x in candidatos(p, i, fuente, h, **kw)
        if coincide(p, x, obj) and not inmune(p, x, fuente) and recargo(p, x, fuente) <= disponible
        and not _excluida(fuente, x, obj)
    ]
    # Los efectos de combate impresos en un Arma equipada afectan a su
    # portador. Nunca deben seleccionar un Oro cualquiera de la mesa.
    if fuente.tipo == Tipo.ARMA and fuente.portador and h.get("accion") in (
        "modificarFuerza", "otorgarPropiedad"
    ) and obj.get("quien") == "esta_carta":
        out = [x for x in out if x.uid == fuente.portador]
    if fuente.nombre.casefold() == "teseo de atenas" and h.get("accion") == "destruir":
        # El texto vigente de Teseo busca ganar ventaja destruyendo un Aliado
        # rival; nunca puede elegir a Teseo ni a otro Aliado propio.
        out = [x for x in out if x.controlador != i]
    if h.get("cuando") == "al_salir_del_juego" and obj.get("quien") != "esta_carta":
        # La carta que está saliendo no es otra carta del Cementerio.
        out = [x for x in out if x is not fuente]
    if obj.get("seleccion") == "mayor_fuerza" and out:
        # Fergus: "el Aliado oponente de mayor fuerza" (entre empatados elige).
        tope = max(fuerza(p, x) for x in out)
        out = [x for x in out if fuerza(p, x) == tope]
    if (h.get("costo") or {}).get("orosSegun") == "coste_objetivo":
        # Ceangal An Fhanaigh: paga el coste de la carta que destruye.
        out = [x for x in out if x.tipo != Tipo.ORO and x.carta.coste <= p.j(i).oro_disponible]
    accion = h.get("accion")
    if accion in ("barajar",) and prohibido(p, "barajar", i):
        return []
    if accion == "barajar" and prohibido(p, "barajar_cementerio", i):
        out = [x for x in out if x.zona != Zona.CEMENTERIO]
    if accion == "desterrar" and "cementerio" in zonas_de(obj) and prohibido(p, "desterrar_cementerio", i):
        return []
    if accion == "desterrar":
        out = [x for x in out if not prohibido(p, "desterrar", i, x)]
        out = _protegidas_cerbero(p, i, out)
    if accion in ("destruir", "desterrar", "subirMano", "barajar", "mover"):
        out = [x for x in out if not no_puede_salir(p, x)]  # Serpiente Roja
    if accion == "ponerEnJuego" and getattr(p.j(i), "veto_aliados_turno", None) == p.e.turno:
        out = [x for x in out if x.tipo != Tipo.ALIADO]  # Meleagro
    if accion == "destruir" and prohibido(p, "destruir", i):
        return []
    if accion == "destruir":
        out = [x for x in out if not (x.en_juego and _sigue_indestructible(p, x, h))]
    if accion == "desterrar":
        out = [x for x in out if not (x.en_juego and tiene_prop(p, x, "indesterrable"))]
    if (h.get("costo") or {}).get("desterrarCementerioSegun") == "coste_objetivo":
        # Nephre-Ka / Neferite I: solo objetivos cuyo coste alcanzo a pagar
        # desterrando del Cementerio (si no, se activaría sin efecto).
        tope = len([x for x in p.j(i).cementerio if x is not fuente])
        out = [x for x in out if x.tipo != Tipo.ORO and x.carta.coste <= tope]
    if accion in ("restringirCombate", "modificarFuerza"):
        # Solo los Aliados tienen fuerza y combaten (Toro Apis no va a un Tótem).
        out = [x for x in out if x.tipo == Tipo.ALIADO]
    if accion == "obligarBloqueo":
        # Un Aliado solo puede bloquear a un atacante: si otro Demoledor ya lo
        # obligó, no es objetivo válido.
        # Solo bloquean Aliados en la Línea de Defensa (no Oros ni Tótems).
        forzados = {x.uid for x in p.bloqueo_forzado.values()}
        out = [
            x for x in out
            if x.uid not in forzados and x.tipo == Tipo.ALIADO and x.zona == Zona.DEFENSA
            and not tiene_estado(p, x, "no_puede_bloquear")  # Djoser con la Lanza de Osiris
        ]
    # Epicuro de Samos exige otro Aliado: subir a la fuente a sí misma no es
    # una jugada legal para pagar el botar 3.
    if fuente.nombre.casefold() == "epicuro de samos" and h.get("accion") == "subirMano":
        out = [x for x in out if x is not fuente]
    return out


def _necesita_objetivo(h: dict) -> bool:
    obj = h.get("objetivo") or {}
    return h.get("accion") in {
        "destruir",
        "desterrar",
        "subirMano",
        "barajar",
        "modificarFuerza",
        "perderHabilidad",
        "mover",
        "ganarControl",
        "restringirCombate",
        "obligarBloqueo",
    } and obj.get("seleccion", "elige") != "todos" and obj.get("quien") != "esta_carta"


# ── Costos ───────────────────────────────────────────────────────────────────
def _costo(fuente: Instancia, h: dict) -> dict:
    """Costo efectivo: un Talismán nunca está en juego, así que se ignoran
    "destruir/desterrar esta carta" si quedaron guardados."""
    c = h.get("costo") or {}
    if fuente.tipo == Tipo.TALISMAN and (c.get("destruirEstaCarta") or c.get("desterrarEstaCarta")):
        c = {k: v for k, v in c.items() if k not in ("destruirEstaCarta", "desterrarEstaCarta")}
    return c


def puede_pagar_costo(p: "Partida", i: int, fuente: Instancia, h: dict) -> bool:
    if _puede_pagar(p, i, fuente, h):
        return True
    alt = h.get("costoAlternativo") or {}
    return bool(alt) and _puede_pagar(p, i, fuente, {**h, "costo": alt})


def _puede_pagar(p: "Partida", i: int, fuente: Instancia, h: dict) -> bool:
    c = _costo(fuente, h)
    jug = p.j(i)
    if len(jug.mazo) < int(c.get("desterrarTopeMazo", 0)):
        return False
    if len([x for x in jug.reserva if x is not fuente]) < int(c.get("desterrarOroReserva", 0)):
        return False
    if jug.oro_disponible < int(c.get("oros", 0)):
        return False
    mano = [x for x in jug.mano if x is not fuente and _filtro_costo(p, x, c)]
    if len(mano) < int(c.get("descartar", 0)):
        return False
    if len([x for x in jug.mano if x is not fuente]) < int(c.get("desterrarMano", 0)):
        return False  # Anhur / Hera: desterrar cartas de tu mano
    if c.get("subirEstaCarta") and not (fuente.en_juego or fuente.zona == Zona.PORTADA):
        return False  # Daga de Bote: sube a tu mano
    if c.get("destruirPropias"):
        # Nemty: destruir una carta que controles; Lady Rachel: "un Arma" (filtro).
        propias = [x for x in p.e.instancias_en_juego(i) if x is not fuente and _filtro_costo(p, x, c)]
        if len(propias) < int(c["destruirPropias"]):
            return False
    if c.get("barajarPropias"):  # Escudo de la Tormenta: baraja un Arma que controles
        if prohibido(p, "barajar", i) or len([x for x in p.e.instancias_en_juego(i)
                                              if _filtro_costo(p, x, c)]) < int(c["barajarPropias"]):
            return False
    if c.get("destruirEstaCarta") and not fuente.en_juego:
        return False
    if c.get("desterrarEstaCarta") and fuente.zona == Zona.DESTIERRO:
        return False
    if c.get("desterrarEstaCarta") and fuente.tipo == Tipo.ORO and fuente.en_juego \
            and prohibido(p, "desterrar", i, fuente):
        return False  # Carmix: "los Oros en juego no pueden ser desterrados" (Biblioteca, Papiros…)
    sale = c.get("desterrarEstaCarta") or c.get("destruirEstaCarta")
    if sale and fuente.zona == Zona.RESERVA and jug.oro_disponible - 1 < int(c.get("oros", 0)):
        return False  # Papiros de Lahun: no sirve para pagar su propio Oro
    if c.get("pagarEstaCarta") and fuente.zona != Zona.RESERVA:
        return False  # solo un Oro sin pagar, en la Reserva
    if c.get("barajarEstaCarta") and (not fuente.en_juego or prohibido(p, "barajar", i)):
        return False  # Trono Dorado: se baraja en el Mazo Castillo
    if c.get("moverEstaCartaAtaque") and fuente.zona != Zona.DEFENSA:
        return False  # Achall: de la Línea de Defensa a la de Ataque
    if c.get("fondoMazoEstaCarta"):
        if not fuente.en_juego:
            return False
        if fuente.zona == Zona.RESERVA and jug.oro_disponible - 1 < int(c.get("oros", 0)):
            return False  # este Oro no sirve para pagarse a sí mismo
    # Oberón: "destruir este u otro Aliado que controles" (incluyeEstaCarta).
    otros = [a for a in jug.aliados if (a is not fuente or c.get("incluyeEstaCarta"))
             and _filtro_costo(p, a, c) and not no_puede_salir(p, a)]
    if len(otros) < int(c.get("desterrarAliados", 0)) + int(c.get("destruirAliados", 0)):
        return False
    if (c.get("destruirEstaCarta") or c.get("desterrarEstaCarta")) and no_puede_salir(p, fuente):
        return False
    if c.get("barajarMano"):
        if prohibido(p, "barajar", i) or len([x for x in jug.mano if x is not fuente]) < int(c["barajarMano"]):
            return False
    n = int(c.get("desterrarCementerio", 0))
    if n or c.get("desterrarCementerioSegun") == "coste_objetivo":
        if prohibido(p, "desterrar_cementerio", i):
            return False
        if len([x for x in jug.cementerio if x is not fuente and _filtro_costo(p, x, c)]) < n:
            return False
    return True


def _filtro_costo(p: "Partida", x: Instancia, c: dict) -> bool:
    """Caballero Negro: "descarta un Arma"; Horda Fomoré: "un Aliado Sombra"."""
    filtro = c.get("filtro") or {}
    return not filtro or coincide(p, x, filtro)


def _desterrar_del_cementerio(p: "Partida", i: int, fuente: Instancia, n: int) -> bool:
    """Costo: desterrar N cartas de tu Cementerio (eliges cuáles)."""
    costo = getattr(p, "ctx_costo", None) or {}
    disponibles = [x for x in p.j(i).cementerio if x is not fuente and _filtro_costo(p, x, costo)]
    if len(disponibles) < n:
        return False
    decide = p.decide(i)
    elegir = getattr(decide, "elegir_destierro_costo", None)
    elegidas = elegir(p, i, fuente, disponibles, n) if elegir else decide.elegir_descartes(p, i, disponibles, n)
    if len(elegidas) != n:
        return False
    for x in elegidas:
        p._mover(x, Zona.DESTIERRO)
    return True


def pagar_costo(p: "Partida", i: int, fuente: Instancia, h: dict, *, narrar: bool = True) -> bool:
    if not puede_pagar_costo(p, i, fuente, h):
        return False
    if not _puede_pagar(p, i, fuente, h):
        h = {**h, "costo": h.get("costoAlternativo") or {}}  # paga el alternativo
    elif h.get("costoAlternativo") and _puede_pagar(p, i, fuente, {**h, "costo": h["costoAlternativo"]}):
        prefiere = getattr(p.decide(i), "preferir_alternativo", None)
        if prefiere and prefiere(p, i, fuente, h):
            h = {**h, "costo": h["costoAlternativo"]}
    c = _costo(fuente, h)
    p.ctx_costo = c
    p.ctx_costo_fuerza = 0
    p.ctx_costo_coste = 0
    p.ctx_costo_fuente = fuente
    if c.get("desterrarEstaCarta") and fuente.tipo == Tipo.ARMA and fuente.zona == Zona.PORTADA:
        portador = _esta_carta(p, fuente)
        p.ctx_costo_fuerza = fuerza(p, portador) if portador is not None else 0
    n_tope = int(c.get("desterrarTopeMazo", 0))
    if n_tope:
        for x in list(p.j(i).mazo[:n_tope]):
            p._mover(x, Zona.DESTIERRO)
        p.anotar(f"J{i} destierra {n_tope} del tope de su mazo para pagar {fuente.nombre}")
        p._comprobar_mazos("efecto")
    n_reserva = int(c.get("desterrarOroReserva", 0))
    if n_reserva:
        disponibles = [x for x in p.j(i).reserva if x is not fuente]
        for x in p.decide(i).elegir_descartes(p, i, disponibles, n_reserva):
            p._mover(x, Zona.DESTIERRO)
            p.anotar(f"J{i} destierra {x.nombre} de su Reserva para pagar {fuente.nombre}")
    if fuente.nombre.casefold() == "bennu" and h.get("accion") == "jugarDesde" and fuente.en_juego:
        p.sale_del_juego(fuente, Zona.CEMENTERIO)
    if c.get("pagarEstaCarta"):
        p._mover(fuente, Zona.PAGADO)
    if c.get("subirEstaCarta"):  # Daga de Bote
        if fuente.en_juego or fuente.zona == Zona.PORTADA:
            p.sale_del_juego(fuente, Zona.MANO) if fuente.en_juego else p._mover(fuente, Zona.MANO)
    for clave, zona in (("desterrarMano", Zona.DESTIERRO),):
        n = int(c.get(clave, 0))
        if n:
            mano = [x for x in p.j(i).mano if x is not fuente]
            for x in p.decide(i).elegir_descartes(p, i, mano, n):
                p._mover(x, zona)
                p.anotar(f"J{i} destierra {x.nombre} de su mano")
    n = int(c.get("barajarPropias", 0))
    if n:
        propias = [x for x in p.e.instancias_en_juego(i) if _filtro_costo(p, x, c)]
        for x in p.decide(i).elegir_descartes(p, i, propias, n):
            p.anotar(f"J{i} baraja {x.nombre} en su mazo para pagar {fuente.nombre}")
            p.sale_del_juego(x, Zona.MAZO)
    n = int(c.get("destruirPropias", 0))
    if n:
        propias = [x for x in p.e.instancias_en_juego(i) if x is not fuente and _filtro_costo(p, x, c)]
        for x in p.decide(i).elegir_descartes(p, i, propias, n):
            p.anotar(f"J{i} destruye {x.nombre} para pagar {fuente.nombre}")
            if x.tipo == Tipo.ALIADO:
                p.aliados_destruidos_turno += 1
                p.ctx_costo_fuerza += fuerza(p, x)
            p.sale_del_juego(x, Zona.CEMENTERIO)
    if fuente.zona == Zona.RESERVA and (c.get("desterrarEstaCarta") or c.get("destruirEstaCarta")):
        # Sale antes de pagar los Oros, para no usarse a sí mismo (Papiros).
        p.sale_del_juego(fuente, Zona.DESTIERRO if c.get("desterrarEstaCarta") else Zona.CEMENTERIO)
    if c.get("barajarEstaCarta") and fuente.en_juego:
        p.sale_del_juego(fuente, Zona.MAZO)  # baraja el Mazo Castillo
    if c.get("moverEstaCartaAtaque") and fuente.zona == Zona.DEFENSA:
        p._mover(fuente, Zona.ATAQUE)
        movido_a_ataque(p, fuente, i)
    if c.get("fondoMazoEstaCarta") and fuente.en_juego:
        p._sacar(fuente)  # sale antes de pagar los oros para no usarse a sí mismo
        fuente.zona = Zona.MANO
        p._mover(fuente, Zona.MAZO, al_tope=False)
    p._pagar_oro(i, int(c.get("oros", 0)), por=fuente)
    if c.get("oros") and narrar:
        p.anotar(f"paga {c['oros']} Oro{'s' if int(c['oros']) > 1 else ''}")
    n = int(c.get("descartar", 0))
    if n:
        mano = [x for x in p.j(i).mano if x is not fuente and _filtro_costo(p, x, c)]
        anterior, p.ctx_fuente_habilidad = getattr(p, "ctx_fuente_habilidad", None), fuente
        try:  # #1 MUh4: Ramsés II sabe que es él quien descarta (guarda la Forma de Lince)
            descartes = p.decide(i).elegir_descartes(p, i, mano, n)
        finally:
            p.ctx_fuente_habilidad = anterior
        for x in descartes:
            p.descartar(x)
        if descartes:
            p.anotar(f"descarta {', '.join(x.nombre for x in descartes)}")
    if c.get("botar"):
        p.botar(i, int(c["botar"]), causa="autodano")
    if c.get("destruirEstaCarta") and fuente.en_juego:
        if fuente.tipo == Tipo.ALIADO:
            p.aliados_destruidos_turno += 1
        p.sale_del_juego(fuente, Zona.CEMENTERIO)
    if c.get("desterrarEstaCarta"):
        if fuente.en_juego:
            p.sale_del_juego(fuente, Zona.DESTIERRO)
        else:
            p._mover(fuente, Zona.DESTIERRO)
    if c.get("barajarMano"):
        mano = [x for x in p.j(i).mano if x is not fuente]
        elegidas = p.decide(i).elegir_descartes(p, i, mano, int(c["barajarMano"]))
        for x in elegidas:
            p._mover(x, Zona.MAZO)
        p.e.rng.shuffle(p.j(i).mazo)
        if elegidas:
            # Piedra Roseta: lo que se baraja desde la mano solo lo sabe quien lo baraja.
            p.anotar(f"J{i} baraja {privado(i, ', '.join(x.nombre for x in elegidas))} de su mano en el mazo")
    for clave, zona in (("desterrarAliados", Zona.DESTIERRO), ("destruirAliados", Zona.CEMENTERIO)):
        n = int(c.get(clave, 0))
        if n:
            otros = [a for a in p.j(i).aliados if (a is not fuente or c.get("incluyeEstaCarta"))
                     and _filtro_costo(p, a, c) and not no_puede_salir(p, a)]
            for a in p.decide(i).elegir_descartes(p, i, otros, n):
                verbo = "destierra" if zona == Zona.DESTIERRO else "destruye"
                p.anotar(f"J{i} {verbo} {a.nombre} para pagar {fuente.nombre}")
                if zona == Zona.CEMENTERIO:
                    p.aliados_destruidos_turno += 1
                    p.ctx_costo_fuerza += fuerza(p, a)
                p.ctx_costo_coste = max(getattr(p, "ctx_costo_coste", 0), a.carta.coste)  # Plutón
                p.sale_del_juego(a, zona)
    # Con "coste_objetivo" se paga después de elegir el objetivo (4.6.2).
    if c.get("desterrarCementerioSegun") != "coste_objetivo" and c.get("desterrarCementerio"):
        _desterrar_del_cementerio(p, i, fuente, int(c["desterrarCementerio"]))
    return True


def _costo_gratis(h: dict) -> bool:
    c = h.get("costo") or {}
    return not any(c.get(k) for k in ("oros", "descartar", "botar", "destruirEstaCarta", "desterrarEstaCarta", "pagarEstaCarta", "desterrarCementerio", "desterrarTopeMazo", "desterrarOroReserva", "desterrarAliados", "destruirAliados", "barajarMano", "fondoMazoEstaCarta", "barajarEstaCarta", "moverEstaCartaAtaque", "desterrarMano", "subirEstaCarta", "destruirPropias", "barajarPropias")) and (
        c.get("desterrarCementerioSegun") != "coste_objetivo" and c.get("orosSegun") != "coste_objetivo"
    )


# ── Consultas que usa el motor ───────────────────────────────────────────────
def _continuas(p: "Partida", accion: str):
    """(fuente, habilidad) de cada habilidad continua activa en juego."""
    for s in p.e.instancias_en_juego():
        for h in s.habilidades:
            if h.get("accion") == accion and h.get("cuando") == "continua":
                anterior = getattr(p, "ctx_fuente_habilidad", None)
                p.ctx_fuente_habilidad = s  # condiciones sobre esta carta (Martillo de Hefestos)
                try:
                    ok = condicion_ok(p, s.controlador, h)
                finally:
                    p.ctx_fuente_habilidad = anterior
                if ok:
                    yield s, h


def fuerza(p: "Partida", inst: Instancia) -> int:
    if inst.tipo != Tipo.ALIADO:
        return 0
    base = inst.fuerza_temporal if inst.fuerza_temporal is not None else inst.carta.fuerza
    valor = base
    # Macha: mientras esté en juego, los Aliados pierden sus modificadores.
    if any(h.get("modoFuerza") == "base" and _afecta_continua(p, s, h, inst)
           for s, h in _continuas(p, "modificarFuerza")):
        return max(0, base)
    # Hienas / Fantasmas: fijada y sin poder volver a modificarse hasta que expire.
    congelados = [m for m in inst.mods if getattr(m, "congela", False)]
    if congelados:
        m = congelados[-1]
        return max(0, base if m.modo == "base" else m.valor)
    # Berserk duplica la fuerza actual con todas sus bonificaciones (también
    # las continuas, como el Carro Celta): los "duplicar" van al final.
    duplicar = 0
    for m in list(inst.mods):
        if m.duracion == "mientras_en_juego" and _instancia_por_uid(p, m.fuente) is None:
            inst.mods.remove(m)
            continue
        if m.modo == "duplicar":
            duplicar += 1
            continue
        valor = base if m.modo == "base" else _aplicar(valor, m.modo, m.valor)
    sin_bonos = any(m.modo == "base" for m in inst.mods)
    for s, h in _continuas(p, "modificarFuerza"):
        if sin_bonos and int(h.get("valor", 0)) > 0:
            continue
        if h.get("modoFuerza") == "base":
            continue  # Macha: ya se resolvió arriba
        if _afecta_continua(p, s, h, inst):
            if h.get("modoFuerza") == "duplicar":
                duplicar += 1
                continue
            valor = _aplicar(valor, h.get("modoFuerza", "sumar"), int(h.get("valor", 0)) * por_cada(p, s, h))
    return max(0, valor * 2 ** duplicar)


def desglose_fuerza(p: "Partida", inst: Instancia) -> list[tuple[str, str]]:
    """Desafío vUsU T9: «al tocar un Aliado debe mostrar quién lo bonifica o
    perjudica». [(carta, «+2» / «-1» / «= 0» / «×2»)], en el orden de `fuerza`."""
    if inst.tipo != Tipo.ALIADO:
        return []
    out: list[tuple[str, str]] = []

    def texto(modo: str, valor: int) -> str:
        return {"fijar": f"= {valor}", "duplicar": "×2", "base": "sin bonos"}.get(modo, f"{valor:+d}")

    def nombre(uid):
        # Forma de Lince ya está en el Cementerio: se busca en todas las zonas.
        for j in p.e.jugadores:
            for x in [*p.e.instancias_en_juego(j.indice), *j.cementerio, *j.destierro, *j.mano, *j.pagado]:
                if x.uid == uid:
                    return x.nombre
        return "efecto"

    for m in inst.mods:
        if m.modo != "sumar" or m.valor:
            out.append((nombre(m.fuente), texto(m.modo, m.valor)))
    for s, h in _continuas(p, "modificarFuerza"):
        if _afecta_continua(p, s, h, inst):
            v = int(h.get("valor", 0)) * por_cada(p, s, h)
            modo = h.get("modoFuerza", "sumar")
            if modo != "sumar" or v:
                out.append((s.nombre, texto(modo, v)))
    return out


def _afecta_continua(p: "Partida", s: Instancia, h: dict, inst: Instancia) -> bool:
    """¿La fuerza continua `h` de `s` alcanza a `inst`?"""
    if inmune(p, inst, s):
        return False
    obj = h.get("objetivo") or {}
    linea = {"linea_defensa": Zona.DEFENSA, "linea_ataque": Zona.ATAQUE}.get(obj.get("zona"))
    if linea is not None and inst.zona != linea:
        return False  # Faeries: solo en la Línea de Defensa; Torc Fiana: en la de Ataque
    if obj.get("quien") == "esta_carta":
        return _esta_carta(p, s) is inst
    if obj.get("excluirPortador") and s.tipo == Tipo.ARMA and s.portador == inst.uid:
        return False  # Martillo de Hefestos: "tus demás Aliados"
    return inst.controlador in _lados(s.controlador, obj.get("quien", "propio")) and coincide(p, inst, obj) \
        and not _excluida(s, inst, obj)


def _aplicar(valor: int, modo: str, n: int) -> int:
    if modo == "fijar":
        return n
    if modo == "duplicar":
        return valor * 2
    return valor + n


def reduccion_coste(p: "Partida", i: int, inst: Instancia) -> int:
    total = 0
    for s, h in _continuas(p, "modificarCoste"):
        obj = _con_raza_nombrada(s, h.get("objetivo") or {})  # Mina Harker: la carta nombrada
        if obj.get("quien") == "esta_carta":
            continue
        if i in _lados(s.controlador, obj.get("quien", "propio")) and coincide(p, inst, obj):
            total += int(h.get("valor", 0))
    # Látigo Dullahan: "si Dullahan está en juego, reduce su coste en 1" (desde la mano).
    for h in inst.habilidades:
        if h.get("accion") == "modificarCoste" and (h.get("objetivo") or {}).get("quien") == "esta_carta" \
                and condicion_ok(p, i, h):
            total += int(h.get("valor", 0))
    return -total  # valor negativo = reduce el coste


def portador_valido(p: "Partida", arma: Instancia, portador: Instancia, jugador: int | None = None) -> bool:
    """¿Puede `portador` cargar `arma`? Respeta el Requisito del portador
    (raza, coste, fuerza; tuyo, del oponente o de cualquiera). Sin requisito,
    solo Aliados propios."""
    if portador.tipo != Tipo.ALIADO or not portador.en_juego:
        return False
    quien_juega = arma.controlador if jugador is None else jugador
    requisito = next((h for h in arma.carta.habilidades if h.get("accion") == "requisitoPortador"), None)
    obj = (requisito or {}).get("objetivo") or {}
    if portador.controlador not in _lados(quien_juega, obj.get("quien", "propio")):
        return False
    if requisito and not coincide(p, portador, obj):
        return False
    if tiene_prop(p, portador, "sinLimiteArmas"):
        return True
    equipadas = [a for a in p.e.portadas if a.portador == portador.uid]
    extras = sum(1 for a in equipadas if any(h.get("accion") == "armaAdicional" for h in a.habilidades))
    return len(equipadas) < 1 + extras


def es_permiso_jugar(h: dict) -> bool:
    """"Esta carta se puede jugar desde X" (Jinetes de Fuego): un permiso,
    no un efecto que se resuelve al jugarla."""
    return h.get("accion") == "jugarDesde" and (h.get("objetivo") or {}).get("quien") == "esta_carta"         and h.get("cuando") in ("al_jugar", None)


def _habilidades_al_jugar(inst: Instancia) -> list[dict]:
    return [h for h in inst.habilidades if h.get("cuando") in ("al_jugar", None) and not es_permiso_jugar(h)]


def _objetivos_suficientes(p: "Partida", i: int, inst: Instancia, h: dict) -> bool:
    if not _necesita_objetivo(h):
        return True
    obj = h.get("objetivo") or {}
    if NOMBRAR_SOLO_AL_ACTIVAR and obj.get("nombrarCarta") and h.get("cuando") in ("activada", "al_hacer_dano"):
        # Desafío vUsU T5 (y g9FE «ya no me deja activar el Orfeo»): Orfeo
        # nombra al activarse; antes se buscaban copias de un nombre que aún no
        # existía y nunca se ofrecía. Basta con que haya dónde buscar.
        h = {**h, "objetivo": {**obj, "nombrarCarta": False}}
    minimo = int(h.get("cantidad", 1)) if h.get("cantidadExacta") else 1
    return len(candidatos_validos(p, i, inst, h)) >= minimo


def requisito_para_jugar(p: "Partida", i: int, inst: Instancia) -> bool:
    """Montuhopet II: "al entrar, sube a la mano un Aliado tuyo" es condición
    para jugarlo; sin otro Aliado propio en juego, no se puede jugar."""
    if UNA_COPIA_EN_JUEGO.search(inst.carta.texto or "") and any(
        otra.nombre == inst.nombre for otra in p.e.instancias_en_juego(i)
    ):
        return False
    for h in inst.habilidades:
        if h.get("accion") == "restriccion" and h.get("modo") == "requisito_jugar" and not condicion_ok(p, i, h):
            return False  # Tutatis: solo si tienes dos o más Aliados en juego
        if h.get("cuando") == "al_jugar" and h.get("accion") == "botar" and not h.get("opcional") \
                and (h.get("objetivo") or {}).get("quien") == "propio" \
                and len(p.j(i).mazo) <= int(h.get("cantidad", 1) or 1):
            return False  # Kobold: para jugarlo debes botar 3
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if (
            h.get("cuando") == "al_jugar" and h.get("accion") == "subirMano" and not h.get("opcional")
            and obj.get("quien") == "propio" and "en_juego" in zonas_de(obj)
            and not candidatos_validos(p, i, inst, h)
        ):
            return False
    return True


def talisman_jugable(p: "Partida", i: int, inst: Instancia, fase: str) -> bool:
    activo = p.e.activo == i
    habs = _habilidades_al_jugar(inst)
    if habs and all(h.get("accion") in ("anular", "redirigir", "prevenir") for h in habs):
        return False  # solo se usan en su ventana (anulación / redirección)
    if not habs and any(h.get("cuando") in ("oponente_juega", "habilidad_oponente") or h.get("zonaActivacion") == "mano"
                        for h in inst.habilidades):
        return False  # Talismán de respuesta (Relámpago Arcano, Venganza de Conall): solo en su ventana
    fases = {h.get("fase", "cualquiera") for h in habs} or {"vigilia"}
    permitida = False
    for f in fases:
        if f == "cualquiera" and fase in VENTANAS_LIBRES:
            permitida = True
        elif f == fase:
            permitida = True
    if not permitida or (fase == "vigilia" and not activo):
        return False
    grupos_revisados: set[str] = set()
    for h in habs:
        grupo = h.get("grupoElegir")
        if grupo:
            if grupo in grupos_revisados:
                continue
            grupos_revisados.add(grupo)
            opciones = [x for x in habs if x.get("grupoElegir") == grupo]
        else:
            opciones = [h]
        if not any(
            turno_ok(p, i, x) and condicion_ok(p, i, x)
            and (x.get("opcional") or _objetivos_suficientes(p, i, inst, x))
            for x in opciones
        ):
            return False
    return True


def activable(p: "Partida", i: int, inst: Instancia, h: dict, k: int, fase: str) -> bool:
    if h.get("cuando") != "activada":
        return False
    if h.get("usaQuien") != "ambos" and (h.get("usaQuien") == "oponente") != (inst.controlador != i):
        return False  # Nudo de Isis: la usa el oponente de quien la controla (o cualquiera)
    if not _en_zona_activacion(inst, h):
        return False
    if h.get("accion") == "reducirDano" and (h.get("modo") or "dano_a_cero") != "aliado_sin_dano":
        return False  # se usa en la ventana de Asignación de Daño
    if h.get("accion") == "cancelarAtaque" and h.get("modo") == "ataque_o_bloqueo":
        if not (p.atacantes and p.e.fase == "guerra_talismanes" and (p.e.activo != i or p.bloqueos)):
            return False  # Ares: en la Guerra, el ataque (defiendo) o un bloqueo (ataco)
    elif h.get("accion") == "cancelarAtaque" and not (
        p.atacantes and p.e.fase in ("declaracion_ataque", "guerra_talismanes") and p.e.activo != i
    ):
        return False  # solo el defensor, durante la batalla
    f = h.get("fase", "cualquiera")
    if h.get("accion") == "reducirDano" and h.get("modo") == "aliado_sin_dano":
        # Salmón del Saber: "un Aliado no hace daño" se usa en la Asignación
        # de Daño (desafío 2026-11-14), no en la Guerra de Talismanes.
        if not (fase == "asignacion_dano" and p.atacantes and p.e.activo != i):
            return False
        f = fase
    if h.get("fases"):  # Escudo Miliciano: Declaración de Ataque o de Bloqueo
        f = fase if fase in h["fases"] else "-"
    if f == "cualquiera":
        if fase not in VENTANAS_LIBRES:
            return False
    elif f != fase:
        return False
    if fase == "vigilia" and p.e.activo != i:
        return False
    limite = int(h.get("limitePorTurno", 0))
    if inst.nombre.casefold() == "neferite i" and h.get("accion") == "desterrar":
        limite = max(limite, 1)
    if limite == 0 and _costo_gratis(h):
        limite = 1  # una habilidad gratis sin límite se usaría infinitas veces
    if limite and usos(p, i, inst, h, k) >= limite:
        return False
    if not turno_ok(p, i, h) or not condicion_ok(p, i, h):
        return False
    if not puede_pagar_costo(p, i, inst, h):
        return False
    if h.get("accion") in ("anular", "prevenir", "cancelarHabilidad"):
        return False  # se usan en sus propias ventanas
    if not _objetivos_suficientes(p, i, inst, h):
        return False
    if h.get("accion") == "jugarDesde" and not _candidatos_jugar(p, i, inst, h):
        return False
    return True


# ── Disparos ──────────────────────────────────────────────────────────────────
def disparar(
    p: "Partida", inst: Instancia, cuando: str, *, forzar: bool = False, declaracion: bool | None = None
) -> None:
    """`declaracion`: True solo las de la fase Declaración de Ataque (Demoledor
    de Amon), False todas menos esas; None, todas."""
    habs = inst.carta.habilidades if (forzar and inst.carta.programada) else inst.habilidades
    i = inst.controlador
    if cuando == "al_jugar":
        # Desafío 5VXY T13: Apophis ("cada vez que tu oponente juegue una
        # carta") se dispara al jugarla, antes de que se resuelva: una Bola de
        # Fuego que lo destruye igual hace botar 3.
        _reacciones_oponente(p, inst)
        nombrar_raza(p, inst)
        nombrar_carta(p, inst)
    elegidos: set[str] = set()  # "elige una de las opciones" (Luz de Prometeo)
    for h in habs:
        if h.get("cuando") != cuando or h.get("accion") in ("anular", "prevenir") or es_permiso_jugar(h):
            continue
        if h.get("soloPorHabilidad") and not getattr(p, "ctx_descarte_por_habilidad", True):
            continue  # Fear Sidhe: "descartado por una habilidad" (no por exceso de mano)
        if not fase_ok(p, h) and inst.tipo != Tipo.TALISMAN:
            continue
        if declaracion is not None and (h.get("fase") == "declaracion_ataque") != declaracion:
            continue
        grupo = h.get("grupoElegir")
        if grupo and grupo in elegidos:
            continue
        opciones = [x for x in habs if x.get("grupoElegir") == grupo and x.get("cuando") == cuando] if grupo else []
        if grupo and len(opciones) > 1 and not any(x.get("opcional") for x in opciones):
            # Nuada: "debes destruir uno de tus Aliados o botar 3": elige una que se pueda.
            posibles = [x for x in opciones if puede_pagar_costo(p, i, inst, x) and condicion_ok(p, i, x)
                        and _objetivos_suficientes(p, i, inst, x)]
            if posibles:
                # Loch Lein: "tu oponente debe elegir entre descartar o botar 2".
                quien = 1 - i if posibles[0].get("eligeOponente") else i
                elegir = getattr(p.decide(quien), "elegir_opcion", None)
                h = posibles[elegir(p, quien, inst, posibles) if elegir else 0]
            elegidos.add(grupo)
            _intentar(p, i, inst, h)
            continue
        if grupo and len(opciones) > 1 and getattr(p.decide(i), "elige_ninguna", False)                 and not all(x.get("accion") == "mirarTope" for x in opciones):  # Rhiannon: mira y elige el modo
            # Bereber (+1 a sí mismo o +2 a otro Guerrero), Erec (1 carta o 2
            # Caballeros): la persona elige cuál, o ninguna.
            elegidos.add(grupo)
            h = _elegir_del_grupo(p, i, inst, opciones)
            if h is not None:
                _intentar(p, i, inst, h)
            continue
        if _intentar(p, i, inst, h) and grupo:
            elegidos.add(grupo)


def _elegir_del_grupo(p: "Partida", i: int, inst: Instancia, opciones: list[dict]) -> dict | None:
    """Opciones excluyentes y opcionales ("puedes X o Y"): quien puede decir
    "ninguna" (la persona) elige una por su nombre. La elegida ya no vuelve a
    preguntar "¿usar?". None = no usa ninguna."""
    posibles = [x for x in opciones if condicion_ok(p, i, x) and puede_pagar_costo(p, i, inst, x)
                and _objetivos_suficientes(p, i, inst, x)]
    if not posibles:
        return None
    k = p.decide(i).elegir_opcion(p, i, inst, posibles)
    if k is None or not 0 <= k < len(posibles):
        return None
    return {**posibles[k], "opcional": False}


def _intentar(p: "Partida", i: int, inst: Instancia, h: dict) -> bool:
    # Todo lo que hace un disparo (Demoledor: obliga, quita la habilidad,
    # -1) va en un solo paso del tablero.
    abrir = getattr(p, "_grupo", None) is None and hasattr(p, "_cerrar_grupo")
    if abrir:
        p._grupo = []
        p._grupo_fuente = inst.nombre
    try:
        return _intentar_sin_agrupar(p, i, inst, h)
    finally:
        if abrir:
            p._cerrar_grupo()


def _intentar_sin_agrupar(p: "Partida", i: int, inst: Instancia, h: dict) -> bool:
    h = {**h, "costo": _costo(inst, h)}
    anterior = getattr(p, "ctx_fuente_habilidad", None)
    p.ctx_fuente_habilidad = inst
    if not turno_ok(p, i, h) or not condicion_ok(p, i, h):
        p.ctx_fuente_habilidad = anterior
        return False
    if h.get("cuando") in ("activada", "al_hacer_dano") and (h.get("objetivo") or {}).get("nombrarCarta"):
        # Orfeo: "una vez por turno, puedes nombrar una carta"; Geb nombra al hacer daño.
        inst.nombrado_carta = None
        nombrar_carta(p, inst, al_activar=True)
    if (h.get("opcional") or not _costo_gratis(h)) and not p.decide(i).usar_opcional(p, i, inst, h):
        p.ctx_fuente_habilidad = anterior
        return False
    if not pagar_costo(p, i, inst, h):
        p.ctx_fuente_habilidad = anterior
        return False
    if not ventana_cancelar(p, i, inst, h):
        resolver(p, i, inst, h)
    p.ctx_fuente_habilidad = anterior
    return True


RESPUESTA_PERDER_HABILIDAD = False  # Carnwennan en respuesta (Héctor 2026-11-12)


def ventana_cancelar(p: "Partida", i: int, fuente: Instancia, h: dict) -> bool:
    """Siete contra Tebas / Desafiar a Arturo: "cancela la habilidad". En
    respuesta a una habilidad del oponente que se activa o dispara (el barajar
    del Escudo, el destruir de Djoser), esa habilidad no se resuelve; la carta
    conserva su habilidad. True = cancelada (los costos ya se pagaron)."""
    if h.get("accion") in PROPIEDADES or h.get("cuando") == "continua":
        return False
    portador = _esta_carta(p, fuente)
    if not fuente.en_juego and not (portador is not None and portador.en_juego):
        return False
    q = 1 - i
    opciones = []
    for t in p.j(q).mano:
        if t.tipo != Tipo.TALISMAN or not p.puede_pagar(q, t):
            continue
        for hc in t.habilidades:
            if hc.get("cuando") == "habilidad_oponente" and hc.get("accion") == "cancelarHabilidad":
                obj = hc.get("objetivo") or {}
                if coincide(p, fuente, {**obj, "quien": None}) and condicion_ok(p, q, hc):
                    opciones.append((t, hc))
                break
    for s in p.e.instancias_en_juego(q):
        for hc in s.habilidades:
            if hc.get("accion") == "cancelarHabilidad" and hc.get("cuando") == "activada" \
                    and _en_zona_activacion(s, hc) and puede_pagar_costo(p, q, s, hc) \
                    and coincide(p, fuente, {**(hc.get("objetivo") or {}), "quien": None}) \
                    and _afecta_raza_propia(p, q, fuente, h, hc.get("afectaRaza")):
                opciones.append((s, hc))
            # Carnwennan: en respuesta a la habilidad que dispara un Aliado (el
            # Demoledor al atacar), le quita la habilidad y esa no se resuelve.
            elif RESPUESTA_PERDER_HABILIDAD and hc.get("accion") == "perderHabilidad" \
                    and hc.get("cuando") == "activada" and fuente.tipo != Tipo.ORO \
                    and h.get("cuando") not in ("activada",) \
                    and _en_zona_activacion(s, hc) and puede_pagar_costo(p, q, s, hc) \
                    and fuente.controlador != q \
                    and coincide(p, fuente, {**(hc.get("objetivo") or {}), "quien": None}):
                opciones.append((s, hc))
    if not opciones:
        return False
    decide = getattr(p.decide(q), "cancelar_habilidad", None)
    k = decide(p, q, fuente, h, opciones) if decide else None
    if k is None:
        return False
    t, hc = opciones[k]
    if t.zona == Zona.MANO:
        p._pagar_oro(q, p.coste_de(q, t))
        p.jugadas[q].add(t.nombre)
        # Un Talismán jugado en respuesta también se puede anular (desafío
        # 2026-11-14: Desafiar a Arturo canceló a Caturix y no hubo ventana
        # para Morir de Pie).
        p.anotar(f"J{q} juega {t.nombre} en respuesta a {fuente.nombre}")
        if ventana_anulacion(p, q, t):
            if t.zona != Zona.CEMENTERIO:
                p._mover(t, Zona.CEMENTERIO)
            return False  # anulado: la habilidad se resuelve
        p._mover(t, zona_final_talisman(t))
    elif not pagar_costo(p, q, t, hc):
        return False
    if hc.get("accion") == "perderHabilidad":
        if fuente.en_juego and not protegida(p, fuente):
            fuente.sin_habilidad_hasta = hc.get("duracion") or "hasta_fase_final"
            fuente.sin_habilidad_fuente = None
        p.anotar(f"J{q} responde con {t.nombre}: {fuente.nombre} pierde su habilidad")
        return True
    p.anotar(f"J{q} cancela la habilidad de {fuente.nombre} con {t.nombre}")
    aplicar_luego(p, q, t, hc, True, [fuente])
    return True


def _afecta_raza_propia(p: "Partida", q: int, fuente: Instancia, h: dict, raza: str | None) -> bool:
    """Knum: "en respuesta a que uno de tus Aliados de raza Eterno sea
    afectado por una habilidad oponente" (sin raza indicada, siempre vale)."""
    if not raza:
        return True
    return any(c.controlador == q and c.tipo == Tipo.ALIADO and _raza_ok(c, raza)
               for c in candidatos_validos(p, 1 - q, fuente, h))


def ventana_respuesta(p: "Partida", jugada: Instancia) -> None:
    """Talismanes en la mano que se juegan "cuando el oponente juega una
    carta" (Resplandor de Heka: le quita la habilidad y, en la Fase Final,
    robas una copia). Se resuelven antes que el "al entrar" de esa carta."""
    if jugada.tipo == Tipo.ORO:
        return
    q = 1 - jugada.controlador
    opciones = []
    for t in p.j(q).mano:
        if t.tipo != Tipo.TALISMAN or not p.puede_pagar(q, t):
            continue
        for h in t.habilidades:
            if h.get("cuando") == "oponente_juega" and h.get("accion") not in ("anular", "redirigir", "otra"):
                if _responde_a(h, jugada) and condicion_ok(p, q, h):
                    opciones.append((t, h))
                break
    if not opciones:
        return
    responder = getattr(p.decide(q), "responder", None)
    elegida = responder(p, q, jugada, opciones) if responder else None
    if elegida is None:
        return
    t, h = opciones[elegida]
    p._pagar_oro(q, p.coste_de(q, t))
    p.jugadas[q].add(t.nombre)
    p.anotar(f"J{q} responde a {jugada.nombre} con {t.nombre}")
    # Como en ventana_cancelar: el Talismán de respuesta también se puede anular.
    if ventana_anulacion(p, q, t):
        if t.zona != Zona.CEMENTERIO:
            p._mover(t, Zona.CEMENTERIO)
        return
    p._mover(t, zona_final_talisman(t))
    # El efecto apunta a la carta recién jugada.
    obj = h.get("objetivo") or {}
    h_resp = {**h, "objetivo": {**obj, "quien": "disparadora"}}
    previa = getattr(p, "ctx_disparadora", None)
    p.ctx_disparadora = jugada
    try:
        resolver(p, q, t, h_resp)
    finally:
        p.ctx_disparadora = previa


def _responde_a(h: dict, jugada: Instancia) -> bool:
    """¿Esta respuesta puede afectar a la carta jugada? Resplandor de Heka le
    quita la habilidad a una carta en juego: un Talismán nunca lo está."""
    obj = h.get("objetivo") or {}
    tipos = obj.get("tipos") or []
    if tipos and jugada.tipo.value not in tipos:
        return False
    disparo = h.get("disparoTipos") or []
    if disparo and jugada.tipo.value not in disparo:
        return False
    return not ("en_juego" in zonas_de(obj, "en_juego") and jugada.tipo == Tipo.TALISMAN)


def _reacciones_oponente(p: "Partida", jugada: Instancia) -> None:
    q = 1 - jugada.controlador
    for s in p.e.instancias_en_juego(q):
        for h in s.habilidades:
            if h.get("cuando") == "oponente_juega" and h.get("accion") != "anular":
                if (h.get("disparoTipos") or []) and jugada.tipo.value not in h["disparoTipos"]:
                    continue
                _intentar(p, q, s, h)


def disparar_ataque_propio(p: "Partida", atacante: int) -> None:
    """Coliseo: "en respuesta a declarar tu ataque" (cartas del atacante)."""
    for s in p.e.instancias_en_juego(atacante):
        for h in s.habilidades:
            if h.get("cuando") == "propio_ataca":
                _intentar(p, atacante, s, h)


# 2026-11-15: los Oros pagados disparan su "al inicio de fase" (Gaitas, Caldero).
# Apagar para reproducir partidas grabadas antes.
ORO_PAGADO_DISPARA = True
# 2026-11-15 (z7to, g9FE): robos al final de la Fase Final; Orfeo nombra solo
# al activarse. Apagar para reproducir partidas grabadas antes.
ROBOS_AL_FINAL = True
NOMBRAR_SOLO_AL_ACTIVAR = True


def disparar_inicio_fase(p: "Partida", fase: str) -> None:
    # Desafío vg1J: los Oros pagados siguen en juego. Gaitas ("agrupa este
    # Oro") solo sirve pagado y el Caldero de Corff pagado no se disparaba.
    pagados = [o for j in p.e.jugadores for o in j.pagado] if ORO_PAGADO_DISPARA else []
    fuentes = p.e.instancias_en_juego() + pagados
    if ROBOS_AL_FINAL:
        # Desafío z7to: primero las habilidades (Látigo y Bastón mira el tope)
        # y al final los robos (Guerrero Escorpión), si no se mira otra carta.
        def roba(x):
            return any(h.get("cuando") == "al_inicio_fase" and h.get("accion") == "robar"
                       and h.get("fase", "cualquiera") in (fase, "cualquiera") for h in x.habilidades)
        fuentes = sorted(fuentes, key=roba)  # sort estable: el resto conserva su orden
    for s in fuentes:
        grupos: set[str] = set()
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") == "al_inicio_fase" and h.get("fase", "cualquiera") in (fase, "cualquiera"):
                if s.zona == Zona.PAGADO and h.get("zonaActivacion") in ("reserva_oro", "reserva"):
                    continue  # "si este Oro está en tu Reserva"
                limite = int(h.get("limitePorTurno", 0))
                if limite and usos(p, s.controlador, s, h, k) >= limite:
                    continue
                grupo = h.get("grupoLimite")
                if grupo and h.get("opcional") and getattr(p.decide(s.controlador), "elige_ninguna", False):
                    # Dario III: "desterrar 1 de un Cementerio o robar 1" (una
                    # sola por turno): la persona elige cuál, o ninguna.
                    if grupo in grupos:
                        continue
                    grupos.add(grupo)
                    hermanas = [x for x in s.habilidades if x.get("grupoLimite") == grupo
                                and x.get("cuando") == "al_inicio_fase" and x.get("opcional")]
                    if len(hermanas) > 1:
                        elegida = _elegir_del_grupo(p, s.controlador, s, hermanas)
                        if elegida is not None and _intentar(p, s.controlador, s, elegida) and limite:
                            sumar_uso(p, s.controlador, s, h, k)
                        continue
                if _intentar(p, s.controlador, s, h) and limite:
                    sumar_uso(p, s.controlador, s, h, k)


def expirar(p: "Partida", duracion: str, *, controlador: int | None = None) -> None:
    if duracion == "hasta_fase_final":
        for j in p.e.jugadores:
            for inst in j.mano + j.cementerio + j.mazo + j.destierro + list(p.e.instancias_en_juego(j.indice)):
                if inst.copia and not getattr(inst, "copia_permanente", False):
                    inst.copia = ()
                if inst.carta_original is not None:
                    inst.carta = inst.carta_original
                    inst.carta_original = None
        for inst in list(p.e.instancias_en_juego()):
            if inst.tipo_temporal is not None:
                inst.tipo_temporal = inst.fuerza_temporal = None
                if inst.carta.tipo == Tipo.ORO:
                    inst.raza_temporal = None
                inst.listo = False
                p._mover(inst, inst.zona_oro_origen or Zona.RESERVA)
                inst.zona_oro_origen = None
                p.anotar(f"{inst.nombre} vuelve a ser un {inst.tipo.value}")
    for inst in p.e.instancias_en_juego():
        inst.mods = [
            m
            for m in inst.mods
            if not (
                m.duracion == duracion
                and (controlador is None or m.creador == controlador)
                and (duracion != "hasta_vigilia" or m.turno < p.e.turno)
            )
        ]
        if inst.sin_habilidad_hasta == duracion:
            inst.sin_habilidad_hasta = None
        inst.estados = [
            e
            for e in inst.estados
            if not (
                e.get("duracion") == duracion
                and (controlador is None or e.get("creador", controlador) == controlador)
            ) and not (
                duracion == "hasta_fase_final" and e.get("duracion") == "proximo_turno"
                and e.get("hasta", 0) <= p.e.turno
            )
        ]


# ── Ventanas de anulación y prevención ───────────────────────────────────────
def ventana_anulacion(p: "Partida", i: int, jugada: Instancia) -> bool:
    """El oponente puede anular la carta recién jugada. True = anulada."""
    if tiene_prop(p, jugada, "noAnulable") or jugada.tipo == Tipo.ORO:
        return False
    for x in list(p.j(i).proximos):
        if x["modo"] == "noAnulable" and x["turno"] == p.e.turno and coincide(p, jugada, {**x["objetivo"], "quien": None}):
            p.j(i).proximos.remove(x)  # Linaje Celta: el próximo Desafiante no puede ser anulado
            p.anotar(f"{jugada.nombre} no puede ser anulado (Linaje Celta)")
            return False
    q = 1 - i
    opciones: list[tuple[Instancia, dict]] = []
    for h in jugada.habilidades:
        if h.get("accion") == "restriccion" and h.get("modo") == "anulable_pagando" \
                and p.j(q).oro_disponible >= int(h.get("valor", 0) or 0):
            # Sombras Areneras: el oponente puede anularla pagando 3 Oros.
            opciones.append((jugada, {"accion": "anular", "costo": {"oros": int(h.get("valor", 0) or 0)},
                                      "objetivo": {}}))
    for t in p.j(q).mano:
        if t.tipo != Tipo.TALISMAN or not p.puede_pagar(q, t):
            continue
        for h in t.habilidades:
            # Reporte qx6H: Morir de Pie exige 2 Aliados de una misma raza.
            if h.get("accion") == "anular" and not (h.get("objetivo") or {}).get("anulaAnulacion")                     and coincide(p, jugada, h.get("objetivo") or {}) and condicion_ok(p, q, h):
                opciones.append((t, h))
                break
    for s in p.e.instancias_en_juego(q):
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "anular" or h.get("cuando") not in ("activada", "oponente_juega"):
                continue
            limite = int(h.get("limitePorTurno", 0)) or 1
            if s.usos_turno.get(k, 0) >= limite or not puede_pagar_costo(p, q, s, h):
                continue
            if (h.get("costo") or {}).get("orosSegun") == "coste_objetivo" \
                    and p.j(q).oro_disponible < jugada.carta.coste:
                continue  # Helénica: paga el coste del Aliado que anula
            if coincide(p, jugada, h.get("objetivo") or {}) and condicion_ok(p, q, h):
                opciones.append((s, h))
    if not opciones:
        return False
    elegida = p.decide(q).anular(p, q, jugada, opciones)
    if elegida is None:
        return False
    fuente, h = opciones[elegida]
    if fuente.zona == Zona.MANO:  # Talismán de anulación
        p._pagar_oro(q, p.coste_de(q, fuente))
        p.jugadas[q].add(fuente.nombre)
        p._mover(fuente, zona_final_talisman(fuente))
    elif fuente is jugada:  # Sombras Areneras: el oponente paga para anularla
        p._pagar_oro(q, int((h.get("costo") or {}).get("oros", 0)))
    else:
        if (h.get("costo") or {}).get("orosSegun") == "coste_objetivo":
            p._pagar_oro(q, jugada.carta.coste, por=fuente)  # Helénica
            p.anotar(f"paga {jugada.carta.coste} Oros")
        if not pagar_costo(p, q, fuente, h):
            return False
        k = fuente.habilidades.index(h) if h in fuente.habilidades else 0
        fuente.usos_turno[k] = fuente.usos_turno.get(k, 0) + 1
    if _contra_anulacion(p, i, fuente):
        return False  # Invocar Chacales: se anula la anulación
    p.anotar(f"J{q} anula {jugada.nombre} con {fuente.nombre}")
    # La carta anulada va al Cementerio; luego los "luego" (Gran Guardián).
    p._sacar(jugada)
    p._mover(jugada, Zona.CEMENTERIO)
    aplicar_luego(p, q, fuente, h, True, [jugada])
    return True


def prevenir(p: "Partida", inst: Instancia, *, combate: bool = False, destruir: bool = False) -> bool:
    """¿Su controlador evita que sea Destruida/Desterrada? Paga si corresponde."""
    c = inst.controlador
    lanzador = getattr(p, "ctx_lanzador", None)
    if destruir and _barajar_en_vez(p, inst, combate, lanzador):
        return True
    if _talisman_que_previene(p, inst):
        return True
    for s in p.e.instancias_en_juego(c):
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "prevenir":
                continue
            modo = (h.get("modo") or "destruir_desterrar")
            if modo in ("afectada", "barajar_mazo") or modo.startswith("barajar_en_vez"):
                # Se usan aparte (prevenir_afectar, _barajar_en_vez). Desafío 2PE6:
                # Amkh ("que sea barajada o puesta en el Mazo") prevenía una destrucción.
                continue
            if modo == "por_habilidad_oponente" and (combate or lanzador is None or lanzador == c):
                continue
            if modo == "destruir" and not destruir:
                continue  # Carruaje Negro: "prevenir que sea destruido" (no desterrado)
            if modo == "combate" and not (combate and destruir):
                continue  # Soteira: solo "destruido por daño de combate"
            obj = h.get("objetivo") or {}
            if not _en_zona_activacion(s, h):
                continue
            if obj.get("quien") == "esta_carta":
                if _esta_carta(p, s) is not inst:
                    continue
            elif c not in _lados(s.controlador, obj.get("quien", "propio")) or not coincide(p, inst, obj) \
                    or _excluida(s, inst, obj):
                continue  # Kamose: "otro Aliado Guerrero", no él mismo
            if inst is s and any((h.get("costo") or {}).get(k) for k in (
                    "barajarEstaCarta", "destruirEstaCarta", "desterrarEstaCarta")):
                continue  # pagar sacándose del juego no lo salva
            limite = int(h.get("limitePorTurno", 0))
            if limite and s.usos_turno.get(k, 0) >= limite:
                continue
            if not condicion_ok(p, c, h) or not puede_pagar_costo(p, c, s, h):
                continue
            if (h.get("opcional") or not _costo_gratis(h)) and not p.decide(c).usar_opcional(p, c, s, h):
                continue
            pagar_costo(p, c, s, h)
            sumar_uso(p, c, s, h, k)
            if s.tipo == Tipo.ALIADO and ventana_cancelar(p, c, s, h):
                # Desafío 5VXY T26: Desafiar a Arturo cancela la prevención de
                # Ra (descartó igual: el costo ya se pagó).
                return False
            p.anotar(f"J{c} previene con {s.nombre}")
            if h.get("zonaDestino") == "mano" and inst.en_juego:
                p.sale_del_juego(inst, Zona.MANO)
            elif h.get("luego"):
                aplicar_luego(p, c, s, h, True, [inst])  # Soteira: además gana 1 de fuerza
            return True
    return False


def _contra_anulacion(p: "Partida", i: int, anulador: Instancia) -> bool:
    """Invocar Chacales: anula una carta que anule una de tus cartas."""
    for t in list(p.j(i).mano):
        if t.tipo != Tipo.TALISMAN or not p.puede_pagar(i, t):
            continue
        if not any(h.get("accion") == "anular" and (h.get("objetivo") or {}).get("anulaAnulacion")
                   and condicion_ok(p, i, h) for h in t.habilidades):
            continue
        if not p.decide(i).usar_opcional(p, i, t, {"accion": "anular", "opcional": True, "objetivo": {"quien": "oponente"}}):
            return False
        p._pagar_oro(i, p.coste_de(i, t))
        p.jugadas[i].add(t.nombre)
        p._mover(t, zona_final_talisman(t))
        p.anotar(f"J{i} anula la anulación de {anulador.nombre} con {t.nombre}")
        return True
    return False


def _barajar_en_vez(p: "Partida", inst: Instancia, combate: bool, lanzador: int | None) -> bool:
    """Daana: tus Desafiantes destruidos se barajan en el Mazo. Libro de los
    Muertos: solo si los destruye una carta o habilidad oponente."""
    c = inst.controlador
    for s in p.e.instancias_en_juego(c):
        for h in s.habilidades:
            modo = h.get("modo") or ""
            if h.get("accion") != "prevenir" or not modo.startswith("barajar_en_vez"):
                continue
            if modo == "barajar_en_vez_oponente" and (combate or lanzador is None or lanzador == c):
                continue
            if not _en_zona_activacion(s, h) or not condicion_ok(p, c, h):
                continue
            obj = h.get("objetivo") or {}
            if not coincide(p, inst, obj) or _excluida(s, inst, obj):
                continue
            p.anotar(f"{inst.nombre} se baraja en el Mazo en vez de ser destruido ({s.nombre})")
            p.sale_del_juego(inst, Zona.MAZO)
            return True
    return False


def _talisman_que_previene(p: "Partida", inst: Instancia) -> bool:
    """La Traición de Macalpin: un Talismán de la mano que previene que un
    Aliado tuyo salga del juego."""
    c = inst.controlador
    for t in list(p.j(c).mano):
        if t.tipo != Tipo.TALISMAN or not p.puede_pagar(c, t):
            continue
        for h in t.habilidades:
            if h.get("accion") != "prevenir" or not coincide(p, inst, h.get("objetivo") or {}):
                continue
            if not p.decide(c).usar_opcional(p, c, inst, {**h, "opcional": True}):
                return False
            p._pagar_oro(c, p.coste_de(c, t))
            p.jugadas[c].add(t.nombre)
            p._mover(t, zona_final_talisman(t))
            p.anotar(f"J{c} previene con {t.nombre}")
            return True
    return False


# ── Resolución de efectos ─────────────────────────────────────────────────────
def _jugadores_objetivo(i: int, h: dict) -> list[int]:
    quien = (h.get("objetivo") or {}).get("quien", "propio")
    return _lados(i, quien if quien != "esta_carta" else "propio")


def _seleccionar(p: "Partida", i: int, fuente: Instancia, h: dict, cands: list[Instancia]) -> list[Instancia]:
    obj = h.get("objetivo") or {}
    n = max(1, int(h.get("cantidad", 1)))
    sel = obj.get("seleccion", "elige")
    if obj.get("quien") in ("esta_carta", "esta_fuente") or sel == "todos":
        return cands
    if sel == "azar":
        return p.e.rng.sample(cands, min(n, len(cands)))
    if sel == "mayorFuerza":
        return sorted(cands, key=lambda x: fuerza(p, x) if x.tipo == Tipo.ALIADO else -1, reverse=True)[:n]
    if sel == "tope":
        return cands[:n]  # el Mazo está ordenado desde el tope
    if obj.get("eligeDueno") and obj.get("quien") == "oponente":
        # Baal-Zaphon: "cada jugador baraja 3 de SU Cementerio": el rival
        # elige las suyas (como si fueran propias: lo que más le sirve).
        q = 1 - i
        return p.decide(q).elegir_objetivos(p, q, cands, min(n, len(cands)),
                                            {**h, "objetivo": {**obj, "quien": "propio"}, "opcional": False})
    if obj.get("eligeOponente"):
        # Ptah: "tu oponente elige 6 cartas de tu Cementerio" para barajar.
        q = 1 - i
        if getattr(p.decide(q), "elige_ninguna", False):  # la persona elige
            return p.decide(q).elegir_objetivos(p, q, cands, min(n, len(cands)), {**h, "opcional": False})
        # La IA elige para el rival lo que menos le sirve (lo más barato).
        return sorted(cands, key=lambda x: (x.carta.coste or 0, fuerza(p, x) if x.tipo == Tipo.ALIADO else 0))[:n]
    mismo = obj.get("mismoValor")
    if mismo in ("coste", "fuerza"):
        grupos: dict[int, list[Instancia]] = {}
        for x in cands:
            v = x.carta.coste if mismo == "coste" else fuerza(p, x)
            grupos.setdefault(v, []).append(x)
        validos = [g for g in grupos.values() if len(g) >= n]
        if not validos:
            return []
        decide = p.decide(i)
        mejor = max(validos, key=lambda g: sum(sorted((fuerza(p, x) + x.carta.coste for x in g), reverse=True)[:n]))
        return decide.elegir_objetivos(p, i, mejor, n, h)
    return p.decide(i).elegir_objetivos(p, i, cands, min(n, len(cands)), h)


def resolver(p: "Partida", i: int, fuente: Instancia, h: dict) -> None:
    """Resuelve el efecto principal y luego los efectos "luego" en orden."""
    # Sacrificio de Tigernmas: "si controlabas Aliados Crom" se mira antes del efecto.
    for e in h.get("luego") or []:
        if isinstance(e, dict) and e.get("condicionPrevia"):
            p.__dict__.setdefault("condiciones_previas", {})[id(e)] = condicion_ok(
                p, i, {"condicion": e["condicionPrevia"]})
    cumplido, afectadas = _resolver_efecto(p, i, fuente, h)
    aplicar_luego(p, i, fuente, h, cumplido, afectadas)


def aplicar_luego(p: "Partida", i: int, fuente: Instancia, h: dict, cumplido: bool, afectadas: list[Instancia]) -> None:
    elegidos: set[str] = set()
    decididos: dict[str, dict | None] = {}
    for e in h.get("luego") or []:
        if not isinstance(e, dict):
            continue
        if e.get("grupoElegir") in elegidos:
            continue  # Cuerno de la Bestia: ya se eligió la otra opción
        relacion = e.get("relacion", "si_se_cumplio")
        if relacion == "si_se_cumplio" and not cumplido:
            break
        if relacion == "si_no_se_cumplio" and cumplido:
            continue  # Idmon: "si no es un Héroe, envíala al Cementerio"
        if e.get("momento") == "fase_final":
            # Se revisa y resuelve en la Fase Final de este turno (también el
            # filtro: Voluntad de Caballero mira si el Aliado atacó o bloqueó).
            p.pendientes_final.append((i, fuente, e, list(afectadas)))
            continue
        if relacion == "si_afectada_cumple":
            cumplen = [x for x in afectadas if coincide(p, x, e.get("filtroAfectada") or {})]
            if not cumplen:
                break  # Druida Sanador: "si ese Aliado es un Druida"
            if h.get("accion") == "botar":
                # Ramsés IX: por qué bota 2 más.
                p.anotar(f"{fuente.nombre}: cayó " + ", ".join(f"{x.nombre} ({x.tipo.value})" for x in cumplen))
        if e.get("momento") == "fase_final":
            # Se revisa y resuelve en la Fase Final de este turno.
            p.pendientes_final.append((i, fuente, e, list(afectadas)))
            continue
        if relacion == "si_afectada_hizo_dano" and not any(x.uid in p.dano_hecho for x in afectadas):
            break
        # Anand: "robas 1 o barajas 1": opciones excluyentes del mismo grupo.
        # Quien juega elige cuál (antes se preguntaba "¿usar?" en orden, sin
        # decir cuál, y el desafío tomaba siempre la primera).
        grupo = e.get("grupoElegir")
        ya_elegida = False
        if grupo and grupo not in decididos:
            hermanas = [x for x in h.get("luego") or [] if isinstance(x, dict) and x.get("grupoElegir") == grupo]
            elegir = getattr(p.decide(i), "elegir_opcion", None)
            if len(hermanas) > 1 and elegir is not None:
                posibles = [x for x in hermanas if condicion_ok(p, i, x) and puede_pagar_costo(p, i, fuente, x)]
                k = elegir(p, i, fuente, posibles) if posibles else None
                decididos[grupo] = posibles[k] if k is not None and 0 <= k < len(posibles) else None
        if grupo in decididos:
            if e is not decididos[grupo]:
                continue
            # Quien puede decir "ninguna" al elegir (la persona) ya decidió usarla.
            ya_elegida = getattr(p.decide(i), "elige_ninguna", False)
        # Condición, "puedes" y costo propios del paso (Kawit, Ib-Mut…).
        if not condicion_ok(p, i, e):
            continue
        if e.get("condicionPrevia") and not p.__dict__.get("condiciones_previas", {}).pop(id(e), False):
            continue
        if (e.get("opcional") or not _costo_gratis(e)) and not puede_pagar_costo(p, i, fuente, e):
            continue
        if (e.get("opcional") or not _costo_gratis(e)) and not ya_elegida \
                and not p.decide(i).usar_opcional(p, i, fuente, e):
            continue
        if not pagar_costo(p, i, fuente, e):
            continue
        p.ctx_previas = afectadas
        cumplido, nuevas = _resolver_efecto(p, i, fuente, e, previas=afectadas)
        if cumplido and e.get("grupoElegir"):
            elegidos.add(e["grupoElegir"])
        if nuevas:
            afectadas = nuevas


def resolver_pendientes_final(p: "Partida") -> None:
    """Efectos "luego" diferidos a la Fase Final (p. ej. Forma de Lince)."""
    pendientes, p.pendientes_final = p.pendientes_final, []
    for i, fuente, e, afectadas in pendientes:
        if e.get("relacion") == "si_afectada_hizo_dano" and not any(x.uid in p.dano_hecho for x in afectadas):
            continue
        if e.get("relacion") == "si_afectada_cumple" and not any(
            coincide(p, x, e.get("filtroAfectada") or {}) for x in afectadas
        ):
            continue
        if not condicion_ok(p, i, e) or not puede_pagar_costo(p, i, fuente, e):
            continue
        if (e.get("opcional") or not _costo_gratis(e)) and not p.decide(i).usar_opcional(p, i, fuente, e):
            continue
        if not pagar_costo(p, i, fuente, e):
            continue
        p.anotar(f"{fuente.nombre}: efecto en la Fase Final")
        _resolver_efecto(p, i, fuente, e, previas=afectadas)


def _por_referencia(p: "Partida", i: int, fuente: Instancia, e: dict, previas: list[Instancia]) -> list[Instancia] | None:
    """Candidatos de un efecto "luego" según su referencia (None = filtro normal)."""
    obj = e.get("objetivo") or {}
    ref = obj.get("referencia", "ninguna")
    if ref == "afectadas":
        return list(previas)
    if ref == "no_afectadas":
        return [x for x in candidatos_validos(p, i, fuente, e) if x not in previas]
    if ref == "mismo_tipo":
        tipos = {x.tipo for x in previas}
        uids = {x.uid for x in previas}
        sin_filtro = {**obj, "tipos": []}
        return [
            x
            for x in candidatos(p, i, fuente, {**e, "objetivo": sin_filtro})
            if x.tipo in tipos and x.uid not in uids and coincide(p, x, {**sin_filtro, "tipos": []})
        ]
    if ref == "copias":
        nombres = {x.nombre for x in previas}
        uids = {x.uid for x in previas}
        sin_filtro = {**obj, "tipos": [], "coste": None, "fuerza": None, "raza": ""}
        return [
            x
            for x in candidatos(p, i, fuente, {**e, "objetivo": sin_filtro})
            if x.nombre in nombres and x.uid not in uids
        ]
    return None


def _resolver_efecto(
    p: "Partida", i: int, fuente: Instancia, h: dict, *, previas: list[Instancia] | None = None
) -> tuple[bool, list[Instancia]]:
    """Aplica un efecto. Devuelve (se cumplió, cartas afectadas)."""
    accion = h.get("accion", "otra")
    if h.get("cantidadSegun") == "fuerza_esta_carta":
        propia = _esta_carta(p, fuente)
        h = {**h, "cantidadSegun": "fijo", "cantidad": fuerza(p, propia) if propia is not None else 0}
    p.ctx_lanzador = i
    n = cantidad(p, i, h, previas or [])
    if accion in PROPIEDADES or accion in ("anular", "prevenir", "modificarCoste", "otra", "redirigir",
                                            "cancelarHabilidad"):
        return False, []  # propiedades/continuas o sin motor: no hacen nada al resolverse
    if accion == "robar":
        for lado in _jugadores_objetivo(i, h):
            p.robar(lado, cantidad(p, i, h, previas or [], lado=lado), desde_fondo=h.get("modo") == "fondo",
                    fuente=fuente.nombre)
        return True, []
    if accion == "robarHasta":
        limite = int(h.get("valor", 8))
        for lado in _jugadores_objetivo(i, h):
            faltan = max(0, limite - len(p.j(lado).mano))
            if faltan:
                p.robar(lado, faltan, fuente=fuente.nombre)
        return True, []
    if accion == "vetarAliados":
        # Meleagro: en el siguiente turno, tu oponente no podrá poner Aliados en juego.
        p.j(1 - i).veto_aliados_turno = p.e.turno + 1
        p.anotar(f"{fuente.nombre}: J{1 - i} no podrá poner Aliados en juego su próximo turno")
        return True, []
    if accion == "ordenarFondo":
        # Shay: mira las N cartas inferiores de tu Mazo Castillo y las ordena.
        mazo = p.j(i).mazo
        vistas = mazo[-n:] if n > 0 else []
        if not vistas:
            return False, []
        orden = p.decide(i).elegir_objetivos(p, i, list(vistas), len(vistas), {**h, "accion": "buscar"})
        orden += [x for x in vistas if x not in orden]
        del mazo[-len(vistas):]
        mazo.extend(reversed(orden))  # la preferida queda al fondo: es la próxima que roba
        p.anotar(f"{fuente.nombre}: J{i} ordena las {len(vistas)} cartas inferiores de su mazo")
        return True, []
    if accion == "barajarTipos":
        if prohibido(p, "barajar", i) or prohibido(p, "barajar_cementerio", i):
            return False, []
        elegidas = []
        for tipo in Tipo:
            opciones = [x for x in p.j(i).cementerio if x.tipo == tipo]
            if opciones:
                t = p.decide(i).elegir_objetivos(p, i, opciones, 1, h)[0]
                elegidas.append(t)
        for t in elegidas:
            p._mover(t, Zona.MAZO)
        if elegidas:
            p.e.rng.shuffle(p.j(i).mazo)
            # Lo que se baraja desde el Cementerio es público: se nombra cada carta.
            p.anotar(f"{fuente.nombre}: baraja una carta de cada tipo: {', '.join(t.nombre for t in elegidas)}")
        return bool(elegidas), elegidas
    if accion == "mirarManoAzar":
        mano = p.j(1 - i).mano
        vistas = p.e.rng.sample(mano, min(n, len(mano)))
        for x in vistas:
            x.revelada = True
        # Maldición Lunar: solo se elige entre las vistas que cumplan el filtro.
        validas = [x for x in vistas if coincide(p, x, {**(h.get("objetivo") or {}), "quien": None})]
        if not validas:
            return False, []
        t = p.decide(i).elegir_objetivos(p, i, validas, 1, h)[0]
        if h.get("zonaDestino") == "cementerio":
            p.descartar(t)
            p.anotar(f"{fuente.nombre}: J{1 - i} descarta {t.nombre}")
            return True, [t]
        p._mover(t, Zona.MAZO, al_tope=False)
        p.anotar(f"{fuente.nombre}: pone {t.nombre} al fondo del mazo oponente")
        return True, [t]
    if accion == "botarOroAMano":
        mazo = p.j(i).mazo
        if not mazo:
            return False, []
        t = mazo[0]
        if t.tipo == Tipo.ORO:
            p._mover(t, Zona.MANO)
            t.revelada = True
            p.anotar(f"{fuente.nombre}: pone {t.nombre} del tope en su mano")
            p._comprobar_mazos("efecto")
            return True, [t]
        p.botar(i, 1, causa="autodano")
        return True, [t]
    if accion == "tomarFondo":
        tomadas = list(p.j(i).mazo[-n:]) if n > 0 else []
        for t in tomadas:
            p._mover(t, Zona.MANO)
        if tomadas:
            p.anotar(f"{fuente.nombre}: J{i} pone {len(tomadas)} del fondo de su mazo en su mano")
        p._comprobar_mazos("efecto")
        return bool(tomadas), tomadas
    if accion == "botar":
        botadas: list[Instancia] = []
        for lado in _jugadores_objetivo(i, h):
            antes = len(p.j(lado).mazo)
            n = cantidad(p, i, h, previas or [], lado=lado)
            if lado != i:
                n += sum(int(x.get("valor", 0)) for s in p.e.instancias_en_juego(i)
                         for x in s.habilidades if x.get("accion") == "modificarDanoDirecto")
            vistas = list(p.j(lado).mazo[:n])
            p.anotar(f"{fuente.nombre}: J{lado} bota {n}")
            p.botar(lado, n, causa="botar" if lado != i else "autodano")
            botadas += [x for x in vistas if x.zona == Zona.CEMENTERIO]  # Ramsés IX: mira lo botado
            if lado != i:
                _reaccion_botar(p, lado, antes - len(p.j(lado).mazo))
        return True, botadas
    if accion == "descartar":
        elegidas_todas = []
        obj = _con_raza_nombrada(fuente, h.get("objetivo") or {})
        for lado in _jugadores_objetivo(i, h):
            n = cantidad(p, i, h, previas or [], lado=lado)
            mano = list(p.j(lado).mano)
            if obj.get("eligeQuienJuega"):
                # Destrozar la Mente / Manipular Mente: miras su mano y eliges tú.
                for x in mano:
                    x.revelada = True
                mano = [x for x in mano if coincide(p, x, {**obj, "quien": None})]
                if obj.get("seleccion") == "todos":
                    elegidas = mano
                else:
                    elegidas = p.decide(i).elegir_objetivos(p, i, mano, min(n, len(mano)), h) if mano else []
            elif (h.get("objetivo") or {}).get("seleccion") == "azar":
                elegidas = p.e.rng.sample(mano, min(n, len(mano)))
            else:
                elegidas = p.decide(lado).elegir_descartes(p, lado, mano, min(n, len(mano)))
            for x in elegidas:
                p.descartar(x)
                p.anotar(f"{fuente.nombre}: J{lado} descarta {x.nombre}")
            elegidas_todas += elegidas
        return bool(elegidas_todas), elegidas_todas
    if accion == "generarOro":
        oros = int(h.get("valor") or n) * por_cada(p, fuente, h)
        tipos, raza = h.get("soloParaTipos") or [], h.get("soloParaRaza") or ""
        if tipos or raza:
            p.j(i).oros_restringidos.append([oros, list(tipos), raza, int(h.get("soloParaCosteMin") or 0)])
        else:
            p.j(i).oros_virtuales += oros
        return True, []
    if accion == "mirar":
        if h.get("modo") == "mano_oponente":
            # Cultistas mira la mano rival: desde ahí esas cartas son conocidas.
            for t in p.j(1 - i).mano:
                t.revelada = True
            # Reporte 5R9h: se muestra la mano aunque no haya Aliado que barajar.
            mostrar_mano_rival(p, i, fuente)
        elif h.get("modo") == "mazo_propio" and p.j(i).mazo:
            # Reporte 4NtK: Olímpicos mira la primera carta: quien mira la ve
            # (y queda a la vista sobre su castillo mientras siga arriba).
            tope = p.j(i).mazo[0]
            p.j(i).tope_visto = tope.uid
            p.anotar(f"{fuente.nombre}: la primera carta del castillo de J{i} es {privado(i, tope.nombre)}")
        return True, []  # información: no cambia el estado
    if accion == "mirarTope":
        return _mirar_tope(p, i, fuente, h, n)
    if accion == "convertirEnAliado" and "Tótem" in ((h.get("objetivo") or {}).get("tipos") or []):
        # Hipatia: un Tótem que controles es un Aliado Indestructible de fuerza
        # igual a su coste hasta la Fase Final (luego vuelve a ser Tótem).
        totems = [x for x in p.j(i).apoyo if x.tipo == Tipo.TOTEM]
        if not totems:
            return False, []
        t = p.decide(i).elegir_objetivos(p, i, totems, 1, h)[0]
        t.zona_oro_origen = t.zona
        t.tipo_temporal = Tipo.ALIADO
        t.fuerza_temporal = t.carta.coste
        p._mover(t, Zona.DEFENSA)
        t.listo = True
        t.estados.append({"modo": "prop:indestructible", "duracion": "hasta_fase_final", "fuente": fuente.uid,
                          "turno": p.e.turno, "creador": i})
        p.anotar(f"{fuente.nombre}: {t.nombre} es un Aliado Indestructible de fuerza {t.fuerza_temporal}")
        return True, [t]
    if accion == "convertirEnAliado":
        # Ave de Hera: este Oro es un Aliado de coste y fuerza N hasta la Fase Final.
        if fuente.zona not in (Zona.RESERVA, Zona.PAGADO):
            return False, []
        fuente.zona_oro_origen = fuente.zona
        fuente.tipo_temporal = Tipo.ALIADO
        fuente.fuerza_temporal = int(h.get("valor") or 0)
        if h.get("razaPropia"):
            # Milano Negro: "nombra una raza": la de mis Aliados (suma a "misma raza").
            razas = [a.raza for a in p.j(i).aliados if a.raza]
            fuente.raza_temporal = max(set(razas), key=razas.count) if razas else None
            if getattr(p.decide(i), "elige_ninguna", False):
                # Reporte ZTSY: la persona nombra la raza que quiera.
                todas = sorted({x.carta.raza for j in p.e.jugadores
                                for x in j.mazo + j.mano + j.defensa + j.ataque + j.cementerio
                                if x.tipo == Tipo.ALIADO and x.carta.raza})
                elegida = p.decide(i).elegir_raza(p, i, todas + [OTRA_RAZA], h)
                fuente.raza_temporal = None if elegida == OTRA_RAZA else elegida
            if fuente.raza_temporal:
                p.anotar(f"{fuente.nombre} nombra la raza {fuente.raza_temporal}")
        p._mover(fuente, Zona.DEFENSA)
        fuente.listo = True  # ya estaba en juego desde antes
        p.anotar(f"{fuente.nombre} se convierte en un Aliado de fuerza {fuente.fuerza_temporal}")
        return True, [fuente]
    if accion == "agrupar" and (h.get("objetivo") or {}).get("quien") == "esta_carta":
        if fuente.zona == Zona.PAGADO:  # Gaitas: "puedes agrupar este Oro"
            p._mover(fuente, Zona.RESERVA)
            return True, [fuente]
        if fuente.zona == Zona.ATAQUE:  # Aed Finn: "puedes agrupar este Aliado"
            p._mover(fuente, Zona.DEFENSA)
            return True, [fuente]
        return False, []
    if accion in ("agrupar", "noAgrupar"):
        modo = (h.get("modo") or "ambos")
        for lado in _jugadores_objetivo(i, h):
            jug = p.j(lado)
            if accion == "noAgrupar":
                jug.no_agrupar = modo
                continue
            if modo in ("aliados", "ambos"):
                for x in list(jug.ataque):
                    p._mover(x, Zona.DEFENSA)
            if modo in ("oros", "ambos"):
                for x in list(jug.pagado):
                    p._mover(x, Zona.RESERVA)
        return True, []
    if accion == "cancelarAtaque":
        return _cancelar(p, i, fuente, h)
    if accion == "otorgarPropiedad" and (h.get("objetivo") or {}).get("quien") == "proximo":
        # Defensores Celtas / Linaje Celta: el próximo Aliado que juegues este turno.
        obj = h.get("objetivo") or {}
        p.j(i).proximos.append({"modo": h.get("modo") or "imbloqueable", "objetivo": obj, "turno": p.e.turno})
        p.anotar(f"{fuente.nombre}: el próximo {obj.get('raza') or 'Aliado'} que juegues será {h.get('modo')}")
        return True, []
    if accion == "copiarHabilidad":
        cands = candidatos_validos(p, i, fuente, h)
        if not cands:
            return False, []
        t = _seleccionar(p, i, fuente, h, cands)[0]
        fuente.copia = tuple(x for x in t.carta.habilidades if x.get("accion") != "copiarHabilidad")
        if h.get("duracion") == "permanente":
            # Fiodhain: "tiene todas las habilidades de ese Aliado por el resto
            # del juego" (mientras siga en juego: al salir vuelve a ser ella).
            fuente.copia_permanente = True
            if fuente.tipo == Tipo.ALIADO and fuente.en_juego and tiene_prop(p, fuente, "furia"):
                fuente.listo = True  # copió "puede atacar cuando entra en juego"
            p.anotar(f"{fuente.nombre}: tiene las habilidades de {t.nombre} por el resto del juego")
        else:
            p.anotar(f"{fuente.nombre}: copia la habilidad de {t.nombre} hasta la Fase Final")
        return True, [t]
    if accion == "copiarEfecto":
        cands = candidatos_validos(p, i, fuente, h)
        if not cands:
            return False, []
        t = _seleccionar(p, i, fuente, h, cands)[0]
        efectos = _habilidades_al_jugar(t)
        if not efectos:
            return False, []
        for efecto in efectos:
            resolver(p, i, t, efecto)
        p.anotar(f"{fuente.nombre}: copia el efecto de {t.nombre}")
        return True, [t]
    if accion == "convertirEnCopia":
        cands = candidatos_validos(p, i, fuente, h)
        if not cands or fuente.carta_original is not None:
            return False, []
        t = _seleccionar(p, i, fuente, h, cands)[0]
        fuente.carta_original = fuente.carta
        fuente.carta = t.carta
        p.anotar(f"{fuente.carta_original.nombre} se convierte en una copia de {t.nombre} hasta la Fase Final")
        return True, [t]
    if accion == "reducirDano" and h.get("modo") != "aliado_sin_dano":
        return False, []
    if accion in ("restriccion", "inmunidad"):
        return False, []  # continuas: se consultan, no se resuelven
    if accion == "jugarDesde":
        return _jugar_desde(p, i, fuente, h)
    if accion in ("buscar", "ponerEnJuego"):
        elegidas = _buscar(p, i, fuente, h, accion)
        if not elegidas:
            # Que la narración muestre que se intentó (Werin sin Talismanes).
            verbo = "pone en juego" if accion == "ponerEnJuego" else accion
            p.anotar(f"{fuente.nombre}: {verbo} → no hay cartas válidas")
        return bool(elegidas), elegidas

    obj = h.get("objetivo") or {}
    if obj.get("quien") == "ambos" and obj.get("seleccion", "elige") != "todos":
        # Cada jugador afecta una de las suyas y la elige él (Ib-Mut). Se
        # cumple solo si ambos pudieron.
        resultados = [
            _resolver_efecto(p, lado, fuente, {**h, "luego": [], "objetivo": {**obj, "quien": "propio"}}, previas=previas)
            for lado in (i, 1 - i)
        ]
        return all(r[0] for r in resultados), [x for r in resultados for x in r[1]]

    h = {**h, "cantidad": n}
    por_ref = _por_referencia(p, i, fuente, h, previas or []) if previas is not None else None
    if por_ref is not None:
        cands = por_ref
    else:
        cands = candidatos_validos(p, i, fuente, h)
    if h.get("cantidadExacta") and len(cands) < n:
        return False, []
    costo = h.get("costo") or {}
    paga_por_objetivo = costo.get("desterrarCementerioSegun") == "coste_objetivo"
    if obj.get("zona") == "mano" and obj.get("quien") == "oponente" and obj.get("seleccion", "elige") == "elige":
        mostrar_mano_rival(p, i, fuente)  # Neferhetepes: "mira la mano" (también sus Oros)
    if paga_por_objetivo:
        # Nephre-Ka: solo objetivos cuyo coste se pueda pagar con el Cementerio.
        tope = len([x for x in p.j(i).cementerio if x is not fuente])
        cands = [x for x in cands if x.tipo != Tipo.ORO and x.carta.coste <= tope]
    if not cands:
        motivo = _motivo_sin_objetivos(p, i, h)
        if motivo:
            p.anotar(f"✗ {fuente.nombre}: {motivo}")
        return False, []
    objetivos = _seleccionar(p, i, fuente, h, cands)
    if h.get("cantidadExacta") and len(objetivos) != n:
        return False, []
    if obj.get("grupoMismoCoste") and objetivos:
        coste_elegido = objetivos[0].carta.coste
        objetivos = [x for x in cands if x.tipo != Tipo.ORO and x.carta.coste == coste_elegido]
    if paga_por_objetivo:
        pagados = []
        for t in objetivos:
            if _desterrar_del_cementerio(p, i, fuente, t.carta.coste):
                pagados.append(t)
        objetivos = pagados
    if costo.get("orosSegun") == "coste_objetivo":
        pagados = []
        for t in objetivos:
            if t.carta.coste <= p.j(i).oro_disponible:
                p._pagar_oro(i, t.carta.coste, por=fuente)
                p.anotar(f"paga {t.carta.coste} Oros")
                pagados.append(t)
        objetivos = pagados
    objetivos = [t for t in objetivos if _pagar_recargo(p, i, t, fuente)]
    if h.get("antesPerderHabilidad"):
        # Artabano: "para que pierda su habilidad y sea destruido". Primero la
        # pierde: ya no se previene a sí mismo (Ptolomeo II), no es
        # Indestructible ni dispara lo suyo al salir.
        for t in objetivos:
            if t.en_juego and t.controlador != i and not inmune(p, t, fuente):
                t.sin_habilidad_hasta = "hasta_fase_final"
                p.anotar(f"{fuente.nombre}: quita la habilidad a {t.nombre}")
        refrescar_perdidas(p)
    objetivos = [t for t in objetivos if not prevenir_afectar(p, t, i, h)]
    if obj.get("seleccion", "elige") in ("elige", "azar") and obj.get("quien") != "esta_carta":
        objetivos = ventana_redireccion(p, i, fuente, h, objetivos)
    for t in objetivos:
        if t.controlador == i or not t.en_juego:
            continue
        for k, hh in enumerate(t.habilidades):
            if hh.get("cuando") == "afectada_por_oponente" and usos(p, t.controlador, t, hh, k) < max(1, int(hh.get("limitePorTurno", 1) or 1)):
                sumar_uso(p, t.controlador, t, hh, k)
                _intentar(p, t.controlador, t, hh)  # Seth: el oponente bota 4
    if accion == "mostrar":
        for t in objetivos:
            t.revelada = True
        if objetivos:
            p.anotar(f"{fuente.nombre}: muestra {', '.join(t.nombre for t in objetivos)}")
        return bool(objetivos), objetivos
    duracion = h.get("duracion", "instantaneo")
    # De dónde salió cada objetivo, para la narración ("Werin (Cementerio)").
    origen = {t.uid: t.zona for t in objetivos}
    mazos_tocados: set[int] = set()
    afectadas: list[Instancia] = []
    for t in objetivos:
        if t.zona == Zona.MAZO:
            mazos_tocados.add(t.dueno)
        ok = True
        if accion == "destruir":
            if t.en_juego:
                ok = p.destruir(t)
            else:
                p._mover(t, Zona.CEMENTERIO)
        elif accion == "desterrar":
            ok = p.desterrar(t)
        elif accion == "subirMano":
            if t.en_juego:
                p.sale_del_juego(t, Zona.MANO)
            else:
                p._mover(t, Zona.MANO)
        elif accion == "barajar":
            if t.en_juego:
                p.sale_del_juego(t, Zona.MAZO)
            else:
                p._mover(t, Zona.MAZO)
                mazos_tocados.add(t.dueno)
        elif accion == "modificarFuerza":
            ok = t.en_juego
            if ok:
                t.mods.append(
                    ModFuerza(
                        modo=h.get("modoFuerza", "sumar"),
                        valor=int(h.get("valor", 0)) * por_cada(p, fuente, h),
                        # Instantáneo = hasta el final del turno (Toro Apis: −1
                        # en ese combate). "Permanente" se elige aparte.
                        duracion="hasta_fase_final" if duracion == "instantaneo" else duracion,
                        turno=p.e.turno,
                        fuente=fuente.uid,
                        creador=i,
                        congela=bool(h.get("congelar")),
                    )
                )
                if t.controlador != i and fuente.tipo == Tipo.ALIADO and h.get("modoFuerza", "sumar") == "sumar" \
                        and int(h.get("valor", 0)) < 0:
                    _disparar_rival_pierde_fuerza(p, i, t)
        elif accion == "perderHabilidad":
            ok = t.en_juego and not protegida(p, t)
            if ok:
                t.sin_habilidad_hasta = "permanente" if duracion == "instantaneo" else duracion
                # Draco Cometa / Averix: "mientras esté en juego" depende de la fuente.
                t.sin_habilidad_fuente = fuente.uid if duracion == "mientras_en_juego" else None
                if any(x.get("accion") == "destruirSiPierdeHabilidad" for x in t.carta.habilidades):
                    p.anotar(f"{t.nombre} iba a perder su habilidad: es destruido")
                    p.destruir(t)  # Herrero
        elif accion == "mover":
            ok = _mover_a(p, t, h.get("zonaDestino", "mazo_tope"))
        elif accion == "obligarBloqueo":
            atk = _esta_carta(p, fuente)
            ok = atk is not None and t.zona == Zona.DEFENSA
            if ok:
                p.bloqueo_forzado[atk.uid] = t
        elif accion == "ganarControl":
            # Héctor (fu7V): el control de Haquika dura mientras ella esté en
            # juego; si la Capa ya la barajó, es como si nunca hubiera pasado.
            # Una habilidad de entrada de un solo efecto (Conchobar) sí se resuelve.
            ok = t.en_juego and t.controlador != i and not (
                duracion == "mientras_en_juego" and not fuente.en_juego)
            if ok:
                original = t.controlador
                _cambiar_control(p, t, i)
                t.control = {
                    "duracion": duracion if duracion != "instantaneo" else "hasta_fase_final",
                    "fuente": fuente.uid,
                    "turno": p.e.turno,
                    "original": original,
                    "volverA": h.get("volverA"),  # Hathor: regresa a la Línea de Ataque oponente
                }
        elif accion == "cambiarRaza" and h.get("arquetipoNuevo"):
            ok = t.en_juego
            if ok:
                t.arquetipo_extra = h["arquetipoNuevo"]  # Acólitos: "se considera un Aliado Drácula"
        elif accion == "cambiarRaza":
            ok = t.en_juego and bool(h.get("razaNueva"))
            if ok:
                t.raza_temporal = h["razaNueva"]  # Alejandro Magno: "se considera Héroe"
        elif accion == "otorgarPropiedad" and h.get("modo") == "quitarGuardian":
            ok = t.en_juego  # Osiris: pierde "no puede ser declarado atacante" por el resto del juego
            if ok:
                t.estados.append({"modo": "sin_guardian", "duracion": "permanente", "fuente": fuente.uid,
                                  "turno": p.e.turno, "creador": i})
        elif accion == "otorgarPropiedad":
            ok = t.en_juego
            if ok:
                t.estados.append({
                    "modo": f"prop:{h.get('modo') or 'indestructible'}",
                    "duracion": "hasta_fase_final" if duracion == "instantaneo" else duracion,
                    "fuente": fuente.uid,
                    "turno": p.e.turno,
                    "creador": i,
                })
        elif accion == "restringirCombate" and h.get("modo") == "puede_atacar_este_turno":
            ok = t.en_juego and t.tipo == Tipo.ALIADO
            if ok:
                t.listo = True
        elif accion == "restringirCombate" and h.get("modo") == "entra_atacando":
            # Nathair-Teine: "…y jugarlo en tu Línea de Ataque como un Aliado
            # declarado atacante". Se suma al ataque en curso de su controlador.
            ok = t.en_juego and t.tipo == Tipo.ALIADO and bool(p.atacantes) and p.e.activo == t.controlador \
                and not p.ataque_cancelado
            if ok:
                if t.zona != Zona.ATAQUE:
                    p._mover(t, Zona.ATAQUE)
                if t not in p.atacantes:
                    p.atacantes.append(t)
                p.ataco_este_turno.add(t.uid)
        elif accion in ("restringirCombate", "reducirDano"):
            ok = t.en_juego
            if ok:
                estado = {
                    "modo": h.get("modo") or ("aliado_sin_dano" if accion == "reducirDano" else "no_puede_bloquear"),
                    "duracion": "hasta_fase_final" if accion == "reducirDano" or duracion == "instantaneo" else duracion,
                    "fuente": fuente.uid,
                    "turno": p.e.turno,
                }
                if duracion == "proximo_turno":
                    # Berserk: rige en el próximo turno de quien lo jugó.
                    estado.update(desde=p.e.turno + 2, hasta=p.e.turno + 2)
                t.estados.append(estado)
        if ok:
            afectadas.append(t)
    if h.get("vetaCarta") and afectadas:
        fuente.carta_vetada = afectadas[0].nombre  # Titán Gorila: el rival no la puede jugar
    # Intervenir un Mazo Castillo obliga a barajarlo (glosario 2).
    for dueno in mazos_tocados:
        p.e.rng.shuffle(p.j(dueno).mazo)
    if objetivos:  # si todos se previnieron, la prevención ya quedó narrada
        p.anotar(f"{fuente.nombre}: {describir(h)} " + ", ".join(
            # Lo que se baraja desde la propia mano no lo ve el rival.
            privado(i, _con_origen(t, origen)) if accion == "barajar" and origen.get(t.uid) == Zona.MANO
            and t.dueno == i else _con_origen(t, origen) for t in objetivos))
    p._comprobar_mazos("botar")
    return bool(afectadas), afectadas


def _buscar(p: "Partida", i: int, fuente: Instancia, h: dict, accion: str) -> list[Instancia]:
    obj = h.get("objetivo") or {}
    if obj.get("quien") == "ambos" and accion == "ponerEnJuego":
        # Tumulario: cada jugador pone un Aliado de su Cementerio (lo elige él).
        todas = []
        for lado in (i, 1 - i):
            todas += _buscar(p, lado, fuente, {**h, "objetivo": {**obj, "quien": "propio"}}, accion)
        return todas
    if obj.get("quien") == "oponente":
        # Sir Bedivere: un Aliado de la mano del oponente pasa a ser mío.
        zonas = [z for z in zonas_de(obj, "mano") if z in _ZONAS_FUERA] or ["mano"]
        cands = []
        for zona in zonas:
            cands += candidatos_validos(p, i, fuente, h, zona=zona)
        elegidas = _seleccionar(p, i, fuente, h, cands) if cands else []
        for t in elegidas:
            t.revelada = True
            poner_en_juego(p, i, t)
        if elegidas:
            p.anotar(f"{fuente.nombre}: toma {', '.join(t.nombre for t in elegidas)} de J{1 - i}")
        return elegidas
    zonas = [z for z in zonas_de(obj, "mazo") if z in _ZONAS_FUERA] or ["mazo"]
    cands = []
    for zona in zonas:
        cands += candidatos_validos(p, i, fuente, {**h, "objetivo": {**obj, "quien": "propio"}}, zona=zona)
    destino = h.get("zonaDestino") or ("en_juego" if accion == "ponerEnJuego" else "mano")
    if fuente.nombre.casefold() == "melisende" and accion == "buscar":
        destino = "mazo_tope"
    if destino not in ("mano", "cementerio", "destierro"):
        cands = [c for c in cands if not c.carta.solo_desde_mano]  # Dragones
    if obj.get("distintoNombre") and cands:
        # Caminar las Estrellas: "busca 2 cartas con distinto nombre".
        elegidas, quedan = [], list(cands)
        while quedan and len(elegidas) < max(1, int(h.get("cantidad", 1))):
            t = _seleccionar(p, i, fuente, {**h, "cantidad": 1}, quedan)[0]
            elegidas.append(t)
            quedan = [x for x in quedan if x.nombre != t.nombre]
    else:
        elegidas = _seleccionar(p, i, fuente, h, cands) if cands else []
    if h.get("oponenteEligeMano") and elegidas:
        # "…y muéstralas a tu oponente. Tu oponente elige una de ellas y la
        # pone en tu Mano, y la otra ponla en tu Cementerio."
        q = 1 - i
        nombres = " y ".join(t.nombre for t in elegidas)
        p.anotar(f"{fuente.nombre}: J{i} muestra {nombres}; J{q} elige cuál va a la mano de J{i}")
        mostrar_a(p, q, f"{fuente.nombre}: elige cuál va a la mano de tu oponente", elegidas)
        a_mano = elegidas[0]
        if len(elegidas) > 1:
            if getattr(p.decide(q), "elige_ninguna", False):  # la persona elige
                a_mano = p.decide(q).elegir_objetivos(
                    p, q, list(elegidas), 1, {"accion": "repartir", "zonaDestino": "mano", "opcional": True})[0]
            else:
                # La IA le deja al rival la que menos le sirve (la más barata).
                a_mano = min(elegidas, key=lambda x: (x.carta.coste or 0, x.carta.fuerza or 0))
        for t in elegidas:
            p._mover(t, Zona.MANO if t is a_mano else Zona.CEMENTERIO)
        a_mano.revelada = True
        p.e.rng.shuffle(p.j(i).mazo)
        resto = [t.nombre for t in elegidas if t is not a_mano]
        p.anotar(f"{fuente.nombre}: {a_mano.nombre} → mano" + (f"; {', '.join(resto)} → Cementerio" if resto else ""))
        return elegidas
    for t in elegidas:
        if destino == "mazo_tope":
            p._mover(t, Zona.MAZO)
        elif destino in ("mano", "cementerio", "destierro"):
            p._mover(t, {"mano": Zona.MANO, "cementerio": Zona.CEMENTERIO, "destierro": Zona.DESTIERRO}[destino])
            if destino == "mano":
                t.revelada = True  # se mostró al buscarla: el rival sabe que la tiene
        else:
            poner_en_juego(p, i, t)
    if "mazo" in zonas and destino != "mazo_tope":
        p.e.rng.shuffle(p.j(i).mazo)  # siempre se baraja tras buscar (glosario 5)
    if elegidas:
        verbo = "pone en juego" if accion == "ponerEnJuego" else accion
        p.anotar(f"{fuente.nombre}: {verbo} {', '.join(t.nombre for t in elegidas)}")
    return elegidas


def poner_en_juego(p: "Partida", i: int, t: Instancia) -> None:
    """Pone en juego sin jugarla (no paga coste, no hay ventana de anulación)."""
    t.controlador = i
    if t.tipo == Tipo.ALIADO:
        p._mover(t, Zona.DEFENSA)
        refrescar_perdidas(p)  # Cleopatra en juego: llega sin habilidad (sin Furia)
        t.listo = tiene_prop(p, t, "furia")
    elif t.tipo == Tipo.TOTEM:
        p._mover(t, Zona.APOYO)
    elif t.tipo == Tipo.ORO:
        p._mover(t, Zona.RESERVA)
    else:
        return  # Armas y Talismanes no se "ponen en juego" así en la v1
    p.jugadas[i].add(t.nombre)
    disparar(p, t, "al_jugar")
    refrescar_perdidas(p)
    disparar_entrada(p, t)


# ── Acciones del catálogo unificado (v3b) ────────────────────────────────────
def oro_para(p: "Partida", i: int, carta: Instancia) -> int:
    """Oro disponible para pagar esta carta (incluye oros restringidos)."""
    jug = p.j(i)
    extra = sum(r[0] for r in jug.oros_restringidos if paga_restringido(carta, r))
    return jug.oro_disponible + extra


def paga_restringido(carta: Instancia, r: list) -> bool:
    tipos, raza = r[1], r[2]
    minimo = r[3] if len(r) > 3 else 0  # Dragones: "Aliados Dragón de coste 4 o más"
    if minimo and (carta.tipo == Tipo.ORO or carta.carta.coste < minimo):
        return False
    return (not tipos or carta.tipo.value in tipos) and _raza_ok(carta, raza)


def tiene_estado(p: "Partida", inst: Instancia, modo: str) -> bool:
    # Draco Cometa: "no puede atacar ni bloquear mientras esté en juego" termina si sale.
    inst.estados = [
        e for e in inst.estados
        if e.get("duracion") != "mientras_en_juego" or _instancia_por_uid(p, e.get("fuente")) is not None
    ]
    if any(e.get("modo") == modo and e.get("desde", 0) <= p.e.turno for e in inst.estados):
        return True
    for s, h in _continuas(p, "restringirCombate"):
        if h.get("modo") != modo or inmune(p, inst, s):
            continue
        obj = h.get("objetivo") or {}
        if obj.get("quien") == "esta_carta":
            if _esta_carta(p, s) is inst:
                return True
        elif inst.controlador in _lados(s.controlador, obj.get("quien", "oponente")) and coincide(p, inst, obj):
            return True
    return False


def prohibido(p: "Partida", modo: str, jugador: int, carta: Instancia | None = None) -> bool:
    """¿Una Restricción en juego impide esta acción a `jugador`?"""
    if modo == "jugar_tipo" and carta is not None:
        for s in p.e.instancias_en_juego():
            if s.carta_vetada and s.controlador != jugador and carta.nombre == s.carta_vetada:
                return True
        if carta.tipo == Tipo.ALIADO and getattr(p.j(jugador), "veto_aliados_turno", None) == p.e.turno:
            return True  # Meleagro: este turno no puede poner Aliados en juego
    return quien_prohibe(p, modo, jugador, carta) is not None


def quien_prohibe(p: "Partida", modo: str, jugador: int, carta: Instancia | None = None) -> Instancia | None:
    """La carta en juego cuya Restricción impide esta acción a `jugador`."""
    for s in p.e.instancias_en_juego():
        for h in s.habilidades:
            if h.get("accion") != "restriccion" or h.get("modo") != modo:
                continue
            anterior = getattr(p, "ctx_fuente_habilidad", None)
            p.ctx_fuente_habilidad = s  # Serpiente Roja: "mientras esté en tu Línea de Defensa"
            try:
                ok = _en_zona_activacion(s, h) and condicion_ok(p, s.controlador, h)
            finally:
                p.ctx_fuente_habilidad = anterior
            if not ok:
                continue
            obj = h.get("objetivo") or {}
            if jugador not in _lados(s.controlador, obj.get("quien", "ambos")):
                continue
            if carta is not None and (modo == "jugar_tipo" or obj.get("tipos")) and not coincide(p, carta, obj):
                continue  # Carmix: "los Oros en juego no pueden ser desterrados"
            if obj.get("cementerioPropio"):
                continue  # Cerbero: se filtra por dueño en _protegidas_cerbero
            return s
    return None


def _motivo_sin_objetivos(p: "Partida", i: int, h: dict) -> str:
    """Desafío SkkvVn (18-11): el Milano Negro hizo daño y no desterró nada,
    sin decir por qué (había un Cinturón de Lady Ann en la Reserva). Si el
    efecto se queda sin objetivos por una Restricción en juego, se dice cuál."""
    accion = h.get("accion")
    zonas = zonas_de(h.get("objetivo") or {})
    modos = {
        "desterrar": ["desterrar_cementerio"] if "cementerio" in zonas else [],
        "barajar": ["barajar"] + (["barajar_cementerio"] if "cementerio" in zonas else []),
        "destruir": ["destruir"],
    }.get(accion, [])
    verbo = {"desterrar": "desterrar del Cementerio", "barajar": "barajar", "destruir": "destruir"}.get(accion, "")
    for modo in modos:
        s = quien_prohibe(p, modo, i)
        if s is not None:
            return f"no se puede {verbo}: lo impide {s.nombre} (J{s.controlador})"
    return ""


def no_puede_salir(p: "Partida", x: Instancia) -> bool:
    """Serpiente Roja: los Aliados de cada jugador no pueden salir del juego."""
    return x.en_juego and x.tipo == Tipo.ALIADO and prohibido(p, "salir_del_juego", x.controlador, x)


def _protegidas_cerbero(p: "Partida", i: int, cartas: list[Instancia]) -> list[Instancia]:
    """Cerbero: "las cartas de tu Cementerio no pueden ser desterradas por
    habilidades ni efectos oponentes"; quita esas cartas de los candidatos."""
    protegidos = {
        s.controlador for s in p.e.instancias_en_juego() if s.controlador != i
        for h in s.habilidades
        if h.get("accion") == "restriccion" and h.get("modo") == "desterrar_cementerio"
        and (h.get("objetivo") or {}).get("cementerioPropio")
    }
    return [x for x in cartas if not (x.zona == Zona.CEMENTERIO and x.dueno in protegidos)]


def inmune(p: "Partida", t: Instancia, fuente: Instancia) -> bool:
    """¿t es inmune a las habilidades de `fuente`?"""
    if t is fuente:
        return False
    for s in p.e.instancias_en_juego(t.controlador):
        for h in s.habilidades:
            protege = h.get("protege")
            if h.get("accion") != "inmunidad" or not protege or not t.en_juego or t.tipo != Tipo.ALIADO:
                continue
            if h.get("protegePortador") and (s.tipo != Tipo.ARMA or s.portador != t.uid):
                continue
            anterior = getattr(p, "ctx_fuente_habilidad", None)
            p.ctx_fuente_habilidad = s
            try:
                cumple_condicion = condicion_ok(p, s.controlador, h)
            finally:
                p.ctx_fuente_habilidad = anterior
            if not cumple_condicion:
                continue
            if protege.get("excluirEstaCarta") and t is s:
                continue
            if not coincide(p, t, {**protege, "quien": None}):
                continue
            tipos = (h.get("objetivo") or {}).get("tipos") or []
            if (not tipos or fuente.tipo.value in tipos) and fuente.controlador != t.controlador:
                return True  # Daana / Helios: no los afectan Talismanes oponentes
    for h in t.habilidades:
        if h.get("accion") != "inmunidad" or h.get("protege"):
            continue
        obj = h.get("objetivo") or {}
        tipos = obj.get("tipos") or []
        if tipos and fuente.tipo.value not in tipos:
            continue
        if fuente.controlador in _lados(t.controlador, obj.get("quien", "oponente")):
            return True
    return False


def atacante_libre_fuerza_1(p: "Partida", defensor: int) -> bool:
    """Macda Tho: en tu Línea de Defensa, el Aliado que ataca y no es bloqueado tiene 1 de fuerza."""
    return any(h.get("accion") == "restriccion" and h.get("modo") == "atacante_libre_fuerza_1"
               for x in p.j(defensor).defensa for h in x.habilidades)


def dano_destierra(p: "Partida", atk: Instancia) -> bool:
    """Seth: su daño de combate se destierra en vez de ir al Cementerio.
    También por su Arma (Espada Encantada) o por un efecto (Forma de Lobo)."""
    if any(e.get("modo") == "prop:dano_destierra" for e in atk.estados):
        return True
    armas = [a for a in p.e.portadas if a.portador == atk.uid]
    return any(h.get("accion") == "restriccion" and h.get("modo") == "dano_destierra"
               for x in [atk] + armas for h in x.habilidades)


def bloqueo_prohibido(p: "Partida", atk: Instancia, blk: Instancia) -> bool:
    """Melisende: no puede ser bloqueada por Aliados de fuerza N o más."""
    for h in atk.habilidades:
        if h.get("accion") == "restringirCombate" and h.get("modo") == "no_bloqueable_por_fuerza" \
                and fuerza(p, blk) >= int(h.get("valor", 0) or 0):
            return True
    return False


def ataque_total(atk: Instancia) -> bool:
    """Tutatis: si es declarado atacante, atacan todos los que puedan."""
    return any(h.get("accion") == "restriccion" and h.get("modo") == "ataque_total" for h in atk.habilidades)


def dispara_al_pagar(oro: Instancia) -> bool:
    return any(h.get("cuando") == "al_pagar_aliado" for h in oro.habilidades)


def disparar_pago(p: "Partida", i: int, pagados: list[Instancia]) -> None:
    """Broche de Tara: cuando lo usas para pagar un Aliado, el oponente bota 1
    (uno por turno entre todas sus copias)."""
    for oro in pagados:
        for k, h in enumerate(oro.habilidades):
            if h.get("cuando") != "al_pagar_aliado":
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, i, oro, h, k) >= limite:
                continue
            sumar_uso(p, i, oro, h, k)
            _intentar(p, i, oro, h)


def zona_activacion(h: dict) -> str:
    """Desde dónde se activa. Qer-Her: "Jugar desde otra zona" de esta carta,
    activada, con la zona en el objetivo (Cementerio) y sin zona de
    activación: se activa desde esa zona."""
    if h.get("zonaActivacion"):
        return h["zonaActivacion"]
    obj = h.get("objetivo") or {}
    if h.get("accion") == "jugarDesde" and h.get("cuando") == "activada" and obj.get("quien") == "esta_carta":
        for z in zonas_de(obj, "cementerio"):
            if z in ("cementerio", "mano"):
                return z
    return "en_juego"


def _en_zona_activacion(inst: Instancia, h: dict) -> bool:
    zona = zona_activacion(h)
    return {
        "en_juego": inst.en_juego and inst.zona != Zona.PAGADO,
        "reserva_oro": inst.zona == Zona.RESERVA,
        "reserva_o_pagado": inst.zona in (Zona.RESERVA, Zona.PAGADO),
        "cementerio": inst.zona == Zona.CEMENTERIO,
        "mano": inst.zona == Zona.MANO,
    }.get(zona, inst.en_juego)


def fuentes_activables(p: "Partida", i: int) -> list[Instancia]:
    """Cartas propias que pueden tener habilidades activadas: en juego, más
    las del Cementerio o la mano que se usan desde ahí."""
    jug = p.j(i)
    fuera = [
        x
        for x in jug.cementerio + jug.mano
        if any(zona_activacion(h) in ("cementerio", "mano") for h in x.habilidades)
    ]
    pagados = [
        x for x in jug.pagado if any(h.get("zonaActivacion") == "reserva_o_pagado" for h in x.habilidades)
    ]
    return p.e.instancias_en_juego(i) + pagados + fuera


def jugadas_desde_otra_zona(p: "Partida", i: int, fase: str = "vigilia") -> list:
    """Jugar desde otra zona como opción permanente (Exhumar: la carta se
    juega desde el Cementerio como si estuviera en la mano; Jinetes de Fuego:
    Talismán que al hacerlo queda desterrado)."""
    from .motor import Jugada

    out = []
    jug = p.j(i)
    activo = p.e.activo == i
    for x in jug.cementerio:
        for h in x.habilidades:
            if h.get("accion") != "jugarDesde" or h.get("cuando") not in ("continua", "al_jugar", None):
                continue
            if not condicion_ok(p, i, h):
                continue
            obj = h.get("objetivo") or {}
            if obj.get("quien") != "esta_carta":
                continue
            # El editor guarda un Talismán así como "Al jugarse": vale igual,
            # siempre que la zona indicada sea el Cementerio.
            if "cementerio" not in zonas_de(obj, "cementerio"):
                continue
            gratis = (h.get("modo") or "sin_pagar") == "sin_pagar"
            if not p.puede_pagar(i, x, gratis=gratis) or prohibido(p, "jugar_tipo", i, x):
                break  # rqHs #3: con Marco Antonio en juego no se juegan Talismanes (tampoco del Cementerio)
            tipo = "jugar_gratis" if gratis else "jugar"
            destino = h.get("zonaDestino") if h.get("zonaDestino") in ("destierro", "cementerio") else None
            if h.get("talismanVaA") == "destierro":
                destino = "destierro"  # Jinetes de Fuego jugado desde el Cementerio
                if prohibido(p, "desterrar_cementerio", i):
                    break  # Cinturón de Lady Ann en la Reserva: no se puede desterrar, no se juega
            if x.tipo in (Tipo.ALIADO, Tipo.TOTEM) and fase == "vigilia" and activo:
                out.append(Jugada(tipo, x))
            elif x.tipo == Tipo.ARMA and fase == "vigilia" and activo:
                for portador in p.j(0).aliados + p.j(1).aliados:
                    if portador_valido(p, x, portador, i):
                        out.append(Jugada(tipo, x, portador=portador))
            elif x.tipo == Tipo.TALISMAN and talisman_jugable(p, i, x, fase):
                out.append(Jugada(tipo, x, destino=destino))
            break
    return out


def errante(p: "Partida", inst: Instancia) -> None:
    """Errante: solo una copia en juego; la anterior va al Cementerio (4.13)."""
    if not tiene_prop(p, inst, "errante") or not inst.en_juego:
        return
    for otra in p.e.instancias_en_juego(inst.controlador):
        if otra is not inst and otra.nombre == inst.nombre:
            p.anotar(f"{otra.nombre}: Errante, la copia anterior sale del juego")
            p.sale_del_juego(otra, Zona.CEMENTERIO)


def revisar_controles(p: "Partida") -> None:
    """Devuelve las cartas cuyo control prestado terminó."""
    for inst in p.e.instancias_en_juego():
        c = inst.control
        if not c:
            continue
        # Perder la habilidad no devuelve lo ya robado (#102); la duración de
        # la carta manda ("permanente" no vuelve nunca).
        termina = (
            (c["duracion"] == "hasta_fase_final" and p.e.fase == "final")
            or (c["duracion"] == "mientras_en_juego" and _instancia_por_uid(p, c["fuente"]) is None)
        )
        if termina:
            _cambiar_control(p, inst, c["original"])
            inst.control = None
            if c.get("volverA") == "linea_ataque" and inst.tipo == Tipo.ALIADO:
                p._mover(inst, Zona.ATAQUE)


def _cambiar_control(p: "Partida", inst: Instancia, nuevo: int) -> None:
    zona = inst.zona if inst.zona != Zona.ATAQUE else Zona.DEFENSA
    p._sacar(inst)
    inst.controlador = nuevo
    inst.zona = zona
    p.j(nuevo).lista(zona).append(inst)
    inst.listo = False
    p.anotar(f"{inst.nombre} pasa a control de J{nuevo}")


def ventana_reducir_dano(p: "Partida", defensor: int, dano: int) -> int:
    """Antes de botar por combate, el defensor puede reducir el daño."""
    for s in fuentes_activables(p, defensor):
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "reducirDano" or (h.get("modo") or "dano_a_cero") == "aliado_sin_dano":
                continue
            if not _en_zona_activacion(s, h) or not condicion_ok(p, defensor, h):
                continue
            limite = int(h.get("limitePorTurno", 0)) or 1
            if s.usos_turno.get(k, 0) >= limite or not puede_pagar_costo(p, defensor, s, h):
                continue
            if not p.decide(defensor).usar_opcional(p, defensor, s, {**h, "_dano": dano}):
                continue
            pagar_costo(p, defensor, s, h)
            s.usos_turno[k] = s.usos_turno.get(k, 0) + 1
            nuevo = 0 if (h.get("modo") or "dano_a_cero") == "dano_a_cero" else max(0, dano - int(h.get("valor", 0)))
            p.anotar(f"J{defensor} reduce el daño con {s.nombre}: {dano} → {nuevo}")
            dano = nuevo
            if dano == 0:
                return 0
    return dano


def _destino_zona(destino: str) -> Zona | None:
    return {
        "mano": Zona.MANO,
        "cementerio": Zona.CEMENTERIO,
        "destierro": Zona.DESTIERRO,
        "linea_ataque": Zona.ATAQUE,
        "linea_defensa": Zona.DEFENSA,
        # Brian Boru y Asaltar la Caravana guardan "ataque" (sin "linea_"):
        # el destino no se reconocía y no movían nada.
        "ataque": Zona.ATAQUE,
        "defensa": Zona.DEFENSA,
        "reserva_oro": Zona.RESERVA,
        "mazo_tope": Zona.MAZO,
        "mazo_fondo": Zona.MAZO,
    }.get(destino)


def _mover_a(p: "Partida", t: Instancia, destino: str) -> bool:
    zona = _destino_zona(destino)
    if destino == "en_juego":
        poner_en_juego(p, t.controlador, t)
        return True
    if zona is None:
        return False
    if zona in (Zona.ATAQUE, Zona.DEFENSA):
        if t.tipo != Tipo.ALIADO or not t.en_juego:
            return False
        antes = t.zona
        p._mover(t, zona)
        if antes == Zona.DEFENSA and zona == Zona.ATAQUE:
            movido_a_ataque(p, t, getattr(p, "ctx_lanzador", None))
        return True
    if t.en_juego and zona == Zona.MAZO:
        # Focea y efectos equivalentes mandan al Aliado con sus Armas al
        # mazo. Se mueven primero las Armas y después el Aliado: éste queda
        # efectivamente en el tope, no una de sus Armas.
        if t.tipo == Tipo.ALIADO:
            for arma in [a for a in p.e.portadas if a.portador == t.uid]:
                p._mover(arma, zona, al_tope=destino == "mazo_tope")
        p._mover(t, zona, al_tope=destino == "mazo_tope")
        disparar(p, t, "al_salir_del_juego", forzar=True)
        return True
    if t.en_juego and zona != Zona.RESERVA:
        p.sale_del_juego(t, zona)
        return True
    p._mover(t, zona, al_tope=destino != "mazo_fondo")
    return True


def movido_a_ataque(p: "Partida", t: Instancia, quien: int | None) -> None:
    """San Patricio: "cuando sea movido de tu Línea de Defensa a tu Línea de
    Ataque por un efecto o habilidad de una carta que controles…"."""
    if quien is None or quien != t.controlador or not t.en_juego:
        return
    disparar(p, t, "al_moverse_a_ataque")


def _cancelar(p: "Partida", i: int, fuente: Instancia, h: dict) -> tuple[bool, list[Instancia]]:
    modo = (h.get("modo") or "todo_el_ataque")
    if modo == "ataque_o_bloqueo":
        modo = "un_atacante" if p.e.activo != i else "un_bloqueo"
    if not p.atacantes:
        return False, []
    if modo == "todo_el_ataque":
        p.ataque_cancelado = True
        return True, []
    if modo == "un_atacante":
        vivos = [x for x in p.atacantes if x.zona == Zona.ATAQUE]
        if not vivos:
            return False, []
        t = p.decide(i).elegir_objetivos(p, i, vivos, 1, {"accion": "destruir"})[0]
        p._mover(t, Zona.DEFENSA)
        p.anotar(f"{fuente.nombre}: cancela el ataque de {t.nombre}")
        return True, [t]
    # un_bloqueo: el atacante queda sin bloquear.
    if not p.bloqueos:
        return False, []
    uids = list(p.bloqueos)
    elegido = p.decide(i).elegir_objetivos(p, i, [p.bloqueos[u] for u in uids], 1, {"accion": "destruir"})[0]
    for u in uids:
        if p.bloqueos[u] is elegido:
            del p.bloqueos[u]
    p.anotar(f"{fuente.nombre}: cancela el bloqueo de {elegido.nombre}")
    return True, [elegido]


# False solo para reproducir partidas grabadas antes de 2026-11-14 (Rhiannon
# probaba siempre su primer modo).
MODOS_MIRAR_TOPE = True


def _mirar_tope(p: "Partida", i: int, fuente: Instancia, h: dict, n: int) -> tuple[bool, list[Instancia]]:
    """Mira las N de arriba del Mazo y las reparte (Tadg, La Odisea, Nacimiento
    de Pegaso, Idmon el Adivino).

    - repartir = [zonas]: una carta a cada zona, en orden (La Odisea).
    - si no: toma hasta `valor` cartas que cumplan el objetivo y las manda a
      `zonaDestino` (mano, o en_juego = jugarla sin pagar); el resto va a
      `restoA` (mazo_fondo, mazo_tope, cementerio, elegir_tope_fondo)."""
    from .motor import Jugada

    obj = h.get("objetivo") or {}
    lado = 1 - i if obj.get("quien") == "oponente" else i
    jug = p.j(lado)
    vistas = list(jug.mazo[:n])
    if not vistas:
        return False, []
    nombrado = None
    if obj.get("nombrarTipo"):
        # Afrodita (reporte HIM0): primero se nombra un tipo, después se mira.
        tipos = list(obj["nombrarTipo"])
        elegir_tipo = getattr(p.decide(i), "nombrar_tipo", None)
        nombrado = elegir_tipo(p, i, fuente, tipos) if elegir_tipo else tipos[0]
        nombrado = nombrado if nombrado in tipos else tipos[0]
        p.anotar(f"{fuente.nombre} nombra el tipo {nombrado}")
        obj = {**obj, "tipos": [nombrado]}
        h = {**h, "objetivo": obj}
    # Afrodita/Idmon la muestran al jugarla; Estrella de Belén "muestra" (ZTSY).
    # Anfiarao ("puedes mirar… y jugar un Aliado de ahí"): con ``privado`` las
    # que no juega no se muestran al rival.
    publica = (h.get("zonaDestino") == "en_juego" and not h.get("privado")) or bool(h.get("muestra")) \
        or _dice_mostrar(fuente)
    nombres_vistas = ", ".join(x.nombre for x in vistas)
    p.anotar(f"{fuente.nombre}: mira {'la primera carta' if len(vistas) == 1 else f'las {len(vistas)} primeras'} "
             f"del Mazo de J{lado}: {nombres_vistas if publica else privado(i, nombres_vistas)}")
    decide = p.decide(i)
    destinos = {"mano": Zona.MANO, "cementerio": Zona.CEMENTERIO, "destierro": Zona.DESTIERRO}
    repartir = [z for z in (h.get("repartir") or []) if z in destinos]
    if repartir:
        quedan = list(vistas)
        for z in repartir:
            if not quedan:
                break
            t = decide.elegir_objetivos(p, i, quedan, 1, {"accion": "repartir", "zonaDestino": z})[0]
            quedan.remove(t)
            p._mover(t, destinos[z])
            p.anotar(f"{fuente.nombre}: {t.nombre} → {z}")
        return True, [t for t in vistas if t not in quedan]

    previas = getattr(p, "ctx_previas", None) or []
    if obj.get("razaDeAfectada") and previas:
        obj = {**obj, "raza": previas[0].raza or "\u0000"}

    def cumple(x, obj=obj):
        if obj.get("filtroSoloAliados") and x.tipo != Tipo.ALIADO:
            return coincide(p, x, {**obj, "raza": "", "arquetipo": ""})
        return coincide(p, x, obj)

    # Rhiannon: "toma un Oro/Talismán/Arma/Tótem, o hasta 3 Aliados Desafiante".
    # Los modos van como habilidades hermanas (grupoElegir): se mira el tope
    # una sola vez y quien juega elige el modo viendo las cartas. Antes se
    # probaba siempre el primer modo y solo se mostraban sus elegibles.
    hermanas = [x for x in fuente.habilidades if MODOS_MIRAR_TOPE and h.get("grupoElegir")
                and x.get("grupoElegir") == h.get("grupoElegir")
                and x.get("accion") == "mirarTope" and x.get("cuando") == h.get("cuando")]
    if len(hermanas) > 1:
        modos = [(x, [c for c in vistas if cumple(c, x.get("objetivo") or {})], int(x.get("valor") or 0))
                 for x in hermanas]
        elegir = getattr(decide, "elegir_mirar_tope", None)
        if elegir is not None:
            k, elegidas = elegir(p, i, fuente, vistas, [(e, v) for _, e, v in modos])
        else:
            k = next((k for k, (_, e, v) in enumerate(modos) if e and v), 0)
            e, v = modos[k][1], modos[k][2]
            elegidas = decide.elegir_objetivos(p, i, e, min(v, len(e)), {**modos[k][0], "accion": "mirarTope"}) \
                if e and v else []
        h = modos[k][0]
        validas = set(map(id, modos[k][1]))
        elegidas = [x for x in elegidas if id(x) in validas][:modos[k][2]]
    else:
        elegibles = [x for x in vistas if cumple(x)]
        tomar = int(h.get("valor") or 0)
        if publica:
            # Desafío 5VXY T4: "muestra las 3 primeras": el rival las ve, y
            # quien la juega también aunque no haya qué tomar.
            mostrar_a(p, 1 - i, f"{fuente.nombre} muestra", vistas)
            if not (elegibles and tomar):
                mostrar_a(p, i, f"{fuente.nombre} muestra", vistas)
        elegidas = decide.elegir_objetivos(p, i, elegibles, min(tomar, len(elegibles)), {**h, "accion": "mirarTope"}) \
            if elegibles and tomar else []
    destino = h.get("zonaDestino") or "mano"
    if not elegidas and destino == "en_juego":
        # Reporte HIM0: que se note cuando Afrodita o Idmon fallan.
        pedido = nombrado or "/".join(obj.get("tipos") or []) or "válida"
        if obj.get("raza"):
            pedido += f" {obj['raza']}"
        salen = ", ".join(x.nombre for x in vistas)
        p.anotar(f"✗ {fuente.nombre} falla: sale {salen if publica else privado(i, salen)}, no es {pedido}")
    for t in elegidas:
        if destino == "en_juego":
            p.ejecutar_jugada(i, Jugada("jugar_gratis", t))  # Idmon: jugarlo sin pagar
        else:
            p._mover(t, destinos.get(destino, Zona.MANO))
        # Reporte 4NtK: lo que toma el rival con Renpet solo lo sabe él.
        p.anotar(f"{fuente.nombre}: toma {t.nombre if destino == 'en_juego' or publica else privado(i, t.nombre)}")
    resto = [x for x in vistas if x not in elegidas and x.zona == Zona.MAZO]
    resto_a = h.get("restoA") or "mazo_tope"
    if resto_a == "elegir_tope_fondo":
        elegir = getattr(decide, "tope_o_fondo", None)
        resto_a = elegir(p, i, resto) if elegir else "mazo_tope"
    if resto_a == "barajar":  # Estrella de Belén: las demás se barajan en el Mazo
        p.e.rng.shuffle(jug.mazo)
    elif resto_a == "mazo_fondo":
        for x in resto:
            jug.mazo.remove(x)
            jug.mazo.append(x)
    elif resto_a == "cementerio":
        for x in resto:
            p._mover(x, Zona.CEMENTERIO)
    if resto and resto_a != "mazo_tope":
        destino_resto = {"mazo_fondo": "al fondo del mazo", "barajar": "se baraja en el mazo"}.get(resto_a, "al Cementerio")
        if resto_a == "cementerio" or publica:
            # Lo que va al Cementerio es público aunque se haya mirado en
            # privado; lo que vuelve al Mazo solo si se mostró.
            destino_resto += ": " + ", ".join(x.nombre for x in resto)
        p.anotar(f"{fuente.nombre}: el resto {destino_resto}")
    # Con modos, ya se miró y se resolvió: las hermanas no vuelven a mirar.
    return bool(elegidas) or len(hermanas) > 1, elegidas


def _jugar_desde(p: "Partida", i: int, fuente: Instancia, h: dict) -> tuple[bool, list[Instancia]]:
    """Invocador: juega una carta desde la zona indicada (sin pagar o pagando)."""
    from .motor import Jugada

    cands = _candidatos_jugar(p, i, fuente, h)
    if not cands:
        return False, []
    gratis = (h.get("modo") or "sin_pagar") == "sin_pagar"
    tipo = "jugar_gratis" if gratis else "jugar"
    elegidas = _seleccionar(p, i, fuente, h, cands)
    jugadas = []
    for t in elegidas:
        if t.tipo == Tipo.ARMA:
            portadores = [a for a in p.j(0).aliados + p.j(1).aliados if portador_valido(p, t, a, i)]
            if not portadores:
                continue
            decide = p.decide(i)
            if hasattr(decide, "elegir_portador"):
                portador = decide.elegir_portador(p, i, t, portadores)
            else:
                portador = decide.elegir_objetivos(p, i, portadores, 1, {"accion": "modificarFuerza", "valor": 1})[0]
            p.ejecutar_jugada(i, Jugada(tipo, t, portador=portador, descuento=int(h.get("descuentoCoste") or 0)))
        else:
            p.ejecutar_jugada(i, Jugada(tipo, t, descuento=int(h.get("descuentoCoste") or 0)))
        jugadas.append(t)
    if "mazo" in zonas_de(h.get("objetivo") or {}, "mano"):
        p.e.rng.shuffle(p.j(i).mazo)
    return bool(jugadas), jugadas


def _candidatos_jugar(p: "Partida", i: int, fuente: Instancia, h: dict) -> list[Instancia]:
    obj = h.get("objetivo") or {}
    gratis = (h.get("modo") or "sin_pagar") == "sin_pagar"
    out = []
    if obj.get("quien") == "esta_carta":
        propios = [fuente] if fuente.zona in (Zona.CEMENTERIO, Zona.MANO, Zona.MAZO, Zona.DESTIERRO) else []
    else:
        propios = []
        for zona in [z for z in zonas_de(obj, "mano") if z in _ZONAS_FUERA] or ["mano"]:
            # Nacer de la Muerte juega un Aliado del Mazo Castillo oponente.
            quien = obj.get("quien") if obj.get("quien") in ("propio", "oponente", "ambos") else "propio"
            propios += candidatos_validos(p, i, fuente, {**h, "objetivo": {**obj, "quien": quien}}, zona=zona)
    for x in propios:
        if x is fuente and obj.get("quien") != "esta_carta":
            continue  # Bennu no se juega a sí misma desde el Cementerio
        descuento = int(h.get("descuentoCoste") or 0)
        if x.tipo == Tipo.ORO or (not gratis and oro_para(p, i, x) < max(0, p.coste_de(i, x) - descuento)):
            continue
        if prohibido(p, "jugar_tipo", i, x):
            continue
        if x.tipo == Tipo.ARMA and not any(portador_valido(p, x, a, i) for a in p.j(0).aliados + p.j(1).aliados):
            continue
        # Un Talismán jugado desde otra zona respeta su momento (no se puede
        # jugar un Talismán de respuesta en la Vigilia propia).
        if x.tipo == Tipo.TALISMAN and not talisman_jugable(p, i, x, p.e.fase):
            continue
        if not requisito_para_jugar(p, i, x):
            continue
        out.append(x)
    return out


# ── Notas de cartas (2026-11-08) ─────────────────────────────────────────────
def oros_en_juego(p: "Partida", i: int) -> int:
    """Oros que controla un jugador: Reserva + pagados."""
    return len(p.j(i).reserva) + len(p.j(i).pagado)


def cantidad(p: "Partida", i: int, h: dict, previas: list[Instancia], *, lado: int | None = None) -> int:
    """"¿Cuántas?": número fijo o "tantas como…" (Mercado Egipcio, Flechas de
    Lava, Relámpago Arcano)."""
    segun = h.get("cantidadSegun", "fijo")
    if segun == "fuerza_costo":
        return int(getattr(p, "ctx_costo_fuerza", 0))
    if segun == "cartas_cementerio_nombre":
        fuente = getattr(p, "ctx_fuente_habilidad", None)
        nombre = str(h.get("contarNombre") or (fuente.nombre if fuente is not None else ""))
        return sum(1 for x in p.j(i).cementerio if x.nombre.casefold() == nombre.casefold())
    if segun == "oros_que_controla":
        return oros_en_juego(p, lado if lado is not None else 1 - i)
    if segun == "fuerza_mayor_aliado_oponente":
        aliados = p.j(1 - i).aliados
        return max((fuerza(p, a) for a in aliados), default=0)
    if segun == "coste_afectada":
        return max((x.carta.coste for x in previas if x.tipo != Tipo.ORO), default=0)
    if segun == "num_afectadas":
        return len(previas)
    if segun == "dano_hecho":
        return int(getattr(p, "ctx_dano", 0))
    if segun == "cartas_botadas":
        return int(getattr(p, "ultimo_botado", 0))
    if segun == "fuerza_afectada":
        return max((fuerza(p, x) if x.en_juego else x.carta.fuerza for x in previas), default=0)
    if segun == "num_atacantes":  # Coliseo: una por cada Aliado atacante
        return len(getattr(p, "atacantes", []) or [])
    if segun == "aliados_propios":  # Avalon: tantas como Aliados tengas en juego
        return len(p.j(i).aliados)
    if segun == "atacantes_este_turno":
        return len(p.ataco_este_turno_inst(i))
    if segun == "totems_propios":  # Busto Imperial: uno por cada Tótem que controlas.
        return sum(1 for x in p.e.instancias_en_juego(i) if x.tipo == Tipo.TOTEM)
    if segun == "totems_en_juego":
        return sum(1 for x in p.e.instancias_en_juego() if x.tipo == Tipo.TOTEM)
    if segun == "aliados_arquetipo":  # Novias de Drácula: por cada Aliado Drácula que controles
        return sum(1 for a in p.j(i).aliados if _arquetipo_ok(a, h.get("porCadaArquetipo", "")))
    if segun == "coste_disparadora":  # País Sin Luz: tantas como el coste del Aliado que sale
        x = getattr(p, "ctx_disparadora", None)
        return x.carta.coste if x is not None and x.tipo != Tipo.ORO else 0
    return int(h.get("cantidad", 1))


def disparar_con_armas(
    p: "Partida", aliado: Instancia, cuando: str, *, forzar: bool = False, declaracion: bool | None = None
) -> None:
    """Dispara al Aliado y a las Armas que porta (Mandoble de Seth: "cuando su
    portador es declarado atacante")."""
    armas = [a for a in p.e.portadas if a.portador == aliado.uid]
    disparar(p, aliado, cuando, forzar=forzar, declaracion=declaracion)
    for arma in armas:
        disparar(p, arma, cuando, forzar=forzar, declaracion=declaracion)


def ventana_redireccion(
    p: "Partida", i: int, fuente: Instancia, h: dict, objetivos: list[Instancia]
) -> list[Instancia]:
    """Relámpago Arcano: si un efecto de `i` elige cartas del rival, éste puede
    redirigirlo a otra carta que cumpla la MISMA definición del efecto (de
    quién, tipo, filtros), salvo Oros. Luego se resuelven sus "luego" sobre la
    nueva carta afectada."""
    q = 1 - i
    nuevos = list(objetivos)
    for k, t in enumerate(objetivos):
        if t.controlador != q or not t.en_juego:
            continue
        talismanes = [
            (x, hr)
            for x in p.j(q).mano
            if x.tipo == Tipo.TALISMAN and p.puede_pagar(q, x)
            for hr in x.habilidades
            if hr.get("accion") == "redirigir"
        ]
        if not talismanes:
            continue
        validos = [
            c
            for c in candidatos_validos(p, i, fuente, h)
            if c is not t and c.tipo != Tipo.ORO and c not in nuevos
        ]
        if not validos:
            continue
        elegido = p.decide(q).redirigir(p, q, t, validos)
        if elegido is None:
            continue
        talisman, hr = talismanes[0]
        p._pagar_oro(q, p.coste_de(q, talisman), carta=talisman)
        p.jugadas[q].add(talisman.nombre)
        p._mover(talisman, zona_final_talisman(talisman))
        nuevo = validos[elegido]
        nuevos[k] = nuevo
        p.anotar(f"J{q} redirige {fuente.nombre}: {t.nombre} → {nuevo.nombre} con {talisman.nombre}")
        aplicar_luego(p, q, talisman, hr, True, [nuevo])
    return nuevos


# ── Notas de cartas, 2ª tanda (2026-11-08) ───────────────────────────────────
def zona_final_talisman(t: Instancia) -> Zona:
    """A dónde va un Talismán después de resolverse (Gran Guardián: Destierro).
    El "va al Destierro" de un permiso para jugarla desde el Cementerio
    (Jinetes de Fuego) solo vale si se jugó desde ahí: desde la mano va al
    Cementerio y se puede volver a jugar."""
    if any(h.get("talismanVaA") == "destierro" and not es_permiso_jugar(h) for h in t.carta.habilidades):
        return Zona.DESTIERRO
    return Zona.CEMENTERIO


OTRA_RAZA = "Otra (ninguna en la partida)"


def nombrar_raza(p: "Partida", inst: Instancia) -> None:
    """Cleopatra VII: al entrar en juego, su controlador nombra una raza."""
    if inst.nombrado is not None:
        return
    for h in inst.habilidades:
        obj = h.get("objetivo") or {}
        if not obj.get("nombrarRaza"):
            continue
        excluidas = {r.lower() for r in obj.get("excluirRazas") or []}
        razas = sorted({
            x.carta.raza
            for j in p.e.jugadores
            for x in j.mazo + j.mano + j.defensa + j.ataque + j.cementerio
            if x.tipo == Tipo.ALIADO and x.carta.raza and x.carta.raza.lower() not in excluidas
        })
        if razas:
            # Se puede nombrar cualquier raza, también una que no está en la partida.
            inst.nombrado = p.decide(inst.controlador).elegir_raza(p, inst.controlador, razas + [OTRA_RAZA], h)
            if inst.nombrado == OTRA_RAZA:
                p.anotar(f"{inst.nombre} nombra una raza que no está en la partida")
            else:
                p.anotar(f"{inst.nombre} nombra la raza {inst.nombrado}")
        return


def refrescar_perdidas(p: "Partida") -> None:
    """Perder habilidad continua (Cleopatra VII): los Aliados afectados la
    pierden mientras la fuente esté en juego, también los que entren después."""
    if getattr(p, "_refrescando_perdidas", False):
        return
    p._refrescando_perdidas = True
    try:
        afectados = _perdidas_continuas(p)
    finally:
        p._refrescando_perdidas = False
    for t in p.e.instancias_en_juego():
        if t.uid in afectados:
            if t.sin_habilidad_hasta is None:
                t.sin_habilidad_hasta = "continua"
        elif t.sin_habilidad_hasta in ("continua", "mientras_en_juego"):
            # Elegido por Draco Cometa: sigue sin habilidad mientras él siga en juego.
            if t.sin_habilidad_hasta == "mientras_en_juego" and t.sin_habilidad_fuente is not None \
                    and _instancia_por_uid(p, t.sin_habilidad_fuente) is not None:
                continue
            # #107: murió Cleopatra: Djedefhor recupera su habilidad.
            t.sin_habilidad_hasta = None
            t.sin_habilidad_fuente = None


def _perdida_continua(h: dict) -> bool:
    """Continua (Takelot) o "al entrar, a todos, mientras esté en juego"
    (Cleopatra VII): afecta también a los que entren después."""
    if h.get("cuando") == "continua":
        return True
    obj = h.get("objetivo") or {}
    return h.get("cuando") == "al_jugar" and h.get("duracion") == "mientras_en_juego" and obj.get("seleccion") == "todos"


def _perdidas_continuas(p: "Partida") -> set[int]:
    en_juego = {x.uid for x in p.e.instancias_en_juego()}
    # Prevenciones ya decididas (fuente, carta) → ¿se previno? Se olvidan
    # cuando alguna de las dos sale del juego.
    decididas: dict = p.__dict__.setdefault("prevencion_continua", {})
    for par in [k for k in decididas if k[0] not in en_juego or k[1] not in en_juego]:
        del decididas[par]
    afectados: set[int] = set()
    for s in p.e.instancias_en_juego():
        for h in s.habilidades:
            if h.get("accion") != "perderHabilidad" or not _perdida_continua(h):
                continue
            if h.get("zonaActivacion") and not _en_zona_activacion(s, h):
                continue  # Águila Imperial: solo desde la Reserva
            if not condicion_ok(p, s.controlador, h):
                continue
            obj = _con_raza_nombrada(s, h.get("objetivo") or {})
            for t in p.e.instancias_en_juego():
                if t is s or inmune(p, t, s) or protegida(p, t):
                    continue
                if t.controlador not in _lados(s.controlador, obj.get("quien", "oponente")) or not coincide(p, t, obj):
                    continue
                # Ptolomeo II: puede prevenir que su carta sea afectada, también
                # por un efecto continuo (Takelot), cuando empieza a afectarla.
                par = (s.uid, t.uid)
                if par not in decididas:
                    decididas[par] = prevenir_afectar(p, t, s.controlador, h)
                if not decididas[par]:
                    afectados.add(t.uid)
    return afectados


def _reaccion_botar(p: "Partida", lado: int, botadas: int) -> None:
    """Tocador: cuando botas por una habilidad oponente, puedes responder."""
    if botadas <= 0 or p.e.terminada or getattr(p, "_reaccionando_botar", False):
        return
    p.ultimo_botado = botadas
    p._reaccionando_botar = True
    try:
        for s in list(p.e.instancias_en_juego(lado)):
            for h in s.habilidades:
                if h.get("cuando") == "al_botar_por_oponente":
                    _intentar(p, lado, s, h)
    finally:
        p._reaccionando_botar = False


# ── Notas de cartas, 3ª tanda (2026-11-08) ───────────────────────────────────
def por_cada(p: "Partida", fuente: Instancia, h: dict) -> int:
    """Multiplicador "por cada…" del valor (Djoser: por cada Arma que porta)."""
    segun = h.get("valorPorCada") or ""
    if not segun:
        return 1
    if segun == "arma_portada":
        portador = _esta_carta(p, fuente)
        return sum(1 for a in p.e.portadas if portador is not None and a.portador == portador.uid)
    if segun == "aliado_propio":
        return len(p.j(fuente.controlador).aliados)
    if segun == "oro_en_juego":
        return oros_en_juego(p, fuente.controlador)
    if segun == "aliado_arquetipo":  # Druida Maldito: −1 por cada Aliado Druida
        return sum(1 for a in p.j(fuente.controlador).aliados if _arquetipo_ok(a, h.get("porCadaArquetipo", "")))
    if segun == "aliado_raza":  # Belial: por cada otro Aliado Faerie en juego
        return sum(1 for j in p.e.jugadores for a in j.aliados
                   if a is not fuente and _raza_ok(a, h.get("porCadaRaza", "")))
    if segun == "otro_en_ataque":  # Guerreras Británicas: por cada otro Aliado en tu Línea de Ataque
        return sum(1 for a in p.j(fuente.controlador).ataque if a is not fuente)
    if segun == "carta_arquetipo":  # Goblin Maligno: por cada otra carta Goblin en juego
        return sum(1 for x in p.e.instancias_en_juego(fuente.controlador)
                   if x is not fuente and _arquetipo_ok(x, h.get("porCadaArquetipo", "")))
    if segun == "totem_en_juego":  # Gronw Pebyr: cada Tótem de ambos jugadores.
        return sum(1 for x in p.e.instancias_en_juego() if x.tipo == Tipo.TOTEM)
    if segun == "totem_propio_coste_min":
        minimo = int(h.get("porCadaCosteMin", 0))
        return sum(1 for x in p.e.instancias_en_juego(fuente.controlador)
                   if x.tipo == Tipo.TOTEM and x.carta.coste >= minimo)
    if segun == "carta_afectada":
        # Goblin Berserker: "por cada carta desterrada" por el efecto anterior.
        return len(getattr(p, "ctx_previas", None) or [])
    if segun == "destierro_propio":
        # Martillo de Galehaut: "por cada Arma y Aliado Sir en tu destierro".
        # ``porCadaFiltros``: cuenta la carta que cumpla alguno (sin filtros, todas).
        filtros = h.get("porCadaFiltros") or [{}]
        return sum(1 for x in p.j(fuente.controlador).destierro
                   if any(coincide(p, x, {**f, "quien": None}) for f in filtros))
    return 1


def recargo(p: "Partida", t: Instancia, fuente: Instancia) -> int:
    """Oros extra que paga quien juega `fuente` para afectar a `t` (Demoledor
    de Amon: Talismanes oponentes pagan 2 más). Solo mientras está en juego:
    en el Cementerio su habilidad no rige (Gran Guardián lo puede desterrar)."""
    if not t.en_juego:
        return 0
    total = 0
    for h in t.habilidades:
        if h.get("accion") != "encarecer" or h.get("protege"):
            continue
        obj = h.get("objetivo") or {}
        tipos = obj.get("tipos") or []
        if tipos and fuente.tipo.value not in tipos:
            continue
        if fuente.controlador in _lados(t.controlador, obj.get("quien", "oponente")):
            total += int(h.get("valor", 0))
    # Las Musas: "los Talismanes oponentes que hagan objetivo a tus Aliados
    # Musa cuestan 1 Oro adicional": el recargo lo da otra carta (``protege``
    # dice a cuáles de las tuyas cubre; puede incluirse a sí misma).
    for s in p.e.instancias_en_juego(t.controlador):
        for h in s.habilidades:
            protege = h.get("protege")
            if h.get("accion") != "encarecer" or not protege:
                continue
            if protege.get("excluirEstaCarta") and t is s:
                continue
            if not coincide(p, t, {**protege, "quien": None}):
                continue
            obj = h.get("objetivo") or {}
            tipos = obj.get("tipos") or []
            if tipos and fuente.tipo.value not in tipos:
                continue
            if fuente.controlador in _lados(s.controlador, obj.get("quien", "oponente")):
                total += int(h.get("valor", 0))
    return total


def _pagar_recargo(p: "Partida", i: int, t: Instancia, fuente: Instancia) -> bool:
    extra = recargo(p, t, fuente)
    if not extra:
        return True
    if p.j(i).oro_disponible < extra:
        return False
    p._pagar_oro(i, extra)
    p.anotar(f"J{i} paga {extra} oros extra para afectar a {t.nombre}")
    return True


def _aplicar_proximos(p: "Partida", entra: Instancia) -> None:
    """Defensores Celtas: el próximo Aliado Defensor que juegues este turno es
    Imbloqueable y puede atacar al entrar."""
    jug = p.j(entra.controlador)
    quedan = []
    usados_modo = set()
    for x in jug.proximos:
        if x["turno"] != p.e.turno:
            continue
        if x["modo"] in usados_modo or x["modo"] == "noAnulable" or entra.tipo != Tipo.ALIADO \
                or not coincide(p, entra, {**x["objetivo"], "quien": None}):
            quedan.append(x)
            continue
        usados_modo.add(x["modo"])
        if x["modo"] == "furia":
            entra.listo = True
        else:
            entra.estados.append({"modo": f"prop:{x['modo']}", "duracion": "permanente", "turno": p.e.turno,
                                  "fuente": entra.uid, "creador": entra.controlador})
        p.anotar(f"{entra.nombre}: {x['modo']} (próximo Aliado)")
    jug.proximos = quedan


def disparar_entrada(p: "Partida", entra: Instancia) -> None:
    """Djoser: "cuando un Arma entra en juego bajo tu control…"."""
    if not entra.en_juego:
        return
    i = entra.controlador
    if p.j(i).proximos:
        _aplicar_proximos(p, entra)
    # PYDO #3: la Corona del Día pagada para Thanatos sigue en juego y baraja.
    for s in list(p.e.instancias_en_juego(i)) + list(p.j(i).pagado):
        if s is entra:
            continue
        grupos: set[str] = set()
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "propia_entra":
                continue
            if h.get("grupoElegir"):
                if h["grupoElegir"] in grupos:
                    continue
                grupos.add(h["grupoElegir"])
                opciones = [x for x in s.habilidades if x.get("grupoElegir") == h["grupoElegir"]
                            and x.get("cuando") == "propia_entra"]
                quien = 1 - i if h.get("eligeOponente") else i
                elegir = getattr(p.decide(quien), "elegir_opcion", None)
                if elegir and len(opciones) > 1:
                    h = opciones[elegir(p, quien, s, opciones)]
            if s.zona == Zona.PAGADO and h.get("zonaActivacion") in ("reserva_oro", "reserva"):
                continue
            if not _dispara_por(entra, h):
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, i, s, h, k) >= limite:
                continue
            p.ctx_disparadora = entra
            if _intentar(p, i, s, h):
                sumar_uso(p, i, s, h, k)
    p.ctx_disparadora = None
    # Espada Encantada: "en tu Fase de Vigilia, si esta carta está en tu
    # Cementerio y juegas un Aliado, puedes descartar … para ponerla en tu Mano".
    for s in list(p.j(i).cementerio):
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "propia_entra" or h.get("zonaActivacion") != "cementerio":
                continue
            if not _dispara_por(entra, h) or not fase_ok(p, h) or not turno_ok(p, i, h):
                continue
            p.ctx_disparadora = entra
            _intentar(p, i, s, h)
            p.ctx_disparadora = None
            break


def fuentes_del_oponente(p: "Partida", i: int) -> list[Instancia]:
    """Cartas del rival con habilidades que puede usar `i` (Nudo de Isis)."""
    return [
        x
        for x in p.e.instancias_en_juego(1 - i)
        if any(h.get("usaQuien") in ("oponente", "ambos") for h in x.habilidades)
    ]


# ── Notas de cartas, 4ª tanda (2026-11-09) ───────────────────────────────────
def usos(p: "Partida", i: int, inst: Instancia, h: dict, k: int) -> int:
    """Usos este turno; con "límite para todas sus copias", por nombre."""
    if h.get("limitePorNombre"):
        return p.usos_nombre.get((i, inst.nombre), 0)
    if h.get("grupoLimite"):
        return inst.usos_turno.get(f"g:{h['grupoLimite']}", 0)
    return inst.usos_turno.get(k, 0)


def sumar_uso(p: "Partida", i: int, inst: Instancia, h: dict, k: int) -> None:
    inst.usos_turno[k] = inst.usos_turno.get(k, 0) + 1
    if h.get("grupoLimite"):
        clave = f"g:{h['grupoLimite']}"
        inst.usos_turno[clave] = inst.usos_turno.get(clave, 0) + 1
    if h.get("limitePorNombre"):
        p.usos_nombre[(i, inst.nombre)] = p.usos_nombre.get((i, inst.nombre), 0) + 1


def _dispara_por(carta: Instancia, h: dict) -> bool:
    """Filtro de "cuando una carta tuya entra/sale": tipo y raza."""
    tipos = h.get("disparoTipos") or []
    if tipos and carta.tipo.value not in tipos:
        return False
    if h.get("disparoCosteMin") and (carta.tipo == Tipo.ORO or carta.carta.coste < int(h["disparoCosteMin"])):
        return False  # Monte Killgharrah: "un Aliado de coste 3 o más"
    if not _arquetipo_ok(carta, h.get("disparoArquetipo") or ""):
        return False  # Musa Calíope: "cuando una carta Musa entre o salga del juego"
    return _raza_ok(carta, h.get("disparoRaza") or "")


def disparar_jugada(p: "Partida", i: int, jugada: Instancia) -> None:
    """"Cuando juegues un Talismán…" (Fruto Fiodhain, Jared el Mago): se
    dispara al jugar la carta, entre o no en juego (un Talismán nunca entra).
    Las cartas que entran en juego además disparan ``propia_entra``."""
    for s in list(p.e.instancias_en_juego(i)) + list(p.j(i).pagado):
        if s is jugada:
            continue
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "propia_juega" or not _dispara_por(jugada, h):
                continue
            if s.zona == Zona.PAGADO and h.get("zonaActivacion") in ("reserva_oro", "reserva"):
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, i, s, h, k) >= limite:
                continue
            p.ctx_disparadora = jugada
            try:
                if _intentar(p, i, s, h):
                    sumar_uso(p, i, s, h, k)
            finally:
                p.ctx_disparadora = None


def _disparar_rival_pierde_fuerza(p: "Partida", i: int, t: Instancia) -> None:
    """Cochero de Drácula: "si un Aliado oponente pierde fuerza por la
    habilidad de un Aliado que controles, puedes robar una carta"."""
    for s in list(p.e.instancias_en_juego(i)):
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "rival_pierde_fuerza":
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, i, s, h, k) >= limite:
                continue
            p.ctx_disparadora = t
            if _intentar(p, i, s, h):
                sumar_uso(p, i, s, h, k)
            p.ctx_disparadora = None


def disparar_salida(p: "Partida", sale: Instancia, controlador: int) -> None:
    """Ptolomeo III: "cada vez que un Aliado Faraón tuyo sale del juego…"."""
    for s in list(p.e.instancias_en_juego(controlador)):
        if s is sale:
            continue
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "propia_sale" or not _dispara_por(sale, h):
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, controlador, s, h, k) >= limite:
                continue
            sumar_uso(p, controlador, s, h, k)
            p.ctx_disparadora = sale
            _intentar(p, controlador, s, h)
    p.ctx_disparadora = None
    if sale.tipo != Tipo.ALIADO and sale.carta.tipo != Tipo.ALIADO:
        return
    # Quién lo sacó: la habilidad que se está resolviendo (None = combate o regla).
    causa = getattr(p, "ctx_fuente_habilidad", None)
    if causa is None or causa.controlador == controlador:
        return
    jug = p.j(controlador)
    for s in list(jug.cementerio) + list(jug.mano):
        for k, h in enumerate(s.habilidades):
            if h.get("cuando") != "propia_sale" or h.get("zonaActivacion") not in ("cementerio", "mano"):
                continue
            if (s.zona == Zona.MANO) != (h.get("zonaActivacion") == "mano"):
                continue
            if h.get("causa") == "aliado_oponente" and causa.tipo != Tipo.ALIADO:
                continue  # Venganza de Conall: "por la habilidad de un Aliado oponente"
            if s.zona == Zona.MANO and s.tipo == Tipo.TALISMAN:
                _jugar_en_respuesta(p, controlador, s, h, sale)
            elif s.zona == Zona.CEMENTERIO:
                p.ctx_disparadora = sale
                _intentar(p, controlador, s, h)  # Últimas Fuerzas: vuelve a la mano
                p.ctx_disparadora = None


def _jugar_en_respuesta(p: "Partida", i: int, t: Instancia, h: dict, sale: Instancia) -> None:
    """Venganza de Conall: un Talismán que solo se juega en respuesta a que
    uno de tus Aliados salga del juego. Se paga su coste y puede anularse."""
    if not p.puede_pagar(i, t) or prohibido(p, "jugar_tipo", i, t):
        return
    if not p.decide(i).usar_opcional(p, i, t, h):
        return
    p._pagar_oro(i, p.coste_de(i, t), carta=t)
    p.jugadas[i].add(t.nombre)
    p.anotar(f"J{i} juega {t.nombre} en respuesta a que sale {sale.nombre}")
    if ventana_anulacion(p, i, t):
        p._mover(t, Zona.CEMENTERIO)
        return
    p._sacar(t)
    anterior = getattr(p, "ctx_fuente_habilidad", None)
    p.ctx_fuente_habilidad = t
    try:
        resolver(p, i, t, h)
    finally:
        p.ctx_fuente_habilidad = anterior
    p._mover(t, zona_final_talisman(t))


def protegida(p: "Partida", t: Instancia) -> bool:
    """Ptolomeo III: "tus Aliados Faraón no pueden perder su habilidad"."""
    for s in p.e.instancias_en_juego():
        for h in s.habilidades:
            if h.get("accion") != "protegerHabilidad" or not condicion_ok(p, s.controlador, h):
                continue
            obj = h.get("objetivo") or {}
            if obj.get("quien") == "esta_carta":
                if _esta_carta(p, s) is t:
                    return True
            elif t.controlador in _lados(s.controlador, obj.get("quien", "propio")) and coincide(p, t, obj):
                return True
    return False


def nombrar_carta(p: "Partida", inst: Instancia, al_activar: bool = False) -> None:
    """Takelot: al entrar en juego, su controlador nombra una carta."""
    if inst.nombrado_carta is not None:
        return
    hn = next((h for h in inst.habilidades if (h.get("objetivo") or {}).get("nombrarCarta")), None)
    if hn is None:
        return
    if NOMBRAR_SOLO_AL_ACTIVAR and hn.get("cuando") in ("activada", "al_hacer_dano") and not al_activar:
        return  # Desafío g9FE: Orfeo nombra al activarse, no también al entrar
    # Reporte HIM0: Sir Bedivere nombra un Aliado: solo nombres de ese tipo.
    tipos = set((hn.get("objetivo") or {}).get("tipos") or [])
    nombres = sorted({
        x.nombre
        for j in p.e.jugadores
        for x in j.mazo + j.mano + j.defensa + j.ataque + j.apoyo + j.reserva + j.cementerio
        if x.carta.id != "__oro_inicial__" and (not tipos or x.carta.tipo.value in tipos)
    })
    if nombres:
        anterior, p.ctx_fuente_habilidad = getattr(p, "ctx_fuente_habilidad", None), inst
        try:  # quien nombra sabe para qué carta (Sir Bedivere: un Aliado de la mano rival)
            inst.nombrado_carta = p.decide(inst.controlador).elegir_carta(p, inst.controlador, nombres)
        finally:
            p.ctx_fuente_habilidad = anterior
        p.anotar(f"{inst.nombre} nombra la carta {inst.nombrado_carta}")
        obj = hn.get("objetivo") or {}
        if obj.get("zona") == "mano" and obj.get("quien") == "oponente":
            # Sir Bedivere / Destrozar la Mente: se mira la mano rival en ese
            # momento, acierte o no (después vuelve a estar oculta).
            mostrar_mano_rival(p, inst.controlador, inst)


def _va_al_mazo(efecto: dict | None) -> bool:
    """El efecto baraja la carta o la pone en el Mazo Castillo (Akhet, Focea)."""
    if not efecto:
        return False
    if efecto.get("accion") == "barajar":
        return True
    return efecto.get("accion") == "mover" and str(efecto.get("zonaDestino") or "").startswith("mazo")


def prevenir_afectar(p: "Partida", t: Instancia, lanzador: int, efecto: dict | None = None) -> bool:
    """Ptolomeo II: su controlador puede prevenir que una carta suya sea
    afectada por una habilidad oponente (pagando el costo)."""
    c = t.controlador
    if c == lanzador:
        return False
    for s in fuentes_activables(p, c):
        for k, h in enumerate(s.habilidades):
            if h.get("accion") != "prevenir" or h.get("modo") not in ("afectada", "barajar_mazo"):
                continue
            if h.get("modo") == "barajar_mazo" and not (t.en_juego and _va_al_mazo(efecto)):
                continue  # Amkh: solo contra barajar / poner en el Mazo Castillo
            obj = h.get("objetivo") or {}
            if obj.get("quien") == "esta_carta":
                if _esta_carta(p, s) is not t:
                    continue
            elif c not in _lados(s.controlador, obj.get("quien", "propio")) or not coincide(p, t, obj):
                continue
            limite = int(h.get("limitePorTurno", 0))
            if limite and usos(p, c, s, h, k) >= limite:
                continue
            if not condicion_ok(p, c, h) or not puede_pagar_costo(p, c, s, h):
                continue
            decide = p.decide(c)
            if hasattr(decide, "prevenir_conviene"):
                quiere = decide.prevenir_conviene(p, c, s, h, t, efecto)
            else:
                quiere = decide.usar_opcional(p, c, s, h)
            if not quiere:
                continue
            mazo, oros = len(p.j(c).mazo), p.j(c).oro_disponible
            pagar_costo(p, c, s, h, narrar=False)
            sumar_uso(p, c, s, h, k)
            # El costo va en la misma línea: "paga 1 Oro" suelto parecía del rival.
            pago = [f"paga {oros - p.j(c).oro_disponible} Oro"] if oros > p.j(c).oro_disponible else []
            if mazo > len(p.j(c).mazo):
                pago.append(f"bota {mazo - len(p.j(c).mazo)}")
            extra = f" ({', '.join(pago)})" if pago else ""
            p.anotar(f"J{c} previene que {t.nombre} sea afectada, con {s.nombre}{extra}")
            return True
    return False



_VERBOS = {
    "destruir": "destruye a",
    "desterrar": "destierra a",
    "subirMano": "sube a la mano a",
    "barajar": "baraja en el mazo a",
    "perderHabilidad": "quita la habilidad a",
    "obligarBloqueo": "obliga a bloquear a",
    "ganarControl": "toma el control de",
    "ponerEnJuego": "pone en juego a",
    "anular": "anula a",
    "elegir": "elige a",
}
_DESTINOS ={"mazo_fondo": "al fondo del mazo", "mazo_tope": "arriba del mazo", "mano": "a la mano"}


def describir(h: dict) -> str:
    """Texto de un efecto para la narración ("otorga Indestructible a")."""
    accion = h.get("accion", "")
    modo = (h.get("modo") or "").replace("_", " ")
    if accion == "otorgarPropiedad":
        return f"otorga {(modo or 'indestructible').capitalize()} a"
    if accion == "modificarFuerza":
        if h.get("modoFuerza") == "duplicar":
            return "duplica la fuerza de"  # Berserk
        if h.get("modoFuerza") == "fijar":
            return f"deja en {int(h.get('valor', 0))} la fuerza de"  # Titanes
        return f"{int(h.get('valor', 0)):+d} de fuerza a"
    if accion == "restringirCombate":
        cuando = " en su próximo turno" if h.get("duracion") == "proximo_turno" else ""
        return f"{modo or 'no puede bloquear'}{cuando}:"
    if accion == "mover":
        return f"manda {_DESTINOS.get(h.get('zonaDestino', ''), 'a otra zona')} a"
    return _VERBOS.get(accion, f"{accion} →")


_ZONAS_NARRADAS = {Zona.CEMENTERIO: "Cementerio", Zona.DESTIERRO: "Destierro", Zona.MANO: "mano", Zona.MAZO: "mazo"}


def _con_origen(t: Instancia, origen: dict) -> str:
    """Nombre con la zona de donde salió, si no estaba en juego: dos copias
    con el mismo nombre (una en juego, otra en el Cementerio) no se confunden."""
    zona = _ZONAS_NARRADAS.get(origen.get(t.uid))
    return f"{t.nombre} ({zona})" if zona else t.nombre
