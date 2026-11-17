"""Autopsia de un desafío: por qué perdió la IA y qué jugadas suyas fueron malas.

El motor es determinista con la misma semilla: si se repiten todas las
decisiones grabadas, la partida vuelve a ser idéntica. Para revisar la
decisión `k` de la IA se reproduce la partida hasta ese punto, la IA toma
otra opción y desde ahí ambos lados juegan con la heurística (varias
muestras, barajando los mazos de nuevo). La opción que gana más seguido que
la elegida, con margen, es un error de la IA.

Se revisan las decisiones marcadas por la persona (✓/✗ en la mesa) y, si la
IA perdió, las que más bajaron su estimación de victoria. Las conclusiones
quedan en el desafío y en ``ia_lecciones`` para convertirlas en reglas.
"""

from __future__ import annotations

import random
from typing import Any

from .jugadores import Heuristico
from .modelo import Instancia
from .motor import FinPartida, Jugada, Partida

# Decisiones que se pueden revisar con alternativas.
REVISABLES = ("elegir_jugada", "elegir_atacantes", "elegir_bloqueos", "elegir_objetivos")
MUESTRAS = 10
MAX_ALTERNATIVAS = 5
MARGEN = 0.25  # la alternativa debe ganar al menos 25 puntos más


# ── Grabar y reproducir decisiones ───────────────────────────────────────────
def _codificar(valor: Any, args: tuple) -> Any:
    if isinstance(valor, Jugada):
        jugadas = next(a for a in args if isinstance(a, list) and a and isinstance(a[0], Jugada))
        return {"j": jugadas.index(valor)}
    if isinstance(valor, Instancia):
        return {"u": valor.uid}
    if isinstance(valor, (list, tuple)):
        return [_codificar(x, args) for x in valor]
    if isinstance(valor, dict):
        return {"d": [{"k": k, "v": _codificar(v, args)} for k, v in valor.items()]}  # Firestore: sin listas anidadas
    return valor


def _instancias(p: Partida) -> dict[int, Instancia]:
    out = {}
    for j in p.e.jugadores:
        for zona in (j.mazo, j.mano, j.reserva, j.pagado, j.defensa, j.ataque, j.apoyo, j.cementerio, j.destierro):
            for x in zona:
                out[x.uid] = x
    for x in p.e.portadas:
        out[x.uid] = x
    return out


def _decodificar(p: Partida, valor: Any, args: tuple) -> Any:
    if isinstance(valor, dict) and "j" in valor:
        jugadas = next(a for a in args if isinstance(a, list) and a and isinstance(a[0], Jugada))
        return jugadas[valor["j"]]
    if isinstance(valor, dict) and "u" in valor:
        return _instancias(p).get(valor["u"])
    if isinstance(valor, dict) and "d" in valor:
        return {x["k"]: _decodificar(p, x["v"], args) for x in valor["d"]}
    if isinstance(valor, list):
        return [_decodificar(p, x, args) for x in valor]
    return valor


def metodos_de(jugador) -> list[str]:
    """Qué decisiones sabe tomar (el motor pregunta por las opcionales con
    getattr: el reproductor debe responder igual que el original)."""
    from .desafio import HumanoRemoto

    nombres = {n for n in dir(Heuristico) + dir(HumanoRemoto) if not n.startswith("_")}
    out = sorted(n for n in nombres if callable(getattr(jugador, n, None)))
    if getattr(jugador, "elige_ninguna", False) is True:
        out.append("elige_ninguna")  # marca, no método: el reproductor la respeta
    return out


class Grabadora:
    """Envuelve a un jugador y anota cada decisión que toma (en orden)."""

    def __init__(self, base, lado: int, registro: list, partida_ref: list, *, revisable: bool | None = None):
        self._base = base
        self._revisable = lado == 1 if revisable is None else revisable  # anota turno y estimación
        self._lado = lado
        self._registro = registro
        self._partida = partida_ref  # [Partida]: se completa después de crearla

    @property
    def nombre(self):
        return getattr(self._base, "nombre", "jugador")

    def __getattr__(self, nombre):
        attr = getattr(self._base, nombre)
        if not callable(attr) or nombre.startswith("_"):
            return attr

        def grabar(*args, **kw):
            valor = attr(*args, **kw)
            p = self._partida[0]
            entrada = {"lado": self._lado, "m": nombre, "v": _codificar(valor, args)}
            if self._revisable and nombre in REVISABLES and p is not None:
                from .busqueda_ataques import valor_estado

                entrada["turno"], entrada["fase"] = p.e.turno, p.e.fase
                try:
                    entrada["valor"] = round(valor_estado(p, self._lado), 3)
                except Exception:  # noqa: BLE001 - la estimación es opcional
                    entrada["valor"] = None
            self._registro.append(entrada)
            return valor

        return grabar


