"""Estado de una partida: cartas, instancias en juego, jugadores.

Los nombres siguen el reglamento (D.A.R.) y el formato de `habilidades` que
guarda la app (lib/models/card_habilidad.dart).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import random
import re


class Tipo(str, Enum):
    ALIADO = "Aliado"
    ARMA = "Arma"
    TALISMAN = "Talismán"
    TOTEM = "Tótem"
    ORO = "Oro"


def normalizar_tipo(valor: str) -> Tipo:
    v = (valor or "").strip().lower()
    for t in Tipo:
        if t.value.lower() == v:
            return t
    return {
        "talisman": Tipo.TALISMAN,
        "totem": Tipo.TOTEM,
    }.get(v.replace("á", "a").replace("ó", "o"), Tipo.TALISMAN)


@dataclass(frozen=True)
class Carta:
    """Datos impresos de una carta (no cambian durante la partida)."""

    id: str
    nombre: str
    tipo: Tipo
    coste: int
    fuerza: int
    raza: str
    texto: str
    habilidades: tuple = ()
    revisada: bool = False

    @property
    def solo_desde_mano(self) -> bool:
        """Dragones: "Sólo puede ser jugado desde tu mano" (no se busca ni se
        pone en juego desde otra zona)."""
        return bool(re.search(r"s[óo]lo puede ser jugad[oa] desde tu mano", self.texto, re.I))

    @property
    def sin_texto(self) -> bool:
        return not self.texto.strip()

    @property
    def programada(self) -> bool:
        """El dueño la marcó como completa en la app.

        No basta con que no tenga texto: la mayoría de las cartas no tiene el
        texto de habilidad cargado en Firestore. El Oro inicial genérico es la
        única carta que se da por completa.
        """
        return self.revisada or self.id == "__oro_inicial__"

    def tiene_propiedad(self, accion: str) -> bool:
        return any(h.get("accion") == accion for h in self.habilidades)


# Oro inicial genérico (Oro sin habilidad, regla 4.2.5).
ORO_INICIAL = Carta(
    id="__oro_inicial__",
    nombre="Oro inicial",
    tipo=Tipo.ORO,
    coste=0,
    fuerza=0,
    raza="",
    texto="",
)


class Zona(str, Enum):
    MAZO = "mazo"
    MANO = "mano"
    RESERVA = "reserva_oro"
    PAGADO = "oro_pagado"
    DEFENSA = "linea_defensa"
    ATAQUE = "linea_ataque"
    APOYO = "linea_apoyo"
    CEMENTERIO = "cementerio"
    DESTIERRO = "destierro"
    PORTADA = "portada"  # Arma cargada en un Aliado


EN_JUEGO = {Zona.RESERVA, Zona.PAGADO, Zona.DEFENSA, Zona.ATAQUE, Zona.APOYO, Zona.PORTADA}


@dataclass
class ModFuerza:
    modo: str  # sumar | fijar | duplicar
    valor: int
    duracion: str  # hasta_fase_final | hasta_vigilia | permanente | mientras_en_juego
    turno: int
    fuente: int | None = None  # uid de la instancia que lo causó
    creador: int = -1  # jugador que lo causó (para "hasta tu próxima Vigilia")
    # Hienas / Fantasmas: "y no pueden volver a modificar su fuerza" hasta que expire.
    congela: bool = False


@dataclass
class Instancia:
    """Una copia concreta de una carta durante la partida."""

    uid: int
    carta: Carta
    dueno: int
    controlador: int
    zona: Zona = Zona.MAZO
    listo: bool = False  # puede atacar (en juego desde su última Agrupación)
    portador: int | None = None  # uid del Aliado, si es un Arma cargada
    mods: list[ModFuerza] = field(default_factory=list)
    sin_habilidad_hasta: str | None = None  # duración de "perder habilidad"
    sin_habilidad_fuente: int | None = None  # Draco Cometa: "mientras esté en juego"
    usos_turno: dict[int, int] = field(default_factory=dict)
    # Estados temporales: {"modo", "duracion", "fuente", "turno", "creador"}
    # (restringir combate, "no hace daño este turno"…).
    estados: list[dict] = field(default_factory=list)
    # Control prestado: {"duracion", "fuente", "turno", "original"}.
    control: dict | None = None
    # Raza nombrada al entrar en juego (Cleopatra VII).
    nombrado: str | None = None
    # Carta nombrada al entrar en juego (Takelot).
    nombrado_carta: str | None = None
    # Alejandro Magno: el Aliado robado "se considera de raza Héroe".
    raza_temporal: str | None = None
    # Ave de Hera: un Oro convertido en Aliado de fuerza N hasta la Fase Final.
    tipo_temporal: Tipo | None = None
    fuerza_temporal: int | None = None
    zona_oro_origen: Zona | None = None  # Mercaderes vuelve a la zona de Oro de la que salió
    # Titán Gorila: nombre de la carta barajada que el rival no puede jugar.
    carta_vetada: str | None = None
    # Acólitos de Drácula: "se considera un Aliado Drácula" (arquetipo extra).
    arquetipo_extra: str | None = None
    # Aker: habilidades copiadas hasta la Fase Final.
    copia: tuple = ()
    # Nimue: copia exacta de otra carta hasta la Fase Final (carta original).
    carta_original: "Carta | None" = None

    @property
    def tipo(self) -> Tipo:
        return self.tipo_temporal or self.carta.tipo

    @property
    def raza(self) -> str:
        if any(e.get("modo") == "sin_raza" for e in self.estados):
            return ""  # Dalriada: pierde su raza hasta la Fase Final
        return self.raza_temporal or self.carta.raza or ""

    @property
    def nombre(self) -> str:
        return self.carta.nombre

    @property
    def en_juego(self) -> bool:
        return self.zona in EN_JUEGO

    @property
    def habilidades(self) -> tuple:
        if self.sin_habilidad_hasta is not None:
            return ()
        if not self.carta.programada:
            return ()
        return tuple(self.carta.habilidades) + tuple(self.copia)

    def tiene(self, accion: str) -> bool:
        return any(h.get("accion") == accion for h in self.habilidades)

    def __repr__(self) -> str:  # pragma: no cover - solo depuración
        return f"<{self.nombre}#{self.uid} {self.zona.value}>"


@dataclass
class Jugador:
    indice: int
    nombre_mazo: str
    mazo: list[Instancia] = field(default_factory=list)
    mano: list[Instancia] = field(default_factory=list)
    reserva: list[Instancia] = field(default_factory=list)
    pagado: list[Instancia] = field(default_factory=list)
    defensa: list[Instancia] = field(default_factory=list)
    ataque: list[Instancia] = field(default_factory=list)
    apoyo: list[Instancia] = field(default_factory=list)
    cementerio: list[Instancia] = field(default_factory=list)
    destierro: list[Instancia] = field(default_factory=list)
    oros_virtuales: int = 0
    # Oros virtuales que solo pagan ciertas cartas: [cantidad, tipos, raza].
    oros_restringidos: list[list] = field(default_factory=list)
    oro_jugado: bool = False
    no_agrupar: str | None = None  # "aliados" | "oros" | "ambos"
    # Defensores Celtas / Linaje Celta: efectos para el próximo Aliado que juegue.
    proximos: list[dict] = field(default_factory=list)
    # Olímpicos: la primera carta del castillo que su dueño ya vio (uid).
    tope_visto: int | None = None

    def lista(self, zona: Zona) -> list[Instancia]:
        return {
            Zona.MAZO: self.mazo,
            Zona.MANO: self.mano,
            Zona.RESERVA: self.reserva,
            Zona.PAGADO: self.pagado,
            Zona.DEFENSA: self.defensa,
            Zona.ATAQUE: self.ataque,
            Zona.APOYO: self.apoyo,
            Zona.CEMENTERIO: self.cementerio,
            Zona.DESTIERRO: self.destierro,
        }[zona]

    @property
    def aliados(self) -> list[Instancia]:
        return self.defensa + self.ataque

    @property
    def oro_disponible(self) -> int:
        return len(self.reserva) + self.oros_virtuales


@dataclass
class Estado:
    jugadores: list[Jugador]
    rng: random.Random
    turno: int = 0
    activo: int = 0
    fase: str = "agrupacion"
    portadas: list[Instancia] = field(default_factory=list)  # Armas cargadas
    ganador: int | None = None  # 0, 1, o -1 = empate
    terminada: bool = False
    causa: str = ""
    log: list[str] | None = None
    _next_uid: int = 0

    def nuevo_uid(self) -> int:
        self._next_uid += 1
        return self._next_uid

    def oponente(self, i: int) -> int:
        return 1 - i

    def instancias_en_juego(self, i: int | None = None) -> list[Instancia]:
        jugadores = self.jugadores if i is None else [self.jugadores[i]]
        out: list[Instancia] = []
        for j in jugadores:
            out += j.reserva + j.defensa + j.ataque + j.apoyo
        out += [a for a in self.portadas if i is None or a.controlador == i]
        return out

    def anotar(self, texto: str) -> None:
        if self.log is not None:
            self.log.append(f"T{self.turno} [{self.fase}] {texto}")
