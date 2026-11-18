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
import re
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


def _norm(nombre: str) -> str:
    import unicodedata
    t = unicodedata.normalize("NFD", str(nombre or "")).encode("ascii", "ignore").decode()
    return " ".join(t.casefold().split())


def _corregir(nombre: str, habs: list[dict]) -> list[dict]:
    """Auditoría de cartas 2026-11-13: diferencias entre el texto impreso y
    las habilidades guardadas en Firestore. Se corrigen al cargar (no toca
    Firestore); `CORRECCIONES_ACTIVAS = False` vuelve a lo guardado."""
    n = _norm(nombre)
    if n in CORRECCIONES_APAGADAS:
        return habs
    if n == "rito de aton":
        # "Sólo puedes activar un Rito de Atón por turno" no es Errante: se
        # pueden tener varios en juego; el límite es de activación por nombre.
        out = []
        for h in habs:
            if h.get("accion") == "errante":
                continue
            if h.get("accion") == "buscar" and h.get("cuando") == "activada":
                h = {**h, "limitePorTurno": 1, "limitePorNombre": True, "zonaActivacion": "reserva_oro"}
            out.append(h)
        return out
    if n == "toro apis" and not any(h.get("accion") == "indestructible" for h in habs):
        return habs + [{"accion": "indestructible", "cuando": "continua"}]  # "Indestructible."
    if n == "qadesh" and not any(h.get("modo") == "anulable_pagando" for h in habs):
        # "Tu oponente puede pagar 5 Oros para anular esta carta."
        return habs + [{"accion": "restriccion", "modo": "anulable_pagando", "valor": 5, "cuando": "continua",
                        "objetivo": {"quien": "oponente"}}]
    if n == "amkh":
        # "prevenir que una carta que controles sea barajada o puesta en el
        # Mazo Castillo": era quien=oponente y modo destruir/desterrar (nunca servía).
        return [{**h, "modo": "barajar_mazo", "objetivo": {**(h.get("objetivo") or {}), "quien": "propio",
                                                           "tipos": []}}
                if h.get("accion") == "prevenir" else h for h in habs]
    if n == "piedra roseta":
        # Duda 1GfZ (Héctor): "En tu Fase de Vigilia... si tienes dos o más
        # Aliados Sacerdote": no exige que el Oro esté en la Reserva ni pagarlo;
        # también se activa ya pagado.
        return [{**h, "zonaActivacion": "reserva_o_pagado"}
                if h.get("cuando") == "activada" and not h.get("zonaActivacion") else h for h in habs]
    if n == "escudo celestial":
        # Desafío 15cB: "barajar tantas cartas como daño haya hecho": era 1 fija.
        return [{**h, "cantidadSegun": "dano_hecho"}
                if h.get("accion") == "barajar" and h.get("cuando") == "al_hacer_dano" else h for h in habs]
    if n == "apophis":
        # "Cada vez que tu oponente juegue una carta que no sea un Oro": los
        # Oros también le hacían botar 3.
        return [{**h, "disparoTipos": ["Aliado", "Talismán", "Arma", "Tótem"]}
                if h.get("cuando") == "oponente_juega" and not h.get("disparoTipos") else h for h in habs]
    if n == "ayu del veneno":
        # Desafío 1bXc T13: "puedes elegir un Tótem en juego para que tu oponente
        # bote tantas como su coste". Estaba como "+0 de fuerza al Tótem", y la
        # fuerza solo va a Aliados: nunca hacía botar.
        return [{**h, "accion": "elegir", "opcional": True}
                if h.get("cuando") == "al_jugar" and h.get("accion") == "modificarFuerza" else h for h in habs]
    if n == "ayu":
        # Desafío 1bXc T14: "Una vez por turno, tu oponente bota…" no dice fase:
        # también se activa en la Guerra de Talismanes del turno rival.
        return [{**h, "fase": "cualquiera"} if h.get("cuando") == "activada" else h for h in habs]
    if n == "soteira":
        # "prevenir que sea destruido por daño de combate" (no por Talismanes).
        return [{**h, "modo": "combate"} if h.get("accion") == "prevenir" else h for h in habs]
    if n == "grandes faraones":
        # "Sólo puedes activar un Grandes Faraones por turno" y "si no controlas
        # Aliados Faraón, bota una adicional" (tenía ≤1 Aliado de cualquier raza).
        out = []
        for h in habs:
            if h.get("accion") == "botar" and h.get("cuando") == "activada":
                h = {**h, "limitePorNombre": True, "luego": [
                    {**e, "condicion": {"tipo": "aliados_raza", "raza": "Faraón", "valor": 0, "op": "=="}}
                    for e in h.get("luego") or []]}
            out.append(h)
        return out
    if n == "quemar los templos":
        # "Por cada carta desterrada, puedes barajar 1 carta de tu Cementerio":
        # el "luego" buscaba en el Mazo y no barajaba nada.
        return [{**h, "luego": [{**e, "opcional": True, "objetivo": {**(e.get("objetivo") or {}), "zona": "cementerio"}}
                                if e.get("accion") == "barajar" else e for e in h.get("luego") or []]}
                if h.get("luego") else h for h in habs]
    R = "reserva_oro"
    if n == "djedefhor":
        # "si sólo controlabas Aliados de raza Sacerdote"
        return [{**h, "condicion": {"tipo": "aliados_no_raza", "raza": "Sacerdote", "valor": 0, "op": "=="}}
                if h.get("cuando") == "al_salir_del_juego" else h for h in habs]
    if n == "resplandor de heka":
        # "Si controlas a Heka, puedes robar una carta adicional."
        out = []
        for h in habs:
            if h.get("accion") == "perderHabilidad" and not any(
                    (e.get("condicion") or {}).get("tipo") == "controla_nombre" for e in h.get("luego") or []):
                extra = {"relacion": "si_se_cumplio", "accion": "robar", "cantidad": 1, "opcional": True,
                         "objetivo": {"quien": "propio"}, "condicion": {"tipo": "controla_nombre", "nombre": "Heka"}}
                h = {**h, "luego": list(h.get("luego") or []) + [extra]}
            out.append(h)
        return out
    if n == "herrero" and not any(h.get("accion") == "destruirSiPierdeHabilidad" for h in habs):
        return habs + [{"accion": "destruirSiPierdeHabilidad", "cuando": "continua"}]
    if n == "milano negro":
        return [{**h, "razaPropia": True} if h.get("accion") == "convertirEnAliado" else h for h in habs]
    if n in ("joya amatista", "busto imperial"):
        # El texto no lo limita a tu Vigilia.
        return [{**h, "fase": "cualquiera", "turno": "cualquiera", "zonaActivacion": R}
                if h.get("cuando") == "activada" else h for h in habs]
    if n == "nacer de la muerte":
        return [{**h, "fase": "vigilia", "turno": "propio"} if h.get("cuando") == "al_jugar" else h for h in habs]
    # Sin programar en Firestore: se programan acá desde el texto impreso.
    if n == "wep renpet" and not habs:
        return [{"accion": "robar", "cuando": "al_jugar", "opcional": True, "cantidad": 1, "objetivo": {"quien": "propio"},
                 "condicion": {"tipo": "totems_propios", "valor": 1, "op": ">="}}]
    if n == "antorcha olimpica" and not habs:
        return [{"accion": "destruir", "cuando": "activada", "zonaActivacion": R, "costo": {"desterrarEstaCarta": True},
                 "condicion": {"tipo": "aliados_raza", "raza": "Héroe", "valor": 2, "op": ">="},
                 "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": ["Aliado", "Arma", "Tótem"],
                              "quien": "oponente"}}]
    if n == "mochuelo" and not habs:
        return [{"accion": "errante", "cuando": "continua"},
                {"accion": "destruir", "cuando": "activada", "fase": "vigilia", "turno": "propio", "zonaActivacion": R,
                 "costo": {"oros": 2, "desterrarEstaCarta": True},
                 "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": ["Aliado"], "quien": "cualquiera",
                              "coste": {"valor": 3, "op": "<="}}}]
    if n == "glas gaibhenenn" and not habs:
        return [{"accion": "destruir", "cuando": "activada", "zonaActivacion": R,
                 "costo": {"oros": 1, "desterrarEstaCarta": True},
                 "objetivo": {"seleccion": "elige", "zona": "en_juego", "tipos": ["Arma", "Tótem"], "quien": "oponente"}}]
    if n == "aguila imperial" and not habs:
        return [{"accion": "perderHabilidad", "cuando": "continua", "zonaActivacion": R,
                 "objetivo": {"seleccion": "todos", "zona": "en_juego", "tipos": ["Aliado"], "quien": "ambos",
                              "fuerza": {"valor": 1, "op": "=="}}}]
    if n == "vino de la eternidad" and not habs:
        return [{"accion": "buscar", "cuando": "activada", "fase": "vigilia", "turno": "propio", "limitePorTurno": 1,
                 "zonaActivacion": R, "costo": {"oros": 2, "desterrarEstaCarta": True}, "zonaDestino": "mano",
                 "objetivo": {"seleccion": "elige", "zona": "cementerio", "tipos": ["Talismán"], "quien": "propio",
                              "coste": {"valor": 3, "op": "<="}}}]
    if n == "corona faraonica":
        # "si este Oro está en tu Reserva de Oros": pagado no dispara.
        return [{**h, "zonaActivacion": "reserva_oro"} if h.get("cuando") == "propia_entra" else h for h in habs]
    return habs


