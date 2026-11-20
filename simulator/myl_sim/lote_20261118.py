"""Lote del 2026-11-18: 11 cartas antiguas que estaban mal programadas.

Figuraban como programadas pero usaban acciones o disparadores que el motor no
tiene (``grupoElegir`` con ``opciones``, ``fondoMazo``, ``subirCementerio``,
``al_descartar_por_habilidad``) o apuntaban mal (Absalon): en la mesa no hacían
nada. Además, al abrirlas en el editor de la app la acción se habría guardado
como «otra». Quedan reescritas con el vocabulario que el motor ejecuta.

    .venv/Scripts/python -m myl_sim.lote_20261118             (lista y valida)
    .venv/Scripts/python -m myl_sim.lote_20261118 --aplicar   (escribe en Firestore)
"""

from __future__ import annotations

import sys

from .lote_20261117 import ESTA, FURIA, IMBLOQUEABLE, PROPIO, RIVAL, _si, hab, luego  # noqa: F401
from .modelo import Carta

CARTAS: dict[str, dict] = {}


def _carta(cid, nombre, tipo, coste, fuerza, raza, texto, habilidades, notas=""):
    CARTAS[cid] = {"nombre": nombre, "tipo": tipo, "coste": coste, "fuerza": fuerza, "raza": raza,
                   "texto": texto, "habilidades": habilidades, "notas": notas}


CEMENTERIO_PROPIO = {"quien": "propio", "zona": "cementerio"}

