"""Selecciona una política aprendida solo para un cruce validado.

Un cambio de cartas o habilidades altera la huella y devuelve la heurística.
El registro local exige dos evaluaciones independientes para cada modelo.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

from .datos import Mazo
from .entrenamiento import huella_mazo
from .exploracion import PoliticaAlternativas
from .jugadores import Heuristico


def crear_registro(pares: list[tuple[Path, Path]], salida: Path) -> dict:
    """Incluye solo modelos que superaron dos controles independientes."""
    entradas = {}
    huella_a = None
    agrupados: dict[Path, list[Path]] = {}
    for archivo_modelo, archivo_informe in pares:
        agrupados.setdefault(archivo_modelo, []).append(archivo_informe)
    for archivo_modelo, archivos_informes in agrupados.items():
        modelo = json.loads(archivo_modelo.read_text(encoding="utf-8"))
        origen = modelo["origen"]
        if huella_a is None:
            huella_a = origen["mazoA"]["huella"]
        if origen["mazoA"]["huella"] != huella_a:
            raise ValueError("Los modelos pertenecen a distintas versiones de Djoser")
        informes = [json.loads(p.read_text(encoding="utf-8")) for p in archivos_informes]
        for informe in informes:
            if (informe["rival"]["huella"] != origen["mazoB"]["huella"]
                    or informe["mazoAprendido"]["huella"] != huella_a):
                raise ValueError("El informe no corresponde al modelo y sus mazos")
        if len(informes) < 2 or any(
            x["partidasValidas"] < 400 or x["anomalas"]
            or x["rival"]["copiasSinProgramar"]
            or x["ic95DiferenciaBootstrap"][0] <= 0 for x in informes
        ):
            continue
        if len({(x["factor"], x["minimo"]) for x in informes}) != 1:
            raise ValueError("Las evaluaciones usan parámetros distintos")
        rangos = sorted((int(x["seed"]), int(x["seed"]) + 2 * int(x["pares"]))
                        for x in informes)
        if any(a[1] > b[0] for a, b in zip(rangos, rangos[1:])):
            raise ValueError("Las evaluaciones comparten semillas")
        huella_b = origen["mazoB"]["huella"]
        if huella_b in entradas:
            raise ValueError("Dos modelos aprobados para el mismo rival")
        entradas[huella_b] = {
            "rival": origen["mazoB"]["nombre"],
            "modelo": archivo_modelo.name,
            "informes": [p.name for p in archivos_informes],
            "factor": informes[0]["factor"],
            "minimo": informes[0]["minimo"],
            "mejoraPuntos": round(sum(x["diferencia"] for x in informes)
                                  / len(informes) * 100, 2),
        }
    registro = {"esquema": 1, "creado": datetime.now(timezone.utc).isoformat(),
                "huellaDjoser": huella_a, "entradas": entradas,
                "fallback": "heuristico"}
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(registro, ensure_ascii=False, indent=2), encoding="utf-8")
    return registro


def jugador_para(registro: dict, carpeta: Path, mazo_a: Mazo, mazo_b: Mazo,
                seed: int):
    """Decide antes de la partida, sin consultar cartas ocultas durante ella."""
    if huella_mazo(mazo_a) != registro.get("huellaDjoser"):
        return Heuristico(seed)
    entrada = registro.get("entradas", {}).get(huella_mazo(mazo_b))
    if entrada is None:
        return Heuristico(seed)
    modelo = json.loads((carpeta / entrada["modelo"]).read_text(encoding="utf-8"))
    if (modelo["origen"]["mazoA"]["huella"] != registro["huellaDjoser"]
            or modelo["origen"]["mazoB"]["huella"] != huella_mazo(mazo_b)):
        raise ValueError("Modelo del registro no coincide con las barajas")
    return PoliticaAlternativas(seed, modelo["preferencias"],
                               preferencias_contexto=modelo.get("preferenciasContexto"),
                               factor=float(entrada["factor"]),
                               minimo=float(entrada["minimo"]))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Registrar solo cruces validados")
    ap.add_argument("--salida", required=True, type=Path)
    ap.add_argument("--par", action="append", nargs=2, metavar=("MODELO", "INFORME"),
                    required=True, type=Path)
    args = ap.parse_args(argv)
    registro = crear_registro(args.par, args.salida)
    print(json.dumps(registro, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