class _Desvio(Exception):
    pass


class Horizonte(Exception):
    """La rama llegó al turno indicado en `p.horizonte` (aprendizaje humano)."""

    def __init__(self, partida):
        super().__init__("horizonte")
        self.partida = partida


class Reproductor:
    """Repite lo grabado. En la decisión `rama` toma `opcion(args)` y desde
    ahí juega con la heurística."""

    def __init__(self, lado: int, registro: list, partida_ref: list, *, rama: int | None,
                 opcion=None, seed: int = 0, metodos: list[str] | None = None):
        self.metodos = set(metodos) if metodos is not None else None
        self.lado = lado
        self.registro = registro
        self.partida = partida_ref
        self.rama = rama
        self.opcion = opcion
        self.libre = Heuristico(seed)
        self.nombre = "reproductor"

    @property
    def elige_ninguna(self) -> bool:
        """Desafío ZTSY: la persona puede decir "No usar" (Saladino, Dario,
        Anand, Ptah) y el motor toma otro camino. No es un método y no se
        grababa: se reconoce a la persona porque paga Oros a mano."""
        return self.metodos is not None and ("elige_ninguna" in self.metodos or "elegir_oros" in self.metodos)

    def __getattr__(self, nombre):
        if nombre.startswith("_") or (self.metodos is not None and nombre not in self.metodos):
            raise AttributeError(nombre)
        p = self.partida[0]
        if p is not None and p.cursor_rama is not None and p.cursor >= p.cursor_rama \
                and not callable(getattr(self.libre, nombre, None)):
            raise AttributeError(nombre)  # tras la bifurcación decide la heurística (sin pago manual)

        def decidir(*args, **kw):
            p = self.partida[0]
            if p.cursor_rama is not None and p.cursor >= p.cursor_rama:
                horizonte = getattr(p, "horizonte", None)
                if horizonte is not None and p.e.turno >= horizonte:
                    raise Horizonte(p)  # se mide cómo quedó, sin jugar hasta el final
                return getattr(self.libre, nombre)(*args, **kw)
            if p.cursor >= len(self.registro):
                raise _Desvio()
            entrada = self.registro[p.cursor]
            if entrada["lado"] != self.lado or entrada["m"] != nombre:
                raise _Desvio()  # la reproducción se separó de lo grabado
            k = p.cursor
            p.cursor += 1
            if k == self.rama:
                p.cursor_rama = p.cursor
                p.al_ramificar(args)
                return self.opcion(p, nombre, args)
            try:
                return _decodificar(p, entrada["v"], args)
            except (IndexError, StopIteration) as e:
                # Grabada con otras reglas (p. ej. el Salmón ya no se ofrece en la
                # Guerra): las opciones cambiaron y la partida ya no es la misma.
                raise _Desvio() from e

        return decidir


ULTIMA_PARTIDA: list = [None]  # la última reproducida (turno final, castillos)


def remuestrear_ocultas(p: Partida, quien: int, rng: random.Random, usadas: tuple = ()) -> None:
    """Reparte de nuevo lo que `1 - quien` no puede ver de `quien`: su mano
    oculta y su Mazo se juntan, se barajan y se vuelven a repartir (mismos
    tamaños; las cartas reveladas se quedan en la mano). Si la decisión en
    curso ya nombra una carta de esa mano (`usadas`), la mano no se toca."""
    from .modelo import Zona

    r = p.j(quien)
    ocultas = [x for x in r.mano if not getattr(x, "revelada", False)]
    en_uso = {id(x) for x in _instancias_en(usadas)}
    if not ocultas or any(id(x) in en_uso for x in r.mano):
        rng.shuffle(r.mazo)
        return
    reveladas = [x for x in r.mano if getattr(x, "revelada", False)]
    bolsa = ocultas + r.mazo
    bolsa.sort(key=lambda x: (x.carta.id, x.uid))
    rng.shuffle(bolsa)
    r.mano = reveladas + bolsa[:len(ocultas)]
    r.mazo = bolsa[len(ocultas):]
    for x in r.mano:
        x.zona = Zona.MANO
    for x in r.mazo:
        x.zona = Zona.MAZO


