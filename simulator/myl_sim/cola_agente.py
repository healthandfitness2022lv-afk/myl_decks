"""Cola de cartas para que el agente (Claude, desde el chat) las programe.

En la app, "cartas por completar" → "Programar" deja cards/{id}.solicitudAgente
= {estado: "pendiente"}. Desde el chat:

    .venv/Scripts/python -m myl_sim.cola_agente          (lista la cola)

y el agente aplica cada carta con aplicar(): guarda respaldo en
habilidadesAntesIA, la marca como programada y cierra la solicitud.
"""

from __future__ import annotations

import json
import sys

from .datos import db
from .ia_cartas import texto_de


def pendientes() -> list[tuple[str, dict]]:
    from google.cloud.firestore_v1.base_query import FieldFilter

    q = db().collection("cards").where(filter=FieldFilter("solicitudAgente.estado", "==", "pendiente"))
    return [(d.id, d.to_dict()) for d in q.stream()]


def aplicar(card_id: str, habilidades: list[dict], notas: str = "") -> None:
    from google.cloud import firestore

    ref = db().collection("cards").document(card_id)
    carta = ref.get().to_dict() or {}
    cambios = {
        "habilidades": habilidades,
        "habilidadesRevisadas": True,
        "habilidadesFuente": "agente",
        "habilidadesUpdatedAt": firestore.SERVER_TIMESTAMP,
        "solicitudAgente": {"estado": "programada", "notas": notas, "at": firestore.SERVER_TIMESTAMP},
    }
    if carta.get("habilidadesFuente") not in ("ia", "agente"):
        # Respaldo de lo que cargó el dueño (no se pisa al reprogramar).
        cambios["habilidadesAntesIA"] = {
            "habilidades": carta.get("habilidades") or [],
            "habilidadesRevisadas": carta.get("habilidadesRevisadas") is True,
        }
    ref.update(cambios)


def main() -> int:
    for flujo in (sys.stdout, sys.stderr):
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8", errors="replace")
    cola = pendientes()
    print(f"{len(cola)} carta(s) en cola")
    for cid, d in cola:
        print(f"\n== {cid} · {d.get('nombre')} ({d.get('tipo')}, coste {d.get('coste')}, "
              f"fuerza {d.get('fuerza')}, raza {d.get('raza')})")
        print("Texto:", texto_de(d) or "(sin leer)")
        if str(d.get("notasSimulador") or "").strip():
            print("Notas del dueño:", d["notasSimulador"])
        print("Habilidades actuales:", json.dumps(d.get("habilidades") or [], ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
