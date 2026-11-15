"""Leer cartas con IA (OpenAI), al menor costo.

Flujo desde la app ("cartas por completar", antes de simular):
1. "Leer habilidades con IA": por cada carta se recorta solo el cuadro de
   habilidad de la imagen oficial y el modelo transcribe el texto a
   cards/{id}.habilidadTextoIA (aparte de las notas; el simulador lo usa como
   texto). Si la carta ya tiene texto, no se llama a la API.
2. "Programar" (una carta a la vez, cuando el dueño quiere): la deja en la
   cola del agente (cola_agente.py); el agente la programa desde el chat y
   crea lo que falte en el editor o el motor.

programar() (propuesta hecha por OpenAI) queda disponible pero la app no la
usa: programar desde el chat no gasta API.

La clave va en la variable OPENAI_API_KEY o en myl_decks/secrets/openai_api_key.txt
(fuera de git). El modelo, en OPENAI_MODEL (por defecto gpt-5.5).
"""

from __future__ import annotations

import base64
import io
import json
import os
import re
import urllib.request

from .datos import RAIZ, db

CLAVE = RAIZ / "secrets" / "openai_api_key.txt"
MODELO_DART = RAIZ / "lib" / "models" / "card_habilidad.dart"
# gpt-5.4-mini leyó "Indestructible e Indestructible" en Ramsés II 2 de 3
# veces; gpt-5.5 acertó 3 de 3 (~470 tokens por carta).
MODELO_IA = os.environ.get("OPENAI_MODEL", "gpt-5.5")
# Franja del cuadro de habilidad, en proporción del alto de la carta.
CUADRO = (0.72, 0.96)
ANCHO = 768  # px: legible y barato (pocos tokens de imagen)

_cliente = None
_vocab: str | None = None
_ejemplos: list[dict] | None = None


def cliente():
    global _cliente
    if _cliente is None:
        from openai import OpenAI

        clave = os.environ.get("OPENAI_API_KEY") or (CLAVE.read_text(encoding="utf-8").strip() if CLAVE.exists() else "")
        if not clave:
            raise RuntimeError(f"Falta la clave de OpenAI: variable OPENAI_API_KEY o {CLAVE}")
        _cliente = OpenAI(api_key=clave)
    return _cliente


# ── 1. Leer ──────────────────────────────────────────────────────────────────
def descargar_imagen(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        if not (r.headers.get_content_type() or "").startswith("image/"):
            raise RuntimeError("La URL de la imagen no devolvió una imagen")
        return r.read()


def recortar_cuadro(datos: bytes) -> bytes:
    """Solo el cuadro de habilidad, achicado y en JPEG."""
    from PIL import Image

    img = Image.open(io.BytesIO(datos)).convert("RGB")
    w, h = img.size
    img = img.crop((0, int(h * CUADRO[0]), w, int(h * CUADRO[1])))
    if img.width > ANCHO:
        img = img.resize((ANCHO, round(img.height * ANCHO / img.width)))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=85)
    return out.getvalue()


def transcribir(url_imagen: str) -> str:
    cuadro = base64.b64encode(recortar_cuadro(descargar_imagen(url_imagen))).decode()
    r = cliente().chat.completions.create(
        model=MODELO_IA,
        messages=[
            {"role": "system", "content": (
                "Copia exactamente el texto de habilidad de esta carta de Mitos y Leyendas, en "
                "español, sin agregar nada. Si no hay texto, responde vacío."
            )},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{cuadro}", "detail": "high"}},
            ]},
        ],
    )
    return (r.choices[0].message.content or "").strip()


def texto_de(carta: dict) -> str:
    """El texto de habilidad guardado, si es texto de verdad: muchas cartas
    tienen solo un "." en el campo oficial (Constantino)."""
    for campo in ("habilidadTextoIA", "habilidad"):
        t = str(carta.get(campo) or "").strip()
        if len(re.findall(r"[^\W\d_]", t)) >= 8:
            return t
    return ""


def procesar_carta(card_id: str, *, forzar: bool = False) -> dict:
    """Transcribe una carta (si hace falta) y guarda el texto."""
    from google.cloud import firestore

    ref = db().collection("cards").document(card_id)
    carta = ref.get().to_dict() or {}
    previo = texto_de(carta)
    if previo and not forzar:
        return {"status": "ok", "texto": previo, "api": False}  # sin gastar en la API
    if not carta.get("officialImageUrl"):
        raise RuntimeError("La carta no tiene imagen oficial")
    texto = transcribir(carta["officialImageUrl"])
    ref.update({
        "habilidadTextoIA": texto,
        "habilidadTextoIAModelo": MODELO_IA,
        "habilidadTextoIAAt": firestore.SERVER_TIMESTAMP,
    })
    return {"status": "ok", "texto": texto, "api": True}


