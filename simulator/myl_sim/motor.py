"""Motor de reglas: una partida completa entre dos jugadores.

Implementa REGLAS.md. Las decisiones (qué jugar, a quién bloquear, objetivos)
las toma el objeto Jugador de cada lado (ver jugadores.py); el motor solo
ofrece las opciones legales y aplica las reglas.
"""

from __future__ import annotations

from dataclasses import dataclass
import random

from . import habilidades as hab
from .modelo import (
    ORO_INICIAL,
    Carta,
    Estado,
    Instancia,
    Jugador,
    Tipo,
    Zona,
)

MANO_INICIAL = 8
MANO_MAXIMA = 8
TURNOS_MAXIMOS = 200  # protección; ver REGLAS.md §7
MAX_MULLIGANS = 4


MAX_JUGADAS_FASE = 60


# 2026-11-15: sin castillo se pierde ya (no solo al robar o botar). Apagar
# para reproducir partidas grabadas antes.
FIN_SIN_CASTILLO = True
# 2026-11-15: pagar a mano también dispara el Broche de Tara (apagar para
# reproducir partidas grabadas antes).
PAGO_MANUAL_DISPARA = True


class FinPartida(Exception):
    """Se lanza en cuanto un Mazo Castillo queda vacío."""


@dataclass
class Jugada:
    """Una opción legal para el jugador con prioridad."""

    tipo: str  # oro | jugar | activar | pasar
    carta: Instancia | None = None
    portador: Instancia | None = None  # Armas: Aliado que la carga
    habilidad: int | None = None  # índice en carta.habilidades (activar)
    destino: str | None = None  # Talismán jugado desde otra zona: a dónde va
    descuento: int = 0  # rebaja puntual al jugar desde otra zona

    def __str__(self) -> str:
        if self.tipo == "pasar":
            return "pasar"
        extra = f" en {self.portador.nombre}" if self.portador else ""
        if self.tipo == "activar":
            return f"activar {self.carta.nombre}"
        return f"{self.tipo} {self.carta.nombre}{extra}"


@dataclass
class Registro:
    """Datos de una partida para las estadísticas."""

    ganador: int  # 0 / 1 / -1 empate / -2 anómala
    inicial: int
    turnos: int
    causa: str
    jugadas: tuple[set, set]  # nombres de cartas jugadas por cada lado
    robadas: tuple[set, set]
    sin_programar_usadas: tuple[set, set]
    dado: tuple[int, int] | None = None  # tirada que decidió (J0, J1); gana = inicial
    mulligans: tuple[int, int] = (0, 0)
    # Oros en juego al terminar su 4º turno propio (None: no llegó).
    oros_turno4: tuple[int | None, int | None] = (None, None)


def _compactar(grupo: list[str]) -> list[str]:
    """Un paso por efecto: sin las consecuencias que el efecto ya dice
    ("Kawit es destruido" si está "Nephre-Ka: destruye a Kawit") y sin
    repetir el nombre de la carta ("Demoledor de Amon: obliga a bloquear a
    Djoser · quita la habilidad a Djoser · -1 de fuerza a Djoser")."""
    def nombres(verbo: str) -> set[str]:
        return {n for t in grupo if verbo in t for n in t.split(verbo, 1)[1].split(", ")}

    destruidos, desterrados = nombres(": destruye a "), nombres(": destierra a ")
    controlados = nombres(": toma el control de ")
    limpio = []
    for t in grupo:
        if t.endswith(" es destruido") and t[: -len(" es destruido")] in destruidos:
            continue
        if t.endswith(" es desterrado") and t[: -len(" es desterrado")] in desterrados:
            continue
        if " pasa a control de " in t and t.split(" pasa a control de ")[0] in controlados:
            continue
        limpio.append(t)
    out, prefijo = [], None
    for t in limpio:
        pre, sep, resto = t.partition(": ")
        if sep and pre == prefijo:
            out.append(resto)
            continue
        prefijo = pre if sep else None
        out.append(t)
    return out



def _cancela_ataque(o) -> bool:
    """Flechas de Lava: una jugada cuya habilidad cancela el ataque."""
    habs = o.carta.habilidades if o.carta is not None else []
    if o.tipo == "activar":
        habs = [habs[o.habilidad]]
    return any(h.get("accion") == "cancelarAtaque" for h in habs)