def _instancias_en(valor) -> list:
    if isinstance(valor, Instancia):
        return [valor]
    if isinstance(valor, Jugada):
        return [x for x in (valor.carta, valor.portador) if isinstance(x, Instancia)]
    if isinstance(valor, dict):
        return [y for v in valor.values() for y in _instancias_en(v)]
    if isinstance(valor, (list, tuple)):
        return [y for v in valor for y in _instancias_en(v)]
    return []


def reproducir(cartas, nombres, seed: int, registro: list, *, rama: int | None = None,
               opcion=None, muestra: int = 0, metodos=None, ocultar: bool = True) -> int | None:
    """Ganador (0/1/-1) de la partida reproducida; None si no se pudo.

    Con `ocultar` (por defecto), al ramificar el rival de quien decide recibe
    otra mano de las que podía tener: la decisión se juzga con lo que su autor
    sabía, no con la mano que el rival tenía esa vez."""
    ref: list = [None]
    jugadores = tuple(Reproductor(i, registro, ref, rama=rama, opcion=opcion, seed=seed * 31 + muestra * 2 + i,
                                  metodos=(metodos or [None, None])[i])
                      for i in (0, 1))
    p = Partida(cartas, jugadores, nombres=nombres, inicial=None, seed=seed)
    p.cursor, p.cursor_rama = 0, None

    def al_ramificar(args: tuple = ()):
        # Variedad entre muestras: el futuro (robos) cambia, el pasado no.
        rng = random.Random(seed * 7919 + muestra)
        lado = registro[rama]["lado"] if rama is not None and rama < len(registro) else None
        for j in p.e.jugadores:
            if ocultar and lado is not None and j.indice == 1 - lado:
                remuestrear_ocultas(p, j.indice, rng, args)
            else:
                rng.shuffle(j.mazo)
        p.e.rng = random.Random(rng.random())

    p.al_ramificar = al_ramificar
    ref[0] = p
    ULTIMA_PARTIDA[0] = p
    try:
        registro_final = p.jugar()
    except _Desvio:
        return None
    except FinPartida:
        return p.e.ganador
    return registro_final.ganador


# ── Alternativas de cada tipo de decisión ────────────────────────────────────
def describir(metodo: str, valor: Any, args: tuple = ()) -> str:
    """Texto concreto de una decisión (sirve para compararla en los tests de posición)."""
    if metodo == "elegir_jugada":
        return str(valor)
    if metodo == "elegir_atacantes":
        return "atacar con " + ", ".join(sorted(c.nombre for c in valor)) if valor else "no atacar"
    if metodo == "elegir_bloqueos":
        if not valor:
            return "no bloquear"
        atacantes = {a.uid: a for a in (args[2] if len(args) > 2 else [])}
        partes = sorted(f"{b.nombre} bloquea a {atacantes[u].nombre if u in atacantes else u}"
                        for u, b in valor.items())
        return "; ".join(partes)
    if metodo == "elegir_objetivos":
        return ", ".join(c.nombre for c in valor) if valor else "ninguno"
    return str(valor)


def alternativas(metodo: str, args: tuple, elegida: Any, p: Partida) -> list[tuple[str, Any]]:
    """(descripción, valor) de las opciones a comparar, empezando por la elegida."""
    if metodo == "elegir_jugada":
        jugadas = args[2]
        orden = [elegida] + [j for j in jugadas if j is not elegida]
        return [(str(j), j) for j in orden[:MAX_ALTERNATIVAS]]
    if metodo == "elegir_atacantes":
        candidatos = args[2]
        valores = [elegida, [], list(candidatos)] + [[c] for c in candidatos]
        out = [(describir(metodo, v, args), v) for v in valores]
        return _sin_repetir(out)[:MAX_ALTERNATIVAS]
    if metodo == "elegir_bloqueos":
        atacantes, bloqueadores = args[2], args[3]
        valores = [elegida, {}]
        for a in atacantes:
            for b in bloqueadores:
                if p.puede_bloquear(a, b):
                    valores.append({a.uid: b})
        return _sin_repetir([(describir(metodo, v, args), v) for v in valores])[:MAX_ALTERNATIVAS]
    if metodo == "elegir_objetivos":
        candidatos, n = args[2], args[3]
        if n != 1:
            return [(describir(metodo, elegida), elegida)]
        orden = list(elegida) + [c for c in candidatos if c not in elegida]
        return [(c.nombre, [c]) for c in orden[:MAX_ALTERNATIVAS]]
    return [(describir(metodo, elegida), elegida)]


def _clave(valor) -> str:
    if isinstance(valor, dict):
        return str(sorted((k, v.uid) for k, v in valor.items()))
    if isinstance(valor, list):
        return str(sorted(x.uid for x in valor))
    return str(id(valor))


