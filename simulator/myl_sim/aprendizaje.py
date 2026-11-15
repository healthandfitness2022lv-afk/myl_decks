"""Primera política aprendida para decisiones de jugada.

Imita las decisiones registradas de la heurística con un perceptrón de ranking.
Los ataques, bloqueos y respuestas siguen delegados a la heurística. La
evaluación usa partidas nuevas y nunca activa el modelo en el desafío real.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
from typing import Any

from .datos import CACHE, Mazo, cargar_mazo
from .entrenamiento import _accion, huella_mazo, vista_legal
from .jugadores import Heuristico
from .motor import Partida
from .simulacion import wilson


ESQUEMA_MODELO = 1


def _tramo(valor: int, cortes: tuple[int, ...]) -> str:
    return str(next((c for c in cortes if valor <= c), f"{cortes[-1]}+"))


def _rasgos(vista: dict[str, Any], accion: dict[str, Any], cantidad: int) -> tuple[str, ...]:
    """Usa solo información visible y atributos de la acción legal."""
    yo, rival = vista["yo"], vista["rival"]
    tipo = accion["tipo"]
    fase = vista["fase"]
    carta_id = accion.get("cartaId", "sin_carta")
    disponibles = len(yo["reserva"]) + int(yo.get("orosVirtuales", 0))
    mano = yo["mano"]
    carta = next((c for zona in (mano, yo["reserva"], yo["pagado"],
                  yo["defensa"], yo["ataque"], yo["apoyo"], yo["cementerio"])
                  for c in zona if c.get("id") == carta_id), None)
    clase = carta["tipo"] if carta else "sin_tipo"
    coste = int(carta.get("coste") or 0) if carta else 0
    fuerza = int(carta.get("fuerza") or 0) if carta else 0
    mi_castillo = _tramo(len_castillo := int(yo["castillo"]), (5, 10, 20, 30, 40))
    su_castillo = _tramo(int(rival["castillo"]), (5, 10, 20, 30, 40))
    tramo_oro = _tramo(disponibles, (0, 1, 2, 3, 5, 8))
    rival_amenaza = bool(rival["ataque"] or rival["defensa"])
    return (
        f"tipo={tipo}", f"tipo_fase={tipo}:{fase}",
        f"carta={carta_id}", f"carta_fase={carta_id}:{fase}",
        f"clase={clase}", f"tipo_clase={tipo}:{clase}",
        f"coste={_tramo(coste, (0, 1, 2, 3, 4, 5, 7))}",
        f"fuerza={_tramo(fuerza, (0, 1, 2, 3, 4, 6))}",
        f"habilidad={accion.get('habilidad', 'ninguna')}",
        f"portador={accion.get('portadorId', 'ninguno')}",
        f"turno_tipo={_tramo(int(vista['turno']), (2, 4, 8, 16))}:{tipo}",
        f"oro_tipo={tramo_oro}:{tipo}",
        f"oro_carta={tramo_oro}:{carta_id}",
        f"mano_tipo={_tramo(len(mano), (0, 2, 4, 6, 8))}:{tipo}",
        f"mesa_tipo={_tramo(len(yo['defensa']), (0, 1, 2, 4, 7))}:{tipo}",
        f"rival_tipo={_tramo(len(rival['defensa']), (0, 1, 2, 4, 7))}:{tipo}",
        f"amenaza_tipo={rival_amenaza}:{tipo}",
        f"castillo_tipo={mi_castillo}:{tipo}",
        f"su_castillo_tipo={su_castillo}:{tipo}",
        f"opciones_tipo={_tramo(cantidad, (1, 2, 4, 8, 16))}:{tipo}",
        f"coste_oro={_tramo(coste, (0, 1, 2, 3, 4, 5, 7))}:{tramo_oro}:{tipo}",
        f"desarrollo={len_castillo > 15 and not yo['defensa']}:{tipo}",
    )


def _puntaje(pesos: dict[str, float], rasgos: tuple[str, ...]) -> float:
    return sum(pesos.get(x, 0.0) for x in rasgos)


def _mejor(pesos: dict[str, float], rasgos: list[tuple[str, ...]]) -> int:
    return max(range(len(rasgos)), key=lambda i: _puntaje(pesos, rasgos[i]))


def _filas(archivo: Path):
    with archivo.open(encoding="utf-8") as f:
        metadata = json.loads(next(f))
        if metadata.get("tipo") != "metadata" or metadata.get("esquema") != 1:
            raise ValueError("Esquema de episodios no compatible")
        for linea in f:
            fila = json.loads(linea)
            if fila.get("tipo") == "decision" and fila.get("tipoDecision") == "jugada":
                yield fila


def _sha256(archivo: Path) -> str:
    resumen = hashlib.sha256()
    with archivo.open("rb") as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b""):
            resumen.update(bloque)
    return resumen.hexdigest()


def entrenar(archivo: Path, destino: Path, *, epocas: int = 3,
            lado: str = "A", solo_victorias: bool = False) -> dict[str, Any]:
    if epocas < 1:
        raise ValueError("Se requiere al menos una época")
    if lado not in ("A", "B"):
        raise ValueError("El lado aprendido debe ser A o B")
    with archivo.open(encoding="utf-8") as f:
        origen = json.loads(next(f))
    if origen.get("tipo") != "metadata" or origen.get("esquema") != 1:
        raise ValueError("Esquema de episodios no compatible")
    pesos: dict[str, float] = {}
    historia = []
    mejor_modelo: dict[str, float] = {}
    mejor_acierto = -1.0
    for epoca in range(1, epocas + 1):
        entrenamiento = cambios = 0
        for fila in _filas(archivo):
            if fila["lado"] != lado:
                continue
            if solo_victorias and fila.get("recompensa") != 1.0:
                continue
            legales = fila["legales"]
            if len(legales) < 2:
                continue
            rasgos = [_rasgos(fila["vista"], a, len(legales)) for a in legales]
            predicho = _mejor(pesos, rasgos)
            esperado = next((i for i, a in enumerate(legales)
                             if a == fila["elegida"]), None)
            if esperado is None:
                raise ValueError("Una decisión registrada no está entre las legales")
            if int(fila["partida"]) % 5 == 0:
                continue
            entrenamiento += 1
            if legales[predicho] != legales[esperado]:
                cambios += 1
                for rasgo, signo in ((x, 1.0) for x in rasgos[esperado]):
                    pesos[rasgo] = pesos.get(rasgo, 0.0) + signo
                for rasgo, signo in ((x, -1.0) for x in rasgos[predicho]):
                    pesos[rasgo] = pesos.get(rasgo, 0.0) + signo
        # Se evalúa después de la época, sin actualizar sobre partidas reservadas.
        validacion = aciertos = 0
        for fila in _filas(archivo):
            if fila["lado"] != lado:
                continue
            if solo_victorias and fila.get("recompensa") != 1.0:
                continue
            legales = fila["legales"]
            if int(fila["partida"]) % 5 != 0 or len(legales) < 2:
                continue
            rasgos = [_rasgos(fila["vista"], a, len(legales)) for a in legales]
            validacion += 1
            aciertos += legales[_mejor(pesos, rasgos)] == fila["elegida"]
        tasa = aciertos / validacion if validacion else 0.0
        historia.append({"epoca": epoca, "entrenamiento": entrenamiento,
                         "validacion": validacion, "acierto": round(tasa, 4),
                         "actualizaciones": cambios})
        if tasa > mejor_acierto:
            mejor_acierto = tasa
            mejor_modelo = pesos.copy()
    modelo = {
        "esquema": ESQUEMA_MODELO,
        "tipo": "perceptron_ranking_imitacion",
        "ladoAprendido": lado,
        "creado": datetime.now(timezone.utc).isoformat(),
        "origen": {"archivo": archivo.name,
                   "sha256": _sha256(archivo),
                   "generado": origen["generado"],
                   "motorHuella": origen.get("motorHuella"),
                   "mazoA": origen["mazoA"], "mazoB": origen["mazoB"]},
        "separacion": "partida % 5 == 0 reservada para validación",
        "filtroRecompensa": "solo victorias" if solo_victorias else "todas las partidas",
        "historia": historia,
        "mejorAcierto": round(mejor_acierto, 4),
        "pesos": {k: v for k, v in mejor_modelo.items() if v},
    }
    from .informe_entrenamiento import guardar_informe_imitacion, ruta_unica

    destino.parent.mkdir(parents=True, exist_ok=True)
    informe = guardar_informe_imitacion(
        archivo, modelo, ruta_unica(destino, "jugadas.md"))
    modelo["informeJugadas"] = informe.name
    destino.write_text(json.dumps(modelo, ensure_ascii=False, indent=2), encoding="utf-8")
    return modelo


class PoliticaAprendida:
    """Selecciona jugadas con el modelo; delega las demás decisiones."""

    nombre = "aprendida_v1"

    def __init__(self, modelo: dict[str, Any], seed: int | None = None):
        if modelo.get("esquema") != ESQUEMA_MODELO:
            raise ValueError("Modelo no compatible")
        self.pesos = modelo["pesos"]
        self.base = Heuristico(seed)
        self.decisiones_modelo = 0
        self.desempates_heuristica = 0
        self.tipos_elegidos: Counter[str] = Counter()

    def __getattr__(self, nombre):
        return getattr(self.base, nombre)

    def elegir_jugada(self, p, yo, jugadas):
        if len(jugadas) < 2:
            return jugadas[0]
        vista = vista_legal(p, yo)
        rasgos = [_rasgos(vista, _accion(j), len(jugadas)) for j in jugadas]
        puntajes = [_puntaje(self.pesos, x) for x in rasgos]
        if max(puntajes) == min(puntajes):
            self.desempates_heuristica += 1
            return self.base.elegir_jugada(p, yo, jugadas)
        self.decisiones_modelo += 1
        elegida = jugadas[max(range(len(jugadas)), key=lambda i: puntajes[i])]
        self.tipos_elegidos[elegida.tipo] += 1
        return elegida


def evaluar(modelo: dict[str, Any], mazo_a: Mazo, mazo_b: Mazo,
            *, pares: int = 40, seed: int = 70001) -> dict[str, Any]:
    """Djoser aprendido contra Sacerdote heurístico, con control heurístico."""
    if modelo.get("ladoAprendido") != "A":
        raise ValueError("Esta evaluación espera una política entrenada para el mazo A")
    for clave, mazo in (("mazoA", mazo_a), ("mazoB", mazo_b)):
        if huella_mazo(mazo) != modelo["origen"][clave]["huella"]:
            raise ValueError(f"{mazo.nombre}: cambió la lista o las habilidades; recolecta episodios nuevos")
    if pares < 1:
        raise ValueError("Se requiere al menos un par de semillas")
    puntos_modelo = puntos_control = validas_modelo = validas_control = 0
    anomalias = 0
    diferencias = []
    decisiones_modelo = desempates = 0
    tipos_elegidos: Counter[str] = Counter()
    for k in range(pares):
        diferencia_par = 0.0
        for invertido in (False, True):
            for aprendido in (False, True):
                s = seed + k * 2 + int(invertido)
                mazos = (mazo_b.cartas, mazo_a.cartas) if invertido else (mazo_a.cartas, mazo_b.cartas)
                lado_a = 1 if invertido else 0
                jugadores = [Heuristico(s * 2), Heuristico(s * 2 + 1)]
                politica = None
                if aprendido:
                    politica = PoliticaAprendida(modelo, s * 2 + lado_a)
                    jugadores[lado_a] = politica
                partida = Partida(mazos, tuple(jugadores), inicial=None, seed=s)
                registro = partida.jugar()
                if politica is not None:
                    decisiones_modelo += politica.decisiones_modelo
                    desempates += politica.desempates_heuristica
                    tipos_elegidos.update(politica.tipos_elegidos)
                if registro.ganador == -2:
                    anomalias += 1
                    continue
                puntos = 1.0 if registro.ganador == lado_a else 0.5 if registro.ganador == -1 else 0.0
                if aprendido:
                    puntos_modelo += puntos
                    validas_modelo += 1
                    diferencia_par += puntos
                else:
                    puntos_control += puntos
                    validas_control += 1
                    diferencia_par -= puntos
        diferencias.append(diferencia_par / 2)
    rng = random.Random(129)
    muestras = sorted(sum(rng.choices(diferencias, k=len(diferencias))) / len(diferencias)
                      for _ in range(1000))
    diferencia = (puntos_modelo / validas_modelo - puntos_control / validas_control
                  if validas_modelo and validas_control else 0.0)
    return {
        "mazoAprendido": mazo_a.nombre, "rival": mazo_b.nombre,
        "pares": pares, "seed": seed, "anomalas": anomalias,
        "modelo": {"partidas": validas_modelo,
                   "winrate": round(puntos_modelo / validas_modelo, 4) if validas_modelo else 0,
                   "ic95": wilson(puntos_modelo, validas_modelo)},
        "control": {"partidas": validas_control,
                    "winrate": round(puntos_control / validas_control, 4) if validas_control else 0,
                    "ic95": wilson(puntos_control, validas_control)},
        "diferencia": round(diferencia, 4),
        "ic95DiferenciaBootstrap": [muestras[25], muestras[975]],
        "aptoParaDesafio": (validas_modelo >= 100 and anomalias == 0
                              and muestras[25] > 0),
        "decisionesModelo": decisiones_modelo,
        "desempatesHeuristica": desempates,
        "tiposElegidos": dict(tipos_elegidos),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Entrenar y evaluar la primera política")
    sub = parser.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("entrenar")
    t.add_argument("episodios", type=Path)
    t.add_argument("modelo", type=Path)
    t.add_argument("--epocas", type=int, default=3)
    t.add_argument("--lado", choices=("A", "B"), default="A")
    t.add_argument("--solo-victorias", action="store_true",
                   help="Aprende solo decisiones de partidas ganadas por el lado indicado")
    e = sub.add_parser("evaluar")
    e.add_argument("modelo", type=Path)
    e.add_argument("--pares", type=int, default=40)
    e.add_argument("--seed", type=int, default=70001)
    e.add_argument("--salida", type=Path)
    args = parser.parse_args(argv)
    if args.cmd == "entrenar":
        resultado = entrenar(args.episodios, args.modelo, epocas=args.epocas,
                            lado=args.lado, solo_victorias=args.solo_victorias)
        print(json.dumps({k: v for k, v in resultado.items() if k != "pesos"},
                         ensure_ascii=False, indent=2))
        print(f"Rasgos aprendidos: {len(resultado['pesos'])}")
    else:
        modelo = json.loads(args.modelo.read_text(encoding="utf-8"))
        mazos = [cargar_mazo("", modelo["origen"][k]["id"], usar_cache=True)
                 for k in ("mazoA", "mazoB")]
        resultado = evaluar(modelo, *mazos, pares=args.pares, seed=args.seed)
        print(json.dumps(resultado, ensure_ascii=False, indent=2))
        if args.salida:
            args.salida.parent.mkdir(parents=True, exist_ok=True)
            args.salida.write_text(json.dumps(resultado, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
