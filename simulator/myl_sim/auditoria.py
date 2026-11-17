"""Auditoría automática de partidas: busca errores sin revisar a mano.

Corre lotes de partidas con un motor instrumentado y registra dos clases de
hallazgos:

- **regla**: invariantes del motor que nunca deberían romperse (una carta en
  dos zonas, una carta que desaparece, Oros virtuales negativos, mano sobre
  el máximo al cerrar el turno, excepciones del motor, partidas sin fin).
  Cualquiera de estos es un bug seguro.
- **jugada**: patrones sospechosos de la heurística (no jugar Oro pudiendo,
  no atacar con daño letal, no bloquear el ataque que mata, ataques que
  pierden el Aliado sin ganar nada…). No todos son errores: el informe los
  agrupa por patrón y carta y ordena por gravedad × frecuencia para que la
  revisión humana sea solo de los 10 primeros.

Cada hallazgo guarda la semilla y quién empezó; `repetir` reproduce la partida
exacta con la narración y marca dónde saltó el auditor.

Ejemplos (desde simulator/):
  .venv/Scripts/python -m myl_sim.auditoria lote <idA> <idB> [<idC> ...] -n 200 --cache
  .venv/Scripts/python -m myl_sim.auditoria lote --formato racial -n 100
  .venv/Scripts/python -m myl_sim.auditoria repetir <idA> <idB> --seed 900017 --inicial 1 --cache
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import itertools
import json
from pathlib import Path
import sys
import traceback

from . import habilidades as hab
from .modelo import Tipo, Zona
from .motor import MANO_MAXIMA, FinPartida, Partida, Registro

GRAVEDAD = {"alta": 3, "media": 2, "baja": 1}
REMOCIONES = {"destruir", "desterrar", "subirMano", "barajar", "ganarControl", "perderHabilidad"}
ZONAS_LISTA = [z for z in Zona if z != Zona.PORTADA]
FUERA_DE_JUEGO = {Zona.MAZO, Zona.MANO, Zona.CEMENTERIO, Zona.DESTIERRO}
# Castillo con margen: perder un Aliado bloqueando no se justifica por daño.
CASTILLO_HOLGADO = 12

DESCRIPCIONES = {
    # regla
    "carta_duplicada": "Una carta aparece en dos zonas a la vez",
    "zona_inconsistente": "La zona registrada de una carta no coincide con la lista donde está",
    "carta_perdida": "Una carta desapareció de todas las zonas",
    "dueno_incorrecto": "Carta fuera del juego en una zona de quien no es su dueño",
    "controlador_incorrecto": "Carta en juego en la mesa de quien no la controla",
    "tipo_en_zona_incorrecta": "Carta en una línea que no corresponde a su tipo",
    "arma_sin_portador": "Arma portada cuyo portador ya no está en juego",
    "oro_virtual_negativo": "Oros virtuales negativos",
    "mano_excedida": "Mano sobre el máximo al cerrar el turno",
    "jugada_no_ofrecida": "El jugador eligió una jugada que no estaba entre las legales",
    "excepcion_motor": "El motor lanzó una excepción",
    "partida_sin_fin": "La partida llegó al límite de turnos",
    # jugada
    "no_ataca_letal": "No atacó teniendo daño letal y el rival sin bloqueadores",
    "no_ataca_letal_con_respuesta": "No atacó con letal: el rival tenía en la mano un cancelador que podía pagar",
    "no_ataca_letal_por_riesgo": "No atacó con letal por riesgo de cancelador (el rival no lo tenía)",
    "no_bloquea_letal": "Perdió por daño de combate teniendo bloqueadores libres",
    "posible_autodano": "Perdió el castillo en su propio turno por un efecto (no combate ni robo)",
    "no_juega_oro": "Terminó la Vigilia sin jugar Oro teniendo uno jugable",
    "oro_temporal_sin_uso": "Generó Oro temporal y terminó la Vigilia sin gastarlo",
    "ataque_perdido": "Atacó, lo bloquearon, murió y el bloqueador sobrevivió",
    "bloqueo_perdido": "Bloqueó con castillo holgado, perdió el bloqueador y el atacante sobrevivió",
    "objetivo_menor": "Removió un objetivo rival de menor valor habiendo uno claramente mayor",
    "guarda_jugables": "Pasó la Vigilia con cartas jugables y Oro sin usar",
    "no_ataca_mesa_vacia": "No atacó con el rival sin Aliados para bloquear",
}
GRAVEDAD_PATRON = {
    "carta_duplicada": "alta", "zona_inconsistente": "alta", "carta_perdida": "alta",
    "dueno_incorrecto": "alta", "controlador_incorrecto": "alta",
    "tipo_en_zona_incorrecta": "alta", "arma_sin_portador": "alta",
    "oro_virtual_negativo": "alta", "mano_excedida": "alta",
    "jugada_no_ofrecida": "alta", "excepcion_motor": "alta", "partida_sin_fin": "alta",
    "no_ataca_letal": "alta", "no_bloquea_letal": "alta",
    "posible_autodano": "media", "no_ataca_letal_con_respuesta": "baja",
    "no_ataca_letal_por_riesgo": "media", "no_juega_oro": "media", "oro_temporal_sin_uso": "media",
    "ataque_perdido": "media", "bloqueo_perdido": "baja", "objetivo_menor": "baja",
    "guarda_jugables": "baja", "no_ataca_mesa_vacia": "baja",
}
TIPO_PATRON = {k: ("regla" if k in {
    "carta_duplicada", "zona_inconsistente", "carta_perdida", "dueno_incorrecto",
    "controlador_incorrecto", "tipo_en_zona_incorrecta", "arma_sin_portador",
    "oro_virtual_negativo", "mano_excedida", "jugada_no_ofrecida", "excepcion_motor",
    "partida_sin_fin"} else "jugada") for k in DESCRIPCIONES}


@dataclass
class Hallazgo:
    patron: str
    lado: int  # jugador que cometió el error (o -1 si es del motor)
    carta: str
    turno: int
    fase: str
    detalle: str
    tipo: str = ""
    gravedad: str = ""

    def __post_init__(self):
        self.tipo = self.tipo or TIPO_PATRON.get(self.patron, "jugada")
        self.gravedad = self.gravedad or GRAVEDAD_PATRON.get(self.patron, "baja")


def valor(inst) -> int:
    """Valor aproximado de una carta en mesa para comparar objetivos."""
    return int(inst.carta.coste or 0) + max(0, int(inst.carta.fuerza or 0))


# ── Invariantes ───────────────────────────────────────────────────────────────
def invariantes(p: Partida, uids_iniciales: set[int] | None = None) -> list[tuple[str, str, str]]:
    """Devuelve (patrón, carta, detalle) por cada invariante roto en este momento."""
    out: list[tuple[str, str, str]] = []
    vistos: dict[int, str] = {}
    for j in p.e.jugadores:
        for zona in ZONAS_LISTA:
            for inst in j.lista(zona):
                lugar = f"J{j.indice}.{zona.value}"
                if inst.uid in vistos:
                    out.append(("carta_duplicada", inst.nombre, f"en {vistos[inst.uid]} y {lugar}"))
                    continue
                vistos[inst.uid] = lugar
                if inst.zona != zona:
                    out.append(("zona_inconsistente", inst.nombre,
                                f"está en {lugar} pero su zona dice {inst.zona.value}"))
                if zona in FUERA_DE_JUEGO and inst.dueno != j.indice:
                    out.append(("dueno_incorrecto", inst.nombre, f"{lugar}, dueño J{inst.dueno}"))
                if zona not in FUERA_DE_JUEGO and inst.controlador != j.indice:
                    out.append(("controlador_incorrecto", inst.nombre,
                                f"{lugar}, controlador J{inst.controlador}"))
                if zona in (Zona.DEFENSA, Zona.ATAQUE) and inst.tipo != Tipo.ALIADO:
                    out.append(("tipo_en_zona_incorrecta", inst.nombre, f"{inst.tipo.value} en {lugar}"))
                if zona in (Zona.RESERVA, Zona.PAGADO) and inst.tipo != Tipo.ORO:
                    out.append(("tipo_en_zona_incorrecta", inst.nombre, f"{inst.tipo.value} en {lugar}"))
        if j.oros_virtuales < 0:
            out.append(("oro_virtual_negativo", "", f"J{j.indice}: {j.oros_virtuales}"))
    aliados_en_juego = {a.uid for j in p.e.jugadores for a in j.aliados}
    for arma in p.e.portadas:
        if arma.uid in vistos:
            out.append(("carta_duplicada", arma.nombre, f"portada y en {vistos[arma.uid]}"))
        vistos[arma.uid] = "portada"
        if arma.zona != Zona.PORTADA:
            out.append(("zona_inconsistente", arma.nombre, f"portada con zona {arma.zona.value}"))
        if arma.portador not in aliados_en_juego:
            out.append(("arma_sin_portador", arma.nombre, f"portador uid {arma.portador}"))
    if uids_iniciales is not None:
        faltan = uids_iniciales - set(vistos)
        if faltan:
            out.append(("carta_perdida", "", f"{len(faltan)} carta(s) sin zona: uids {sorted(faltan)[:5]}"))
    return out


# ── Jugador observado ─────────────────────────────────────────────────────────
class Observado:
    """Envuelve a un jugador: delega todo y mira cada decisión."""

    def __init__(self, interno, yo: int, partida: "PartidaAuditada"):
        self._interno = interno
        self._yo = yo
        self._p = partida
        self._genero_oro_turno: int | None = None
        self._genero_oro_carta = ""

    def __getattr__(self, nombre):
        return getattr(self._interno, nombre)

    def elegir_jugada(self, p, yo, jugadas):
        self._p.revisar("decision")
        elegida = self._interno.elegir_jugada(p, yo, jugadas)
        if elegida not in jugadas:
            self._p.registrar("jugada_no_ofrecida", -1, str(elegida), f"opciones: {len(jugadas)}")
        if p.e.fase == "vigilia" and yo == p.e.activo:
            jug = p.j(yo)
            if elegida.tipo == "activar" and elegida.carta is not None:
                h = elegida.carta.habilidades[elegida.habilidad] if elegida.habilidad is not None \
                    and elegida.habilidad < len(elegida.carta.habilidades) else {}
                if h.get("accion") == "generarOro":
                    self._genero_oro_turno = p.e.turno
                    self._genero_oro_carta = elegida.carta.nombre
            if elegida.tipo == "pasar":
                oros = sorted({o.carta.nombre for o in jugadas if o.tipo == "oro"})
                if oros:
                    self._p.registrar("no_juega_oro", yo, oros[0],
                                      f"Oros jugables en mano: {', '.join(oros)}")
                if self._genero_oro_turno == p.e.turno and jug.oros_virtuales > 0:
                    self._p.registrar("oro_temporal_sin_uso", yo, self._genero_oro_carta,
                                      f"quedaron {jug.oros_virtuales} Oro(s) temporales")
                # Los Talismanes se guardan a propósito como respuesta: solo
                # cuenta lo que se baja a la mesa (Aliados, Tótems, Armas).
                jugables = sorted({o.carta.nombre for o in jugadas if o.tipo == "jugar" and o.carta
                                   and o.carta.tipo != Tipo.TALISMAN})
                if jugables and jug.oro_disponible > 0:
                    for nombre in jugables:
                        self._p.registrar("guarda_jugables", yo, nombre,
                                          f"Oro disponible {jug.oro_disponible}; jugables: {', '.join(jugables)}")
        return elegida

    def elegir_atacantes(self, p, yo, candidatos):
        self._p.revisar("decision")
        elegidos = self._interno.elegir_atacantes(p, yo, candidatos)
        analisis = getattr(self._interno, "ultimo_analisis", None)
        if analisis and analisis.get("turno") == p.e.turno:
            # Por qué atacó así: estimación de cada alternativa simulada.
            ops = sorted(analisis["opciones"], key=lambda o: -o["estimacion"])[:4]
            self._p.motivo_ataque[(yo, p.e.turno)] = "búsqueda: " + " · ".join(
                f"{'+'.join(o['atacantes']) or 'no atacar'} {o['estimacion'] * 100:.0f}%"
                + (" ✔" if o["elegida"] else "") + (" (heurística)" if o["heuristica"] else "")
                for o in ops)
        rival = p.j(1 - yo)
        bloqueadores = [b for b in rival.defensa if not hab.tiene_estado(p, b, "no_puede_bloquear")]
        puede_bloquear = any(p.puede_bloquear(c, b) for c in candidatos for b in bloqueadores)
        total = sum(max(0, hab.fuerza(p, c)) for c in candidatos)
        elegido = sum(max(0, hab.fuerza(p, c)) for c in (elegidos or []))
        castillo = len(rival.mazo)
        if not puede_bloquear and total >= castillo and elegido < castillo:
            from .jugadores import _UMBRAL_CANCELADOR_LETAL, _defensivo, _prob_cancelador_con_bote

            # Si el rival tenía en la mano un cancelador que podía pagar
            # (Flechas de Lava), no atacar fue correcto: queda como dato. Si no
            # lo tenía pero por lo visto era probable, es una decisión con
            # riesgo, no un error grave. Con 1 carta de castillo no atacar
            # pierde igual: ahí siempre es error.
            patron = "no_ataca_letal"
            if len(p.j(yo).mazo) > 1:
                if any(_defensivo(c) and p.coste_de(1 - yo, c) <= rival.oro_disponible for c in rival.mano):
                    patron = "no_ataca_letal_con_respuesta"
                elif _prob_cancelador_con_bote(p, yo) >= _UMBRAL_CANCELADOR_LETAL:
                    patron = "no_ataca_letal_por_riesgo"
            self._p.registrar(
                patron, yo, max(candidatos, key=lambda c: hab.fuerza(p, c)).nombre,
                f"fuerza disponible {total} ≥ castillo rival {castillo}; atacó con {elegido}")
        elif not bloqueadores and candidatos and not elegidos:
            self._p.registrar("no_ataca_mesa_vacia", yo, candidatos[0].nombre,
                              f"{len(candidatos)} posible(s) atacante(s), fuerza {total}")
        return elegidos

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        self._p.revisar("decision")
        self._p.ofrecido_bloqueo = {
            "turno": p.e.turno, "castillo": len(p.j(yo).mazo),
            "atacantes": {a.uid: hab.fuerza(p, a) for a in atacantes},
            "bloqueadores": [(b, hab.fuerza(p, b)) for b in bloqueadores],
        }
        return self._interno.elegir_bloqueos(p, yo, atacantes, bloqueadores)

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        elegidos = self._interno.elegir_objetivos(p, yo, candidatos, n, h)
        accion = (h or {}).get("accion")
        if accion in REMOCIONES and elegidos:
            rivales = [c for c in candidatos if getattr(c, "controlador", yo) != yo
                       and getattr(c, "en_juego", False)]
            elegidos_rivales = [c for c in elegidos if c in rivales]
            if elegidos_rivales and len(elegidos_rivales) == len(elegidos):
                resto = [c for c in rivales if c not in elegidos]
                if resto:
                    mejor = max(resto, key=valor)
                    peor = min(elegidos_rivales, key=valor)
                    if valor(mejor) >= valor(peor) + 3:
                        self._p.registrar(
                            "objetivo_menor", yo, self._p.ultima_fuente[yo] or accion,
                            f"{accion}: eligió {peor.nombre} (valor {valor(peor)}) "
                            f"y dejó {mejor.nombre} (valor {valor(mejor)})")
        return elegidos


# ── Partida instrumentada ─────────────────────────────────────────────────────
class PartidaAuditada(Partida):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.hallazgos: list[Hallazgo] = []
        self._vistos: set[tuple] = set()
        self.ultima_fuente = ["", ""]
        self.ofrecido_bloqueo: dict | None = None
        self.motivo_ataque: dict = {}
        self.uids_iniciales = {inst.uid for j in self.e.jugadores for z in ZONAS_LISTA for inst in j.lista(z)}
        self.jugadores = tuple(Observado(x, k, self) for k, x in enumerate(self.jugadores))

    # Registro ────────────────────────────────────────────────────────────────
    def registrar(self, patron: str, lado: int, carta: str, detalle: str) -> None:
        # Una vez por partida, patrón, lado y carta (y turno en las de jugada):
        # evita que un mismo bug llene el informe.
        clave = (patron, lado, carta) if TIPO_PATRON.get(patron) == "regla" \
            else (patron, lado, carta, self.e.turno)
        if clave in self._vistos:
            return
        self._vistos.add(clave)
        h = Hallazgo(patron, lado, carta, self.e.turno, self.e.fase, detalle)
        self.hallazgos.append(h)
        if self.e.log is not None:
            quien = f"J{lado} " if lado in (0, 1) else ""
            self.e.log.append(f"T{self.e.turno} [{self.e.fase}] ⚠ AUDITOR {h.gravedad}: "
                              f"{quien}{DESCRIPCIONES.get(patron, patron)} · {carta} · {detalle}")

    def revisar(self, momento: str) -> None:
        for patron, carta, detalle in invariantes(self, self.uids_iniciales):
            self.registrar(patron, -1, carta, f"{momento}: {detalle}")

    # Ganchos del motor ─────────────────────────────────────────────────────────
    def ejecutar_jugada(self, i, jugada):
        if jugada.carta is not None and jugada.tipo != "pasar":
            self.ultima_fuente[i] = jugada.carta.nombre
        return super().ejecutar_jugada(i, jugada)

    def _cerrar_turno(self, a: int) -> None:
        if len(self.j(a).mano) > MANO_MAXIMA:
            self.registrar("mano_excedida", -1, "", f"J{a} cierra con {len(self.j(a).mano)} cartas")
        self.revisar("fin de turno")
        super()._cerrar_turno(a)

    def botar(self, i, n, *, causa="botar"):
        self.turno_bote = getattr(self, "turno_bote", {})
        self.turno_bote[i] = self.e.turno
        return super().botar(i, n, causa=causa)

    def _perder(self, perdedores, causa):
        if len(perdedores) == 1:
            p = perdedores[0]
            real = self.ultimo_dano.get(p) or causa
            if causa == "robo" and getattr(self, "turno_bote", {}).get(p) != self.e.turno:
                real = "robo"  # robo obligatorio con el castillo ya agotado por turnos anteriores
            if p == self.e.activo and real not in ("combate", "robo") and not self.e.terminada:
                self.registrar("posible_autodano", p, self.ultima_fuente[p] or "?",
                               f"causa '{real}' en su propio turno")
        super()._perder(perdedores, causa)

    def _batalla(self, a: int) -> None:
        d = 1 - a
        defensa_previa = list(self.j(d).defensa)
        try:
            super()._batalla(a)
        finally:
            self._revisar_combate(a, d, defensa_previa)

    def _revisar_combate(self, a: int, d: int, defensa_previa: list) -> None:
        atacantes = list(self.atacantes)
        if not atacantes:
            return
        bloqueos = dict(self.bloqueos)
        usados = set(id(b) for b in bloqueos.values())
        of = self.ofrecido_bloqueo
        if self.e.terminada and self.e.ganador == a and self.e.causa == "combate" \
                and of is not None and of["turno"] == self.e.turno:
            from .jugadores import _castigo_si_lo_bloquean

            # Fuerza al final del combate (con lo que subieron en la Guerra de
            # Talismanes); los bloqueadores, con la que tenían al bloquear.
            def fa(x):
                return max(0, hab.fuerza(self, x)) if x.en_juego else of["atacantes"].get(x.uid, 0)

            fuerza_blk = {id(b): f for b, f in of["bloqueadores"]}
            libres = [(b, f) for b, f in of["bloqueadores"] if id(b) not in usados]
            sin_bloquear = [x for x in atacantes if x.uid not in bloqueos and x.uid in of["atacantes"]]
            dano = sum(fa(x) for x in sin_bloquear) + sum(
                max(0, fa(x) - fuerza_blk.get(id(bloqueos[x.uid]), 0))
                for x in atacantes if x.uid in bloqueos)
            mejor, par = 0, None
            for x in sin_bloquear:
                castigo = _castigo_si_lo_bloquean(self, x)  # Ramsés II: bloquearlo también bota
                for b, fb in libres:
                    if self.puede_bloquear(x, b):
                        evita = fa(x) - max(0, fa(x) - fb) - castigo
                        if evita > mejor:
                            mejor, par = evita, (x, b)
            # Solo cuando la cuenta del combate explica la derrota y bloquear
            # la evitaba (sin contar efectos "al hacer daño").
            if par and dano >= of["castillo"] and dano - mejor < of["castillo"]:
                self.registrar("no_bloquea_letal", d, par[1].nombre,
                               f"castillo {of['castillo']}, daño {dano}; bloquear a {par[0].nombre} "
                               f"con {par[1].nombre} evitaba {mejor} y sobrevivía")
            return
        if self.e.terminada:
            return
        # Un ataque masivo que hizo daño, o un Aliado que gana algo al morir o
        # salir (o errante, que vuelve a jugarse), no cuentan como pérdida.
        dano_hecho = bool(self.dano_hecho)
        for atk in atacantes:
            blk = bloqueos.get(atk.uid)
            if blk is None:
                continue
            gana_al_morir = hab.tiene_prop(self, atk, "errante") or any(
                h.get("cuando") in ("al_salir_del_juego", "al_ser_destruido", "propia_sale")
                for h in atk.carta.habilidades)
            if not atk.en_juego and blk.en_juego and not gana_al_morir \
                    and not (dano_hecho and len(atacantes) > 1):
                motivo = self.motivo_ataque.get((a, self.e.turno))
                self.registrar("ataque_perdido", a, atk.nombre, f"bloqueado por {blk.nombre}"
                               + (f"; {motivo}" if motivo else ""))
            elif not blk.en_juego and atk.en_juego and len(self.j(d).mazo) > CASTILLO_HOLGADO \
                    and atk.uid not in self.bloqueo_forzado \
                    and not hab.tiene_prop(self, atk, "retador"):
                self.registrar("bloqueo_perdido", d, blk.nombre,
                               f"bloqueó a {atk.nombre} con castillo {len(self.j(d).mazo)}")

    def jugar(self) -> Registro:
        try:
            r = super().jugar()
        except Exception as ex:  # el motor no debería romperse nunca
            ultimo = traceback.extract_tb(ex.__traceback__)[-1]
            self.registrar("excepcion_motor", -1, self.ultima_fuente[self.e.activo] or "?",
                           f"{type(ex).__name__}: {ex} ({Path(ultimo.filename).name}:{ultimo.lineno})")
            return Registro(ganador=-2, inicial=self.inicial, turnos=self.e.turno, causa="excepcion",
                            jugadas=self.jugadas, robadas=self.robadas,
                            sin_programar_usadas=self.sin_programar)
        if r.ganador == -2:
            self.registrar("partida_sin_fin", -1, "", f"causa {r.causa}")
        return r


# ── Lotes ─────────────────────────────────────────────────────────────────────
def crear_partida(mazo_a, mazo_b, seed: int, inicial: int, *, log: bool = False,
                  jugador: str = "heuristico") -> PartidaAuditada:
    """Misma receta para el lote y para `repetir`: la partida es reproducible."""
    from .jugadores import JUGADORES

    clase = JUGADORES[jugador]
    return PartidaAuditada(
        (mazo_a.cartas, mazo_b.cartas),
        (clase(seed * 2), clase(seed * 2 + 1)),
        nombres=(mazo_a.nombre, mazo_b.nombre),
        inicial=inicial,
        seed=seed,
        log=log,
    )


def auditar_cruce(mazo_a, mazo_b, n: int, *, seed: int = 900001,
                  jugador: str = "heuristico", meta: list | None = None) -> dict:
    hallazgos: list[dict] = []
    victorias = Counter()
    for k in range(n):
        s, inicial = seed + k, k % 2
        p = crear_partida(mazo_a, mazo_b, s, inicial, jugador=jugador)
        if meta is not None:
            p.meta_listas = meta  # la IA estima la mano rival con las listas del lote
        r = p.jugar()
        victorias[r.ganador] += 1
        nombres = (mazo_a.nombre, mazo_b.nombre)
        for h in p.hallazgos:
            d = asdict(h)
            d.update({
                "seed": s, "inicial": inicial,
                "mazoA": {"id": mazo_a.id, "nombre": mazo_a.nombre},
                "mazoB": {"id": mazo_b.id, "nombre": mazo_b.nombre},
                "mazo": nombres[h.lado] if h.lado in (0, 1) else "(motor)",
                "rival": nombres[1 - h.lado] if h.lado in (0, 1) else "",
            })
            hallazgos.append(d)
    return {"partidas": n, "victorias": {str(k): v for k, v in victorias.items()},
            "hallazgos": hallazgos}


def agrupar(hallazgos: list[dict], partidas_por_mazo: Counter) -> list[dict]:
    """Agrupa por (patrón, mazo, carta) y ordena por gravedad × frecuencia."""
    grupos: dict[tuple, dict] = {}
    partidas: dict[tuple, set] = defaultdict(set)
    for h in hallazgos:
        clave = (h["patron"], h["mazo"], h["carta"])
        g = grupos.setdefault(clave, {
            "patron": h["patron"], "tipo": h["tipo"], "gravedad": h["gravedad"],
            "descripcion": DESCRIPCIONES.get(h["patron"], h["patron"]),
            "mazo": h["mazo"], "carta": h["carta"], "veces": 0, "ejemplos": [],
            "rivales": Counter(), "turnos": Counter(),
        })
        g["veces"] += 1
        g["rivales"][h["rival"] or "-"] += 1
        g["turnos"][h["turno"]] += 1
        partidas[clave].add((h["mazoA"]["id"], h["mazoB"]["id"], h["seed"]))
        if len(g["ejemplos"]) < 3:
            g["ejemplos"].append({k: h[k] for k in ("seed", "inicial", "turno", "fase", "detalle")}
                                 | {"a": h["mazoA"]["id"], "b": h["mazoB"]["id"]})
    out = []
    for clave, g in grupos.items():
        g["partidasAfectadas"] = len(partidas[clave])
        base = partidas_por_mazo.get(g["mazo"]) or max(partidas_por_mazo.values() or [1])
        g["tasa"] = round(g["partidasAfectadas"] / base, 4)
        # Los bugs de regla van siempre arriba; luego gravedad × frecuencia.
        g["puntaje"] = round((10 if g["tipo"] == "regla" else 1) * GRAVEDAD[g["gravedad"]] * g["tasa"], 5)
        g["rivales"] = dict(g["rivales"].most_common(5))
        g["turnos"] = dict(sorted(g["turnos"].items())[:12])
        out.append(g)
    # Bugs de regla primero; después por gravedad y, dentro, por frecuencia.
    return sorted(out, key=lambda g: (g["tipo"] != "regla", -GRAVEDAD[g["gravedad"]],
                                      -g["tasa"], -g["veces"]))


def _cruce_en_proceso(args):
    a, b, n, seed, jugador, meta = args
    return auditar_cruce(a, b, n, seed=seed, jugador=jugador, meta=meta)


def auditar_lote(mazos: list, n: int, *, seed: int = 900001, progreso=None,
                 procesos: int | None = None, jugador: str = "heuristico") -> dict:
    """Todos los cruces entre `mazos` (cada par una vez, con asientos alternados).

    `procesos`: núcleos a usar (por defecto todos). Cada cruce tiene su semilla
    fija, así que el resultado no depende de cuántos núcleos se usen."""
    import os
    from concurrent.futures import ProcessPoolExecutor

    hallazgos: list[dict] = []
    por_mazo: Counter = Counter()
    pares = list(itertools.combinations(mazos, 2))
    meta = [m.cartas for m in mazos]
    trabajos = [(a, b, n, seed + idx * 10_007, jugador, meta) for idx, (a, b) in enumerate(pares)]
    procesos = procesos or os.cpu_count() or 1
    resultados: list = [None] * len(pares)
    if procesos <= 1 or len(pares) <= 1:
        for idx, t in enumerate(trabajos):
            resultados[idx] = _cruce_en_proceso(t)
            if progreso:
                progreso(idx + 1, len(pares), t[0].nombre, t[1].nombre, len(resultados[idx]["hallazgos"]))
    else:
        with ProcessPoolExecutor(max_workers=procesos) as ex:
            futuros = {ex.submit(_cruce_en_proceso, t): idx for idx, t in enumerate(trabajos)}
            from concurrent.futures import as_completed

            for hechos, fut in enumerate(as_completed(futuros), 1):
                idx = futuros[fut]
                resultados[idx] = fut.result()
                if progreso:
                    a, b = pares[idx]
                    progreso(hechos, len(pares), a.nombre, b.nombre, len(resultados[idx]["hallazgos"]))
    cruces = []
    for (a, b), r in zip(pares, resultados):
        hallazgos += r["hallazgos"]
        por_mazo[a.nombre] += n
        por_mazo[b.nombre] += n
        cruces.append({"a": a.nombre, "b": b.nombre, "partidas": n,
                       "hallazgos": len(r["hallazgos"]), "victorias": r["victorias"]})
    from .informe_entrenamiento import huella_motor
    from .datos import huella_mazo

    return {
        "esquema": 1,
        "creado": datetime.now(timezone.utc).isoformat(),
        "motorHuella": huella_motor(),
        "mazos": [{"id": m.id, "nombre": m.nombre, "huella": huella_mazo(m),
                   "sinProgramar": m.sin_programar()} for m in mazos],
        "partidasPorCruce": n,
        "seedInicial": seed,
        "cruces": cruces,
        "grupos": agrupar(hallazgos, por_mazo),
        "hallazgos": hallazgos,
    }


def informe_md(r: dict, top: int = 10) -> str:
    total = sum(c["partidas"] for c in r["cruces"])
    reglas = [g for g in r["grupos"] if g["tipo"] == "regla"]
    jugadas = [g for g in r["grupos"] if g["tipo"] == "jugada"]
    lineas = [
        f"# Auditoría automática · {r['creado'][:16].replace('T', ' ')}",
        "",
        f"{len(r['cruces'])} cruces · {total} partidas · motor `{r['motorHuella']}`",
        "",
        f"- Bugs de regla: **{sum(g['veces'] for g in reglas)}** en {len(reglas)} grupos",
        f"- Jugadas sospechosas: **{sum(g['veces'] for g in jugadas)}** en {len(jugadas)} grupos",
        "",
    ]
    pendientes = [m for m in r["mazos"] if m["sinProgramar"]]
    if pendientes:
        lineas += ["> Mazos con cartas sin programar (sus hallazgos pueden venir de eso): "
                   + ", ".join(f"{m['nombre']} ({sum(k for _, k in m['sinProgramar'])} copias)" for m in pendientes), ""]

    def bloque(titulo, grupos):
        if not grupos:
            return
        lineas.extend([f"## {titulo}", ""])
        for k, g in enumerate(grupos[:top], 1):
            lineas.append(f"### {k}. {g['descripcion']} · {g['carta'] or '—'} ({g['mazo']})")
            lineas.append(f"Gravedad {g['gravedad']} · {g['veces']} veces en {g['partidasAfectadas']} "
                          f"partidas ({g['tasa'] * 100:.1f} %) · rivales: "
                          + ", ".join(f"{n} ({c})" for n, c in g["rivales"].items()))
            e = g["ejemplos"][0]
            lineas.append(f"Ejemplo: turno {e['turno']} ({e['fase']}): {e['detalle']}")
            lineas.append(f"Repetir: `python -m myl_sim.auditoria repetir {e['a']} {e['b']} "
                          f"--seed {e['seed']} --inicial {e['inicial']} --cache`")
            lineas.append("")

    bloque("Bugs de regla (arreglar siempre)", reglas)
    bloque(f"Top {top} jugadas sospechosas", jugadas)
    return "\n".join(lineas)


# ── CLI ───────────────────────────────────────────────────────────────────────
def _cargar(ids: list[str], usar_cache: bool):
    from .datos import CACHE, Mazo, cargar_mazo, uid_por_email

    if usar_cache and all((CACHE / f"mazo_{i.removeprefix('notable:')}.json").exists() for i in ids):
        return [Mazo.from_json(json.loads((CACHE / f"mazo_{i.removeprefix('notable:')}.json")
                                          .read_text(encoding="utf-8"))) for i in ids]
    from .cli import DUENO

    uid = uid_por_email(DUENO)
    return [cargar_mazo(uid, i, usar_cache=usar_cache) for i in ids]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="myl_sim.auditoria", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    l = sub.add_parser("lote", help="auditar todos los cruces entre varios mazos")
    l.add_argument("ids", nargs="*", help="ids de mazo (o notable:<id>)")
    l.add_argument("--formato", help="usar todos tus mazos de este formato")
    l.add_argument("-n", type=int, default=100, help="partidas por cruce")
    l.add_argument("--seed", type=int, default=900001)
    l.add_argument("--top", type=int, default=10)
    l.add_argument("--procesos", type=int, help="núcleos a usar (por defecto todos)")
    l.add_argument("--jugador", default="heuristico", help="heuristico o busqueda_ataques")
    l.add_argument("--cache", action="store_true", help="usar mazos guardados en simulator/cache")
    l.add_argument("--salida", type=Path)
    rp = sub.add_parser("repetir", help="narrar una partida auditada exacta")
    rp.add_argument("a")
    rp.add_argument("b")
    rp.add_argument("--seed", type=int, required=True)
    rp.add_argument("--inicial", type=int, choices=(0, 1), default=0)
    rp.add_argument("--cache", action="store_true")
    rp.add_argument("--solo-auditor", action="store_true", help="mostrar solo líneas del auditor")
    args = ap.parse_args(argv)
    try:  # consola de Windows: que "⚠" y los acentos no rompan la salida
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    if args.cmd == "repetir":
        a, b = _cargar([args.a, args.b], args.cache)
        p = crear_partida(a, b, args.seed, args.inicial, log=True)
        r = p.jugar()
        for linea in p.e.log or []:
            if not args.solo_auditor or "⚠ AUDITOR" in linea:
                print(linea.replace("J0", a.nombre).replace("J1", b.nombre))
        print(f"\nGanador: {[a.nombre, b.nombre][r.ganador] if r.ganador in (0, 1) else 'empate/anómala'}"
              f" · {r.turnos} turnos · {r.causa} · {len(p.hallazgos)} hallazgos")
        return 0

    ids = list(args.ids)
    if args.formato:
        from .datos import listar_mazos, uid_por_email
        from .cli import DUENO

        ids += [did for did, _, fmt in listar_mazos(uid_por_email(DUENO)) if fmt == args.formato]
    if len(ids) < 2:
        ap.error("se necesitan al menos dos mazos")
    mazos = _cargar(ids, args.cache)

    def avance(k, total, a, b, nh):
        print(f"{k}/{total}  {a} vs {b}: {nh} hallazgos", flush=True)

    r = auditar_lote(mazos, args.n, seed=args.seed, progreso=avance, procesos=args.procesos,
                     jugador=args.jugador)
    from .datos import CACHE

    salida = args.salida or CACHE / "auditoria" / f"auditoria_{datetime.now():%Y%m%d_%H%M%S}.json"
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(r, ensure_ascii=False, indent=1), encoding="utf-8")
    md = informe_md(r, args.top)
    salida.with_suffix(".md").write_text(md, encoding="utf-8")
    print("\n" + md)
    print(f"\nInforme: {salida.with_suffix('.md')}\nDetalle: {salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