def _sin_repetir(opciones):
    vistas, out = set(), []
    for texto, valor in opciones:
        k = _clave(valor)
        if k not in vistas:
            vistas.add(k)
            out.append((texto, valor))
    return out


def revisar_decision(cartas, nombres, seed: int, registro: list, k: int,
                     muestras: int = MUESTRAS, metodos=None) -> dict | None:
    """Compara la decisión k (de quien la tomó) con sus alternativas."""
    entrada = registro[k]
    lado = entrada["lado"]
    descripciones: list[str] = []

    def elegir(indice):
        def opcion(p, metodo, args):
            elegida = _decodificar(p, entrada["v"], args)
            opciones = alternativas(metodo, args, elegida, p)
            if not descripciones:
                descripciones.extend(t for t, _ in opciones)
            return opciones[min(indice, len(opciones) - 1)][1]
        return opcion

    # Primero la elegida (índice 0) para conocer cuántas alternativas hay.
    tasas = []
    for indice in range(MAX_ALTERNATIVAS):
        if descripciones and indice >= len(descripciones):
            break
        victorias, jugadas = 0, 0
        for m in range(muestras):
            g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=elegir(indice), muestra=m,
                           metodos=metodos)
            if g is None:
                return None
            jugadas += 1
            victorias += 1 if g == lado else 0.5 if g == -1 else 0
        tasas.append(victorias / jugadas)
    if not descripciones:
        return None
    mejor = max(range(len(tasas)), key=lambda i: tasas[i])
    return {
        "paso": k,
        "lado": lado,
        "turno": entrada.get("turno"),
        "fase": entrada.get("fase"),
        "tipo": entrada["m"].replace("elegir_", ""),
        "elegida": descripciones[0],
        "ganaElegida": round(tasas[0], 2),
        "mejor": descripciones[mejor],
        "ganaMejor": round(tasas[mejor], 2),
        "opciones": [{"texto": d, "gana": round(t, 2)} for d, t in zip(descripciones, tasas)],
        "error": mejor != 0 and tasas[mejor] - tasas[0] >= MARGEN,
        "_elegir": elegir,
    }


def decisiones_a_revisar(registro: list, ia_perdio: bool, marcadas: list[int], maximo: int = 3,
                         lado: int = 1) -> list[int]:
    """Las marcadas por la persona y las de mayor caída en la estimación de
    victoria de la IA (`lado`), de esa decisión a la siguiente suya. Se miran
    también cuando la IA gana: las sutilezas cuentan igual."""
    ia = [k for k, e in enumerate(registro) if e["lado"] == lado and e["m"] in REVISABLES]
    out = [k for k in marcadas if k in ia]
    if ia_perdio or maximo:
        caidas = []
        for a, b in zip(ia, ia[1:]):
            va, vb = registro[a].get("valor"), registro[b].get("valor")
            if va is not None and vb is not None:
                caidas.append((va - vb, a))
        for _, k in sorted(caidas, reverse=True)[:maximo]:
            if k not in out:
                out.append(k)
    return out


# Sutilezas: cuando el final no separa las opciones (las dos ganan o pierden
# casi siempre, o la diferencia es chica), se compara cómo queda la partida
# 2 turnos después. Así salen los errores chicos que se repiten partida a partida.
TURNOS_SUTIL = 2
MUESTRAS_SUTIL = 8
MARGEN_SUTIL = 0.08
REVISAR_IA = 6      # decisiones de la IA con alternativas que se revisan
CANDIDATAS_IA = 18  # cuántas se prueban como máximo para hallar esas 6


def _a_horizonte(cartas, nombres, seed: int, registro: list, k: int, opcion, metodos,
                 muestras: int = MUESTRAS_SUTIL, turnos: int = TURNOS_SUTIL) -> float | None:
    from .busqueda_ataques import valor_estado

    lado = registro[k]["lado"]

    def con_horizonte(p, metodo, args):
        p.horizonte = p.e.turno + turnos
        return opcion(p, metodo, args)

    total = 0.0
    for m in range(muestras):
        try:
            g = reproducir(cartas, nombres, seed, registro, rama=k, opcion=con_horizonte, muestra=m,
                           metodos=metodos)
        except Horizonte as h:
            total += valor_estado(h.partida, lado)
            continue
        if g is None:
            return None
        total += 1 if g == lado else 0.5 if g == -1 else 0
    return total / muestras