CORRECCIONES_ACTIVAS = True
PROGRAMADAS_AQUI = {"wep renpet", "antorcha olimpica", "mochuelo", "glas gaibhenenn", "aguila imperial",
                    "vino de la eternidad"}  # sin habilidades en Firestore: programadas en _corregir
CORRECCIONES_APAGADAS: set[str] = set()  # nombres normalizados (mediciones)


# Fuerza impresa distinta de la cargada en el catálogo (desafío gXXd: Sir Erec es 2).
# Enialio está cargado con fuerza 22 (error de tipeo: coste 2, fuerza 2).
FUERZA_CORREGIDA = {"sir erec": 2, "enialio": 2}
# Coste impreso distinto del catálogo (desafío 1bXc T15: Saqqara es 2).
COSTE_CORREGIDO = {"saqqara": 2}

# Costos con los que un Oro se saca a sí mismo: también se pagan si ya está pagado.
_SE_SACA = ("desterrarEstaCarta", "destruirEstaCarta", "subirEstaCarta", "barajarEstaCarta")


def _oro_activable_pagado(texto: str, habs: list[dict]) -> list[dict]:
    """Desafío BwBe (Clochafarmore) y duda 1GfZ (Piedra Roseta): un Oro que se
    activa desterrándose, destruyéndose o subiéndose a la mano también se usa
    ya pagado, salvo que su texto pida estar en la Reserva («de tu Reserva»:
    Joya Amatista, Rito de Atón) o que el costo sea pagarlo a él mismo."""
    if re.search(r"reserva", texto, re.IGNORECASE):
        return habs
    out = []
    for h in habs:
        costo = h.get("costo") or {}
        if h.get("cuando") == "activada" and h.get("zonaActivacion") in (None, "reserva_oro", "en_juego") \
                and not costo.get("pagarEstaCarta") and h.get("accion") != "convertirEnAliado" \
                and any(costo.get(k) for k in _SE_SACA):
            h = {**h, "zonaActivacion": "reserva_o_pagado"}
        out.append(h)
    return out


