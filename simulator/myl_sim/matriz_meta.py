"""Matriz reproducible de un mazo contra los mazos de un formato.

Ejemplo (desde simulator/):
  .venv/Scripts/python -m myl_sim.matriz_meta --mazo "Dragón" -n 1000
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

from .datos import CACHE, cargar_mazo, huella_mazo, listar_mazos, uid_por_email
from .simulacion import simular


DUENO = "hecturnicolas@gmail.com"


def ejecutar_matriz(
    uid: str,
    base_id: str,
    *,
    formato: str = "racial",
    partidas: int = 1000,
    seed: int = 750001,
    progreso=None,
) -> dict:
    """Corre una matriz por id de mazo, reutilizable por el worker local.

    ``progreso(indice, total, base_nombre, rival_nombre, fila)`` se llama al
    terminar cada cruce. El informe completo queda en el llamador, para que la
    app pueda guardar solo el resumen que necesita mostrar.
    """
    disponibles = listar_mazos(uid)
    bases = [x for x in disponibles if x[0] == base_id]
    if len(bases) != 1:
        raise ValueError("No se encontró el mazo base seleccionado")
    _, base_nombre, _ = bases[0]
    rivales = [(did, nombre) for did, nombre, fmt in disponibles
               if fmt == formato and did != base_id]
    if not rivales:
        raise ValueError(f"No hay rivales de formato {formato}")

    mazo_base = cargar_mazo(uid, base_id)
    filas = []
    for indice, (rival_id, rival_nombre) in enumerate(rivales):
        rival = cargar_mazo(uid, rival_id)
        informe = simular(mazo_base, rival, partidas, seed=seed + indice * 100_003)
        fila = {
            "rival": {"id": rival_id, "nombre": rival_nombre,
                      "huella": huella_mazo(rival)},
            "partidas": informe["validas"],
            "winrate": informe["winrateA"],
            "ic95": informe["ic95A"],
            "anomalas": informe["anomalas"],
            "sinProgramarBase": informe["sinProgramarA"],
            "sinProgramarRival": informe["sinProgramarB"],
            "versiones": informe["versiones"],
        }
        filas.append(fila)
        if progreso:
            progreso(indice + 1, len(rivales), base_nombre, rival_nombre, fila)
        else:
            print(f"{indice + 1}/{len(rivales)}  {base_nombre} vs {rival_nombre}: "
                  f"{fila['winrate'] * 100:.1f}%")

    filas.sort(key=lambda x: x["winrate"], reverse=True)
    return {
        "esquema": 1,
        "creado": datetime.now(timezone.utc).isoformat(),
        "base": {"id": base_id, "nombre": base_nombre,
                 "huella": huella_mazo(mazo_base)},
        "formatoRivales": formato,
        "partidasPorCruce": partidas,
        "seedInicial": seed,
        "cruces": filas,
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Matriz de un mazo contra un formato")
    ap.add_argument("--mazo", required=True, help="nombre exacto del mazo base")
    ap.add_argument("-n", "--partidas", type=int, default=1000)
    ap.add_argument("--formato", default="racial")
    ap.add_argument("--seed", type=int, default=750001)
    ap.add_argument("--salida", type=Path)
    args = ap.parse_args(argv)

    uid = uid_por_email(DUENO)
    disponibles = listar_mazos(uid)
    base = [x for x in disponibles if x[1].casefold() == args.mazo.casefold()]
    if len(base) != 1:
        nombres = ", ".join(nombre for _, nombre, _ in disponibles)
        raise ValueError(f"Mazo base no único: {args.mazo}. Disponibles: {nombres}")
    base_id, base_nombre, _ = base[0]
    resultado = ejecutar_matriz(uid, base_id, formato=args.formato,
                                partidas=args.partidas, seed=args.seed)
    salida = args.salida or CACHE / "entrenamiento" / (
        f"matriz_{base_nombre.lower().replace(' ', '_')}_{args.formato}.json")
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(resultado, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Informe: {salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
