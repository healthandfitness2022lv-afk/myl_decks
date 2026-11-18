"""Partida humana contra la IA, mediada por un documento de Firestore.

El motor sigue siendo síncrono. ``HumanoRemoto`` detiene ese hilo justo en
cada decisión y ``SesionDesafio`` publica las opciones legales; la app escribe
la respuesta y el hilo continúa. Así las reglas y las decisiones de la IA son
exactamente las mismas que en una simulación normal.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import time
import types
from typing import Any, Callable
from google.api_core.exceptions import DeadlineExceeded, ServiceUnavailable
from google.api_core.exceptions import RetryError

from . import habilidades as hab
from .busqueda_bloqueos import PoliticaConBusqueda
from .datos import CACHE
from .jugadores import Heuristico
from .politica_meta import jugador_para
from .modelo import Instancia, Zona
from .motor import Jugada, Partida
from .simulacion import _sin_ids_reservados, _solo_cambios


def reintentar_red(operacion):
    """Conserva la partida en memoria durante un corte temporal de Firestore."""
    while True:
        try:
            return operacion()
        except (DeadlineExceeded, ServiceUnavailable, RetryError):
            time.sleep(5)


def _carta(inst: Instancia, partida: Partida) -> dict[str, Any]:
    out = {
        "id": str(inst.uid),
        "cartaId": inst.carta.id,
        "nombre": inst.nombre,
        "tipo": inst.tipo.value,
        "fuerza": hab.fuerza(partida, inst) if inst.en_juego and inst.tipo.value == "Aliado" else None,
    }
    if inst.en_juego:
        out.update(_estado_habilidad(inst, partida))
    return out


def _estado_habilidad(inst: Instancia, partida: Partida) -> dict[str, Any]:
    """Lo que la mesa debe avisar de una carta en juego: que perdió su
    habilidad (y por quién: Cleopatra VII sobre los Titanes) o que ya usó su
    habilidad de «una vez por turno» (Damarchus)."""
    out: dict[str, Any] = {}
    if inst.carta.habilidades and not inst.habilidades:
        out["sinHabilidad"] = True
        fuente = next((x for x in partida.e.instancias_en_juego(0) + partida.e.instancias_en_juego(1)
                       if x.uid == inst.sin_habilidad_fuente), None) if inst.sin_habilidad_fuente else None
        if fuente is not None:
            out["sinHabilidadPor"] = fuente.nombre
        return out
    for k, h in enumerate(inst.habilidades):
        limite = int(h.get("limitePorTurno") or 0)
        if h.get("cuando") == "activada" and limite and hab.usos(partida, inst.controlador, inst, h, k) >= limite:
            out["usadaEsteTurno"] = True
            break
    return out


def _carta_mesa(inst: Instancia, partida: Partida) -> dict[str, Any]:
    """Un Aliado en la mesa con las Armas que porta (se ven sobre él)."""
    carta = _carta(inst, partida)
    armas = [_carta(a, partida) for a in partida.e.portadas if a.portador == inst.uid]
    if armas:
        carta["armas"] = armas
    return carta


_ROBO_IA = re.compile(r"J1 (?:finaliza: )?roba [^·]*")
_ACCIONES = ("juega", "ataca", "activa", "anula", "bloque", "destru", "bota", "destierr", "descarta",
             "previene", "cancela", "responde", "baraja", "pasa a control", "pierde", "gana", "busca",
             "sube", "mueve", "reduce", "debe")


_PRIVADO = re.compile(r"⟪J(\d)\|(.*?)⟫")


def texto_publico(texto: str, humano: int = 0) -> str:
    """Narración para la persona: sin revelar qué roba o mira la IA; J0/J1 → Tú/IA."""
    texto = _PRIVADO.sub(lambda m: m.group(2) if int(m.group(1)) == humano else "(oculto)", texto)
    texto = _ROBO_IA.sub("J1 roba una carta ", texto).strip()
    return texto.replace("J0", "Tú").replace("J1", "IA")


def _es_accion_ia(texto: str, partida: Partida) -> bool:
    """¿Hay que mostrar esta línea como jugada de la IA? Lo que hace en su
    turno y sus respuestas en el turno de la persona (no sus robos)."""
    t = _ROBO_IA.sub("", texto).lower()  # robar solo no es una jugada visible
    if partida.e.activo == 1:
        return any(a in t for a in _ACCIONES)
    return "J1" in texto and any(a in t for a in _ACCIONES)


def vista_desafio(partida: Partida, humano: int) -> dict[str, Any]:
    """Estado visible para la persona: jamás filtra la mano rival."""
    lados = []
    for i, jugador in enumerate(partida.e.jugadores):
        defensa = []
        for inst in jugador.defensa:
            carta = _carta_mesa(inst, partida)
            carta["puedeAtacar"] = (
                inst.listo and not hab.tiene_prop(partida, inst, "guardian")
                and not hab.tiene_estado(partida, inst, "no_puede_atacar")
            )
            defensa.append(carta)
        lados.append({
            "nombre": jugador.nombre_mazo,
            "castillo": len(jugador.mazo),
            # Reporte 5R9h: los Oros virtuales (Dragones) también se ven al pagar.
            "orosVirtuales": jugador.oros_virtuales + sum(max(0, r[0]) for r in jugador.oros_restringidos),
            # Saladino/Arcas (libres) y Herrero, Ogham, Dragones (solo ciertas cartas).
            "orosVirtualesDetalle": ([f"{jugador.oros_virtuales} libres"] if jugador.oros_virtuales else []) + [
                f"{r[0]} solo {'/'.join(r[1]) or 'cartas'}{(' ' + r[2]) if r[2] else ''}"
                + (f" coste {r[3]}+" if len(r) > 3 and r[3] else "")
                for r in jugador.oros_restringidos if r[0] > 0],
            # La primera del castillo que la persona ya miró (Olímpicos): boca arriba.
            **({"topeCastillo": _carta(jugador.mazo[0], partida)}
               if i == humano and jugador.mazo and jugador.tope_visto == jugador.mazo[0].uid else {}),
            "mano": [_carta(x, partida) for x in jugador.mano] if i == humano else [],
            "manoCantidad": len(jugador.mano),
            "reserva": [_carta(x, partida) for x in jugador.reserva],
            "pagado": [_carta(x, partida) for x in jugador.pagado],
            "defensa": defensa,
            "ataque": [_carta_mesa(x, partida) for x in jugador.ataque],
            "apoyo": [_carta(x, partida) for x in jugador.apoyo],
            "cementerio": len(jugador.cementerio),
            "destierro": len(jugador.destierro),
            "cementerioCartas": [_carta(x, partida) for x in jugador.cementerio],
            "destierroCartas": [_carta(x, partida) for x in jugador.destierro],
        })
    # Quién bloquea a quién en el combate en curso (uid del atacante → uid del
    # bloqueador): la mesa los une con una flecha.
    bloqueos = {str(a): str(b.uid) for a, b in partida.bloqueos.items()
                if b.en_juego and any(x.uid == a for x in partida.atacantes)} if partida.atacantes else {}
    return {
        "turno": partida.e.turno,
        "fase": partida.e.fase,
        "activo": partida.e.activo,
        "lados": lados,
        **({"bloqueos": bloqueos} if bloqueos else {}),
        "log": [texto_publico(x, humano) for x in (partida.e.log or [])[-30:]],
    }


class HumanoRemoto:
    """Adaptador del contrato de jugadores para una interfaz humana."""

    nombre = "humano"
    elige_ninguna = True  # al elegir entre opciones puede responder "No usar"

    def __init__(self, pedir: Callable[[str, list[dict], dict], Any]):
        self._pedir = pedir
        self._oros_pendientes: list[str] | None = None

    def _coste_pendiente(self, p, yo, carta, *, restringidos=False):
        cantidad = p.coste_de(yo, carta)
        if restringidos:
            for r in p.j(yo).oros_restringidos:
                if cantidad and r[0] > 0 and hab.paga_restringido(carta, r):
                    cantidad -= min(r[0], cantidad)
        return max(0, cantidad - p.j(yo).oros_virtuales)

    def _respuesta_con_pago(self, tipo, opciones, config):
        self._oros_pendientes = None
        r = self._pedir(tipo, opciones, config)
        if isinstance(r, dict):
            self._oros_pendientes = [str(x) for x in r["oros"]]
            return r["id"]
        return r

    def quedarse_mano(self, p, yo):
        # Desafío SkkvVn (18-11): «no sé si voy primero o no»: la mano se decide
        # sabiendo quién empieza (el que empieza juega su Oro antes y ataca antes).
        dado = p.dados[-1] if getattr(p, "dados", None) else None
        tirada = f" (dado: tú {dado[yo]}, rival {dado[1 - yo]})" if dado else ""
        quien = "Empiezas tú" if p.inicial == yo else "Empieza el rival"
        return self._pedir("mano_inicial", [], {
            "titulo": f"{quien}{tirada}. ¿Te quedas esta mano?"}) == "quedarse"

    def confirmar_fase(self, p, yo, titulo):
        """Sin jugadas posibles el turno sigue solo (antes abría una ventana
        "Terminar turno" que había que aceptar cada vez)."""

    def elegir_jugada(self, p, yo, jugadas):
        opciones = [
            {
                "id": str(k),
                # Desafío 5VXY T4: Gaspar y Pixie mostraban dos «activar»
                # iguales; ahora dicen qué hace cada una.
                "titulo": f"{x} · {describir_habilidad(x.carta.habilidades[x.habilidad])}"
                if x.tipo == "activar" else str(x),
                "tipoJugada": x.tipo,
                "carta": x.carta.nombre if x.carta else None,
                "cartaUid": str(x.carta.uid) if x.carta else None,
                "cartaTipo": x.carta.tipo.value if x.carta else None,
                "portadorUid": str(x.portador.uid) if x.portador else None,
                "cantidadPago": self._coste_pendiente(p, yo, x.carta, restringidos=True)
                if x.carta is not None and x.tipo == "jugar" else 0,
            }
            for k, x in enumerate(jugadas)
        ]
        accionables = {x.carta.uid for x in jugadas if x.carta is not None}
        motivos = {}
        jug = p.j(yo)
        for inst in jug.mano + jug.reserva + jug.pagado + jug.defensa + jug.ataque + jug.apoyo:
            activadas = [h for h in inst.habilidades if h.get("cuando") == "activada"]
            if not activadas or inst.uid in accionables:
                continue
            h = activadas[0]
            if inst.zona.value == "mano":
                if inst.tipo.value == "Oro":
                    motivo = "Primero baja este Oro en Vigilia; luego podrás activar su habilidad desde la Reserva."
                else:
                    motivo = "Primero juega esta carta. Su habilidad se activa cuando está en juego."
                    if not p.puede_pagar(yo, inst):
                        motivo += f" Necesitas {p.coste_de(yo, inst)} Oros para jugarla."
            elif h.get("fase", "cualquiera") not in ("cualquiera", p.e.fase):
                motivo = f"Esta habilidad se activa en {h['fase']}."
            elif not hab.condicion_ok(p, yo, h):
                c = h.get("condicion") or {}
                if c.get("tipo") == "aliados_raza":
                    motivo = f"Necesitas {c.get('valor', 1)} Aliados {c.get('raza', '')} en juego."
                else:
                    motivo = "No se cumple la condición de la habilidad."
            elif not hab.puede_pagar_costo(p, yo, inst, h):
                costo = h.get("costo") or {}
                impide = _quien_impide_desterrar(p, yo, inst) if costo.get("desterrarEstaCarta") else None
                if impide is not None:
                    # Desafío gXXd: «¿por qué no puedo activar la Llama de Brigit?»: tu Carmix.
                    motivo = (f"No se puede desterrar: {impide.nombre}"
                              f"{' (tuyo)' if impide.controlador == yo else ' (del rival)'} dice que los Oros"
                              " en juego no pueden ser desterrados.")
                elif costo.get("barajarMano"):
                    motivo = f"Necesitas {costo['barajarMano']} carta(s) en la mano para barajar como coste."
                else:
                    motivo = "No puedes pagar el coste de esta habilidad."
            elif hab._necesita_objetivo(h) and not hab.candidatos_validos(p, yo, inst, h):
                costo = h.get("costo") or {}
                impide = _quien_impide_desterrar_cementerio(p, yo) if (
                    h.get("accion") == "desterrar"
                    and "cementerio" in hab.zonas_de(h.get("objetivo") or {})) else None
                if impide is not None:
                    # Desafío fu7V: «no siempre tengo disponible Anillos de Badbury»:
                    # el Cinturón De Lady Ann del rival estaba en su Reserva.
                    en_reserva = any(x.get("zonaActivacion") == "reserva_oro" for x in impide.habilidades
                                     if x.get("modo") == "desterrar_cementerio")
                    motivo = (f"No se puede desterrar del Cementerio: {impide.nombre}"
                              f"{' (tuyo)' if impide.controlador == yo else ' (del rival)'} lo impide"
                              f"{' mientras esté en la Reserva' if en_reserva else ''}.")
                else:
                    motivo = ("No hay objetivo legal o faltan cartas en tu Cementerio para pagar su coste."
                              if costo.get("desterrarCementerioSegun") else "No hay un objetivo legal para esta habilidad.")
            else:
                motivo = "Esta habilidad no tiene una activación legal ahora."
            motivos[str(inst.uid)] = motivo
        for inst in jug.mano:
            # Desafío lj65: Nacimiento de Pegaso no salía porque Marco Antonio
            # (tuyo) dice "No se pueden jugar Talismanes": decir quién lo impide.
            if inst.tipo.value != "Oro" and str(inst.uid) not in motivos and inst.uid not in accionables                     and hab.prohibido(p, "jugar_tipo", yo, inst):
                quien = next((s for s in p.e.instancias_en_juego() for h in s.habilidades
                              if h.get("accion") == "restriccion" and h.get("modo") == "jugar_tipo"
                              and hab.coincide(p, inst, h.get("objetivo") or {})), None)
                motivos[str(inst.uid)] = (f"No se puede jugar: {quien.nombre}"
                                          f"{' (tuyo)' if quien.controlador == yo else ' (del rival)'} lo impide."
                                          if quien else "Una carta en juego impide jugarla ahora.")
        propia_vigilia = p.e.fase == "vigilia" and p.e.activo == yo
        if all(x.tipo == "pasar" for x in jugadas) and (not motivos or not propia_vigilia):
            # Reporte w8nI: sin nada que jugar, activar ni explicar, la fase pasa
            # sola. Desafío gXXd: fuera de tu Vigilia (Guerra de Talismanes) pasa
            # sola aunque haya cartas que expliquen por qué no se usan.
            return jugadas[0]
        elegido = int(self._respuesta_con_pago("jugada", opciones, {
            "titulo": "Elige tu jugada",
            "oros": [_carta(x, p) for x in p.j(yo).reserva],
            "motivos": motivos,
        }))
        return jugadas[elegido]

    def elegir_oros(self, p, yo, disponibles, cantidad, carta=None, por=None):
        opciones = [_carta(x, p) for x in disponibles]
        titulo = f"Paga {cantidad} Oro{'s' if cantidad != 1 else ''}"
        if self._oros_pendientes is not None:
            respuesta = self._oros_pendientes
            self._oros_pendientes = None
        else:
            respuesta = self._pedir("pago_oro", opciones, {"titulo": titulo, "cantidad": cantidad})
        ids = {int(x) for x in respuesta}
        elegidos = [x for x in disponibles if x.uid in ids][:cantidad]
        if len(elegidos) < cantidad:
            # Desafío AkOg: la app preseleccionaba Oros que no pagan esta
            # carta; el pago quedaba corto y la jugada no pasaba (sin aviso).
            # Se completa con los que sí sirven, primero los sin habilidad.
            resto = sorted((x for x in disponibles if x not in elegidos), key=lambda x: len(x.habilidades))
            elegidos += resto[:cantidad - len(elegidos)]
        return elegidos

    def elegir_atacantes(self, p, yo, candidatos):
        opciones = [_carta(x, p) for x in candidatos]
        ids = {int(x) for x in self._pedir("atacantes", opciones, {"titulo": "Declara tus atacantes"})}
        return [x for x in candidatos if x.uid in ids]

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        # Desafío 1bXc T14: cada atacante con sus bloqueadores posibles
        # (Melisende no puede ser bloqueada por fuerza 3 o más); antes se
        # ofrecían todos a todos.
        opciones = [{"atacante": _carta(a, p), "bloqueadores": [_carta(b, p) for b in bloqueadores
                                                              if p.puede_bloquear(a, b)]} for a in atacantes]
        elegidos = self._pedir("bloqueos", opciones, {"titulo": "Declara tus bloqueos"}) or {}
        por_uid = {x.uid: x for x in bloqueadores}
        usados: set[int] = set()
        out = {}
        for atacante in atacantes:
            uid = elegidos.get(str(atacante.uid))
            if uid is not None and int(uid) in por_uid and int(uid) not in usados \
                    and p.puede_bloquear(atacante, por_uid[int(uid)]):
                out[atacante.uid] = por_uid[int(uid)]
                usados.add(int(uid))
        return out

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        obj = (h or {}).get("objetivo") or {}
        barajar_todo = (h or {}).get("accion") == "barajar" and obj.get("zona") == "cementerio"             and obj.get("quien") in ("propio", None)  # Escudo Celestial: n o menos en el Cementerio
        if candidatos and len(candidatos) <= n and (barajar_todo or not (h or {}).get("opcional"))                 and (h or {}).get("accion") not in ("descartar",):
            # Corona Faraónica: el único objetivo posible (el Aliado que
            # entra) se toma solo, sin preguntar lo obvio.
            return list(candidatos)
        opciones = [_carta(x, p) for x in candidatos]
        ids = {int(x) for x in self._pedir("objetivos", opciones, {"titulo": "Elige objetivo", "cantidad": n})}
        return [x for x in candidatos if x.uid in ids][:n]

    def elegir_descartes(self, p, yo, mano, n):
        opciones = [_carta(x, p) for x in mano]
        ids = {int(x) for x in self._pedir("descartes", opciones, {"titulo": "Elige cartas para descartar", "cantidad": n})}
        return [x for x in mano if x.uid in ids][:n]

    def usar_opcional(self, p, yo, fuente, h):
        que = _texto_habilidad(h) if h.get("accion") else ""
        return self._pedir("confirmar", [], {
            "titulo": f"¿Usar {fuente.nombre}" + (f" ({que})" if que else "") + "?"}) == "si"

    def prevenir_conviene(self, p, yo, s, h, t, efecto):
        """Reporte 4NtK: decir qué viene (Jeroglíficos sube a Helios a la
        mano) antes de preguntar si se previene."""
        origen = getattr(p, "ctx_fuente_habilidad", None)
        que = _texto_habilidad(efecto) if (efecto or {}).get("accion") else "un efecto"
        de = f" de {origen.nombre}" if origen is not None and origen is not s else ""
        return self._pedir("confirmar", [], {
            "titulo": f"{t.nombre} va a ser afectada por «{que}»{de}. ¿Prevenirlo con {s.nombre}?"
        }) == "si"

    def anular(self, p, yo, carta, opciones):
        datos = [{"id": str(k), "titulo": x.nombre, "cartaUid": str(x.uid),
                  "cantidadPago": self._coste_pendiente(p, yo, x) if x.zona.value == "mano" else 0}
                 for k, (x, _) in enumerate(opciones)]
        r = self._respuesta_con_pago("anular", datos, {
            "titulo": f"¿Anular {carta.nombre}?",
            "oros": [_carta(x, p) for x in p.j(yo).reserva],
        })
        return int(r) if r not in (None, "", "pasar") else None

    def cancelar_habilidad(self, p, yo, fuente, h, opciones):
        """Desafiar a Arturo / Siete contra Tebas en respuesta a una habilidad
        del rival que se activa o dispara (desafío 5VXY: Mut, la prevención de
        Ra). Antes no había esta ventana para la persona."""
        datos = [{"id": str(k), "titulo": x.nombre, "cartaUid": str(x.uid),
                  "cantidadPago": self._coste_pendiente(p, yo, x) if x.zona == Zona.MANO else 0}
                 for k, (x, _) in enumerate(opciones)]
        r = self._respuesta_con_pago("responder", datos, {
            "titulo": f"¿Cancelar la habilidad de {fuente.nombre}? ({describir_habilidad(h)})",
            "oros": [_carta(x, p) for x in p.j(yo).reserva],
        })
        return int(r) if r not in (None, "", "pasar") else None

    def responder(self, p, yo, carta, opciones):
        datos = [{"id": str(k), "titulo": x.nombre, "cartaUid": str(x.uid),
                  "cantidadPago": self._coste_pendiente(p, yo, x)}
                 for k, (x, _) in enumerate(opciones)]
        r = self._respuesta_con_pago("responder", datos, {
            "titulo": f"¿Responder a {carta.nombre}?",
            "oros": [_carta(x, p) for x in p.j(yo).reserva],
        })
        return int(r) if r not in (None, "", "pasar") else None

    def preferir_alternativo(self, p, yo, fuente, h):
        return self._pedir("confirmar", [], {
            "titulo": f"¿Pagar el costo alternativo de {fuente.nombre}?"
        }) == "si"

    def redirigir(self, p, yo, objetivo, opciones):
        datos = [{"id": str(k), "titulo": x.nombre} for k, x in enumerate(opciones)]
        r = self._pedir("redirigir", datos, {"titulo": "¿Redirigir el efecto?"})
        return int(r) if r not in (None, "", "pasar") else None

    def elegir_raza(self, p, yo, razas, h):
        return self._pedir("raza", [{"id": x, "titulo": x} for x in razas], {"titulo": "Elige una raza"})

    def elegir_carta(self, p, yo, nombres):
        # Reporte HIM0: se nombra cualquier carta del tipo pedido (se escribe
        # con autocompletar), no solo las de esta partida: así la lista no
        # delata qué trae el mazo rival.
        fuente = getattr(p, "ctx_fuente_habilidad", None)
        hn = next((h for h in (fuente.habilidades if fuente else [])
                   if (h.get("objetivo") or {}).get("nombrarCarta")), None)
        objn = (hn or {}).get("objetivo") or {}
        if objn.get("zona") == "mazo" and objn.get("quien") == "oponente":
            # Desafío g9FE: Orfeo "busca en el Mazo Castillo oponente": ves su
            # mazo (una carta por nombre) y eliges la que quieres desterrar.
            unicas = {}
            for x in p.j(1 - yo).mazo:
                unicas.setdefault(x.nombre, x)
            if unicas:
                cartas = sorted(unicas.values(), key=lambda x: x.nombre)
                ids = self._pedir("objetivos", [_carta(x, p) for x in cartas],
                                  {"titulo": f"{fuente.nombre if fuente else 'Busca'}: elige una carta del mazo rival",
                                   "cantidad": 1}) or []
                por_uid = {str(x.uid): x.nombre for x in cartas}
                elegida = next((por_uid[str(u)] for u in ids if str(u) in por_uid), None)
                if elegida:
                    return elegida
        tipos = set(objn.get("tipos") or [])
        razas: set[str] = set()
        if ((hn or {}).get("objetivo") or {}).get("quien") == "oponente" and "Aliado" in tipos:
            # Sir Bedivere: solo Aliados de la raza del rival (pública en Racial).
            rival = p.j(1 - yo)
            razas = {x.carta.raza for x in rival.mazo + rival.mano + rival.cementerio + rival.destierro
                     + list(p.e.instancias_en_juego(1 - yo))
                     if x.carta.tipo.value == "Aliado" and x.carta.raza}
        propios = {n for n in nombres if not razas or _raza_de_nombre(p, n) in razas}
        todos = sorted(propios | _nombres_conocidos(tipos, razas))
        tipo = " o ".join(sorted(tipos)) or "carta"
        if razas:
            tipo += " " + " o ".join(sorted(razas))
        return self._pedir("carta", [{"id": x, "titulo": x} for x in todos],
                           {"titulo": f"Nombra un {tipo}" if tipos else "Nombra una carta", "escribir": True})

    def elegir_portador(self, p, yo, arma, portadores):
        opciones = [_carta(x, p) for x in portadores]
        uid = int(self._pedir("portador", opciones, {"titulo": f"¿Quién porta {arma.nombre}?"}))
        return next(x for x in portadores if x.uid == uid)

    def elegir_opcion(self, p, yo, fuente, opciones):
        """Anand ("robas o barajas", reporte 4n5oe), Nuada, Loch Lein: el
        jugador elige cuál usar (antes el motor tomaba la primera)."""
        datos = [{"id": str(k), "titulo": _texto_habilidad(h)} for k, h in enumerate(opciones)]
        if all(h.get("opcional") for h in opciones):
            datos.append({"id": "ninguna", "titulo": "No usar"})
        r = self._pedir("opcion", datos, {"titulo": f"{fuente.nombre}: elige una"})
        return None if r == "ninguna" else int(r)

    def ver_cartas(self, p, yo, titulo, cartas):
        """Mostrar cartas un momento (Sir Bedivere: la mano del rival)."""
        self._pedir("objetivos", [_carta(x, p) for x in cartas],
                    {"titulo": f"{titulo} · toca Confirmar para seguir", "cantidad": 0})

    def nombrar_tipo(self, p, yo, fuente, tipos):
        """Afrodita: nombras el tipo antes de ver la primera carta."""
        r = self._pedir("opcion", [{"id": t, "titulo": t} for t in tipos],
                        {"titulo": f"{fuente.nombre}: nombra un tipo de carta (antes de mirar)"})
        return str(r)

    def tope_o_fondo(self, p, yo, cartas):
        """Nacimiento de Pegaso (reporte FeCs): ves las cartas y eliges si
        quedan arriba (las robas) o van al fondo (robas otras)."""
        nombres = ", ".join(x.nombre for x in cartas)
        r = self._pedir("opcion", [
            {"id": "tope", "titulo": f"Dejar arriba: {nombres}"},
            {"id": "fondo", "titulo": f"Al fondo del mazo: {nombres}"},
        ], {"titulo": f"Miras {nombres}: ¿arriba o al fondo?"})
        return "mazo_fondo" if r == "fondo" else "mazo_tope"

    def elegir_mirar_tope(self, p, yo, fuente, vistas, modos):
        """Rhiannon: ves todas las cartas miradas y tomas las de un solo modo."""
        opciones = [_carta(x, p) for x in vistas]
        datos = [{"titulo": _titulo_modo(h_elegibles, maximo), "ids": [str(x.uid) for x in h_elegibles],
                  "maximo": maximo} for h_elegibles, maximo in modos]
        ids = [str(x) for x in self._pedir("mirar", opciones, {
            "titulo": f"{fuente.nombre}: elige qué tomar (el resto se va)", "modos": datos,
        }) or []]
        k = _modo_de(datos, ids)
        por_uid = {str(x.uid): x for x in vistas}
        return (0 if k is None else k), [por_uid[u] for u in ids if u in por_uid]


_VERBOS = {"robar": "Robar", "barajar": "Barajar en el mazo", "botar": "Botar", "destruir": "Destruir",
           "desterrar": "Desterrar", "descartar": "Descartar", "subirMano": "Subir a la mano",
           "buscar": "Buscar", "modificarFuerza": "Cambiar la fuerza", "generarOro": "Generar Oro"}
_ZONAS = {"cementerio": "Cementerio", "mano": "mano", "mazo": "mazo", "en_juego": "en juego"}


_URLS_CACHE: dict[str, str] = {}


def _urls_imagenes(ids: set[str]) -> dict[str, str]:
    """URL de la imagen de cada carta (officialImageUrl, imageUrl o la de su
    variante oficial). Se guarda en memoria entre partidas."""
    from .datos import db

    faltan = [i for i in ids if i and not i.startswith("__") and i not in _URLS_CACHE]
    if faltan:
        col = db().collection("cards")
        for doc in db().get_all([col.document(i) for i in faltan]):
            if not doc.exists:
                continue
            d = doc.to_dict() or {}
            url = (d.get("officialImageUrl") or d.get("imageUrl") or "").strip()
            if not url:
                for v in doc.reference.collection("variants").limit(3).stream():
                    url = ((v.to_dict() or {}).get("imageFrontUrl") or "").strip()
                    if url:
                        break
            if url:
                _URLS_CACHE[doc.id] = url
    return {i: _URLS_CACHE[i] for i in ids if i in _URLS_CACHE}


_NOMBRES_CACHE: dict[tuple[str, str], set[str]] | None = None


def _nombres_conocidos(tipos: set[str], razas: set[str] = frozenset()) -> set[str]:
    """Nombres de cartas de esos tipos (y razas) en todos los mazos guardados
    en simulator/cache: un catálogo amplio para nombrar sin pistas."""
    global _NOMBRES_CACHE
    if _NOMBRES_CACHE is None:
        _NOMBRES_CACHE = {}
        cache = Path(__file__).resolve().parents[1] / "cache"
        for f in cache.glob("mazo_*.json"):
            try:
                for c in json.loads(f.read_text(encoding="utf-8")).get("cartas") or []:
                    if c.get("nombre") and c.get("tipo"):
                        _NOMBRES_CACHE.setdefault((c["tipo"], c.get("raza") or ""), set()).add(c["nombre"])
            except (OSError, ValueError):
                continue
    return {n for (t, r), ns in _NOMBRES_CACHE.items() if t in tipos and (not razas or r in razas) for n in ns}


def _raza_de_nombre(p, nombre: str) -> str:
    for j in p.e.jugadores:
        for x in j.mazo + j.mano + j.cementerio + j.destierro:
            if x.nombre == nombre:
                return x.carta.raza or ""
    for x in p.e.instancias_en_juego():
        if x.nombre == nombre:
            return x.carta.raza or ""
    return ""


def _texto_habilidad(h: dict) -> str:
    """Una opción legible: «Robar 1» · «Barajar en el mazo 1 de tu Cementerio»."""
    obj = h.get("objetivo") or {}
    if h.get("accion") == "modificarFuerza":
        # Bereber: «+1 de fuerza a esta carta» · «+2 de fuerza a otro Guerrero».
        quien = "esta carta" if obj.get("quien") == "esta_carta" else             f"otro {obj.get('arquetipo') or obj.get('raza') or 'Aliado'}" if obj.get("excluirEstaCarta")             else (obj.get("arquetipo") or obj.get("raza") or "un Aliado")
        return f"{int(h.get('valor', 0) or 0):+d} de fuerza a {quien}"
    texto = f"{_VERBOS.get(h.get('accion'), str(h.get('accion')))} {h.get('cantidad', 1) or 1}"
    que = " ".join(x for x in ("/".join(obj.get("tipos") or []), obj.get("raza") or obj.get("arquetipo") or "") if x)
    if que:
        texto += f" {que}"  # Erec: «Barajar en el mazo 2 Aliado Caballero de tu Cementerio»
    zona = _ZONAS.get(str(obj.get("zona") or ""))
    if zona and h.get("accion") != "robar":
        de = {"propio": "de tu", "oponente": "del rival:"}.get(obj.get("quien"), "de")
        texto += f" {de} {zona}" if zona != "en juego" else f" {zona}"
    return texto


def _titulo_modo(elegibles, maximo: int) -> str:
    tipos = sorted({x.tipo.value for x in elegibles})
    return f"{'Una' if maximo == 1 else f'Hasta {maximo}'} · {', '.join(tipos) or 'ninguna calza'}"


def _modo_de(modos: list[dict], ids: list[str]) -> int | None:
    """El modo en que caben todas las cartas elegidas (None si ninguno)."""
    for k, m in enumerate(modos):
        if set(ids) <= set(m["ids"]) and len(ids) <= int(m["maximo"]):
            return k
    return None


_ACCIONES_TEXTO = {
    "robar": "roba", "barajar": "baraja", "buscar": "busca", "destruir": "destruye", "desterrar": "destierra",
    "botar": "hace botar", "subirMano": "sube a la mano", "perderHabilidad": "quita la habilidad",
    "mirarTope": "mira el tope", "jugarDesde": "juega", "ponerEnJuego": "pone en juego", "generarOro": "genera Oro",
    "convertirEnAliado": "se vuelve Aliado", "cancelarAtaque": "cancela el ataque", "reducirDano": "reduce el daño",
    "mover": "mueve", "ganarControl": "toma el control", "descartar": "descarta", "prevenir": "previene",
}


def describir_habilidad(h: dict) -> str:
    """Qué hace una habilidad, en pocas palabras: «baraja 2 Aliado Dragón del
    Cementerio», «roba 3», «+2 de fuerza»."""
    accion = h.get("accion", "")
    obj = h.get("objetivo") or {}
    if accion == "modificarFuerza":
        v = int(h.get("valor") or 0)
        return f"{'+' if v >= 0 else ''}{v} de fuerza"
    if accion == "generarOro":
        return f"genera {int(h.get('valor') or 1)} Oro"
    partes = [_ACCIONES_TEXTO.get(accion, h.get("featureName") or accion)]
    n = int(h.get("cantidad") or 1)
    if accion in ("robar", "barajar", "botar", "buscar", "destruir", "desterrar", "descartar", "mirarTope") and (
            n > 1 or accion in ("robar", "botar")):
        partes.append(str(n))
    tipos = [t for t in obj.get("tipos") or [] if t]
    if tipos and accion not in ("robar", "botar"):
        partes.append("/".join(tipos))
    if obj.get("raza") and accion not in ("robar", "botar"):
        partes.append(str(obj["raza"]))
    zonas = hab.zonas_de(obj, "")
    if "cementerio" in zonas:
        partes.append("del Cementerio")
    elif "mazo" in zonas and accion not in ("robar", "botar"):
        partes.append("del Mazo")
    if obj.get("quien") == "oponente" and accion not in ("botar",):
        partes.append("rival")
    destino = {"mazo_fondo": "al fondo del Mazo", "mazo_tope": "arriba del Mazo", "mano": "a la mano"}.get(
        h.get("zonaDestino") or "")
    if destino and accion in ("mover", "buscar", "subirMano"):
        partes.append(destino)
    return " ".join(partes)


def _quien_impide_desterrar(p, yo: int, inst: Instancia) -> Instancia | None:
    """La carta en juego que prohíbe desterrar este Oro (Carmix)."""
    if inst.tipo.value != "Oro" or not hab.prohibido(p, "desterrar", yo, inst):
        return None
    return next((s for s in p.e.instancias_en_juego(0) + p.e.instancias_en_juego(1) for h in s.habilidades
                 if h.get("accion") == "restriccion" and h.get("modo") == "desterrar"), None)


def _quien_impide_desterrar_cementerio(p, yo: int) -> Instancia | None:
    """La carta en juego que prohíbe desterrar de los Cementerios (Cinturón De
    Lady Ann en la Reserva)."""
    if not hab.prohibido(p, "desterrar_cementerio", yo):
        return None
    return next((s for s in p.e.instancias_en_juego(0) + p.e.instancias_en_juego(1) for h in s.habilidades
                 if h.get("accion") == "restriccion" and h.get("modo") == "desterrar_cementerio"
                 and hab._en_zona_activacion(s, h) and not (h.get("objetivo") or {}).get("cementerioPropio")),
                None)


def respuesta_valida(tipo: str, opciones: list[dict], config: dict, valor: Any) -> bool:
    """Rechaza entradas viejas o inválidas antes de reanudar el motor."""
    ids = {str(o["id"]) for o in opciones if "id" in o}
    if tipo in ("jugada", "anular", "responder") and isinstance(valor, dict):
        opcion = next((o for o in opciones if str(o.get("id")) == str(valor.get("id"))), None)
        if opcion is None or set(valor) != {"id", "oros"}:
            return False
        oros = valor["oros"]
        disponibles = {str(o["id"]) for o in config.get("oros", [])}
        cantidad = int(opcion.get("cantidadPago", 0))
        return (isinstance(oros, list) and len(oros) == cantidad
                and len({str(x) for x in oros}) == cantidad
                and all(str(x) in disponibles for x in oros))
    if tipo == "mirar":
        return isinstance(valor, list) and len({str(x) for x in valor}) == len(valor) \
            and _modo_de(config.get("modos") or [], [str(x) for x in valor]) is not None
    if tipo in ("mano_inicial", "confirmar"):
        return valor in (("quedarse", "mulligan") if tipo == "mano_inicial" else ("si", "no"))
    if tipo == "avance_fase":
        return valor == "continuar"
    if tipo in ("anular", "responder", "redirigir") and valor == "pasar":
        return True
    if tipo == "bloqueos":
        atacantes = {str(o["atacante"]["id"]) for o in opciones}
        permitidos = {
            str(o["atacante"]["id"]): {str(b["id"]) for b in o["bloqueadores"]}
            for o in opciones
        }
        return isinstance(valor, dict) and set(valor) <= atacantes and all(
            str(b) in permitidos[str(a)] for a, b in valor.items() if b is not None
        ) and len({str(b) for b in valor.values() if b is not None}) == len(
            [b for b in valor.values() if b is not None]
        )
    if tipo in ("atacantes", "objetivos", "descartes", "pago_oro"):
        if not isinstance(valor, list) or len({str(x) for x in valor}) != len(valor):
            return False
        cantidad = config.get("cantidad")
        return (cantidad is None or len(valor) == cantidad) and all(str(x) in ids for x in valor)
    if tipo in ("jugada", "anular", "responder"):
        opcion = next((o for o in opciones if str(o.get("id")) == str(valor)), None)
        # Compatibilidad con clientes Android anteriores: ellos confirman la
        # jugada primero y reciben luego la decisión separada de pago_oro.
        return isinstance(valor, str) and opcion is not None
    return isinstance(valor, str) and valor in ids


class GrabadorIa:
    """Registra las decisiones estratégicas de la heurística para auditarlas."""

    def __init__(self, politica, registrar: Callable[[int, str, list[dict], Any], None]):
        self.politica = politica
        self.registrar = registrar

    def __getattr__(self, nombre):
        return getattr(self.politica, nombre)

    def elegir_jugada(self, p, yo, jugadas):
        elegida = self.politica.elegir_jugada(p, yo, jugadas)
        opciones = [{"id": str(k), "titulo": str(x)} for k, x in enumerate(jugadas)]
        self.registrar(yo, "jugada", opciones, str(jugadas.index(elegida)))
        return elegida

    def elegir_atacantes(self, p, yo, candidatos):
        elegidos = self.politica.elegir_atacantes(p, yo, candidatos)
        opciones = [_carta(x, p) for x in candidatos]
        self.registrar(yo, "atacantes", opciones, [str(x.uid) for x in elegidos])
        return elegidos

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        elegidos = self.politica.elegir_bloqueos(p, yo, atacantes, bloqueadores)
        opciones = [{"atacante": _carta(a, p), "bloqueadores": [_carta(b, p) for b in bloqueadores]} for a in atacantes]
        # Solo el análisis de bloqueos: otros buscadores dejan ahí el de sus ataques.
        analisis = getattr(self.politica, "ultimo_analisis", None)
        self.registrar(yo, "bloqueos", opciones, {str(a): str(b.uid) for a, b in elegidos.items()},
                       analisis=analisis if analisis and "muestrasPorOpcion" in analisis else None)
        return elegidos

    def elegir_objetivos(self, p, yo, candidatos, n, h):
        elegidos = self.politica.elegir_objetivos(p, yo, candidatos, n, h)
        self.registrar(yo, "objetivos", [_carta(x, p) for x in candidatos], [str(x.uid) for x in elegidos])
        return elegidos


# Probabilidad de que la IA tome una decisión al azar (entre las legales) en
# vez de la mejor. Nivel 5 decide simulando (BuscadorVigilia, la "IA buena").
NIVELES = {
    1: ("Principiante", 0.60),
    2: ("Fácil", 0.35),
    3: ("Normal", 0.15),
    4: ("Difícil", 0.0),
    5: ("Experto", 0.0),
}


class PoliticaDificultad:
    """Rebaja la heurística: con probabilidad `error` decide al azar."""

    _DECISIONES = ("elegir_jugada", "elegir_atacantes", "elegir_bloqueos", "elegir_objetivos")

    def __init__(self, base, nivel: int, seed: int):
        import random

        from .jugadores import Aleatorio

        self.base = base
        self.nivel = nivel
        self.error = NIVELES[nivel][1]
        self.rng = random.Random(seed)
        self.azar = Aleatorio(seed + 7)
        self.nombre = f"{base.nombre} · nivel {nivel}"

    def __getattr__(self, nombre):
        attr = getattr(self.base, nombre)
        if nombre in self._DECISIONES and self.error:
            def decidir(*args, **kw):
                if self.rng.random() < self.error:
                    return getattr(self.azar, nombre)(*args, **kw)
                return attr(*args, **kw)
            return decidir
        return attr


def politica_ia_para(mazo_humano, mazo_ia, seed: int,
                    registro_path: Path | None = None):
    """Usa aprendizaje solo si las dos barajas coinciden con un cruce aprobado."""
    ruta = registro_path or CACHE / "entrenamiento" / "modelos" / "djoser_registro_v2.json"
    if not ruta.exists():
        return Heuristico(seed)
    registro = json.loads(ruta.read_text(encoding="utf-8"))
    return jugador_para(registro, ruta.parent, mazo_ia, mazo_humano, seed)


class _AnotarEnVivo:
    """Anota en el estado real y publica las acciones de la IA al momento.

    La IA copia la partida para simular futuros (búsqueda de bloqueos y de
    ataques). Una copia no debe publicar ni escribir en el registro real: lo
    que pasa en esas partidas imaginarias aparecía en la mesa como si fuera
    de verdad (Godofredo jugado y atacando en la fase de bloqueo rival)."""

    def __init__(self, estado, sesion: "SesionDesafio"):
        self.estado = estado
        self.sesion = sesion

    def __call__(self, texto: str) -> None:
        type(self.estado).anotar(self.estado, texto)
        if self.sesion.pausa and _es_accion_ia(texto, self.sesion.partida):
            self.sesion.publicar_accion(texto)

    def __deepcopy__(self, memo):
        # La copia anota en sí misma, sin publicar (el estado ya está en memo).
        copia = memo.get(id(self.estado))
        return None if copia is None else types.MethodType(type(copia).anotar, copia)


SEGUNDOS_NIVEL5 = 5.0   # tope por búsqueda del nivel 5 en el Desafío
MUESTRAS_NIVEL5 = 28    # 4 de criba + hasta 24 de confirmación


class SesionDesafio:
    """Ejecuta una sesión y bloquea solo su hilo mientras espera a la app."""

    def __init__(self, ref, mazo_humano, mazo_ia, *, seed: int,
                 buscar_bloqueos: bool = False, nivel: int = 4, pausa: float = 0.0):
        self.ref = ref
        self.mazo_humano = mazo_humano
        self.mazo_ia = mazo_ia
        self.secuencia = 0
        self.decisiones: list[dict[str, Any]] = []
        self.humano = HumanoRemoto(self.pedir)
        self.nivel = nivel if nivel in NIVELES else 4
        self.pausa = pausa
        self.politica_base_ia = politica_ia_para(mazo_humano, mazo_ia, seed * 2 + 1)
        self.politica_ia = self.politica_base_ia
        if self.nivel == 5:
            # La IA más fuerte medida en la arena (+100 Elo sobre la heurística;
            # la búsqueda de bloqueos sola empata con ella): simula la Vigilia,
            # los ataques, los objetivos, los Oros y la Guerra de Talismanes.
            from .busqueda_vigilia import BuscadorVigilia

            # En vivo piensa hasta `SEGUNDOS_NIVEL5` por búsqueda y confirma con
            # más muestras que en las simulaciones (donde no hay tope, para que
            # el resultado se repita).
            self.politica_ia = BuscadorVigilia(seed * 2 + 1, max_segundos=SEGUNDOS_NIVEL5,
                                               max_muestras=MUESTRAS_NIVEL5)
        elif buscar_bloqueos:
            self.politica_ia = PoliticaConBusqueda(self.politica_ia, seed * 2 + 1)
        if NIVELES[self.nivel][1]:
            self.politica_ia = PoliticaDificultad(self.politica_ia, self.nivel, seed * 2 + 3)
        from .autopsia import Grabadora, metodos_de

        # Todas las decisiones de ambos lados, para reproducir la partida en la
        # autopsia (por qué perdió la IA, y las jugadas que la persona marcó).
        self.seed = seed
        self.grabacion: list[dict] = []
        self._ref_partida: list = [None]
        ia = GrabadorIa(self.politica_ia, self.registrar)
        self.metodos = [metodos_de(self.humano), metodos_de(ia)]
        self.acciones_ia: list[dict] = []
        self.partida = Partida(
            (mazo_humano.cartas, mazo_ia.cartas),
            (Grabadora(self.humano, 0, self.grabacion, self._ref_partida, revisable=True),
             Grabadora(ia, 1, self.grabacion, self._ref_partida)),
            nombres=(mazo_humano.nombre, mazo_ia.nombre),
            inicial=None,
            seed=seed,
            log=True,
        )
        self._ref_partida[0] = self.partida
        # Cada acción de la IA se publica al momento (con una pausa) para que
        # la persona la vea en la mesa, en vez de saltar a su próxima decisión.
        self.partida.e.anotar = _AnotarEnVivo(self.partida.e, self)

    def publicar_accion(self, texto: str) -> None:
        from .autopsia import REVISABLES

        # La decisión de la IA que produjo esta acción (la última que tomó).
        decision = next((k for k in range(len(self.grabacion) - 1, -1, -1)
                         if self.grabacion[k]["lado"] == 1 and self.grabacion[k]["m"] in REVISABLES), None)
        accion = {"id": str(len(self.acciones_ia)), "texto": texto_publico(texto), "turno": self.partida.e.turno,
                  "fase": self.partida.e.fase, "decision": decision}
        self.acciones_ia.append(accion)
        reintentar_red(lambda: self.ref.update({
            "status": "jugando",
            "decision": None,
            "accionIa": accion,
            "accionesIa": self.acciones_ia[-60:],  # para marcarlas ✓/✗ aunque ya hayan pasado
            "estado": vista_desafio(self.partida, 0),
            "pasoGrabacion": len(self.grabacion),  # reportes en vivo: el punto exacto
        }))
        # Lo que cambia la mesa (jugar, activar, atacar, anular) se queda más
        # tiempo a la vista: a 1,2 s por acción no alcanzaba a leerse.
        importante = any(x in texto for x in ("juega", "activa", "ataca", "anula", "cancela", "responde"))
        time.sleep(self.pausa * (1.8 if importante else 1.0))

    def autopsia(self, votos: dict[str, str], ganador: int | None) -> dict:
        """Revisa las jugadas marcadas ✓/✗ y, si la IA perdió, sus errores clave."""
        from .autopsia import informe

        return informe((self.mazo_humano.cartas, self.mazo_ia.cartas),
                       (self.mazo_humano.nombre, self.mazo_ia.nombre), self.seed,
                       self.grabacion, self.metodos, self.acciones_ia, votos, ganador)

    def registrar(self, lado: int, tipo: str, opciones: list[dict], elegida: Any,
                  *, analisis: dict | None = None) -> None:
        """Traza compacta. Conserva las alternativas sin llenar Firestore."""
        if len(self.decisiones) >= 500:
            return
        self.decisiones.append({
            "paso": len(self.decisiones) + 1,
            "quien": "Tú" if lado == 0 else "IA",
            "lado": lado,
            "turno": self.partida.e.turno,
            "fase": self.partida.e.fase,
            "tipo": tipo,
            "opciones": opciones[:30],
            "elegida": elegida,
            **({"analisisBloqueos": analisis} if analisis is not None else {}),
            "narracion": texto_publico((self.partida.e.log or [])[-1]) if self.partida.e.log else "",
        })

    def pedir(self, tipo: str, opciones: list[dict], config: dict) -> Any:
        self.secuencia += 1
        decision = str(self.secuencia)
        reintentar_red(lambda: self.ref.update({
            "status": "esperando",
            "decision": {"id": decision, "tipo": tipo, "opciones": opciones, **config},
            "estado": vista_desafio(self.partida, 0),
            "pasoGrabacion": len(self.grabacion),
            "respuesta": None,
        }))
        while True:
            data = reintentar_red(lambda: self.ref.get()).to_dict() or {}
            respuesta = data.get("respuesta") or {}
            if str(respuesta.get("decisionId")) == decision:
                valor = respuesta.get("valor")
                if not respuesta_valida(tipo, opciones, config, valor):
                    reintentar_red(lambda: self.ref.update({
                        "respuesta": None, "errorDecision": "Selección inválida; vuelve a elegir."
                    }))
                    continue
                reintentar_red(lambda: self.ref.update({"status": "jugando", "respuesta": None}))
                self.registrar(0, tipo, opciones, valor)
                return valor
            if data.get("status") == "abandonado":
                raise RuntimeError("Desafío abandonado por el jugador")
            time.sleep(0.35)

    def jugar(self) -> dict:
        # Las imágenes de los dos mazos, antes de empezar: la app las descarga
        # todas y no depende de pedir carta por carta durante la partida.
        try:
            ids = {c.id for c in self.mazo_humano.cartas + self.mazo_ia.cartas}
            imagenes = _urls_imagenes(ids)
            if imagenes:
                reintentar_red(lambda: self.ref.update({"imagenes": imagenes}))
        except Exception:  # noqa: BLE001 - sin imágenes previas la app las pide igual
            pass
        registro = self.partida.jugar()
        ganador = self.partida.e.jugadores[registro.ganador].nombre_mazo if registro.ganador in (0, 1) else "Empate"
        nombres = {"J0": self.mazo_humano.nombre, "J1": self.mazo_ia.nombre}
        pasos = []
        for paso in self.partida.pasos[:1500]:
            texto = paso["x"]
            for codigo, nombre in nombres.items():
                texto = texto.replace(codigo, nombre)
            pasos.append({**paso, "x": texto})
        cartas = {c.id: c.nombre for c in self.mazo_humano.cartas + self.mazo_ia.cartas}
        cartas["oro_inicial"] = "Oro inicial"
        return {
            "ganador": ganador,
            "ganadorLado": registro.ganador,
            "turnos": registro.turnos,
            "causa": registro.causa,
            "politicaIa": self.politica_ia.nombre,
            "nivelIa": self.nivel,
            "nivelIaNombre": NIVELES[self.nivel][0],
            "politicaBaseIa": self.politica_base_ia.nombre,
            "narracion": [hab.sin_marcas(x) for x in (self.partida.e.log or [])[-1000:]],  # repetición: todo a la vista
            "decisiones": self.decisiones,
            "estado": vista_desafio(self.partida, 0),
            "repeticion": {
                "mazoA": {"nombre": self.mazo_humano.nombre},
                "mazoB": {"nombre": self.mazo_ia.nombre},
                "cartas": _sin_ids_reservados(cartas),
                "pasos": _sin_ids_reservados(_solo_cambios(pasos)),
            },
        }