def carta_desde_doc(cid: str, d: dict) -> Carta:
    habs = tuple(h for h in (d.get("habilidades") or []) if isinstance(h, dict))
    if CORRECCIONES_ACTIVAS:
        habs = tuple(_corregir(str(d.get("nombre", cid)), [dict(h) for h in habs]))
    tipo = normalizar_tipo(str(d.get("tipo", "")))
    if CORRECCIONES_ACTIVAS and tipo == Tipo.ORO:
        habs = tuple(_oro_activable_pagado(str(d.get("habilidadTextoIA") or d.get("habilidad") or ""), list(habs)))

    def entero(v, defecto=0):
        try:
            return int(v)
        except (TypeError, ValueError):
            return defecto

    return Carta(
        id=cid,
        nombre=str(d.get("nombre", cid)),
        tipo=tipo,
        coste=0 if tipo == Tipo.ORO else (
            COSTE_CORREGIDO.get(_norm(str(d.get("nombre", cid))), entero(d.get("coste")))
            if CORRECCIONES_ACTIVAS else entero(d.get("coste"))),
        fuerza=(FUERZA_CORREGIDA.get(_norm(str(d.get("nombre", cid))), entero(d.get("fuerza")))
                if CORRECCIONES_ACTIVAS else entero(d.get("fuerza"))) if tipo == Tipo.ALIADO else 0,
        raza=str(d.get("raza") or ""),
        # El texto leído de la imagen por la IA (campo aparte de las notas)
        # primero: muchas cartas tienen solo "." en el campo oficial.
        texto=str(d.get("habilidadTextoIA") or d.get("habilidad") or ""),
        habilidades=habs,
        revisada=(d.get("habilidadesRevisadas") is True and not str(d.get("notasSimulador") or "").strip())
        or (CORRECCIONES_ACTIVAS and _norm(str(d.get("nombre", cid))) in PROGRAMADAS_AQUI),
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
    # Rival del modo Entrenamiento: su lista está en el caché local del worker.
    if deck_id.startswith("escalera:"):
        from .escalera import cargar_mazo_rival

        return cargar_mazo_rival(deck_id)
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


ORO_INICIAL_ID = "__oro_inicial__"
TAMANO_MAZO = 49  # cartas del Mazo Castillo (sin el Oro inicial)
_ban_cache: dict[str, dict[str, int]] = {}


SIN_LIMITE_DE_COPIAS = re.compile(r"puedes\s+tener\s+m[áa]s\s+de\s+(?:3|tres)\b", re.IGNORECASE)


def copias_maximas(carta: Carta) -> int:
    """Copias permitidas si la Ban List no dice otra cosa: 3, salvo que la
    carta diga "Puedes tener más de 3 … en tu Mazo Castillo" (Draco Águila)."""
    return TAMANO_MAZO if SIN_LIMITE_DE_COPIAS.search(carta.texto or "") else 3


def problemas_mazo(mazo: "Mazo", ban: dict[str, int] | None = None) -> list[str]:
    """Por qué un mazo no se puede simular: debe tener 49 cartas y respetar la
    Ban List de su formato. Lista vacía si cumple. Sin `ban` se usa la del
    caché (o Firestore si no hay)."""
    if ban is None:
        if mazo.formato not in _ban_cache:
            _ban_cache[mazo.formato] = cargar_ban_list(mazo.formato, usar_cache=True)
        ban = _ban_cache[mazo.formato]
    out = []
    if len(mazo.cartas) != TAMANO_MAZO or mazo.faltantes:
        falta = f" y {len(mazo.faltantes)} que no están en el catálogo" if mazo.faltantes else ""
        out.append(f"tiene {len(mazo.cartas)} cartas{falta} (deben ser {TAMANO_MAZO})")
    nombres = {c.id: c.nombre for c in mazo.cartas}
    conteo: dict[str, int] = {}
    for c in mazo.cartas:
        conteo[c.id] = conteo.get(c.id, 0) + 1
    for cid, k in sorted(conteo.items(), key=lambda x: nombres[x[0]]):
        maximo = ban.get(cid, copias_maximas(next(c for c in mazo.cartas if c.id == cid)))
        if cid != ORO_INICIAL_ID and k > maximo:
            out.append(f"{nombres[cid]} ×{k} (prohibida)" if maximo == 0 else f"{nombres[cid]} ×{k} (máximo {maximo})")
    return out


def exigir_validos(*mazos: "Mazo", ban: dict[str, int] | None = None) -> None:
    """ValueError con el detalle si algún mazo no cumple (lo muestra la app)."""
    malos = [f"{m.nombre}: {'; '.join(p)}" for m in mazos if (p := problemas_mazo(m, ban))]
    if malos:
        raise ValueError("Mazo fuera de reglamento (49 cartas y Ban List). " + " · ".join(malos))


def solo_validos(mazos: list["Mazo"], *, avisar: bool = False) -> list["Mazo"]:
    buenos = [m for m in mazos if not problemas_mazo(m)]
    if avisar and len(buenos) < len(mazos):
        fuera = [m.nombre for m in mazos if m not in buenos]
        print(f"Fuera por no cumplir 49 cartas o Ban List ({len(fuera)}): {', '.join(fuera)}")
    return buenos


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