_dos_heroes = _si("aliados_raza", 2, raza="Héroe")
_carta(
    "adonis", "Adonis", "Aliado", 3, 3, "Héroe",
    "Imbloqueable. Si controlas 2 o más Aliados de raza Héroe, puedes desterrarlo para robar 2 cartas o para "
    "que tu oponente bote 2 cartas.",
    [IMBLOQUEABLE,
     hab("robar", "Destiérralo: roba 2", cuando="activada", limitePorTurno=1, grupoLimite="adonis",
         costo={"desterrarEstaCarta": True}, condicion=_dos_heroes, cantidad=2, objetivo=PROPIO),
     hab("botar", "Destiérralo: el oponente bota 2", cuando="activada", limitePorTurno=1, grupoLimite="adonis",
         costo={"desterrarEstaCarta": True}, condicion=_dos_heroes, cantidad=2, objetivo=RIVAL)],
    "Antes: acción «grupoElegir» (no existe en el motor). Ahora son dos activaciones; se usa una sola.",
)
_carta(
    "ascenso_draco", "Ascenso Draco", "Talismán", 3, None, "",
    "Elige entre que los Aliados oponentes pierdan 1 a la fuerza por cada Aliado Draco que controles hasta la "
    "Fase Final o que tus Aliados de raza Dragón ganen 1 a la fuerza hasta la Fase Final.",
    [hab("modificarFuerza", "Los Aliados oponentes pierden 1 por cada Aliado Draco tuyo", cuando="al_jugar",
         grupoElegir="ascenso", valor=-1, valorPorCada="aliado_arquetipo", porCadaArquetipo="Draco",
         duracion="hasta_fase_final", cantidad=99,
         objetivo={"quien": "oponente", "tipos": ["Aliado"], "seleccion": "todos"}),
     hab("modificarFuerza", "Tus Aliados Dragón ganan 1", cuando="al_jugar", grupoElegir="ascenso", valor=1,
         duracion="hasta_fase_final", cantidad=99,
         objetivo={"quien": "propio", "tipos": ["Aliado"], "raza": "Dragón", "seleccion": "todos"})],
    "Antes no hacía nada, y la primera opción restaba 1 fijo (el texto dice 1 por cada Aliado Draco).",
)
_carta(
    "ataque_de_vampiros", "Ataque de Vampiros", "Talismán", 2, None, "",
    "Si controlas una o más cartas Drácula, este Talismán no puede ser anulado. Elige entre barajar 4 cartas "
    "de tu Cementerio en tu Mazo Castillo o desterrar 2 cartas de un Cementerio.",
    [hab("noAnulable", "No puede ser anulado si controlas una carta Drácula", cuando="continua",
         condicion=_si("cartas_arquetipo_en_juego", 1, arquetipo="Drácula")),
     hab("barajar", "Baraja 4 cartas de tu Cementerio", cuando="al_jugar", grupoElegir="vampiros", cantidad=4,
         objetivo=CEMENTERIO_PROPIO),
     hab("desterrar", "Destierra 2 cartas de un Cementerio", cuando="al_jugar", grupoElegir="vampiros",
         cantidad=2, objetivo={"quien": "cualquiera", "zona": "cementerio"})],
    "Antes no hacía nada y le faltaba «no puede ser anulado si controlas una carta Drácula».",
)
_carta(
    "dominios_de_ra_pianjy", "Pianjy", "Aliado", 2, 2, "Faraón",
    "Cuando Pianjy entra en juego, puedes elegir entre barajar dos cartas de tu Cementerio en tu Mazo "
    "Castillo o que tu oponente bote dos cartas de su Mazo Castillo.",
    [hab("barajar", "Baraja 2 cartas de tu Cementerio", cuando="al_jugar", opcional=True, grupoElegir="pianjy",
         cantidad=2, objetivo=CEMENTERIO_PROPIO),
     hab("botar", "El oponente bota 2", cuando="al_jugar", opcional=True, grupoElegir="pianjy", cantidad=2,
         objetivo=RIVAL)],
)
_carta(
    "dominios_de_ra_traicion_de_seth", "Traición de Seth", "Talismán", 2, None, "",
    "Puedes jugar Traición de Seth desde tu Cementerio, si lo haces destiérralo. Elige entre desterrar una "
    "carta del Cementerio oponente, barajar una carta de tu Cementerio en tu Mazo Castillo, o que tu oponente "
    "bote una carta. Luego, roba una carta de tu Mazo Castillo.",
    [hab("desterrar", "Destierra 1 carta del Cementerio oponente", cuando="al_jugar", grupoElegir="seth",
         cantidad=1, objetivo={"quien": "oponente", "zona": "cementerio"}),
     hab("barajar", "Baraja 1 carta de tu Cementerio", cuando="al_jugar", grupoElegir="seth", cantidad=1,
         objetivo=CEMENTERIO_PROPIO),
     hab("botar", "El oponente bota 1", cuando="al_jugar", grupoElegir="seth", cantidad=1, objetivo=RIVAL),
     hab("robar", "Luego roba 1", cuando="al_jugar", cantidad=1, objetivo=PROPIO),
     hab("jugarDesde", "Se puede jugar desde tu Cementerio (y se destierra)", cuando="al_jugar", modo="pagando",
         talismanVaA="destierro", objetivo={"quien": "esta_carta", "zona": "cementerio"})],
    "Antes no elegía nada (solo robaba) y le faltaba poder jugarse desde el Cementerio.",
)
_carta(
    "espada_sagrada_dragon_nube", "Dragón Nube", "Aliado", 4, 3, "Dragón",
    "Cuando entra en juego, puedes elegir entre robar 2 cartas o que tu oponente bote 2 cartas.",
    [hab("robar", "Roba 2", cuando="al_jugar", opcional=True, grupoElegir="nube", cantidad=2, objetivo=PROPIO),
     hab("botar", "El oponente bota 2", cuando="al_jugar", opcional=True, grupoElegir="nube", cantidad=2,
         objetivo=RIVAL)],
)
_carta(
    "helenica_eneas", "Eneas", "Aliado", 2, 2, "Héroe",
    "Puede atacar cuando entra en juego. Cuando sea destruido, puedes barajar dos cartas de tu Cementerio en "
    "tu Mazo Castillo o robar una carta.",
    [FURIA,
     hab("barajar", "Al ser destruido: baraja 2 cartas de tu Cementerio", cuando="al_ser_destruido",
         opcional=True, grupoElegir="eneas", cantidad=2, objetivo=CEMENTERIO_PROPIO),
     hab("robar", "Al ser destruido: roba 1", cuando="al_ser_destruido", opcional=True, grupoElegir="eneas",
         cantidad=1, objetivo=PROPIO)],
    "Antes estaba como «cuando otra carta tuya sale del juego» y sin efecto. Ahora es al ser destruido él.",
)
_carta(
    "cadena_espiritual", "Cadena Espiritual", "Talismán", 3, None, "",
    "Envía todas las carta de tu Destierro hacia tu Cementerio.",
    [hab("mover", "Todo tu Destierro va a tu Cementerio", cuando="al_jugar", zonaDestino="cementerio",
         cantidad=99, objetivo={"quien": "propio", "zona": "destierro", "seleccion": "todos"})],
    "Antes: acción «subirCementerio» (no existe en el motor).",
)
_carta(
    "hijos_de_daana_danza_sidhe", "Danza Sidhe", "Talismán", 1, None, "",
    "Roba 2 cartas. Luego, descarta 2 cartas. Si esta carta está en tu Cementerio, y controlas Aliados "
    "Sidhe, puedes pagar 1 Oro para ponerla al fondo de tu Mazo Castillo.",
    [hab("robar", "Roba 2", cuando="al_jugar", cantidad=2, objetivo=PROPIO),
     hab("descartar", "Luego descarta 2", cuando="al_jugar", cantidad=2, objetivo=PROPIO),
     hab("mover", "Desde el Cementerio: paga 1 y va al fondo de tu Mazo", cuando="activada",
         zonaActivacion="cementerio", costo={"oros": 1}, zonaDestino="mazo_fondo",
         condicion=_si("aliados_arquetipo", 1, arquetipo="Sidhe"),
         objetivo={"quien": "esta_carta", "zona": "cementerio"})],
    "Antes: acción «fondoMazo» (no existe en el motor): nunca volvía al Mazo.",
)
_carta(
    "hijos_de_daana_fear_sidhe", "Fear Sidhe", "Aliado", 3, 4, "Desafiante",
    "En tu Fase de Vigilia, una vez por turno, puedes pagar el coste de un Aliado Sidhe de tu Cementerio para "
    "jugarlo sin pagar su coste. Si este Aliado es descartado por una habilidad, puedes barajar 2 cartas de tu "
    "Cementerio en tu Mazo Castillo.",
    [hab("jugarDesde", "Juega un Aliado Sidhe de tu Cementerio pagando su coste", cuando="activada",
         fase="vigilia", turno="propio", limitePorTurno=1, modo="pagando",
         objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"], "arquetipo": "Sidhe"}),
     hab("barajar", "Descartado por una habilidad: baraja 2 cartas de tu Cementerio", cuando="al_descartarse",
         soloPorHabilidad=True, opcional=True, cantidad=2, objetivo=CEMENTERIO_PROPIO)],
    "Antes jugaba el Aliado gratis (el texto pide pagar su coste) y el descarte no disparaba nada. "
    "El descarte por exceso de mano (regla, no habilidad) no lo dispara.",
)
_carta(
    "dominios_de_ra_absalon", "Absalon", "Aliado", 5, 2, "Sacerdote",
    "Mientras esté en tu Línea de Defensa, en respuesta a que juegues un Talismán que no sea de anulación o en "
    "respuesta, barájalo en tu Mazo Castillo.",
    [hab("barajar", "El Talismán que juegas vuelve barajado a tu Mazo", cuando="propia_juega",
         disparoTipos=["Talismán"], condicion=_si("esta_carta_en_linea", 1, zona="linea_defensa"),
         objetivo={"quien": "disparadora"})],
    "Antes buscaba un Talismán «en juego» (nunca lo hay). Los Talismanes de anulación o respuesta se juegan en "
    "su propia ventana y no lo disparan. El Talismán se resuelve y después se baraja.",
)


def carta(cid: str) -> Carta:
    from .datos import carta_desde_doc

    d = CARTAS[cid]
    return carta_desde_doc(cid, {"nombre": d["nombre"], "tipo": d["tipo"], "coste": d["coste"],
                                 "fuerza": d["fuerza"], "raza": d["raza"], "habilidadTextoIA": d["texto"],
                                 "habilidades": d["habilidades"], "habilidadesRevisadas": True})


def validar() -> list[str]:
    from .ia_cartas import validar as validar_habs

    return [f"{cid}: {e}" for cid, d in CARTAS.items() for e in validar_habs(d["habilidades"])]


def main(argv=None) -> int:
    for flujo in (sys.stdout, sys.stderr):
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8", errors="replace")
    argv = sys.argv[1:] if argv is None else argv
    errores = validar()
    for e in errores:
        print("✗", e)
    print(f"{len(CARTAS)} cartas en el lote, {sum(len(d['habilidades']) for d in CARTAS.values())} habilidades")
    if errores:
        return 1
    if "--aplicar" not in argv:
        return 0
    from google.cloud import firestore

    from .datos import db

    for cid, d in CARTAS.items():
        ref = db().collection("cards").document(cid)
        doc = ref.get()
        if not doc.exists:
            print(f"– {cid}: no existe en el catálogo, se omite")
            continue
        anterior = doc.to_dict() or {}
        # Estas cartas ya venían del agente: `cola_agente.aplicar` no respalda
        # en ese caso. Aquí se guarda lo anterior en un campo aparte.
        ref.update({
            "habilidades": d["habilidades"],
            "habilidadesRevisadas": True,
            "habilidadesFuente": "agente",
            "habilidadesUpdatedAt": firestore.SERVER_TIMESTAMP,
            "habilidadesAntesCorreccion": {"habilidades": anterior.get("habilidades") or [], "fecha": "2026-11-18"},
            "solicitudAgente": {"estado": "programada", "notas": d["notas"], "at": firestore.SERVER_TIMESTAMP},
        })
        print(f"✓ {cid}: {len(d['habilidades'])} habilidad(es)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
