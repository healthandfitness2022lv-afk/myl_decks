"""Búsqueda por simulación para elegir bloqueos legales.

Asume conocidas las listas de ambos mazos. La mano oculta rival y el orden de
los mazos se muestrean; las cartas reveladas en mano permanecen visibles.
Las continuaciones usan la heurística existente y terminan en victoria o derrota.
"""

from __future__ import annotations

import argparse
from collections import Counter
from collections.abc import Callable
import copy
import json
from pathlib import Path
import random
import time

from .datos import cargar_mazo
from .entrenamiento import huella_mazo
from .entrenamiento import vista_legal
from .jugadores import Heuristico
from .modelo import Zona
from .motor import FinPartida, Partida
from .simulacion import intervalo_pareado, wilson


def _copia_muestreada(partida: Partida, defensor: int, seed: int) -> Partida:
    """Copia el estado sin copiar el adaptador humano ni usar el azar real."""
    memo = {id(j): None for j in partida.jugadores}
    memo[id(partida.pasos)] = []
    if partida.e.log is not None:
        memo[id(partida.e.log)] = None
    for jugador in partida.e.jugadores:
        for zona in (jugador.mazo, jugador.mano, jugador.reserva, jugador.pagado,
                     jugador.defensa, jugador.ataque, jugador.apoyo,
                     jugador.cementerio, jugador.destierro):
            for instancia in zona:
                memo[id(instancia.carta)] = instancia.carta
    for instancia in partida.e.portadas:
        memo[id(instancia.carta)] = instancia.carta
    copia = copy.deepcopy(partida, memo)
    copia.e.log = None
    copia.pasos = []
    copia.jugadores = (Heuristico(seed * 2 + 1), Heuristico(seed * 2 + 2))
    rng = random.Random(seed)

    propio = copia.j(defensor)
    propio.mazo.sort(key=lambda x: (x.carta.id, x.uid))
    rng.shuffle(propio.mazo)

    rival = copia.j(1 - defensor)
    reveladas = [x for x in rival.mano if getattr(x, "revelada", False)]
    cantidad_oculta = len(rival.mano) - len(reveladas)
    desconocidas = [x for x in rival.mano if not getattr(x, "revelada", False)] + rival.mazo
    desconocidas.sort(key=lambda x: (x.carta.id, x.uid))
    rng.shuffle(desconocidas)
    rival.mano = reveladas + desconocidas[:cantidad_oculta]
    rival.mazo = desconocidas[cantidad_oculta:]
    for carta in rival.mano:
        carta.zona = Zona.MANO
    for carta in rival.mazo:
        carta.zona = Zona.MAZO
        carta.revelada = False
    copia.e.rng = random.Random(seed ^ 0x6D796C)
    return copia


def _clave(mapa: dict[int, object]) -> tuple[tuple[int, int], ...]:
    return tuple(sorted((int(atk), int(blk.uid)) for atk, blk in mapa.items()))


def _opciones(partida: Partida, atacantes: list, bloqueadores: list,
              prior: tuple[tuple[int, int], ...], rng: random.Random,
              max_candidatos: int) -> tuple[list[tuple[tuple[int, int], ...]], bool]:
    """Enumera asignaciones sin reutilizar bloqueadores y conserva no bloquear."""
    limite = 5000
    todas: list[tuple[tuple[int, int], ...]] = []
    truncado = False

    def visitar(indice: int, usados: set[int], parcial: list[tuple[int, int]]) -> None:
        nonlocal truncado
        if len(todas) >= limite:
            truncado = True
            return
        if indice == len(atacantes):
            todas.append(tuple(sorted(parcial)))
            return
        atacante = atacantes[indice]
        visitar(indice + 1, usados, parcial)
        for b in bloqueadores:
            if b.uid not in usados and partida.puede_bloquear(atacante, b):
                usados.add(b.uid)
                parcial.append((atacante.uid, b.uid))
                visitar(indice + 1, usados, parcial)
                parcial.pop()
                usados.remove(b.uid)
                if truncado:
                    return

    visitar(0, set(), [])
    obligatorias = [()]
    if prior != ():
        obligatorias.append(prior)
    restantes = [x for x in todas if x not in obligatorias]
    cupos = max(0, max_candidatos - len(obligatorias))
    if len(restantes) > cupos:
        restantes = rng.sample(restantes, cupos)
        truncado = True
    return obligatorias + restantes, truncado