class Partida:
    def __init__(
        self,
        mazos: tuple[list[Carta], list[Carta]],
        jugadores: tuple,
        nombres: tuple[str, str] = ("A", "B"),
        inicial: int | None = 0,
        seed: int | None = None,
        log: bool = False,
    ):
        # inicial=None: se tira el dado y empieza quien lo gana.
        self.e = Estado(
            jugadores=[Jugador(0, nombres[0]), Jugador(1, nombres[1])],
            rng=random.Random(seed),
            activo=inicial or 0,
            log=[] if log else None,
        )
        self.jugadores = jugadores
        self.dados: list[tuple[int, int]] = []  # tiradas (J0, J1), con repeticiones
        if inicial is None:
            inicial = self._tirar_dado()
        self.e.activo = inicial
        self.inicial = inicial
        self.jugadas: tuple[set, set] = (set(), set())
        self.robadas: tuple[set, set] = (set(), set())
        self.sin_programar: tuple[set, set] = (set(), set())
        self.ultimo_dano: dict[int, str] = {0: "", 1: ""}
        self.pasos: list[dict] = []  # fotos de la mesa (partida narrada)
        self.mulligans = [0, 0]
        self.turnos_propios = [0, 0]
        self.oros_turno4: list[int | None] = [None, None]
        # Estado de la Batalla Mitológica en curso (para cancelar ataques).
        self.atacantes: list[Instancia] = []
        self.bloqueos: dict[int, Instancia] = {}
        self.ataque_cancelado = False
        # Aliados que hicieron daño al Mazo Castillo este turno, y efectos
        # "luego" que esperan a la Fase Final.
        self.dano_hecho: set[int] = set()
        self.aliados_destruidos_turno = 0
        self.descartadas_turno = [0, 0]
        # Aliados declarados atacantes en el turno actual (Dario III).
        self.ataco_este_turno: set[int] = set()
        # Demoledor de Amon: atacante → Aliado oponente obligado a bloquearlo.
        self.bloqueo_forzado: dict[int, Instancia] = {}
        # Usos por turno compartidos entre copias (jugador, nombre) → usos.
        self.usos_nombre: dict[tuple[int, str], int] = {}
        self.ctx_lanzador: int | None = None
        self.ctx_disparadora: Instancia | None = None
        self.pendientes_final: list = []
        for i, cartas in enumerate(mazos):
            j = self.e.jugadores[i]
            j.mazo = [self._instancia(c, i, Zona.MAZO) for c in cartas]
            self.e.rng.shuffle(j.mazo)
            oro = self._instancia(ORO_INICIAL, i, Zona.RESERVA)
            j.reserva.append(oro)

    def _tirar_dado(self) -> int:
        """Cada jugador tira un d6; si empatan, repiten. Quien gana empieza."""
        while True:
            a, b = self.e.rng.randint(1, 6), self.e.rng.randint(1, 6)
            self.dados.append((a, b))
            if a != b:
                return 0 if a > b else 1

    # ── Utilidades ────────────────────────────────────────────────────────────
    def _instancia(self, carta: Carta, jugador: int, zona: Zona) -> Instancia:
        return Instancia(
            uid=self.e.nuevo_uid(),
            carta=carta,
            dueno=jugador,
            controlador=jugador,
            zona=zona,
        )

    def j(self, i: int) -> Jugador:
        return self.e.jugadores[i]

    def decide(self, i: int):
        return self.jugadores[i]

    def anotar(self, texto: str) -> None:
        grupo = getattr(self, "_grupo", None)
        if grupo is not None:
            # Activación en curso (Ramsés II): se junta en un solo paso.
            if texto not in grupo:
                grupo.append(texto)
            return
        self.e.anotar(texto)
        if self.e.log is not None:
            self.pasos.append(self.foto(texto))

    def _cerrar_grupo(self) -> None:
        grupo, self._grupo = self._grupo, None
        fuente, self._grupo_fuente = getattr(self, "_grupo_fuente", None), None
        if grupo and fuente:
            # Primero lo que hace la carta que disparó (Montuhopet sube a
            # Amyrteos) y después lo que eso provoca (Amyrteos acelera un Oro).
            grupo = sorted(grupo, key=lambda t: not t.startswith(f"{fuente}:"))
        if grupo:
            self.anotar(" · ".join(_compactar(grupo)))

    def foto(self, texto: str) -> dict:
        """Estado de la mesa en este momento (para el tablero de la app)."""

        def aliado(a: Instancia) -> list:
            armas = [x.carta.id for x in self.e.portadas if x.portador == a.uid]
            return [a.carta.id, hab.fuerza(self, a), armas]

        jugadores = []
        for j in self.e.jugadores:
            jugadores.append({
                "m": len(j.mazo),
                "h": [x.carta.id for x in j.mano],
                "c": len(j.cementerio),
                "ct": j.cementerio[-1].carta.id if j.cementerio else None,
                "d": len(j.destierro),
                "dt": j.destierro[-1].carta.id if j.destierro else None,
                # Contenido completo (para verlo en el tablero); narrar() lo
                # deja solo en los pasos donde cambia.
                "cl": [x.carta.id for x in j.cementerio],
                "dl": [x.carta.id for x in j.destierro],
                "r": [x.carta.id for x in j.reserva],
                "p": [x.carta.id for x in j.pagado],
                "v": j.oros_virtuales,
                "def": [aliado(a) for a in j.defensa],
                "atk": [aliado(a) for a in j.ataque],
                "ap": [x.carta.id for x in j.apoyo],
            })
        return {"t": self.e.turno, "f": self.e.fase, "a": self.e.activo, "x": texto, "j": jugadores}

    # ── Partida completa ──────────────────────────────────────────────────────
    def jugar(self) -> Registro:
        try:
            for a, b in self.dados:
                fin = (
                    "empate, se repite" if a == b
                    else f"J{self.inicial} gana el dado y empieza"
                )
                self.anotar(f"Dado: J0 saca {a} · J1 saca {b} → {fin}")
            for i in (self.inicial, 1 - self.inicial):
                self._mano_inicial(i)
            self._ciclo_turnos()
        except FinPartida:
            pass
        return Registro(
            ganador=self.e.ganador if self.e.ganador is not None else -1,
            inicial=self.inicial,
            turnos=self.e.turno,
            causa=self.e.causa,
            jugadas=self.jugadas,
            robadas=self.robadas,
            sin_programar_usadas=self.sin_programar,
            dado=self.dados[-1] if self.dados else None,
            mulligans=(self.mulligans[0], self.mulligans[1]),
            oros_turno4=(self.oros_turno4[0], self.oros_turno4[1]),
        )

    def _cerrar_turno(self, a: int) -> None:
        if self.turnos_propios[a] == 4:
            j = self.j(a)
            self.oros_turno4[a] = len(j.reserva) + len(j.pagado)
        self.e.activo = 1 - self.e.activo

    def _ciclo_turnos(self) -> None:
        while not self.e.terminada:
            self.e.turno += 1
            if self.e.turno > TURNOS_MAXIMOS:
                self.e.terminada = True
                self.e.ganador = -2
                self.e.causa = "limite_turnos"
                break
            a = self.e.activo
            self.turnos_propios[a] += 1
            self._turno()
            self._cerrar_turno(a)

    def _mano_inicial(self, i: int) -> None:
        jug = self.j(i)
        n = MANO_INICIAL
        for intento in range(MAX_MULLIGANS + 1):
            self.robar(i, n, inicial=True)
            if intento == MAX_MULLIGANS or self.decide(i).quedarse_mano(self, i):
                break
            self.anotar(f"J{i} hace mulligan ({n} → {n - 1})")
            for inst in list(jug.mano):
                self._sacar(inst)
                inst.zona = Zona.MAZO
                jug.mazo.append(inst)
            self.e.rng.shuffle(jug.mazo)
            n -= 1
            self.mulligans[i] += 1
        for inst in jug.mano:
            self.robadas[i].add(inst.nombre)

    # ── Turno (REGLAS.md §4) ──────────────────────────────────────────────────
    def _turno(self) -> None:
        a = self.e.activo
        jug = self.j(a)
        self.e.fase = "agrupacion"
        self.anotar(f"── Turno de J{a} ({jug.nombre_mazo}) ──")
        if self.e.log is not None:
            # Resumen solo para la narración de texto: en el tablero ya se ve.
            for k in (0, 1):
                x = self.j(k)
                self.e.anotar(
                    f"J{k}: castillo {len(x.mazo)} · mano {len(x.mano)} · "
                    f"oros {len(x.reserva) + len(x.pagado)} · "
                    f"aliados {', '.join(f'{a.nombre} ({hab.fuerza(self, a)})' for a in x.aliados) or '—'}"
                )
        # FqvR #3: también los Oros pagados (La Ilíada usada desde ahí) y lo que
        # se activa desde el Cementerio: "una vez por turno" vuelve a valer.
        for x in self.e.jugadores:
            for inst in list(self.e.instancias_en_juego(x.indice)) + x.pagado + x.cementerio + x.mano + x.destierro:
                inst.usos_turno.clear()
        hab.refrescar_perdidas(self)
        self.dano_hecho.clear()
        self.aliados_destruidos_turno = 0
        self.descartadas_turno = [0, 0]
        self.ataco_este_turno.clear()
        self.pendientes_final.clear()
        self.bloqueo_forzado.clear()
        # La batalla del turno anterior ya terminó (si no, "estamos en
        # combate" seguiría siendo cierto en la Vigilia siguiente).
        self.atacantes, self.bloqueos = [], {}
        self.usos_nombre.clear()

        # Agrupación
        self.e.fase = "agrupacion"
        bloqueo = jug.no_agrupar
        jug.no_agrupar = None
        saltada = hab.prohibido(self, "saltar_agrupacion", a)
        if not saltada:
            pagando = []
            if bloqueo not in ("aliados", "ambos"):
                for inst in list(jug.ataque):
                    if hab.tiene_estado(self, inst, "no_agrupar"):
                        # Muerte del Príncipe: no se agrupa en este turno de su controlador.
                        inst.estados = [e for e in inst.estados if e.get("modo") != "no_agrupar"]
                        self.anotar(f"{inst.nombre} no puede ser agrupado")
                        continue
                    if any(h.get("accion") == "restriccion" and h.get("modo") == "agrupar_pagando"
                           for h in inst.habilidades):
                        pagando.append(inst)  # Gigante de la Niebla: se paga con los Oros ya agrupados
                        continue
                    self._mover(inst, Zona.DEFENSA)
            if bloqueo not in ("oros", "ambos"):
                for inst in list(jug.pagado):
                    self._mover(inst, Zona.RESERVA)
            for inst in pagando:
                h = next(h for h in inst.habilidades
                         if h.get("accion") == "restriccion" and h.get("modo") == "agrupar_pagando")
                if hab.puede_pagar_costo(self, a, inst, h) and self.decide(a).usar_opcional(self, a, inst, h) \
                        and hab.pagar_costo(self, a, inst, h):
                    self._mover(inst, Zona.DEFENSA)
                else:
                    self.anotar(f"{inst.nombre} no se agrupa")
            for inst in jug.defensa:
                inst.listo = True
        else:
            self.anotar(f"J{a} salta su Fase de Agrupación")
        hab.revisar_controles(self)
        if not saltada:
            hab.disparar_inicio_fase(self, "agrupacion")
            self._fin_si_castillo_vacio()
            self._ventana_activadas(a, "agrupacion")

        # Vigilia
        self.e.fase = "vigilia"
        jug.oro_jugado = False
        hab.expirar(self, "hasta_vigilia", controlador=a)
        hab.disparar_inicio_fase(self, "vigilia")
        self._fin_si_castillo_vacio()
        self._vigilia(a)

        # Batalla Mitológica
        self.e.fase = "batalla"
        self._batalla(a)

        self._finalizar_turno(a)

    def _finalizar_turno(self, a: int) -> None:
        jug = self.j(a)
        # Fase Final
        self.e.fase = "final"
        # Un Oro temporal como Mercaderes vuelve, resuelve su salida y puede
        # destruirse: es una sola resoluciÃ³n de fase, no cuatro jugadas.
        agrupar_temporal = any(
            x.tipo_temporal is not None for j in self.e.jugadores
            for x in j.aliados
        )
        if agrupar_temporal:
            self._grupo = []
            self._grupo_fuente = None
        hab.expirar(self, "hasta_fase_final")
        hab.revisar_controles(self)
        hab.resolver_pendientes_final(self)
        hab.disparar_inicio_fase(self, "final")
        self._fin_si_castillo_vacio()
        if agrupar_temporal:
            self._cerrar_grupo()
        hubo_opciones = self._ventana_activadas(a, "final")
        if not hubo_opciones:
            avanzar = getattr(self.decide(a), "confirmar_fase", None)
            if avanzar is not None:
                avanzar(self, a, "Terminar turno")
        for j in self.e.jugadores:
            j.oros_virtuales = 0
            j.oros_restringidos.clear()

        # Final del turno: robar 1 y descartar hasta 8
        self.robar(a, 1)
        exceso = len(jug.mano) - MANO_MAXIMA
        if exceso > 0:
            sobran = self.decide(a).elegir_descartes(self, a, list(jug.mano), exceso)
            for inst in sobran:
                self.descartar(inst)
            self.anotar(f"J{a} descarta por exceso de mano: {', '.join(x.nombre for x in sobran)}")

    def _vigilia(self, a: int) -> None:
        jug = self.j(a)
        jugadas = 0
        while not self.e.terminada:
            jugadas += 1
            if jugadas > MAX_JUGADAS_FASE:
                break  # seguro: una decisión que no cambia nada no cuelga la partida
            opciones = self.jugadas_legales(a, "vigilia")
            elegida = self.decide(a).elegir_jugada(self, a, opciones)
            if elegida.tipo == "pasar":
                break
            if elegida.tipo == "oro":
                self._mover(elegida.carta, Zona.RESERVA)
                jug.oro_jugado = True
                self.jugadas[a].add(elegida.carta.nombre)
                self.anotar(f"J{a} juega oro {elegida.carta.nombre}")
                hab.errante(self, elegida.carta)
                hab.disparar(self, elegida.carta, "al_jugar")
            else:
                self.ejecutar_jugada(a, elegida)
            # El Oro solo se juega como primera acción de la Vigilia.
            jug.oro_jugado = True

    def _ventana_activadas(self, i: int, fase: str) -> bool:
        """Agrupación/Final: el activo puede usar habilidades de esa fase."""
        for _ in range(10):
            opciones = [o for o in self.jugadas_legales(i, fase) if o.tipo == "activar"]
            if not opciones:
                return False
            elegida = self.decide(i).elegir_jugada(self, i, opciones + [Jugada("pasar")])
            if elegida.tipo == "pasar":
                return True
            self.ejecutar_jugada(i, elegida)
        return True

    # ── Opciones legales ─────────────────────────────────────────────────────
    def coste_de(self, i: int, inst: Instancia) -> int:
        return max(0, inst.carta.coste - hab.reduccion_coste(self, i, inst))

    def puede_pagar(self, i: int, inst: Instancia, *, gratis: bool = False) -> bool:
        if gratis:
            return True
        return hab.oro_para(self, i, inst) >= self.coste_de(i, inst)

    def jugadas_legales(self, i: int, fase: str) -> list[Jugada]:
        jug = self.j(i)
        activo = i == self.e.activo
        opciones: list[Jugada] = []
        if fase == "vigilia" and activo and not jug.oro_jugado:
            for inst in jug.mano:
                if inst.tipo == Tipo.ORO:
                    if hab.tiene_prop(self, inst, "errante") and any(
                        otra.nombre == inst.nombre for otra in self.e.instancias_en_juego(i)
                    ):
                        continue  # #3 c0p0: un segundo Dragones bota el primero
                    opciones.append(Jugada("oro", inst))
        for inst in jug.mano:
            if inst.tipo == Tipo.ORO or not self.puede_pagar(i, inst):
                continue
            # Errante impide bajar una segunda copia del Aliado.
            if inst.tipo == Tipo.ALIADO and hab.tiene_prop(self, inst, "errante") and any(
                otra.nombre == inst.nombre for otra in self.e.instancias_en_juego(i)
            ):
                continue
            if not hab.requisito_para_jugar(self, i, inst):
                continue
            if hab.prohibido(self, "jugar_tipo", i, inst):
                continue
            if inst.tipo in (Tipo.ALIADO, Tipo.TOTEM):
                if fase == "vigilia" and activo:
                    opciones.append(Jugada("jugar", inst))
            elif inst.tipo == Tipo.ARMA:
                if fase == "vigilia" and activo:
                    for portador in self.j(0).aliados + self.j(1).aliados:
                        if hab.portador_valido(self, inst, portador, i):
                            opciones.append(Jugada("jugar", inst, portador=portador))
            elif inst.tipo == Tipo.TALISMAN:
                if hab.talisman_jugable(self, i, inst, fase):
                    opciones.append(Jugada("jugar", inst))
        for inst in hab.fuentes_activables(self, i) + hab.fuentes_del_oponente(self, i):
            for k, h in enumerate(inst.habilidades):
                if hab.activable(self, i, inst, h, k, fase):
                    opciones.append(Jugada("activar", inst, habilidad=k))
        opciones += hab.jugadas_desde_otra_zona(self, i, fase)
        opciones.append(Jugada("pasar"))
        return opciones

    # ── Ejecutar jugadas ─────────────────────────────────────────────────────
    def ejecutar_jugada(self, i: int, jugada: Jugada) -> None:
        try:
            self._ejecutar_jugada(i, jugada)
        finally:
            self._fin_si_castillo_vacio()

    def _fin_si_castillo_vacio(self) -> None:
        """Desafío w8nI: dos Oillipheist desterraron las últimas cartas del
        castillo rival y la partida siguió. Sin castillo se pierde ya, no solo
        al robar o botar."""
        import sys
        if FIN_SIN_CASTILLO and sys.exc_info()[0] is None and not self.e.terminada and self.e.turno >= 1:
            self._comprobar_mazos("destierro")

    def _ejecutar_jugada(self, i: int, jugada: Jugada) -> None:
        if jugada.tipo == "activar":
            inst = jugada.carta
            h = inst.habilidades[jugada.habilidad]
            # Costo, efecto y sus "luego" en un solo paso del tablero.
            propio = getattr(self, "_grupo", None) is None
            if propio:
                self._grupo = [f"J{i} activa {inst.nombre}: {h.get('featureName', '')}"]
            try:
                if not hab.pagar_costo(self, i, inst, h):
                    if propio:
                        self._grupo = None
                    return
                hab.sumar_uso(self, i, inst, h, jugada.habilidad)
                if (h.get("objetivo") or {}).get("nombrarCarta"):
                    inst.nombrado_carta = None  # Sir Bedivere: nombra en cada uso
                    hab.nombrar_carta(self, inst, al_activar=True)
                # La IA sabe qué carta resuelve (Vouivre elige qué Dragón busca).
                anterior, self.ctx_fuente_habilidad = getattr(self, "ctx_fuente_habilidad", None), inst
                try:
                    if not hab.ventana_cancelar(self, i, inst, h):
                        hab.resolver(self, i, inst, h)
                finally:
                    self.ctx_fuente_habilidad = anterior
            finally:
                if propio and self._grupo is not None:
                    self._cerrar_grupo()
            return
        inst = jugada.carta
        inst.jugada_sin_pagar = jugada.tipo == "jugar_gratis"  # Sheut la puede anular
        if jugada.tipo != "jugar_gratis":
            self._pagar_oro(i, max(0, self.coste_de(i, inst) - jugada.descuento), carta=inst)
        inst.controlador = i
        self.jugadas[i].add(inst.nombre)
        if not inst.carta.programada:
            self.sin_programar[i].add(inst.nombre)
        self.anotar(
            f"J{i} juega {inst.nombre} (coste {inst.carta.coste})"
            + (f" en {jugada.portador.nombre}" if jugada.portador else "")
        )
        if hab.ventana_anulacion(self, i, inst):
            self._mover(inst, Zona.CEMENTERIO)
            return
        if inst.tipo == Tipo.TALISMAN:
            # Se resuelve "en tránsito" de la Mano al Cementerio (4.2.3): fuera
            # de la mano para que sus propios efectos no la vean.
            self._sacar(inst)
        elif inst.tipo == Tipo.ALIADO:
            self._mover(inst, Zona.DEFENSA)
            inst.listo = hab.tiene_prop(self, inst, "furia")
        elif inst.tipo == Tipo.TOTEM:
            self._mover(inst, Zona.APOYO)
        elif inst.tipo == Tipo.ARMA:
            portador = jugada.portador
            if portador is None or not portador.en_juego:
                self._mover(inst, Zona.CEMENTERIO)
                return
            self._sacar(inst)
            inst.zona = Zona.PORTADA
            inst.portador = portador.uid
            inst.controlador = i
            self.e.portadas.append(inst)
        hab.errante(self, inst)
        # Cleopatra VII en juego: el que entra ya llega sin habilidad.
        hab.refrescar_perdidas(self)
        # Resplandor de Heka: el rival responde antes de que se resuelva su
        # "al entrar" (Haquika no alcanza a robar).
        hab.ventana_respuesta(self, inst)
        if inst.tipo == Tipo.ALIADO and inst.listo and not hab.tiene_prop(self, inst, "furia"):
            inst.listo = False  # #118: sin habilidad (Cleopatra) no tiene Furia para atacar
        hab.disparar(self, inst, "al_jugar")
        hab.disparar_entrada(self, inst)
        if self.e.fase == "vigilia" and self.e.activo == inst.controlador and inst.en_juego:
            # GdWO: "En tu fase de Vigilia, Saladino genera 2 Oros": jugado en
            # la Vigilia, genera ya en esa misma Vigilia.
            for h in inst.habilidades:
                if h.get("cuando") == "al_inicio_fase" and h.get("fase") == "vigilia" \
                        and h.get("accion") == "generarOro":
                    hab._intentar(self, inst.controlador, inst, h)
        if inst.tipo == Tipo.TALISMAN and inst.zona in (Zona.MANO, Zona.CEMENTERIO, Zona.MAZO, Zona.DESTIERRO):
            # Jugado desde otra zona puede terminar desterrado (Jinetes de Fuego).
            self._mover(
                inst, Zona.DESTIERRO if jugada.destino == "destierro" else hab.zona_final_talisman(inst)
            )
        hab.refrescar_perdidas(self)

    def _pagar_oro(
        self, i: int, cantidad: int, *, carta: Instancia | None = None, por: Instancia | None = None
    ) -> None:
        """`carta`: la que se juega (usa Oros restringidos); `por`: la que
        paga un costo de activación (solo decide qué Oros se giran)."""
        jug = self.j(i)
        if carta is not None:
            for r in jug.oros_restringidos:
                if cantidad and r[0] > 0 and hab.paga_restringido(carta, r):
                    usa = min(r[0], cantidad)
                    r[0] -= usa
                    cantidad -= usa
        virtuales = min(jug.oros_virtuales, cantidad)
        jug.oros_virtuales -= virtuales
        cantidad -= virtuales
        # Primero los Oros sin habilidad: los con habilidad continua la
        # pierden al pagarse (ej. Ofrenda a los Dioses). Pero si un Oro
        # restringe lo que hace la carta que se paga, va ése primero: pagar el
        # Nudo de Isis deja barajar al Escudo Miliciano.
        quien = carta or por
        hace = {h.get("accion") for h in quien.habilidades} if quien is not None else set()
        # El Nudo de Isis se paga primero si este turno voy a barajar con otra
        # carta: una activada en mi mesa o una de la mano que alcanzo a pagar.
        # Si no, se guarda sin pagar para que siga limitando al rival.
        quedan = jug.oro_disponible - cantidad
        for x in self.e.instancias_en_juego(i):
            hace |= {h.get("accion") for h in x.habilidades if h.get("cuando") == "activada"}
        for x in jug.mano:
            if x is not carta and x.tipo != Tipo.ORO and self.coste_de(i, x) <= quedan:
                hace |= {h.get("accion") for h in x.habilidades if h.get("cuando") in ("al_jugar", "activada", None)}

        # Una persona en Desafío IA escoge físicamente qué Oros paga. El
        # adaptador entrega instancias de la Reserva; se valida aquí para que
        # la interfaz nunca pueda pagar un Oro ajeno, repetido o insuficiente.
        elegir_oros = getattr(self.decide(i), "elegir_oros", None)
        if cantidad and elegir_oros is not None:
            disponibles = list(jug.reserva)
            elegidos = elegir_oros(self, i, disponibles, cantidad, carta=carta, por=por)
            validos = []
            for oro in elegidos:
                if oro in disponibles and oro not in validos:
                    validos.append(oro)
            if len(validos) == cantidad:
                for oro in validos:
                    self._mover(oro, Zona.PAGADO)
                if PAGO_MANUAL_DISPARA and carta is not None and carta.tipo == Tipo.ALIADO:
                    # Desafío uX2m: el Broche de Tara pagado a mano no se disparaba.
                    hab.disparar_pago(self, i, validos)
                return

        def destierra_oro(j):
            """Oros en la Reserva que se destierran como costo (Biblioteca,
            Salmón, Clochafarmore, Codex, Papiros...)."""
            return sum(1 for o in j.reserva if any(
                h.get("cuando") == "activada" and (h.get("costo") or {}).get("desterrarEstaCarta")
                for h in o.habilidades))
        # Héctor 2026-11-13: Carmix limita los Oros de destierro del rival; se
        # paga primero cuando me estorba más a mí (los Hijos de Daana lo pagan
        # para activar Clochafarmore o dejar los Salmones usables).
        carmix_estorba = destierra_oro(jug) > destierra_oro(self.j(1 - i))

        def orden(o):
            estorba = any(
                h.get("accion") == "restriccion" and (h.get("modo") or "").split("_")[0] in hace
                for h in o.habilidades
            ) or (carmix_estorba and any(
                h.get("accion") == "restriccion" and h.get("modo") == "desterrar"
                and "Oro" in ((h.get("objetivo") or {}).get("tipos") or []) for h in o.habilidades))
            if estorba:
                return 0
            if any(h.get("accion") == "agrupar" and (h.get("objetivo") or {}).get("quien") == "esta_carta"
                   and h.get("fase") == "final" for h in o.habilidades):
                return -1  # Héctor: Gaitas se paga primero, vuelve a la Reserva en la Fase Final
            if not o.habilidades:
                return 1
            # #4 MUh4: al final lo que solo sirve sin pagar: una continua (el
            # Nudo de Isis le impide barajar al rival) o una activada desde la
            # Reserva (Escarabeo). Látigo y Bastón ya hizo lo suyo al entrar.
            if any(h.get("cuando") == "continua" and h.get("accion") != "errante" for h in o.habilidades):
                return 4
            if any(h.get("cuando") == "activada" and h.get("usaQuien") not in ("oponente", "ambos")
                   and h.get("zonaActivacion", "reserva_oro") == "reserva_oro" for h in o.habilidades):
                return 3
            # #5 3W4d: Corona Faraónica (al entrar un Aliado, puede atacar) se
            # dispara solo sin pagar: se paga después de Látigo y Bastón.
            if any(h.get("cuando") == "propia_entra" for h in o.habilidades):
                return 3.5
            return 2

        es_aliado = carta is not None and carta.tipo == Tipo.ALIADO
        jug.reserva.sort(key=lambda o: (not (es_aliado and hab.dispara_al_pagar(o)), orden(o)))
        pagados = jug.reserva[:cantidad]
        for oro in pagados:
            self._mover(oro, Zona.PAGADO)
        if es_aliado:
            hab.disparar_pago(self, i, pagados)

    # ── Batalla Mitológica (REGLAS.md §4.3) ───────────────────────────────────
    def _paga_para_atacar(self, a: int, x: Instancia) -> bool:
        """Guerrero Fianna: "para declararlo atacante, paga 1 Oro por cada
        Guerrero Fianna que controles". Si no paga, no ataca."""
        h = next((h for h in x.habilidades
                  if h.get("accion") == "restriccion" and h.get("modo") == "pagar_para_combatir"), None)
        if h is None:
            return True
        costo = dict(h.get("costo") or {})
        if costo.get("porCadaMismoNombre"):
            n = sum(1 for y in self.j(a).aliados if y.nombre == x.nombre)
            costo = {k: v for k, v in costo.items() if k != "porCadaMismoNombre"}
            costo["oros"] = int(costo.get("oros", 0)) * n
        h = {**h, "costo": costo}
        if not hab.puede_pagar_costo(self, a, x, h) or not hab.pagar_costo(self, a, x, h):
            self.anotar(f"{x.nombre} no ataca: no se paga su costo")
            return False
        return True

    def _batalla(self, a: int) -> None:
        d = 1 - a
        jug, rival = self.j(a), self.j(d)
        candidatos = [
            x
            for x in jug.defensa
            if x.listo
            and not hab.tiene_prop(self, x, "guardian")
            and not hab.tiene_estado(self, x, "no_puede_atacar")
        ]
        if not candidatos or hab.prohibido(self, "declarar_ataque", a):
            return  # Pwyll: mientras esté en juego no se puede declarar ataque
        atacantes = self.decide(a).elegir_atacantes(self, a, candidatos)
        # Hathor: "este Aliado debe ser declarado atacante este turno si puede".
        atacantes += [x for x in candidatos if hab.tiene_estado(self, x, "debe_atacar") and x not in atacantes]
        if not atacantes and hab.prohibido(self, "ataque_obligatorio", a):
            # Demonio de Tara: el oponente debe declarar ataque con al menos un Aliado.
            atacantes = [min(candidatos, key=lambda x: (hab.fuerza(self, x) + x.carta.coste))]
            self.anotar(f"J{a} debe declarar ataque (Demonio de Tara)")
        atacantes = [x for x in atacantes if self._paga_para_atacar(a, x)]
        if not atacantes:
            return
        if any(h.get("accion") == "restringirCombate" and h.get("modo") == "limite_un_atacante"
               for x in self.e.instancias_en_juego() for h in x.habilidades):
            atacantes = atacantes[:1]
        solitarios = [x for x in atacantes if any(
            h.get("accion") == "restringirCombate" and h.get("modo") == "solo_esta_carta_ataca"
            for h in x.habilidades
        )]
        if solitarios:
            atacantes = [solitarios[0]]
        if any(hab.ataque_total(x) for x in atacantes):
            atacantes = list(candidatos)  # Tutatis: deben atacar todos los que puedan
        self.e.fase = "declaracion_ataque"
        for x in atacantes:
            self._mover(x, Zona.ATAQUE)
            self.ataco_este_turno.add(x.uid)
        self.anotar(f"J{a} ataca con {', '.join(x.nombre for x in atacantes)}")
        self.atacantes, self.ataque_cancelado = atacantes, False
        # Flechas de Lava responde a la declaración: si cancela el ataque, no
        # se aplica ningún efecto de la declaración (el Mandoble no bota 3).
        self._ventana_declaracion_ataque(d, solo_canceladores=True)
        if not self.ataque_cancelado:
            # Lo que pasa al declarar el ataque (Demoledor de Amon obliga a
            # bloquear y le quita la habilidad a Djoser) va antes de que se
            # jueguen las demás cartas: el Escudo Miliciano ya no le hace
            # destruir a Djoser.
            for x in atacantes:
                if x.en_juego:
                    hab.disparar_con_armas(self, x, "al_atacar", declaracion=True)
            # Canceladores de ataque: se juegan en este paso (D.A.R. 5.3.1).
            self._ventana_declaracion_ataque(d)
        if self.ataque_cancelado:
            # Cancelado: no corre nada de "al atacar" (Mandoble no bota).
            self.anotar("El ataque fue cancelado")
            for x in atacantes:
                if x.zona == Zona.ATAQUE:
                    self._mover(x, Zona.DEFENSA)
            return
        for x in atacantes:
            if x.en_juego:
                hab.disparar_con_armas(self, x, "al_atacar", declaracion=False)
        hab.disparar_ataque_propio(self, a)  # Coliseo: roba por cada atacante

        self.e.fase = "declaracion_bloqueo"
        bloqueadores = [b for b in rival.defensa if not hab.tiene_estado(self, b, "no_puede_bloquear")]
        bloqueos: dict[int, Instancia] = {}
        # Bloqueos obligados por habilidades al atacar (Demoledor de Amon).
        for atk in atacantes:
            blk = self.bloqueo_forzado.get(atk.uid)
            if blk is not None and blk in bloqueadores and blk not in bloqueos.values():
                bloqueos[atk.uid] = blk
        # Retador: el atacante obliga a un Aliado oponente a bloquearlo.
        for atk in atacantes:
            if atk.uid in bloqueos:
                continue
            if hab.tiene_prop(self, atk, "retador") and atk.en_juego:
                libres = [b for b in bloqueadores if b not in bloqueos.values()]
                if libres:
                    bloqueos[atk.uid] = self.decide(a).elegir_objetivos(
                        self, a, libres, 1, {"accion": "destruir"}
                    )[0]

        libres = [b for b in bloqueadores if b not in bloqueos.values()]
        bloqueables = [
            x for x in atacantes if x.en_juego and x.uid not in bloqueos and any(self.puede_bloquear(x, b) for b in libres)
        ]
        # La decisión puede necesitar los bloqueos obligatorios ya asignados.
        self.bloqueos = dict(bloqueos)
        if bloqueables and libres:
            elegidos = self.decide(d).elegir_bloqueos(self, d, bloqueables, libres)
            for atk_uid, blk in elegidos.items():
                atk = next((x for x in bloqueables if x.uid == atk_uid), None)
                if atk is not None and blk in libres and self.puede_bloquear(atk, blk) and blk not in bloqueos.values():
                    bloqueos[atk_uid] = blk
        for blk in [b for b in libres if hab.tiene_estado(self, b, "debe_bloquear") and b not in bloqueos.values()]:
            for atk in atacantes:
                if atk.en_juego and atk.uid not in bloqueos and self.puede_bloquear(atk, blk):
                    bloqueos[atk.uid] = blk
                    self.anotar(f"J{d} debe bloquear con {blk.nombre}")
                    break
        for atk in [x for x in atacantes if x.en_juego and x.uid not in bloqueos
                    and hab.tiene_estado(self, x, "debe_ser_bloqueado")]:
            # Hacha Solar: el portador debe ser bloqueado (el defensor elige con cuál).
            libres_ahora = [b for b in libres if b not in bloqueos.values() and self.puede_bloquear(atk, b)]
            if libres_ahora:
                blk = max(libres_ahora, key=lambda b: hab.fuerza(self, b))
                bloqueos[atk.uid] = blk
                self.anotar(f"J{d} debe bloquear a {atk.nombre} con {blk.nombre}")
        if not bloqueos and hab.prohibido(self, "bloqueo_obligatorio", d):
            # Laberinto de Creta: el defensor debe bloquear con al menos un Aliado.
            pares = [(x, b) for x in bloqueables for b in libres if self.puede_bloquear(x, b)]
            if pares:
                atk, blk = max(pares, key=lambda par: hab.fuerza(self, par[1]))
                bloqueos[atk.uid] = blk
                self.anotar(f"J{d} debe bloquear (Laberinto de Creta)")
        # Ventana impresa de Declaración de Bloqueo: aquí se juega, por
        # ejemplo, Demonio de Piedra. Exponer el mapa antes de abrirla permite
        # que sus objetivos sean exactamente los Aliados ya bloqueados.
        self.bloqueos = dict(bloqueos)
        self._ventana_activadas(d, "declaracion_bloqueo")
        bloqueos = dict(self.bloqueos)
        self._resolver_bloqueos(atacantes, bloqueos, d)

    def ataco_este_turno_inst(self, i: int) -> list[Instancia]:
        """Aliados de `i` en juego que fueron declarados atacantes este turno."""
        return [x for x in self.j(i).aliados if x.uid in self.ataco_este_turno]

    def puede_bloquear(self, atacante: Instancia, bloqueador: Instancia) -> bool:
        if hab.bloqueo_prohibido(self, atacante, bloqueador):
            return False  # Melisende: no la bloquean Aliados de fuerza 3 o más
        imb = hab.tiene_prop(self, atacante, "imbloqueable") or hab.tiene_estado(self, atacante, "no_puede_ser_bloqueado")
        return not imb or hab.tiene_estado(self, bloqueador, "puede_bloquear_imbloqueables")

    def _resolver_bloqueos(self, atacantes: list[Instancia],
                            bloqueos: dict[int, Instancia], defensor: int) -> None:
        d = defensor
        self.bloqueos = bloqueos
        for atk_uid, blk in bloqueos.items():
            atk = next((x for x in atacantes if x.uid == atk_uid), None)
            self.anotar(f"J{d} bloquea a {atk.nombre if atk else '?'} con {blk.nombre}")
            hab.disparar_con_armas(self, blk, "al_bloquear")
            if atk is not None:
                hab.disparar_con_armas(self, atk, "al_ser_bloqueado")

        self.e.fase = "guerra_talismanes"
        self._guerra_de_talismanes(d)
        self._tras_guerra(atacantes, bloqueos, d)

    def _tras_guerra(self, atacantes: list[Instancia],
                     bloqueos: dict[int, Instancia], defensor: int) -> None:
        """Lo que sigue a la Guerra de Talismanes: daño y destrucciones del
        combate. Separado para que la búsqueda pueda continuar desde ahí."""
        d = defensor
        hab.expirar(self, "hasta_guerra_talismanes")
        if self.ataque_cancelado:
            self.anotar("El ataque fue cancelado")
            for x in atacantes:
                if x.zona == Zona.ATAQUE:
                    self._mover(x, Zona.DEFENSA)
            return

        self.e.fase = "asignacion_dano"
        # Respuestas de Asignación de Daño, como Olabisi. Se resuelven antes
        # de calcular el daño que llegará al Mazo Castillo.
        self._ventana_activadas(d, "asignacion_dano")
        dano = 0
        hicieron: list[Instancia] = []
        aporte: dict[int, int] = {}
        destruidos: list[Instancia] = []
        for atk in atacantes:
            if atk.zona != Zona.ATAQUE:
                continue
            fa = hab.fuerza(self, atk)
            hace_dano = not hab.tiene_estado(self, atk, "aliado_sin_dano")
            blk = bloqueos.get(atk.uid)
            if (blk is None or not blk.en_juego) and hab.atacante_libre_fuerza_1(self, d):
                fa = min(fa, 1)  # Macda Tho en la Línea de Defensa
            if blk is None or not blk.en_juego:
                if hace_dano and fa > 0:
                    dano += fa
                    hicieron.append(atk)
                    aporte[atk.uid] = fa
                continue
            fb = hab.fuerza(self, blk)
            if fa > fb:
                if hace_dano:
                    dano += fa - fb
                    hicieron.append(atk)
                    aporte[atk.uid] = fa - fb
                destruidos.append(blk)
            elif fa == fb:
                destruidos += [atk, blk]
            else:
                destruidos.append(atk)
        if dano:
            dano = hab.ventana_reducir_dano(self, d, dano)
        if dano:
            self.anotar(f"J{d} recibe {dano} de daño")
            self.dano_hecho.update(x.uid for x in hicieron)
            antes = len(self.j(d).cementerio)
            self.botar(d, dano, causa="combate")
            destierra = sum(aporte.get(x.uid, 0) for x in hicieron if hab.dano_destierra(self, x))
            if destierra:  # Seth: esas cartas se destierran en vez de ir al Cementerio
                for x in self.j(d).cementerio[antes:antes + destierra]:
                    self._mover(x, Zona.DESTIERRO)
                self.anotar(f"J{d} destierra {destierra} cartas del daño de combate")
            for x in hicieron:
                if x.en_juego:
                    self.ctx_dano = aporte.get(x.uid, 0)
                    hab.disparar_con_armas(self, x, "al_hacer_dano")
            self.ctx_dano = 0
        if destruidos:
            self._grupo = []
            self._grupo_fuente = None
            for x in destruidos:
                if x.en_juego:
                    self.destruir(x, combate=True)
            self._cerrar_grupo()

    def _ventana_declaracion_ataque(self, defensor: int, *, solo_canceladores: bool = False) -> None:
        """Cartas de la fase Declaración de Ataque: primero el atacante (Escudo
        Miliciano desde su Cementerio en un atacante), después el defensor
        (canceladores como Flechas de Lava). Con `solo_canceladores`, solo el
        defensor y solo lo que cancela el ataque."""
        for quien in ((defensor,) if solo_canceladores else (1 - defensor, defensor)):
            for _ in range(5):
                if self.e.terminada or self.ataque_cancelado:
                    return
                opciones = [
                    o for o in self.jugadas_legales(quien, "declaracion_ataque") if o.tipo != "oro"
                    and (not solo_canceladores or o.tipo == "pasar" or _cancela_ataque(o))
                ]
                if solo_canceladores and len(opciones) <= 1:
                    break
                elegida = self.decide(quien).elegir_jugada(self, quien, opciones)
                if elegida.tipo == "pasar":
                    break
                self.ejecutar_jugada(quien, elegida)

    def _guerra_de_talismanes(self, defensor: int) -> None:
        turno = defensor
        pases = 0
        for _ in range(40):
            if pases >= 2 or self.e.terminada:
                return
            opciones = self.jugadas_legales(turno, "guerra_talismanes")
            elegida = self.decide(turno).elegir_jugada(self, turno, opciones)
            if elegida.tipo == "pasar":
                pases += 1
            else:
                pases = 0
                self.ejecutar_jugada(turno, elegida)
            turno = 1 - turno

    # ── Movimientos entre zonas ──────────────────────────────────────────────
    def _sacar(self, inst: Instancia) -> None:
        if inst.zona == Zona.PORTADA:
            if inst in self.e.portadas:
                self.e.portadas.remove(inst)
            inst.portador = None
            return
        lista = self.j(inst.controlador).lista(inst.zona)
        if inst in lista:
            lista.remove(inst)
        else:  # puede estar en una zona del dueño (mazo, mano, cementerio…)
            lista = self.j(inst.dueno).lista(inst.zona)
            if inst in lista:
                lista.remove(inst)

    def _mover(self, inst: Instancia, zona: Zona, *, al_tope: bool = True) -> None:
        """Mueve sin disparar habilidades. Fuera del juego vuelve al dueño."""
        estaba_en_juego = inst.en_juego
        if not inst.en_juego or zona not in (Zona.RESERVA, Zona.PAGADO, Zona.DEFENSA, Zona.ATAQUE, Zona.APOYO):
            inst.control = None
        self._sacar(inst)
        if zona in (Zona.RESERVA, Zona.PAGADO, Zona.DEFENSA, Zona.ATAQUE, Zona.APOYO):
            destino = self.j(inst.controlador)
        else:
            inst.controlador = inst.dueno
            destino = self.j(inst.dueno)
        inst.zona = zona
        if zona != Zona.MANO:
            inst.revelada = False  # vuelve a ser secreta si sale de la mano
        if zona == Zona.MAZO and not al_tope:
            destino.mazo.append(inst)
        elif zona == Zona.MAZO:
            destino.mazo.insert(0, inst)
        else:
            destino.lista(zona).append(inst)
        if estaba_en_juego and not inst.en_juego:
            inst.mods.clear()
            inst.estados.clear()
            inst.sin_habilidad_hasta = None
            inst.listo = False
            # Las Armas portadas siguen a su portador (4.2.2).
            for arma in [a for a in self.e.portadas if a.portador == inst.uid]:
                self._mover(arma, zona if zona != Zona.MAZO else Zona.CEMENTERIO)

    def descartar(self, inst: Instancia) -> None:
        """Descarta desde la mano y dispara habilidades de descarte."""
        era_mano = inst.zona == Zona.MANO
        dueno = inst.dueno
        self._mover(inst, Zona.CEMENTERIO)
        if era_mano:
            self.descartadas_turno[dueno] += 1
            costo_anterior = getattr(self, "ctx_costo", None)
            try:
                hab.disparar(self, inst, "al_descartarse", forzar=True)
            finally:
                self.ctx_costo = costo_anterior

    def sale_del_juego(self, inst: Instancia, zona: Zona) -> None:
        """Saca una carta del juego y dispara 'al salir del juego'."""
        if not inst.en_juego:
            return
        armas = [a for a in self.e.portadas if a.portador == inst.uid]
        controlador = inst.controlador
        # Haquika sin habilidad al salir (Cleopatra se la quitó): ya no puede
        # devolver lo que robó, así que el control queda para siempre.
        if inst.sin_habilidad_hasta is not None:
            for x in self.e.instancias_en_juego():
                if x.control and x.control.get("fuente") == inst.uid and x.control.get("duracion") == "mientras_en_juego":
                    x.control["duracion"] = "permanente"
        # PYDO #8: Nefertiti sin habilidad por el Apophis no baraja al salir.
        sin_habilidad = inst.sin_habilidad_hasta is not None
        self._mover(inst, zona)
        if zona == Zona.MAZO:
            self.e.rng.shuffle(self.j(inst.dueno).mazo)
        if not sin_habilidad:
            hab.disparar(self, inst, "al_salir_del_juego", forzar=True)
        for arma in armas:
            hab.disparar(self, arma, "al_salir_del_juego", forzar=True)
        hab.refrescar_perdidas(self)
        hab.revisar_controles(self)  # Haquika sale con su habilidad: devuelve lo robado ya
        hab.disparar_salida(self, inst, controlador)

    def destruir(self, inst: Instancia, *, combate: bool = False) -> bool:
        if not inst.en_juego or hab.tiene_prop(self, inst, "indestructible") or hab.no_puede_salir(self, inst):
            return False
        if hab.prevenir(self, inst, combate=combate, destruir=True):
            return False
        self.anotar(f"{inst.nombre} es destruido" + (" en combate" if combate else ""))
        if inst.tipo == Tipo.ALIADO:
            self.aliados_destruidos_turno += 1
        self.sale_del_juego(inst, Zona.CEMENTERIO)
        # Crom Dubh y cartas equivalentes distinguen destrucción de cualquier
        # otra forma de salir (destierro, barajar o subir a la mano).
        hab.disparar(self, inst, "al_ser_destruido", forzar=True)
        return True

    def desterrar(self, inst: Instancia) -> bool:
        if hab.tiene_prop(self, inst, "indesterrable") or hab.no_puede_salir(self, inst):
            return False
        if inst.en_juego:
            if hab.prevenir(self, inst):
                return False
            self.anotar(f"{inst.nombre} es desterrado")
            self.sale_del_juego(inst, Zona.DESTIERRO)
        else:
            self._mover(inst, Zona.DESTIERRO)
        return True

    # ── Robar / botar / fin del juego ────────────────────────────────────────
    def robar(self, i: int, n: int, *, inicial: bool = False, desde_fondo: bool = False,
              fuente: str | None = None) -> None:
        jug = self.j(i)
        # Shay: "sólo puedes robar cartas de la parte inferior de tu Mazo Castillo".
        desde_fondo = desde_fondo or (not inicial and hab.prohibido(self, "robar_fondo", i))
        for _ in range(n):
            if not jug.mazo:
                self._perder([i], "robo")
                return
            inst = jug.mazo.pop(-1 if desde_fondo else 0)
            inst.zona = Zona.MANO
            jug.mano.append(inst)
            if not inicial:
                self.robadas[i].add(inst.nombre)
                if fuente:
                    # Forma de Lince / Guerrero Escorpión en la Fase Final: no es el robo del turno.
                    self.anotar(f"{fuente}: J{i} roba {inst.nombre}")
                elif self.e.fase == "final":
                    self.anotar(f"J{i} finaliza: roba {inst.nombre}")
                else:
                    self.anotar(f"J{i} roba {inst.nombre}")
        self._comprobar_mazos("robo")

    def botar(self, i: int, n: int, *, causa: str = "botar") -> None:
        jug = self.j(i)
        for _ in range(n):
            if not jug.mazo:
                break
            inst = jug.mazo.pop(0)
            inst.zona = Zona.CEMENTERIO
            jug.cementerio.append(inst)
        self.ultimo_dano[i] = causa
        self._comprobar_mazos(causa)

    def _comprobar_mazos(self, causa: str) -> None:
        vacios = [i for i in (0, 1) if not self.j(i).mazo]
        if vacios:
            self._perder(vacios, causa)

    def _perder(self, perdedores: list[int], causa: str) -> None:
        self.e.terminada = True
        if len(perdedores) == 2:
            self.e.ganador = -1
            self.e.causa = "empate"
        else:
            p = perdedores[0]
            self.e.ganador = 1 - p
            self.e.causa = self.ultimo_dano.get(p) or causa
        self.anotar(f"Fin: ganador {self.e.ganador} ({self.e.causa})")
        raise FinPartida()
