"""Leer con IA el código impreso de cada variante (esquina inferior derecha).

Ej.: "ARAX 13 - 36", "LPB4 - 127/320 R", "033 - 364 / ANIVERSARIO HD",
"CRPB2 - 60 - 72", "EDICIÓN LIMITADA JO". Va a la derecha del ilustrador
(o del copyright) en la última línea de la carta. Se recorta solo esa franja
(pocos tokens) y se guarda en cards/{id}/variants/{vid}.code, el campo que ya
usa la app. Las variantes que ya tienen código no se vuelven a leer.

El OCR local de Windows se probó y falló en ~la mitad de los diseños (Kit
Racial, Shogun, JO): por eso se usa el modelo.

Uso: python -m myl_sim.codigos_cartas [--todas] [--forzar] [card_id ...]
"""

from __future__ import annotations

import base64
import io
import sys

from .datos import db
from .ia_cartas import MODELO_IA, cliente, descargar_imagen

FRANJA = 0.915  # desde esta proporción del alto hasta el borde inferior
ANCHO = 1024

SISTEMA = (
    "Esta es la franja inferior de una carta de Mitos y Leyendas. Abajo a la derecha está el "
    "código de la carta (a la derecha del nombre del ilustrador o del copyright), por ejemplo "
    "\"ARAX 13 - 36\", \"LPB4 - 127/320 R\", \"033 - 364 / ANIVERSARIO HD\", \"CRPB2-60-72\" o "
    "\"EDICIÓN LIMITADA JO\". Copia SOLO ese código, exactamente como está impreso (mayúsculas, "
    "guiones, barras y espacios). No incluyas el ilustrador ni el copyright. Si no hay código, "
    "responde vacío."
)


def recortar_franja(datos: bytes) -> bytes:
    from PIL import Image

    img = Image.open(io.BytesIO(datos)).convert("RGB")
    w, h = img.size
    img = img.crop((0, int(h * FRANJA), w, h))
    img = img.resize((ANCHO, round(img.height * ANCHO / img.width)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    return out.getvalue()


def leer_codigo(url_imagen: str) -> str:
    franja = base64.b64encode(recortar_franja(descargar_imagen(url_imagen))).decode()
    r = cliente().chat.completions.create(
        model=MODELO_IA,
        messages=[
            {"role": "system", "content": SISTEMA},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{franja}", "detail": "high"}},
            ]},
        ],
    )
    return (r.choices[0].message.content or "").strip().strip('"').strip()


def procesar_carta(card_id: str, *, forzar: bool = False) -> dict:
    """Lee el código de todas las variantes de una carta."""
    from google.cloud import firestore

    leidas, codigos, errores = 0, {}, {}
    for v in db().collection("cards").document(card_id).collection("variants").stream():
        d = v.to_dict() or {}
        url = d.get("imageFrontUrl") or d.get("officialImageUrl")
        if not url or (d.get("code") and not forzar):
            continue
        try:
            codigo = leer_codigo(url)
        except Exception as e:  # noqa: BLE001
            if "no credits remaining" in str(e).lower() or "insufficient_quota" in str(e).lower():
                raise  # sin saldo: se detiene el lote entero
            errores[v.id] = str(e)[:200]
            continue
        v.reference.update({
            "code": codigo,
            "codeFuente": "ia",
            "codeModelo": MODELO_IA,
            "codeAt": firestore.SERVER_TIMESTAMP,
        })
        leidas += 1
        codigos[v.id] = codigo
    res = {"status": "ok", "variantes": leidas, "codigos": codigos}
    if errores:
        res["errores"] = errores
    return res


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    forzar = "--forzar" in args
    ids = [a for a in args if not a.startswith("--")]
    if "--todas" in args:
        ids = [d.id for d in db().collection("cards").select([]).stream()]
    from concurrent.futures import ThreadPoolExecutor

    def una(cid):
        try:
            return cid, procesar_carta(cid, forzar=forzar)
        except Exception as e:  # noqa: BLE001 - se informa y sigue
            return cid, e

    total, fallidas = 0, 0
    with ThreadPoolExecutor(8) as pool:  # cada lectura espera a la API: en paralelo
        for cid, r in pool.map(una, ids):
            if isinstance(r, Exception):
                print(f"{cid}: ERROR {r}", flush=True)
                fallidas += 1
                continue
            total += r["variantes"]
            fallidas += len(r.get("errores", {}))
            for vid, c in r["codigos"].items():
                print(f"{cid}/{vid}: {c or '(sin código)'}", flush=True)
            for vid, e in r.get("errores", {}).items():
                print(f"{cid}/{vid}: ERROR {e}", flush=True)
    print(f"Listo: {total} variantes leídas, {fallidas} con error", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