def _continuar(copia: Partida, defensor: int,
               opcion: tuple[tuple[int, int], ...]) -> int:
    """Resuelve los bloqueos, el resto del turno y los turnos posteriores."""
    por_uid = {b.uid: b for b in copia.j(defensor).defensa}
    bloqueos = dict(copia.bloqueos)
    bloqueos.update({atk: por_uid[blk] for atk, blk in opcion})
    activo = copia.e.activo
    try:
        copia._resolver_bloqueos(copia.atacantes, bloqueos, defensor)
        copia._finalizar_turno(activo)
        copia._cerrar_turno(activo)
        copia._ciclo_turnos()
    except FinPartida:
        pass
    return copia.e.ganador if copia.e.ganador is not None else -2


class BuscadorBloqueos(Heuristico):
    """Usa simulaciones para bloqueos y la heurística para las demás decisiones."""

    nombre = "busqueda_bloqueos"

    def __init__(self, seed: int | None = None, *, muestras: int = 4,
                 max_candidatos: int = 8, max_segundos: float | None = 5.0,
                 guardar_decisiones: bool = False, muestras_validacion: int = 0):
        super().__init__(seed)
        if (muestras < 1 or max_candidatos < 2 or muestras_validacion < 0
                or (max_segundos is not None and max_segundos <= 0)):
            raise ValueError("Presupuesto de búsqueda inválido")
        self.muestras = muestras
        self.max_candidatos = max_candidatos
        self.max_segundos = max_segundos
        self.rng_busqueda = random.Random(seed)
        self.ultimo_analisis: dict | None = None
        self.busquedas = 0
        self.desviaciones = 0
        self.simulaciones = 0
        self.simulaciones_validacion = 0
        self.segundos_busqueda = 0.0
        self.guardar_decisiones = guardar_decisiones
        self.muestras_validacion = muestras_validacion
        self.historial: list[dict] = []

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        inicio = time.monotonic()
        seed_prior = self.rng_busqueda.randrange(1, 2**31)
        copia = _copia_muestreada(p, yo, seed_prior)
        ataques_copia = {x.uid: x for x in copia.atacantes}
        defensas_copia = {x.uid: x for x in copia.j(yo).defensa}
        prior_mapa = copia.decide(yo).elegir_bloqueos(
            copia, yo, [ataques_copia[a.uid] for a in atacantes],
            [defensas_copia[b.uid] for b in bloqueadores])
        por_atk = {a.uid: a for a in atacantes}
        por_blk = {b.uid: b for b in bloqueadores}
        usados: set[int] = set()
        prior_limpio = {}
        for atk, blk in prior_mapa.items():
            if (atk in por_atk and blk.uid in por_blk and blk.uid not in usados
                    and p.puede_bloquear(por_atk[atk], por_blk[blk.uid])):
                prior_limpio[atk] = por_blk[blk.uid]
                usados.add(blk.uid)
        prior = _clave(prior_limpio)
        opciones, limitada = _opciones(p, atacantes, bloqueadores, prior,
                                      self.rng_busqueda, self.max_candidatos)
        puntos = [0.0] * len(opciones)
        validas = [0] * len(opciones)
        resultados: list[list[float | None]] = [[] for _ in opciones]
        realizadas = 0
        semillas_busqueda = []
        for _ in range(self.muestras):
            seed = self.rng_busqueda.randrange(1, 2**31)
            semillas_busqueda.append(seed)
            for i, opcion in enumerate(opciones):
                copia = _copia_muestreada(p, yo, seed)
                ganador = _continuar(copia, yo, opcion)
                if ganador != -2:
                    validas[i] += 1
                    valor = 1.0 if ganador == yo else 0.5 if ganador == -1 else 0.0
                    puntos[i] += valor
                    resultados[i].append(valor)
                else:
                    resultados[i].append(None)
            realizadas += 1
            if self.max_segundos is not None and time.monotonic() - inicio >= self.max_segundos:
                break
        scores = [puntos[i] / validas[i] if validas[i] else -1.0 for i in range(len(opciones))]
        elegido = max(range(len(opciones)), key=lambda i: (scores[i], opciones[i] == prior))
        indice_prior = opciones.index(prior)

        def diferencia_con_prior(i: int) -> tuple[float | None, int]:
            comparables = [(a, b) for a, b in zip(resultados[i], resultados[indice_prior])
                           if a is not None and b is not None]
            if not comparables:
                return None, 0
            return round(sum(a - b for a, b in comparables) / len(comparables), 4), len(comparables)

        validacion = None
        semillas_validacion = []
        if self.muestras_validacion and opciones[elegido] != prior:
            rng_validacion = random.Random(seed_prior ^ 0x56414C)
            comparables: list[tuple[float, float]] = []
            validacion_detalle = []
            for _ in range(self.muestras_validacion):
                semilla = rng_validacion.randrange(1, 2**31)
                semillas_validacion.append(semilla)
                resultados_par = []
                for opcion in (opciones[elegido], prior):
                    ganador = _continuar(_copia_muestreada(p, yo, semilla), yo, opcion)
                    resultados_par.append(None if ganador == -2 else
                                          1.0 if ganador == yo else 0.5 if ganador == -1 else 0.0)
                self.simulaciones_validacion += sum(x is not None for x in resultados_par)
                validacion_detalle.append({"semilla": semilla, "elegida": resultados_par[0],
                                           "referencia": resultados_par[1]})
                if None not in resultados_par:
                    comparables.append((resultados_par[0], resultados_par[1]))
            n = len(comparables)
            validacion = {"muestras": n,
                          "estimacionElegida": round(sum(a for a, _ in comparables) / n, 4) if n else None,
                          "estimacionReferencia": round(sum(b for _, b in comparables) / n, 4) if n else None,
                          "diferencia": round(sum(a - b for a, b in comparables) / n, 4) if n else None,
                          "mejora": sum(a > b for a, b in comparables),
                          "igual": sum(a == b for a, b in comparables),
                          "empeora": sum(a < b for a, b in comparables),
                          "resultados": validacion_detalle}

        self.busquedas += 1
        self.desviaciones += opciones[elegido] != prior
        self.simulaciones += sum(validas)
        duracion = time.monotonic() - inicio
        self.segundos_busqueda += duracion
        self.ultimo_analisis = {
            "muestrasPorOpcion": realizadas,
            "opcionesLimitadas": limitada,
            "segundos": round(duracion, 3),
            **({"validacionIndependiente": validacion} if validacion is not None else {}),
            "bloqueosObligatorios": [
                {"atacante": a.nombre, "atacanteUid": a.uid,
                 "bloqueador": p.bloqueos[a.uid].nombre,
                 "bloqueadorUid": p.bloqueos[a.uid].uid}
                for a in p.atacantes if a.uid in p.bloqueos
            ],
            "opciones": [
                {"bloqueos": [{"atacante": por_atk[a].nombre, "atacanteUid": a,
                               "bloqueador": por_blk[b].nombre, "bloqueadorUid": b}
                              for a, b in opcion],
                 "validas": validas[i],
                 "estimacionVictoria": round(scores[i], 4) if validas[i] else None,
                 "referenciaHeuristica": i == indice_prior,
                 "diferenciaConReferencia": diferencia_con_prior(i)[0],
                 "muestrasComparables": diferencia_con_prior(i)[1],
                 "elegida": i == elegido}
                for i, opcion in enumerate(opciones)
            ],
        }
        if self.guardar_decisiones:
            self.historial.append({"tipo": "bloqueo", "turno": p.e.turno,
                                   "defensor": yo, "vista": vista_legal(p, yo),
                                   "seedReferencia": seed_prior,
                                   "semillasBusqueda": semillas_busqueda,
                                   "semillasValidacion": semillas_validacion,
                                   "resultadosBusqueda": [
                                       {"semilla": semilla,
                                        "porOpcion": [resultados[i][k] for i in range(len(opciones))]}
                                       for k, semilla in enumerate(semillas_busqueda)
                                   ],
                                   "analisis": copy.deepcopy(self.ultimo_analisis)})
        return {atk: por_blk[blk] for atk, blk in opciones[elegido]}