# ── 2. Programar (propuesta para revisar en la app) ──────────────────────────
def _bloques_tomap(src: str) -> list[str]:
    """Los toMap() de cada clase: el formato exacto en que se guarda."""
    out = []
    for m in re.finditer(r"Map<String, dynamic> toMap\(\) =>", src):
        clase = re.findall(r"class (\w+)", src[:m.start()])
        i = src.index("{", m.end())
        prof, j = 0, i
        while True:
            prof += {"{": 1, "}": -1}.get(src[j], 0)
            j += 1
            if prof == 0:
                break
        out.append(f"// {clase[-1] if clase else '?'}\n{src[m.start():j]}")
    return out


def vocabulario() -> str:
    """Resumen compacto del modelo del editor (acciones, opciones y formato):
    unos pocos miles de tokens en vez del archivo completo."""
    global _vocab
    if _vocab is None:
        src = MODELO_DART.read_text(encoding="utf-8")
        enum = src[src.index("enum Accion {"):]
        enum = enum[:enum.index(";")]
        acciones = [
            f"- {n}: {a} — {b}"
            for n, _, a, _, b in re.findall(r"(\w+)\(\s*(['\"])(.*?)\2,\s*(['\"])(.*?)\4", enum, re.S)
        ]
        listas = []
        for m in re.finditer(r"const (k\w+) = \[(.*?)\];", src, re.S):
            ops = re.findall(r"Opcion\(\s*'([^']*)',\s*'([^']*)'", m.group(2))
            if ops:
                listas.append(f"{m.group(1)}: " + "; ".join(f"{i or '(vacío)'}={t}" for i, t in ops))
        _vocab = (
            "ACCIONES (campo accion):\n" + "\n".join(acciones)
            + "\n\nOPCIONES:\n" + "\n".join(listas)
            + "\n\nFORMATO (toMap de cada clase):\n" + "\n\n".join(_bloques_tomap(src))
        )
    return _vocab


def _palabras(t: str) -> set[str]:
    return {w for w in re.findall(r"[a-záéíóúñ]+", t.lower()) if len(w) > 3}


def ejemplos(texto: str, n: int = 4, excluir: str = "") -> list[dict]:
    """Cartas ya programadas por el dueño, con texto: las más parecidas."""
    global _ejemplos
    if _ejemplos is None:
        _ejemplos = []
        for doc in db().collection("cards").stream():
            d = doc.to_dict()
            t = texto_de(d)
            if t and d.get("habilidadesRevisadas") is True and d.get("habilidades") \
                    and d.get("habilidadesFuente") != "ia":
                _ejemplos.append({"id": doc.id, "nombre": d.get("nombre"), "texto": t,
                                  "habilidades": d.get("habilidades")})
    clave = _palabras(texto)
    otras = [e for e in _ejemplos if e["id"] != excluir]  # no copiarse a sí misma
    return sorted(otras, key=lambda e: -len(clave & _palabras(e["texto"])))[:n]


def _vocab_validacion() -> tuple[set[str], set[str]]:
    src = MODELO_DART.read_text(encoding="utf-8")
    enum = src[src.index("enum Accion {"):]
    acciones = set(re.findall(r"^\s{2}(\w+)\(", enum[:enum.index(";")], re.M))
    cuando = src[src.index("const kCuando"):]
    return acciones, set(re.findall(r"Opcion\(\s*'(\w+)'", cuando[:cuando.index("];")]))


# Campos de un solo valor en el editor: la IA a veces manda ["Héroe"].
_ESCALARES = {"raza", "quien", "zona", "seleccion", "fase", "turno", "cuando", "accion", "duracion",
              "modo", "zonaDestino", "modoFuerza", "cantidadSegun", "nombre", "relacion", "tipo", "op"}


def normalizar(x):
    """Listas de un elemento en campos de un solo valor → ese valor."""
    if isinstance(x, list):
        return [normalizar(v) for v in x]
    if not isinstance(x, dict):
        return x
    out = {}
    for k, v in x.items():
        if k in _ESCALARES and isinstance(v, list):
            v = v[0] if v else ""
        out[k] = normalizar(v)
    return out


def validar(habs: list) -> list[str]:
    acciones, cuando = _vocab_validacion()
    errores = []
    for i, h in enumerate(habs):
        for e in [h] + [x for x in (h.get("luego") or []) if isinstance(x, dict)]:
            if e.get("accion") not in acciones:
                errores.append(f"habilidad {i + 1}: acción desconocida {e.get('accion')!r}")
            if e.get("cuando") and e.get("cuando") not in cuando:
                errores.append(f"habilidad {i + 1}: momento desconocido {e.get('cuando')!r}")
    return errores


