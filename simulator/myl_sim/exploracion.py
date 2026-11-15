"""Experimento de mejora conservadora para Faraón Djoser.

Prueba alternativas cercanas a las jugadas de la heurística, registra la
diferencia frente a partidas de control con las mismas semillas y aprende
preferencias por carta. El resultado no se conecta al Desafío IA.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from collections.abc import Callable
from datetime import datetime, timezone
import json
from pathlib import Path
import random

from .datos import Mazo, cargar_mazo
from .entrenamiento import _accion, huella_mazo, vista_legal
from . import habilidades as hab
from .jugadores import Heuristico, _es_letal
from .motor import Partida
from .simulacion import intervalo_pareado, wilson


def _puntos(ganador: int, lado: int) -> float | None:
    if ganador == -2:
        return None
    return 1.0 if ganador == lado else 0.5 if ganador == -1 else 0.0


def _momento(turno: int) -> str:
    return "inicio" if turno <= 6 else "medio" if turno <= 14 else "final"


def _contextos_plan(p, yo: int) -> tuple[str, ...]:
    """Contextos visibles que separan planes incompatibles del Dragón.

    Una carta que sirve para acelerar la curva no debe aprenderse como mejor
    respuesta cuando el castillo está en peligro. Se conservan varios
    contextos por decisión porque control de mesa y rush de Lady pueden
    coexistir en la misma Vigilia.
    """
    propio, rival = p.j(yo), p.j(1 - yo)
    out = [_momento(p.e.turno)]
    fuerza_propia = sum(max(0, hab.fuerza(p, a)) for a in propio.aliados)
    fuerza_rival = sum(max(0, hab.fuerza(p, a)) for a in rival.aliados)
    if len(propio.mazo) <= 12 or fuerza_rival >= 4:
        out.append("reducir_dano")
    if len(propio.reserva) + len(propio.pagado) <= 4 and p.e.turno <= 10:
        out.append("acelerar_oro")
    if rival.aliados and (fuerza_rival >= fuerza_propia or len(rival.aliados) > len(propio.aliados)):
        out.append("controlar_mesa")
    lady_lista = any(c.nombre.casefold() == "lady calvaur" for c in propio.cementerio)
    draig_en_mano = any(c.nombre.casefold() == "draig ifanc" for c in propio.mano)
    lady_pagable = any(c.nombre.casefold() == "lady calvaur" and p.puede_pagar(yo, c) for c in propio.mano)
    if (lady_lista and draig_en_mano) or lady_pagable:
        out.append("rush_lady")
    return tuple(out)


class _BaseConAlternativas:
    def __init__(self, seed: int):
        self.base = Heuristico(seed)

    def __getattr__(self, nombre):
        return getattr(self.base, nombre)

    def _alternativas(self, p, yo, jugadas, elegida):
        if (elegida.tipo != "jugar" or p.e.fase != "vigilia"
                or len(p.j(1 - yo).mazo) <= 6 or _es_letal(p, yo, elegida)):
            return []
        estado_rng = self.base.rng.getstate()
        try:
            puntaje_base = self.base._puntaje(p, yo, elegida)
            alternativas = []
            for j in jugadas:
                if j is elegida or j.tipo != "jugar" or j.carta is elegida.carta:
                    continue
                if not self.base._vale_la_pena(p, yo, j):
                    continue
                puntaje = self.base._puntaje(p, yo, j)
                if puntaje >= puntaje_base - 3.0:
                    alternativas.append((j, puntaje - puntaje_base))
            return alternativas
        finally:
            self.base.rng.setstate(estado_rng)


class Explorador(_BaseConAlternativas):
    nombre = "explorador_djoser"

    def __init__(self, seed: int, epsilon: float):
        super().__init__(seed)
        self.rng = random.Random(seed + 99173)
        self.epsilon = epsilon
        self.eventos = []

    def elegir_jugada(self, p, yo, jugadas):
        elegida = self.base.elegir_jugada(p, yo, jugadas)
        if self.rng.random() >= self.epsilon:
            return elegida
        alternativas = self._alternativas(p, yo, jugadas, elegida)
        if not alternativas:
            return elegida
        alternativa, diferencia = self.rng.choice(alternativas)
        self.eventos.append({
            "turno": p.e.turno,
            "contextos": _contextos_plan(p, yo),
            "base": elegida.carta.carta.id,
            "alternativa": alternativa.carta.carta.id,
            "diferenciaPuntaje": round(diferencia, 3),
            "vista": vista_legal(p, yo),
            "opcionesLegales": [_accion(j) for j in jugadas],
            "accionBase": _accion(elegida),
            "accionAlternativa": _accion(alternativa),
        })
        return alternativa


class PoliticaAlternativas(_BaseConAlternativas):
    nombre = "alternativas_djoser"

    def __init__(self, seed: int, preferencias: dict[str, float],
                 *, preferencias_contexto: dict[str, float] | None = None,
                 factor: float = 20.0, minimo: float = 0.02,
                 guardar_decisiones: bool = False):
        super().__init__(seed)
        self.preferencias = preferencias
        self.preferencias_contexto = preferencias_contexto or {}
        self.factor = factor
        self.minimo = minimo
        self.desviaciones = 0
        self.cambios: Counter[tuple[str, str]] = Counter()
        self.guardar_decisiones = guardar_decisiones
        self.historial: list[dict] = []

    def _preferencia(self, p, yo: int, carta_id: str) -> float:
        global_ = self.preferencias.get(carta_id, 0.0)
        contextos = [self.preferencias_contexto[f"{carta_id}@{contexto}"]
                     for contexto in _contextos_plan(p, yo)
                     if f"{carta_id}@{contexto}" in self.preferencias_contexto]
        return global_ if not contextos else 0.7 * (sum(contextos) / len(contextos)) + 0.3 * global_

    def elegir_jugada(self, p, yo, jugadas):
        elegida = self.base.elegir_jugada(p, yo, jugadas)
        alternativas = self._alternativas(p, yo, jugadas, elegida)
        if not alternativas:
            return elegida
        preferencia_base = self._preferencia(p, yo, elegida.carta.carta.id)
        mejor = max(alternativas, key=lambda item:
                    item[1] + self.factor * self._preferencia(p, yo, item[0].carta.carta.id))
        candidata, diferencia_puntaje = mejor
        diferencia_preferencia = (self._preferencia(p, yo, candidata.carta.carta.id)
                                 - preferencia_base)
        if (diferencia_preferencia >= self.minimo
                and diferencia_puntaje + self.factor * diferencia_preferencia > 0):
            self.desviaciones += 1
            self.cambios[(elegida.carta.carta.id, candidata.carta.carta.id)] += 1
            if self.guardar_decisiones:
                self.historial.append({"turno": p.e.turno,
                    "base": elegida.carta.carta.id, "alternativa": candidata.carta.carta.id,
                    "vista": vista_legal(p, yo),
                    "opcionesLegales": [_accion(j) for j in jugadas],
                    "accionBase": _accion(elegida), "accionAlternativa": _accion(candidata)})
            return candidata
        return elegida


def _partida(mazo_a: Mazo, mazo_b: Mazo, seed: int, invertido: bool,
             politica=None):
    lado_a = 1 if invertido else 0
    mazos = (mazo_b.cartas, mazo_a.cartas) if invertido else (mazo_a.cartas, mazo_b.cartas)
    jugadores = [Heuristico(seed * 2), Heuristico(seed * 2 + 1)]
    if politica is not None:
        jugadores[lado_a] = politica
    registro = Partida(mazos, tuple(jugadores), inicial=None, seed=seed).jugar()
    return _puntos(registro.ganador, lado_a)


def recolectar(mazo_a: Mazo, mazo_b: Mazo, salida: Path, *,
              pares: int = 1000, seed: int = 81001,
              epsilon: float = 0.3) -> dict:
    if pares < 1 or not 0 < epsilon <= 1:
        raise ValueError("Pares y epsilon deben ser positivos")
    from .informe_entrenamiento import huella_motor

    salida.parent.mkdir(parents=True, exist_ok=True)
    eventos = anomalias = 0
    with salida.open("w", encoding="utf-8") as f:
        metadata = {"tipo": "metadata", "esquema": 1,
                    "generado": datetime.now(timezone.utc).isoformat(),
                    "politica": "heuristico_con_exploracion",
                    "motorHuella": huella_motor(),
                    "epsilon": epsilon, "seed": seed, "pares": pares,
                    "mazoA": {"id": mazo_a.id, "nombre": mazo_a.nombre,
                              "huella": huella_mazo(mazo_a)},
                    "mazoB": {"id": mazo_b.id, "nombre": mazo_b.nombre,
                              "huella": huella_mazo(mazo_b)}}
        f.write(json.dumps(metadata, ensure_ascii=False) + "\n")
        for k in range(pares):
            for invertido in (False, True):
                s = seed + 2 * k + int(invertido)
                control = _partida(mazo_a, mazo_b, s, invertido)
                explorador = Explorador(s * 2 + int(invertido), epsilon)
                explorado = _partida(mazo_a, mazo_b, s, invertido, explorador)
                if control is None or explorado is None:
                    anomalias += 1
                    continue
                eventos += len(explorador.eventos)
                f.write(json.dumps({"tipo": "partida", "par": k,
                                    "invertido": invertido, "seed": s,
                                    "control": control, "explorado": explorado,
                                    "eventos": explorador.eventos}, ensure_ascii=False) + "\n")
    from .informe_entrenamiento import guardar_informe_exploracion

    informe, detalle = guardar_informe_exploracion(salida)
    return {"archivo": str(salida), "pares": pares, "eventos": eventos,
            "anomalas": anomalias, "mazoA": metadata["mazoA"],
            "mazoB": metadata["mazoB"], "informeJugadas": str(informe),
            "detalleJugadas": str(detalle)}


def aprender(archivo: Path, salida: Path, *, suavizado: int = 15) -> dict:
    with archivo.open(encoding="utf-8") as f:
        metadata = json.loads(next(f))
        if metadata.get("esquema") != 1 or metadata.get("tipo") != "metadata":
            raise ValueError("Datos de exploración incompatibles")
        suma = defaultdict(float)
        conteo = defaultdict(int)
        suma_contexto = defaultdict(float)
        conteo_contexto = defaultdict(int)
        for linea in f:
            fila = json.loads(linea)
            eventos = fila["eventos"]
            if not eventos:
                continue
            ventaja = fila["explorado"] - fila["control"]
            for evento in eventos:
                alternativa, base = evento["alternativa"], evento["base"]
                suma[alternativa] += ventaja
                conteo[alternativa] += 1
                suma[base] -= ventaja
                conteo[base] += 1
                contextos = evento.get("contextos") or [_momento(int(evento["turno"]))]
                for contexto in contextos:
                    suma_contexto[f"{alternativa}@{contexto}"] += ventaja
                    conteo_contexto[f"{alternativa}@{contexto}"] += 1
                    suma_contexto[f"{base}@{contexto}"] -= ventaja
                    conteo_contexto[f"{base}@{contexto}"] += 1
    preferencias = {c: round(suma[c] / (conteo[c] + suavizado), 5)
                    for c in conteo if conteo[c] >= 10}
    preferencias_contexto = {
        c: round(suma_contexto[c] / (conteo_contexto[c] + suavizado), 5)
        for c in conteo_contexto if conteo_contexto[c] >= 12
    }
    modelo = {"esquema": 2, "tipo": "preferencias_exploratorias_contextuales",
              "creado": datetime.now(timezone.utc).isoformat(),
              "origen": {"archivo": archivo.name,
                         "mazoA": metadata["mazoA"], "mazoB": metadata["mazoB"],
                         "pares": metadata["pares"], "epsilon": metadata["epsilon"],
                         "motorHuella": metadata.get("motorHuella")},
              "suavizado": suavizado,
              "preferencias": preferencias,
              "preferenciasContexto": preferencias_contexto,
              "muestras": dict(conteo),
              "muestrasContexto": dict(conteo_contexto)}
    from .informe_entrenamiento import guardar_informe_exploracion, huella_archivo, ruta_unica

    salida.parent.mkdir(parents=True, exist_ok=True)
    informe, detalle = guardar_informe_exploracion(
        archivo, ruta_unica(salida, "jugadas.md"))
    modelo["origen"]["sha256"] = huella_archivo(archivo)
    modelo["informeJugadas"] = informe.name
    modelo["detalleJugadas"] = detalle.name
    salida.write_text(json.dumps(modelo, ensure_ascii=False, indent=2), encoding="utf-8")
    return modelo


def evaluar(modelo: dict, mazo_a: Mazo, mazo_b: Mazo, *,
            pares: int, seed: int, factor: float = 20.0,
            minimo: float = 0.02,
            decisiones: list[dict] | Callable[[dict], None] | None = None) -> dict:
    if huella_mazo(mazo_a) != modelo["origen"]["mazoA"]["huella"]:
        raise ValueError(f"Cambió el mazo {mazo_a.nombre}: recolecta datos nuevos")
    if pares < 1:
        raise ValueError("Se requiere al menos un par")
    from .informe_entrenamiento import huella_motor

    motor_huella = huella_motor()
    puntos_modelo = puntos_control = validas = anomalas = desviaciones = 0
    cambios: Counter[tuple[str, str]] = Counter()
    diferencias: Counter[float] = Counter()
    for k in range(pares):
        diferencia_par = 0.0
        validas_par = 0
        for invertido in (False, True):
            s = seed + 2 * k + int(invertido)
            control = _partida(mazo_a, mazo_b, s, invertido)
            politica = PoliticaAlternativas(s * 2 + int(invertido),
                                            modelo["preferencias"],
                                            preferencias_contexto=modelo.get("preferenciasContexto"),
                                            factor=factor, minimo=minimo,
                                            guardar_decisiones=decisiones is not None)
            candidato = _partida(mazo_a, mazo_b, s, invertido, politica)
            desviaciones += politica.desviaciones
            cambios.update(politica.cambios)
            if control is None or candidato is None:
                anomalas += 1
                continue
            if decisiones is not None:
                fila = {"tipo": "partida", "par": k, "seed": s,
                        "invertido": invertido, "control": control,
                        "explorado": candidato, "eventos": politica.historial}
                if callable(decisiones):
                    decisiones(fila)
                else:
                    decisiones.append(fila)
            validas += 1
            validas_par += 1
            puntos_modelo += candidato
            puntos_control += control
            diferencia_par += candidato - control
        if validas_par == 2:
            diferencias[diferencia_par / 2] += 1
    intervalo, metodo = intervalo_pareado(diferencias, seed=154)
    nombres = {c.id: c.nombre for c in mazo_a.cartas}
    mejora = validas >= 200 and anomalas == 0 and intervalo is not None and intervalo[0] > 0
    return {"pares": pares, "seed": seed, "factor": factor, "minimo": minimo,
            "motorHuella": motor_huella,
            "mazoAprendido": {"id": mazo_a.id, "nombre": mazo_a.nombre,
                               "huella": huella_mazo(mazo_a)},
            "rival": {"id": mazo_b.id, "nombre": mazo_b.nombre,
                      "huella": huella_mazo(mazo_b),
                      "copiasSinProgramar": sum(n for _, n in mazo_b.sin_programar()),
                      "usadoEnEntrenamiento": (
                          huella_mazo(mazo_b) == modelo["origen"]["mazoB"]["huella"])},
            "partidasValidas": validas, "anomalas": anomalas,
            "winrateModelo": round(puntos_modelo / validas, 4) if validas else 0,
            "winrateHeuristica": round(puntos_control / validas, 4) if validas else 0,
            "diferencia": round((puntos_modelo - puntos_control) / validas, 4)
                          if validas else 0,
            "ic95Modelo": wilson(puntos_modelo, validas),
            "ic95Heuristica": wilson(puntos_control, validas),
            "ic95Diferencia": intervalo, "ic95DiferenciaBootstrap": intervalo,
            "metodoIntervaloDiferencia": metodo,
            "desviaciones": desviaciones,
            "cambiosMasFrecuentes": [
                {"de": nombres.get(a, a), "a": nombres.get(b, b), "veces": n}
                for (a, b), n in cambios.most_common(8)
            ],
            "mejoraEnEsteCruce": mejora,
            "aptoParaDesafio": False}


def main(argv=None):
    ap = argparse.ArgumentParser(description="Exploración y mejora de Djoser")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("recolectar")
    r.add_argument("mazo_a")
    r.add_argument("mazo_b")
    r.add_argument("salida", type=Path)
    r.add_argument("--pares", type=int, default=1000)
    r.add_argument("--seed", type=int, default=81001)
    r.add_argument("--epsilon", type=float, default=0.3)
    t = sub.add_parser("aprender")
    t.add_argument("episodios", type=Path)
    t.add_argument("modelo", type=Path)
    e = sub.add_parser("evaluar")
    e.add_argument("modelo", type=Path)
    e.add_argument("--pares", type=int, default=100)
    e.add_argument("--seed", type=int, default=99001)
    e.add_argument("--factor", type=float, default=20.0)
    e.add_argument("--minimo", type=float, default=0.02)
    e.add_argument("--rival", help="id de otra baraja para probar generalización")
    e.add_argument("--salida", type=Path)
    args = ap.parse_args(argv)
    if args.cmd == "recolectar":
        mazos = [cargar_mazo("", x, usar_cache=True) for x in (args.mazo_a, args.mazo_b)]
        resultado = recolectar(*mazos, args.salida, pares=args.pares,
                               seed=args.seed, epsilon=args.epsilon)
    elif args.cmd == "aprender":
        resultado = aprender(args.episodios, args.modelo)
    else:
        modelo = json.loads(args.modelo.read_text(encoding="utf-8"))
        mazos = [cargar_mazo("", modelo["origen"][k]["id"], usar_cache=True)
                 for k in ("mazoA", "mazoB")]
        if args.rival:
            mazos[1] = cargar_mazo("", args.rival, usar_cache=True)
        from .informe_entrenamiento import (guardar_informe_exploracion, huella_motor,
                                           ruta_ejecucion, ruta_unica)

        salida = args.salida or ruta_ejecucion("evaluacion_politica", args.seed)
        salida.parent.mkdir(parents=True, exist_ok=True)
        informe = ruta_unica(salida, "jugadas.md")
        detalle = informe.with_name(informe.name.removesuffix("_jugadas.md") + "_decisiones.jsonl")
        with detalle.open("w", encoding="utf-8") as f:
            f.write(json.dumps({"tipo": "metadata", "esquema": 1,
                                "motorHuella": huella_motor(),
                                "mazoA": modelo["origen"]["mazoA"],
                                "mazoB": {"id": mazos[1].id, "nombre": mazos[1].nombre,
                                          "huella": huella_mazo(mazos[1])}}, ensure_ascii=False) + "\n")

            def guardar_decision(fila: dict) -> None:
                f.write(json.dumps(fila, ensure_ascii=False) + "\n")

            resultado = evaluar(modelo, *mazos, pares=args.pares, seed=args.seed,
                                factor=args.factor, minimo=args.minimo,
                                decisiones=guardar_decision)
        informe, datos = guardar_informe_exploracion(detalle, informe)
        resultado.update({"archivoResultado": str(salida), "detalleDecisiones": detalle.name,
                          "informeJugadas": informe.name, "datosJugadas": datos.name})
        salida.write_text(json.dumps(resultado, ensure_ascii=False, indent=2),
                          encoding="utf-8")
    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