class PoliticaConBusqueda:
    """Mantiene la política elegida para cada decisión salvo los bloqueos."""

    nombre = "busqueda_bloqueos"

    def __init__(self, base, seed: int, *, muestras: int = 8,
                 max_candidatos: int = 8, max_segundos: float | None = 5.0):
        self.base = base
        self.buscador = BuscadorBloqueos(seed, muestras=muestras,
                                         max_candidatos=max_candidatos,
                                         max_segundos=max_segundos)

    def __getattr__(self, nombre):
        return getattr(self.base, nombre)

    @property
    def ultimo_analisis(self):
        return self.buscador.ultimo_analisis

    def elegir_bloqueos(self, p, yo, atacantes, bloqueadores):
        return self.buscador.elegir_bloqueos(p, yo, atacantes, bloqueadores)


def evaluar(mazo_a, mazo_b, *, pares: int, seed: int, muestras: int,
            max_candidatos: int, max_segundos: float | None,
            decisiones: list[dict] | Callable[[dict], None] | None = None,
            muestras_validacion: int = 0) -> dict:
    """Compara Djoser con búsqueda y heurística, alternando asientos."""
    if pares < 1:
        raise ValueError("Se requiere al menos un par de semillas")
    from .informe_entrenamiento import huella_motor

    motor_huella = huella_motor()
    puntos_busqueda = puntos_control = validas = anomalas = busquedas = 0
    desviaciones = simulaciones = simulaciones_validacion = 0
    segundos_busqueda = 0.0
    diferencias: Counter[float] = Counter()
    inicio = time.monotonic()
    for k in range(pares):
        diferencia_par = 0.0
        validas_par = 0
        for invertido in (False, True):
            s = seed + 2 * k + int(invertido)
            lado = 1 if invertido else 0
            mazos = (mazo_b.cartas, mazo_a.cartas) if invertido else (mazo_a.cartas, mazo_b.cartas)
            resultados = []
            for usar_busqueda in (False, True):
                jugadores = [Heuristico(s * 2), Heuristico(s * 2 + 1)]
                buscador = None
                if usar_busqueda:
                    buscador = BuscadorBloqueos(s * 2 + lado, muestras=muestras,
                                                max_candidatos=max_candidatos,
                                                max_segundos=max_segundos,
                                                guardar_decisiones=decisiones is not None,
                                                muestras_validacion=muestras_validacion)
                    jugadores[lado] = buscador
                registro = Partida(mazos, tuple(jugadores), inicial=None, seed=s).jugar()
                if buscador:
                    busquedas += buscador.busquedas
                    desviaciones += buscador.desviaciones
                    simulaciones += buscador.simulaciones
                    simulaciones_validacion += buscador.simulaciones_validacion
                    segundos_busqueda += buscador.segundos_busqueda
                ganador = registro.ganador
                resultados.append(None if ganador == -2 else
                                  1.0 if ganador == lado else 0.5 if ganador == -1 else 0.0)
            if None in resultados:
                anomalas += 1
                continue
            control, resultado = resultados
            puntos_control += control
            puntos_busqueda += resultado
            validas += 1
            validas_par += 1
            diferencia_par += resultado - control
            if decisiones is not None and buscador is not None:
                for evento in buscador.historial:
                    fila = {**evento, "seedPartida": s, "par": k,
                            "invertido": invertido, "resultadoBusqueda": resultado,
                            "resultadoControl": control}
                    if callable(decisiones):
                        decisiones(fila)
                    else:
                        decisiones.append(fila)
        if validas_par == 2:
            diferencias[diferencia_par / 2] += 1
    intervalo, metodo = intervalo_pareado(diferencias, seed=378)
    return {
        "mazo": mazo_a.nombre, "rival": mazo_b.nombre, "pares": pares, "seed": seed,
        "motorHuella": motor_huella,
        "huellaMazo": huella_mazo(mazo_a), "huellaRival": huella_mazo(mazo_b),
        "copiasSinProgramar": [sum(n for _, n in mazo_a.sin_programar()),
                               sum(n for _, n in mazo_b.sin_programar())],
        "partidasValidas": validas, "anomalas": anomalas,
        "muestras": muestras, "maxCandidatos": max_candidatos,
        "muestrasValidacion": muestras_validacion,
        "maxSegundosPorDecision": max_segundos,
        "winrateBusqueda": round(puntos_busqueda / validas, 4) if validas else 0,
        "winrateHeuristica": round(puntos_control / validas, 4) if validas else 0,
        "diferencia": round((puntos_busqueda - puntos_control) / validas, 4) if validas else 0,
        "ic95Busqueda": wilson(puntos_busqueda, validas),
        "ic95Heuristica": wilson(puntos_control, validas),
        "ic95Diferencia": intervalo, "ic95DiferenciaBootstrap": intervalo,
        "metodoIntervaloDiferencia": metodo,
        "decisionesBuscadas": busquedas, "desviacionesHeuristica": desviaciones,
        "simulacionesCompletadas": simulaciones,
        "simulacionesValidacion": simulaciones_validacion,
        "segundosBusqueda": round(segundos_busqueda, 2),
        "segundosPorDecision": round(segundos_busqueda / busquedas, 3) if busquedas else 0,
        "segundos": round(time.monotonic() - inicio, 2),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Probar búsqueda de bloqueos")
    ap.add_argument("mazo_a")
    ap.add_argument("mazo_b")
    ap.add_argument("--pares", type=int, default=10)
    ap.add_argument("--seed", type=int, default=710001)
    ap.add_argument("--muestras", type=int, default=4)
    ap.add_argument("--max-candidatos", type=int, default=8)
    ap.add_argument("--max-segundos", type=float, default=5.0)
    ap.add_argument("--sin-limite-tiempo", action="store_true",
                    help="evaluación reproducible con el número fijo de muestras")
    ap.add_argument("--muestras-validacion", type=int, default=8,
                    help="escenarios nuevos para comparar la opción elegida con la referencia")
    ap.add_argument("--salida", type=Path)
    args = ap.parse_args(argv)
    mazos = [cargar_mazo("", x, usar_cache=True) for x in (args.mazo_a, args.mazo_b)]
    from .informe_entrenamiento import (huella_motor, resumir_informe_bloqueos,
                                       ruta_ejecucion, rutas_informe_bloqueos)

    salida = args.salida or ruta_ejecucion("busqueda_bloqueos", args.seed)
    salida.parent.mkdir(parents=True, exist_ok=True)
    detalle, resumen = rutas_informe_bloqueos(salida)
    with detalle.open("w", encoding="utf-8") as archivo:
        archivo.write(json.dumps({"tipo": "metadata", "motorHuella": huella_motor(),
                                  "seed": args.seed, "pares": args.pares,
                                  "huellaMazo": huella_mazo(mazos[0]),
                                  "huellaRival": huella_mazo(mazos[1])}, ensure_ascii=False) + "\n")

        def guardar_decision(evento: dict) -> None:
            archivo.write(json.dumps(evento, ensure_ascii=False) + "\n")

        informe = evaluar(*mazos, pares=args.pares, seed=args.seed, muestras=args.muestras,
                          max_candidatos=args.max_candidatos,
                          max_segundos=None if args.sin_limite_tiempo else args.max_segundos,
                          decisiones=guardar_decision,
                          muestras_validacion=args.muestras_validacion)
    resumir_informe_bloqueos(informe, detalle, resumen)
    informe["archivoResultado"] = str(salida)
    informe["detalleDecisiones"] = detalle.name
    informe["informeJugadas"] = resumen.name
    salida.write_text(json.dumps(informe, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(informe, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