SISTEMA_PROGRAMAR = (
    "Programas habilidades de cartas de Mitos y Leyendas (Chile) para un simulador. Usa SOLO "
    "acciones y valores del vocabulario. Varias habilidades si el texto tiene varias; los efectos "
    "encadenados (\"luego\", \"si lo haces\") van en \"luego\"; \"puedes\" = opcional true. Respeta "
    "restricciones (\"que no sea…\", \"una vez por turno\", fases, turnos, duraciones).\n"
    "Si algo del texto es ambiguo, pregúntalo en \"preguntas\" (cortas, al dueño). Si algo NO se "
    "puede expresar con el vocabulario, prográmalo lo más cerca posible y descríbelo en "
    "\"funcionesFaltantes\" (qué haría falta agregar al editor/motor, con un ejemplo), para que el "
    "desarrollador lo implemente. Responde solo JSON: {\"habilidades\": [...], \"preguntas\": [...], "
    "\"funcionesFaltantes\": [...], \"notas\": \"...\"}.\n\n"
)


def _pedir(mensajes: list[dict]) -> tuple[str, dict]:
    r = cliente().chat.completions.create(model=MODELO_IA, messages=mensajes,
                                          response_format={"type": "json_object"})
    crudo = r.choices[0].message.content or "{}"
    return crudo, json.loads(crudo)


def programar(card_id: str, respuestas: str = "") -> dict:
    """Propuesta de habilidades para revisar en la app (no la aplica)."""
    from google.cloud import firestore

    ref = db().collection("cards").document(card_id)
    carta = ref.get().to_dict() or {}
    texto = texto_de(carta)
    if not texto:
        texto = procesar_carta(card_id)["texto"]
    ej = "\n\n".join(
        f"Carta: {e['nombre']}\nTexto: {e['texto']}\nHabilidades: "
        f"{json.dumps(e['habilidades'], ensure_ascii=False, default=str)}"
        for e in ejemplos(texto, excluir=card_id)
    )
    previa = carta.get("propuestaIA") or {}
    pedido = (
        f"Ejemplos de cartas ya programadas:\n\n{ej}\n\nPrograma: {carta.get('nombre')} "
        f"({carta.get('tipo')}, coste {carta.get('coste')}, fuerza {carta.get('fuerza')}, "
        f"raza {carta.get('raza')})\nTexto: {texto}"
    )
    if respuestas:
        pedido += (
            f"\n\nTu propuesta anterior: {json.dumps(previa.get('habilidades') or [], ensure_ascii=False, default=str)}"
            f"\nTus preguntas: {json.dumps(previa.get('preguntas') or [], ensure_ascii=False)}"
            f"\nRespuestas del dueño: {respuestas}"
        )
    mensajes = [{"role": "system", "content": SISTEMA_PROGRAMAR + vocabulario()},
                {"role": "user", "content": pedido}]
    crudo, prop = _pedir(mensajes)
    habs = [normalizar(h) for h in (prop.get("habilidades") or []) if isinstance(h, dict)]
    errores = validar(habs)
    if errores:  # una corrección: suele bastar con decirle qué no existe
        mensajes += [{"role": "assistant", "content": crudo},
                     {"role": "user", "content": "Corrige, esto no existe en el vocabulario: " + "; ".join(errores)}]
        crudo, prop = _pedir(mensajes)
        habs = [normalizar(h) for h in (prop.get("habilidades") or []) if isinstance(h, dict)]
        errores = validar(habs)
    faltan = [f if isinstance(f, str) else json.dumps(f, ensure_ascii=False)
              for f in (prop.get("funcionesFaltantes") or [])]
    notas = str(prop.get("notas") or "")
    if errores:
        notas += "\nNo válido: " + "; ".join(errores)
    propuesta = {
        "habilidades": habs,
        "preguntas": [str(q) for q in (prop.get("preguntas") or [])],
        "funcionesFaltantes": faltan,
        "notas": notas.strip(),
        "respuestas": respuestas,
        "texto": texto,
        "modelo": MODELO_IA,
        "estado": "propuesta",
        "at": firestore.SERVER_TIMESTAMP,
    }
    cambios = {"propuestaIA": propuesta}
    if faltan:
        # Para que el agente de desarrollo las encuentre (cards con este campo).
        cambios["funcionesFaltantesIA"] = firestore.ArrayUnion(faltan)
    ref.update(cambios)
    return {"status": "ok", "habilidades": len(habs), "preguntas": len(propuesta["preguntas"]),
            "funcionesFaltantes": len(faltan)}
