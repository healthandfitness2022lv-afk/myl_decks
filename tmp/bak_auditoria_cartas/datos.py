"""Carga de cartas y mazos desde Firestore (cuenta de servicio local).

La credencial es myl_decks/secrets/firebase-admin.json (fuera de git). Los
mazos se guardan como users/{uid}/decks/{deckId} con cards[] = {cardId,
name, count}; cada carta en cards/{id}.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from .modelo import Carta, Tipo, normalizar_tipo

RAIZ = Path(__file__).resolve().parents[2]  # myl_decks/
CREDENCIAL = RAIZ / "secrets" / "firebase-admin.json"
CACHE = RAIZ / "simulator" / "cache"

_db = None


def huella_mazo(mazo: "Mazo") -> str:
    """Huella estable de cartas y habilidades; identifica una versión jugable."""
    cartas = sorted([
        {"id": c.id, "tipo": c.tipo.value, "coste": c.coste, "fuerza": c.fuerza,
         "habilidades": list(c.habilidades), "revisada": c.revisada}
        for c in mazo.cartas
    ], key=lambda x: json.dumps(x, ensure_ascii=False, sort_keys=True))
    bruto = json.dumps(cartas, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(bruto.encode("utf-8")).hexdigest()[:16]


def guardar_snapshot(mazo: "Mazo") -> Path:
    """Conserva una copia inmutable por huella antes de que el caché se reemplace."""
    huella = huella_mazo(mazo)
    carpeta = CACHE / "historial_mazos"
    carpeta.mkdir(parents=True, exist_ok=True)
    archivo = carpeta / f"{mazo.id}_{huella}.json"
    if not archivo.exists():
        data = mazo.to_json()
        data["snapshotHuella"] = huella
        data["snapshotCreadoEn"] = datetime.now(timezone.utc).isoformat()
        archivo.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return archivo


def db():
    global _db
    if _db is None:
        import firebase_admin
        from firebase_admin import credentials, firestore

        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(str(CREDENCIAL)))
        _db = firestore.client()
    return _db


def carta_desde_doc(cid: str, d: dict) -> Carta:
    habs = tuple(h for h in (d.get("habilidades") or []) if isinstance(h, dict))
    tipo = normalizar_tipo(str(d.get("tipo", "")))

    def entero(v, defecto=0):
        try:
            return int(v)
        except (TypeError, ValueError):
            return defecto

    return Carta(
        id=cid,
        nombre=str(d.get("nombre", cid)),
        tipo=tipo,
        coste=0 if tipo == Tipo.ORO else entero(d.get("coste")),
        fuerza=entero(d.get("fuerza")) if tipo == Tipo.ALIADO else 0,
        raza=str(d.get("raza") or ""),
        # El texto leído de la imagen por la IA (campo aparte de las notas)
        # primero: muchas cartas tienen solo "." en el campo oficial.
        texto=str(d.get("habilidadTextoIA") or d.get("habilidad") or ""),
        habilidades=habs,
        revisada=d.get("habilidadesRevisadas") is True and not str(d.get("notasSimulador") or "").strip(),
    )


@dataclass
class Mazo:
    id: str
    nombre: str
    formato: str
    raza: str
    cartas: list[Carta]  # una entrada por copia
    faltantes: list[str]  # nombres sin carta en el catálogo
    side: list[Carta] = field(default_factory=list)  # side deck (hasta 10), una entrada por copia

    def sin_programar(self) -> list[tuple[str, int]]:
        """Cartas con texto de habilidad que aún no están completas."""
        conteo: dict[str, int] = {}
        for c in self.cartas:
            if not c.programada:
                conteo[c.nombre] = conteo.get(c.nombre, 0) + 1
        return sorted(conteo.items(), key=lambda x: -x[1])

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "nombre": self.nombre,
            "formato": self.formato,
            "raza": self.raza,
            "faltantes": self.faltantes,
            "cartas": [
                {
                    "id": c.id,
                    "nombre": c.nombre,
                    "tipo": c.tipo.value,
                    "coste": c.coste,
                    "fuerza": c.fuerza,
                    "raza": c.raza,
                    "habilidad": c.texto,
                    "habilidades": list(c.habilidades),
                    "habilidadesRevisadas": c.revisada,
                }
                for c in self.cartas
            ],
            "side": [
                {"id": c.id, "nombre": c.nombre, "tipo": c.tipo.value, "coste": c.coste,
                 "fuerza": c.fuerza, "raza": c.raza, "habilidad": c.texto,
                 "habilidades": list(c.habilidades), "habilidadesRevisadas": c.revisada}
                for c in self.side
            ],
        }

    @staticmethod
    def from_json(d: dict) -> "Mazo":
        return Mazo(
            id=d["id"],
            nombre=d["nombre"],
            formato=d.get("formato", ""),
            raza=d.get("raza", ""),
            faltantes=d.get("faltantes", []),
            cartas=[carta_desde_doc(c["id"], c) for c in d["cartas"]],
            side=[carta_desde_doc(c["id"], c) for c in d.get("side") or []],
        )


def _cartas_doc(ids) -> dict:
    """Documentos de cards/{id}, en tandas."""
    ids = sorted(set(ids) - {""})
    docs = {}
    for k in range(0, len(ids), 300):
        refs = [db().collection("cards").document(i) for i in ids[k:k + 300]]
        for doc in db().get_all(refs):
            if doc.exists:
                docs[doc.id] = doc.to_dict() or {}
    return docs


def _mazo_desde_doc(deck_id: str, d: dict, docs: dict | None = None) -> Mazo:
    entradas = [e for e in (d.get("cards") or []) if isinstance(e, dict)]
    entradas_side = [e for e in (d.get("sideboardCards") or []) if isinstance(e, dict)]
    ids = sorted({str(e.get("cardId") or "") for e in entradas + entradas_side} - {""})
    if docs is None:
        docs = _cartas_doc(ids)

    cartas: list[Carta] = []
    faltantes: list[str] = []
    for e in entradas:
        cid = str(e.get("cardId") or "")
        n = int(e.get("count") or 0)
        if cid in docs:
            cartas += [carta_desde_doc(cid, docs[cid])] * n
        else:
            faltantes.append(str(e.get("name") or cid))
    side: list[Carta] = []
    for e in entradas_side:
        cid = str(e.get("cardId") or "")
        if cid in docs:
            side += [carta_desde_doc(cid, docs[cid])] * int(e.get("count") or 0)
    mazo = Mazo(
        side=side,
        id=deck_id,
        nombre=str(d.get("name") or deck_id),
        formato=str(d.get("format") or ""),
        raza=str(d.get("race") or ""),
        cartas=cartas,
        faltantes=faltantes,
    )
    return mazo


def cargar_mazo(owner_uid: str, deck_id: str, *, usar_cache: bool = False) -> Mazo:
    # Las listas notables son snapshots globales: se pueden enfrentar contra
    # cualquier mazo propio sin pertenecer a users/{uid}/decks.
    if deck_id.startswith("notable:"):
        notable_id = deck_id.removeprefix("notable:")
        snap = db().collection("notable_decks").document(notable_id).get()
        if not snap.exists:
            raise ValueError(f"No existe la baraja notable {notable_id}")
        d = snap.to_dict() or {}
        deck_id = notable_id
    else:
        d = None
    archivo = CACHE / f"mazo_{deck_id}.json"
    if d is None and usar_cache and archivo.exists():
        return Mazo.from_json(json.loads(archivo.read_text(encoding="utf-8")))

    if d is None:
        snap = db().collection("users").document(owner_uid).collection("decks").document(deck_id).get()
        if not snap.exists:
            raise ValueError(f"No existe el mazo {deck_id}")
        d = snap.to_dict() or {}
    mazo = _mazo_desde_doc(deck_id, d)
    CACHE.mkdir(parents=True, exist_ok=True)
    archivo.write_text(json.dumps(mazo.to_json(), ensure_ascii=False), encoding="utf-8")
    guardar_snapshot(mazo)
    return mazo


def uid_por_email(email: str) -> str:
    from firebase_admin import auth

    db()
    return auth.get_user_by_email(email).uid


def listar_mazos(owner_uid: str) -> list[tuple[str, str, str]]:
    out = []
    for doc in db().collection("users").document(owner_uid).collection("decks").stream():
        d = doc.to_dict() or {}
        out.append((doc.id, str(d.get("name") or ""), str(d.get("format") or "")))
    return sorted(out, key=lambda x: x[1].lower())


def listar_notables(formato: str | None = None) -> list[tuple[str, str, str]]:
    """Barajas notables (torneos) como ("notable:<id>", nombre, formato)."""
    out = []
    for doc in db().collection("notable_decks").stream():
        d = doc.to_dict() or {}
        fmt = str(d.get("format") or "")
        if formato is None or fmt == formato:
            out.append((f"notable:{doc.id}", str(d.get("name") or doc.id), fmt))
    return sorted(out, key=lambda x: x[1].lower())


def cargar_todos(formato: str | None = None, *, notables: bool = True) -> list[Mazo]:
    """Todos los mazos de la app (de todos los jugadores) y las barajas
    notables, del formato pedido. Los repetidos (misma huella) van una vez."""
    fuentes = []
    for doc in db().collection_group("decks").stream():
        if doc.reference.parent.parent is None or doc.reference.parent.parent.parent.id != "users":
            continue
        fuentes.append((doc.id, doc.to_dict() or {}))
    if notables:
        fuentes += [(doc.id, doc.to_dict() or {}) for doc in db().collection("notable_decks").stream()]
    fuentes = [(i, d) for i, d in fuentes if formato is None or str(d.get("format") or "") == formato]
    ids = {str(e.get("cardId") or "") for _, d in fuentes
           for e in (d.get("cards") or []) + (d.get("sideboardCards") or []) if isinstance(e, dict)}
    docs = _cartas_doc(ids)
    out, vistas = [], set()
    CACHE.mkdir(parents=True, exist_ok=True)
    for i, d in fuentes:
        m = _mazo_desde_doc(i, d, docs)
        h = huella_mazo(m)
        if h in vistas or len(m.cartas) < 40:
            continue
        vistas.add(h)
        (CACHE / f"mazo_{i}.json").write_text(json.dumps(m.to_json(), ensure_ascii=False), encoding="utf-8")
        out.append(m)
    return out


BAN_LIST_COLECCION = {"racial": "ban_list", "racialLibre": "ban_list_libre", "full": "ban_list_full"}


def cargar_ban_list(formato: str, *, usar_cache: bool = False) -> dict[str, int]:
    """carta.id → copias máximas según la Ban List del formato (las que no
    están en la lista: 3). Se guarda en cache/ban_list_<formato>.json."""
    archivo = CACHE / f"ban_list_{formato}.json"
    if usar_cache and archivo.exists():
        return json.loads(archivo.read_text(encoding="utf-8"))
    coleccion = BAN_LIST_COLECCION.get(formato)
    if coleccion is None:
        return {}
    out = {}
    for doc in db().collection(coleccion).stream():
        d = doc.to_dict() or {}
        cid = str(d.get("cardId") or "")
        if cid:
            out[cid] = max(0, min(3, int(d.get("maxCopies") or 0)))
    CACHE.mkdir(parents=True, exist_ok=True)
    archivo.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    return out
