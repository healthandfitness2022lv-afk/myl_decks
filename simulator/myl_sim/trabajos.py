"""Trabajos largos de meta pedidos desde la app (colección ml_jobs).

Cada tipo corre la misma CLI que se usa a mano, en un proceso aparte (así el
pool de procesos de la simulación no choca con los hilos del worker), y se
devuelve un resumen chico para guardar en Firestore. El informe completo
queda en el PC (JSON + Markdown).

Tipos:
  meta_matriz    {"meta"?: nombre guardado, "n"?: 20, "formato"?: "racial", "fuente"?: "app"|"cache"}
  optimizar      {"deckBase": id, "rondas"?: 1, "n0"?: 6, "confirmar"?: 40, "meta"?: nombre|"evolutivo",
                  "soloSide"?: bool}
  Todos aceptan "jugador" y "fuente": "cache" (sin Firestore, desde simulator/cache).
  evaluar_carta  {"cardId": id, "n0"?: 4, "confirmar"?: 20}
"""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

from .meta import CARPETA

TIPOS = ("meta_matriz", "optimizar", "evaluar_carta")
RAIZ = Path(__file__).resolve().parent.parent


def _ent(data: dict, clave: str, defecto: int, maximo: int) -> int:
    return max(1, min(int(data.get(clave) or defecto), maximo))


def comando(tipo: str, data: dict, salida: Path) -> list[str]:
    """Argumentos de la CLI para el trabajo (sin el intérprete)."""
    if tipo == "meta_matriz":
        args = ["myl_sim.meta", "matriz"]
        if data.get("meta"):
            args.append(str(data["meta"]))
        elif data.get("fuente", "app") == "app":
            args += ["--app", "--formato", str(data.get("formato") or "racial")]
        args += ["-n", str(_ent(data, "n", 20, 200))]
    elif tipo == "optimizar":
        args = ["myl_sim.optimizador", str(data["deckBase"]),
                "--rondas", str(_ent(data, "rondas", 1, 5)),
                "--n0", str(_ent(data, "n0", 6, 40)),
                "--confirmar", str(_ent(data, "confirmar", 40, 200))]
        if data.get("meta"):
            args += ["--meta", str(data["meta"])]
        if data.get("soloSide"):
            args.append("--solo-side")
    elif tipo == "evaluar_carta":
        args = ["myl_sim.evaluador", str(data["cardId"]),
                "--n0", str(_ent(data, "n0", 4, 40)),
                "--confirmar", str(_ent(data, "confirmar", 20, 200))]
    else:
        raise ValueError(f"Tipo de trabajo ML no soportado: {tipo}")
    if data.get("fuente") == "cache":
        args.append("--cache")
    if data.get("jugador"):
        args += ["--jugador", str(data["jugador"])]
    return ["-m", *args, "--salida", str(salida)]


def resumen(tipo: str, r: dict) -> dict:
    """Lo justo para mostrar en la app (Firestore limita el tamaño del doc)."""
    if tipo == "meta_matriz":
        return {"meta": r["meta"], "mazos": len(r["ranking"]), "partidasPorCruce": r["partidasPorCruce"],
                "ranking": [{"id": f["id"], "nombre": f["nombre"], "score": round(f["score"], 4),
                             "ic95": [round(x, 4) for x in f["ic95"]],
                             "scoreEvolutivo": round(f["scoreEvolutivo"], 4),
                             "equilibrio": round(f["equilibrio"], 4)} for f in r["ranking"][:30]]}
    if tipo == "optimizar":
        ro = r["rondas"]
        return {"base": r["base"]["nombre"], "rivales": len(r["rivales"]), "origenPool": r["origenPool"],
                "winrateBase": ro[0]["winrateBase"] if ro else None,
                "cambiosAceptados": [f"−{a} +{b}" for a, b in r["cambiosAceptados"]],
                "probados": [{"cambio": c["etiqueta"], "dif": round(c["dif"], 4),
                              "ic95": [round(x, 4) for x in c["ic95"]]}
                             for x in ro for c in x["confirmadas"]][:20]}
    return {"carta": r["carta"]["nombre"], "veredicto": r["veredicto"],
            "mazos": [{"mazo": f["mazo"], "copias": f["copias"], "dif": round(f["dif"], 4),
                       "cambios": [f"−{a} +{b}" for a, b in f["cambios"]]} for f in r["mazos"]]}


def ejecutar(tipo: str, data: dict, job_id: str, linea=None) -> tuple[dict, Path]:
    """Corre el trabajo; `linea(texto)` recibe cada línea de avance. Devuelve (resumen, ruta .json)."""
    salida = CARPETA / "ml_jobs" / f"{job_id}_{tipo}"
    salida.parent.mkdir(parents=True, exist_ok=True)
    p = subprocess.Popen([sys.executable, *comando(tipo, data, salida)], cwd=RAIZ,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace")
    ultimas: list[str] = []
    for texto in p.stdout:
        texto = texto.rstrip()
        if not texto:
            continue
        print(f"  [{job_id}] {texto}", flush=True)
        ultimas = (ultimas + [texto])[-5:]
        if linea:
            linea(texto)
    if p.wait() != 0:
        raise RuntimeError(" | ".join(ultimas)[-500:] or f"salió con código {p.returncode}")
    ruta = salida.with_suffix(".json")
    return resumen(tipo, json.loads(ruta.read_text(encoding="utf-8"))), ruta