def revisar_sutil(cartas, nombres, seed: int, registro: list, r: dict, metodos=None) -> dict:
    """Si no hubo un error claro, mira a 2 turnos la elegida contra las demás."""
    elegir = r.pop("_elegir", None)
    if r["error"] or elegir is None or len(r["opciones"]) < 2:
        return r
    estimas = []
    for indice in range(len(r["opciones"])):
        v = _a_horizonte(cartas, nombres, seed, registro, r["paso"], elegir(indice), metodos)
        if v is None:
            return r
        estimas.append(v)
    mejor = max(range(len(estimas)), key=lambda i: estimas[i])
    for o, v in zip(r["opciones"], estimas):
        o["estima"] = round(v, 3)
    # Revisión 7 desafíos: Clochafarmore rendía menos a 2 turnos pero ganaba
    # más al final (90% contra 50%): no es error si el final lo contradice.
    no_contradice = r["opciones"][mejor]["gana"] >= r["opciones"][0]["gana"]
    if mejor != 0 and estimas[mejor] - estimas[0] >= MARGEN_SUTIL and no_contradice:
        r.update({"sutil": True, "mejor": r["opciones"][mejor]["texto"],
                  "estimaElegida": round(estimas[0], 3), "estimaMejor": round(estimas[mejor], 3),
                  "turnosHorizonte": TURNOS_SUTIL})
    return r


def explicar(revision: dict) -> str:
    """Una línea en castellano para la revisión de la partida."""
    t = f"T{revision['turno']} ({str(revision['fase']).replace('_', ' ')})"
    if revision.get("sutil"):
        return (f"{t}: eligió «{revision['elegida']}»; con «{revision['mejor']}» la partida le quedaba "
                f"mejor a {revision['turnosHorizonte']} turnos ({revision['estimaMejor']:.0%} contra "
                f"{revision['estimaElegida']:.0%}): error chico.")
    if revision["error"]:
        return (f"{t}: eligió «{revision['elegida']}» (gana {revision['ganaElegida']:.0%}); "
                f"con «{revision['mejor']}» ganaba {revision['ganaMejor']:.0%}.")
    return f"{t}: «{revision['elegida']}» fue de las mejores opciones (gana {revision['ganaElegida']:.0%})."


def informe(cartas, nombres, seed: int, grabacion: list, metodos, acciones: list[dict],
            votos: dict[str, str], ganador: int | None) -> dict:
    """Autopsia completa: las jugadas marcadas ✓/✗ (por id de acción) y, si la
    IA perdió (ganador 0), sus errores clave."""
    por_accion = {str(a["id"]): a for a in acciones}
    marcadas = {}
    for accion_id, voto in (votos or {}).items():
        a = por_accion.get(str(accion_id))
        if a is not None and a.get("decision") is not None and voto in ("buena", "mala"):
            marcadas[a["decision"]] = (voto, a["texto"])
    revisiones = []
    revisadas_ia = 0
    for k in decisiones_a_revisar(grabacion, ganador == 0, list(marcadas), maximo=CANDIDATAS_IA):
        if k not in marcadas and revisadas_ia >= REVISAR_IA:
            continue
        r = revisar_decision(cartas, nombres, seed, grabacion, k, metodos=metodos)
        if r is None:
            continue
        if k not in marcadas and len(r["opciones"]) < 2:
            continue  # sin alternativas (un "pasar" obligado) no hay nada que aprender
        r = revisar_sutil(cartas, nombres, seed, grabacion, r, metodos=metodos)
        r.pop("_elegir", None)
        revisadas_ia += k not in marcadas
        voto, texto = marcadas.get(k, (None, None))
        r.update({"voto": voto, "accion": texto, "explicacion": explicar(r)})
        revisiones.append(r)
    errores = [r for r in revisiones if r["error"]]
    sutiles = [r for r in revisiones if r.get("sutil")]
    if errores:
        peor = max(errores, key=lambda r: r["ganaMejor"] - r["ganaElegida"])
        resumen = ("La IA perdió sobre todo por esto: " if ganador == 0 else "Error claro de la IA: ")             + peor["explicacion"]
        if sutiles:
            resumen += f" Además, {len(sutiles)} jugada(s) mejorables."
    elif sutiles:
        resumen = (f"Sin errores graves, pero {len(sutiles)} de {len(revisiones)} decisiones revisadas eran "
                   f"mejorables (quedan como lecciones pendientes).")
    else:
        resumen = f"La IA eligió bien en las {len(revisiones)} decisiones revisadas (con alternativas reales)."
    return {"resumen": resumen, "revisiones": revisiones}
