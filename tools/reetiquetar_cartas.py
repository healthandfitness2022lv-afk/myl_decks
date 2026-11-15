"""Reemplaza en cada carta (cards.caracteristicasRaw) las características
antiguas por su genérica, según `unificadaEn` del catálogo
(ver unificar_catalogo.py).

Antes de escribir guarda las etiquetas actuales en
tools/respaldos/caracteristicas_<fecha>.json para poder revertir.

Uso (desde myl_decks/):
    simulator/.venv/Scripts/python tools/reetiquetar_cartas.py             (simulación)
    simulator/.venv/Scripts/python tools/reetiquetar_cartas.py --confirmar
"""

from collections import Counter
from datetime import date
import json
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "simulator"))

from myl_sim.datos import db  # noqa: E402

# Variantes antiguas escritas como clave (enum CardTag) en vez de nombre.
ALIAS = {
    "control_aliados": "Control de aliados",
    "generador_oros": "Generador de oros",
    "dano_directo": "Daño Directo",
    "removal": "Removal masivo",
}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.strip().lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return " ".join(s.replace("_", " ").split())


def main() -> int:
    confirmar = "--confirmar" in sys.argv
    feats = {d.id: d.to_dict() or {} for d in db().collection("card_custom_features").stream()}
    nombre_gen = {fid: f["name"] for fid, f in feats.items() if f.get("generica")}
    mapa: dict[str, str] = {}  # nombre antiguo normalizado → genérica
    for f in feats.values():
        gid = f.get("unificadaEn")
        if gid in nombre_gen:
            mapa[norm(f.get("name", ""))] = nombre_gen[gid]
    for clave, nombre in ALIAS.items():
        if norm(nombre) in mapa:
            mapa[norm(clave)] = mapa[norm(nombre)]

    cambios = []
    conteo = Counter()
    for d in db().collection("cards").stream():
        raw = (d.to_dict() or {}).get("caracteristicasRaw") or []
        if not isinstance(raw, list):
            continue
        nuevo: list[str] = []
        for etiqueta in raw:
            destino = mapa.get(norm(str(etiqueta)), str(etiqueta))
            if destino != etiqueta:
                conteo[f"{etiqueta} → {destino}"] += 1
            if destino not in nuevo:
                nuevo.append(destino)
        if nuevo != raw:
            cambios.append((d.reference, d.id, raw, nuevo))

    for k, n in conteo.most_common():
        print(f"{n:4}  {k}")
    print(f"\nCartas que cambian: {len(cambios)}")
    if not confirmar:
        print("Simulación: no se escribió nada. Agrega --confirmar.")
        return 0

    carpeta = Path(__file__).resolve().parent / "respaldos"
    carpeta.mkdir(exist_ok=True)
    archivo = carpeta / f"caracteristicas_{date.today().isoformat()}.json"
    archivo.write_text(
        json.dumps({cid: antes for _, cid, antes, _ in cambios}, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    for k in range(0, len(cambios), 400):
        batch = db().batch()
        for ref, _, _, nuevo in cambios[k : k + 400]:
            batch.update(ref, {"caracteristicasRaw": nuevo})
        batch.commit()
    print(f"Listo. Etiquetas anteriores guardadas en {archivo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
