"""Lote del 2026-11-17: 38 cartas nuevas de Helénica y Espada Sagrada.

Héctor las cargó con su texto (leído de la imagen) pero sin programar. Aquí
queda la programación de cada una, tal como se guardó en ``cards/{id}``, para
que los tests la prueben sin tocar Firestore.

    .venv/Scripts/python -m myl_sim.lote_20261117             (lista y valida)
    .venv/Scripts/python -m myl_sim.lote_20261117 --aplicar   (escribe en Firestore)

``--aplicar`` usa ``cola_agente.aplicar``: guarda respaldo de lo anterior en
``habilidadesAntesIA`` y marca la carta como programada. Solo toca cartas que
sigan sin revisar (no pisa lo que el dueño haya programado después).
"""

from __future__ import annotations

import sys

from .modelo import Carta, normalizar_tipo


def hab(accion: str, nombre: str, **campos) -> dict:
    return {"featureId": f"gen_{accion}", "featureName": nombre, "accion": accion, **campos}


def luego(accion: str, relacion: str = "si_se_cumplio", **campos) -> dict:
    return {"relacion": relacion, "accion": accion, "cantidad": 1, **campos}


FURIA = hab("furia", "Puede atacar al entrar", cuando="continua")
IMBLOQUEABLE = hab("imbloqueable", "Imbloqueable", cuando="continua")
ERRANTE = hab("errante", "Solo uno en juego", cuando="continua")
PROPIO = {"quien": "propio"}
RIVAL = {"quien": "oponente"}
ESTA = {"quien": "esta_carta"}


def _si(tipo: str, valor: int, **extra) -> dict:
    return {"tipo": tipo, "op": ">=", "valor": valor, **extra}


# id → (nombre, tipo, coste, fuerza, raza, texto, habilidades, notas)
CARTAS: dict[str, dict] = {}


def _carta(cid, nombre, tipo, coste, fuerza, raza, texto, habilidades, notas=""):
    CARTAS[cid] = {"nombre": nombre, "tipo": tipo, "coste": coste, "fuerza": fuerza, "raza": raza,
                   "texto": texto, "habilidades": habilidades, "notas": notas}


# ── Helénica ─────────────────────────────────────────────────────────────────
_carta(
    "amazonas_guerreras", "Amazonas Guerreras", "Aliado", 2, 3, "Héroe",
    "Puede atacar cuando entra en juego. Si controlas 2 o más Aliados Amazona, puedes jugar este Aliado "
    "de tu Mano sin pagar su coste.",
    [FURIA,
     hab("modificarCoste", "Gratis con 2 o más Aliados Amazona", cuando="continua", valor=-2, objetivo=ESTA,
         condicion=_si("aliados_arquetipo", 2, arquetipo="Amazona", incluyeFuente=True))],
    "Jugarla sin pagar = su coste baja a 0 mientras controles 2 o más Aliados Amazona.",
)
_carta(
    "anfiarao", "Anfiarao", "Aliado", 4, 4, "Héroe",
    "Cuando entra en juego, puedes mirar las 3 primeras cartas de tu Mazo Castillo y jugar un Aliado de "
    "Coste 3 o menos de ahí sin pagar su coste. Luego, debes dejar las otras cartas en la parte inferior de "
    "tu Mazo Castillo en cualquier orden.",
    [hab("mirarTope", "Mira 3 y juega gratis un Aliado de coste 3 o menos", cuando="al_jugar", opcional=True,
         cantidad=3, valor=1, zonaDestino="en_juego", restoA="mazo_fondo", privado=True,
         objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"], "costeMax": 3})],
    "Las cartas que no juega van al fondo sin mostrarse al rival (privado).",
)
_carta(
    "aqueloo", "Aqueloo", "Aliado", 1, 1, "Titán",
    "En tu Fase de Vigilia, una vez por turno, puedes desterrar una carta de tu Cementerio para barajar una "
    "carta de tu Cementerio en tu Mazo Castillo.",
    [hab("barajar", "Destierra 1 de tu Cementerio: baraja otra en tu Mazo", cuando="activada", fase="vigilia",
         turno="propio", limitePorTurno=1, costo={"desterrarCementerio": 1},
         condicion=_si("cartas_cementerio", 2), cantidad=1, objetivo={"quien": "propio", "zona": "cementerio"})],
    "Pide 2 cartas en el Cementerio: una se destierra y la otra se baraja.",
)
_carta(
    "atalanta_la_amazona", "Atalanta La Amazona", "Aliado", 4, 4, "Héroe",
    "Puede atacar cuando entra en juego. Si controlas 1 o más Armas, este Aliado es Indestructible. Cuando "
    "entra en juego, puedes jugar un Arma de tu Mano sin pagar su coste.",
    [FURIA,
     hab("indestructible", "Indestructible si controlas un Arma", cuando="continua",
         condicion=_si("armas_propias", 1)),
     hab("jugarDesde", "Juega gratis un Arma de tu mano", cuando="al_jugar", opcional=True, modo="sin_pagar",
         objetivo={"quien": "propio", "zona": "mano", "tipos": ["Arma"]})],
)
_carta(
    "behemot", "Behemot", "Aliado", 4, 4, "Titán",
    "Cuando entra en juego, tus Aliados de raza Titán ganan 1 a la fuerza permanentemente. Cuando entra en "
    "juego, todos tus Aliados deben ser bloqueados por los Aliados de tu oponente este turno.",
    [hab("modificarFuerza", "+1 permanente a tus Titanes", cuando="al_jugar", valor=1, duracion="permanente",
         cantidad=99, objetivo={"quien": "propio", "tipos": ["Aliado"], "raza": "Titán", "seleccion": "todos"}),
     hab("restringirCombate", "Tus Aliados deben ser bloqueados este turno", cuando="al_jugar",
         modo="debe_ser_bloqueado", duracion="hasta_fase_final", cantidad=99,
         objetivo={"quien": "propio", "tipos": ["Aliado"], "seleccion": "todos"})],
    "El +1 lo reciben los Titanes en juego al entrar (también él). El defensor elige con qué bloquea a cada uno.",
)
_carta(
    "caminar_las_estrellas", "Caminar Las Estrellas", "Talismán", 2, None, "",
    "Busca 2 cartas en tu Mazo Castillo con distinto nombre y muéstralas a tu oponente. Tu oponente elige "
    "una de ellas y la pone en tu Mano, y la otra ponla en tu Cementerio.",
    [hab("buscar", "Busca 2 de distinto nombre; el oponente elige cuál va a tu mano", cuando="al_jugar",
         cantidad=2, zonaDestino="mano", oponenteEligeMano=True,
         objetivo={"quien": "propio", "zona": "mazo", "distintoNombre": True})],
    "Función nueva del motor: el rival elige (la IA te deja la más barata).",
)
_carta(
    "cornucopia_de_aqueloo", "Cornucopia De Aqueloo", "Oro", None, None, "",
    "Si este Oro está en tu Reserva de Oros o en tu Zona de Oro Pagado, puedes poner este Oro en la parte "
    "inferior de tu Mazo Castillo para subir un Oro, que no sea Cornucopia de Aqueloo, de tu Cementerio a tu Mano.",
    [hab("subirMano", "Al fondo del Mazo: sube un Oro de tu Cementerio", cuando="activada",
         zonaActivacion="reserva_o_pagado", costo={"fondoMazoEstaCarta": True},
         objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Oro"], "excluirEstaCarta": True})],
)
_carta(
    "enialio", "Enialio", "Aliado", 2, 2, "Olímpico",
    "Puede atacar cuando entra en juego. Una vez por turno, puedes pagar 1 Oro para mover un Aliado oponente "
    "de la Línea de Ataque a la Línea de Defensa.",
    [FURIA,
     hab("mover", "Paga 1: un Aliado oponente pasa de Ataque a Defensa", cuando="activada", limitePorTurno=1,
         costo={"oros": 1}, zonaDestino="linea_defensa",
         objetivo={"quien": "oponente", "zona": "linea_ataque", "tipos": ["Aliado"]})],
    "En el catálogo figura con fuerza 22 (error de tipeo): el simulador usa 2. Corregir la carta en la app.",
)
_carta(
    "harma", "Harma", "Arma", 2, None, "",
    "El portador gana 2 a la fuerza. Cuando entra en juego, puedes barajar hasta 2 cartas de tu Cementerio "
    "en tu Mazo Castillo. Luego, puedes robar 1 carta.",
    [hab("modificarFuerza", "+2 al portador", cuando="continua", valor=2, objetivo=ESTA),
     hab("barajar", "Baraja hasta 2 cartas de tu Cementerio", cuando="al_jugar", opcional=True, cantidad=2,
         objetivo={"quien": "propio", "zona": "cementerio"}),
     hab("robar", "Luego puedes robar 1", cuando="al_jugar", opcional=True, cantidad=1, objetivo=PROPIO)],
)
_carta(
    "las_musas", "Las Musas", "Aliado", 2, 3, "Olímpico",
    "Cuando entra en juego, puedes buscar una carta Musa en tu Mazo Castillo o Cementerio y ponerla en tu "
    "Mano. Los Talismanes oponentes que hagan objetivo a tus Aliados Musa cuestan 1 Oro adicional.",
    [hab("buscar", "Busca una carta Musa en tu Mazo o Cementerio", cuando="al_jugar", opcional=True,
         zonaDestino="mano",
         objetivo={"quien": "propio", "zona": "mazo", "zonas": ["mazo", "cementerio"], "arquetipo": "Musa"}),
     hab("encarecer", "Talismanes oponentes pagan 1 más por afectar a tus Musas", cuando="continua", valor=1,
         objetivo={"quien": "oponente", "tipos": ["Talismán"]},
         protege={"arquetipo": "Musa", "tipos": ["Aliado"]})],
    "Ampliación del motor: el recargo cubre a todas tus Musas, no solo a esta carta.",
)
_carta(
    "melinoe", "Melinoe", "Aliado", 2, 2, "Olímpico",
    "Cuando entra en juego, puedes botar 2 cartas para buscar un Aliado de coste 3 o más en tu Mazo "
    "Castillo y ponlo en tu Mano.",
    [hab("buscar", "Bota 2: busca un Aliado de coste 3 o más", cuando="al_jugar", opcional=True,
         costo={"botar": 2}, zonaDestino="mano",
         objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"], "coste": {"op": ">=", "valor": 3}})],
)
_carta(
    "men", "Men", "Aliado", 6, 3, "Olímpico",
    "Sólo puedes tener un Men en juego. Cuando entra en juego, puedes elegir un Aliado de tu Cementerio y "
    "jugarlo sin pagar su coste. Luego, bota tantas cartas como coste tenga ese Aliado.",
    [ERRANTE,
     hab("jugarDesde", "Juega gratis un Aliado de tu Cementerio; luego botas su coste", cuando="al_jugar",
         opcional=True, modo="sin_pagar", objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"]},
         luego=[luego("botar", cantidadSegun="coste_afectada", objetivo=PROPIO)])],
    "Quien juega a Men bota tantas cartas como el coste del Aliado que trajo.",
)
_carta(
    "minotauro_del_hades", "Minotauro Del Hades", "Aliado", 3, 3, "Titán",
    "Indesterrable. Si controlas otro Aliado Minotauro, este Aliado puede atacar cuando entra en juego. En "
    "tu Fase de Vigilia, si este Aliado está en tu Cementerio, puedes desterrar una carta de tu Cementerio y "
    "pagar 2 Oros para jugarlo sin pagar su coste.",
    [hab("indesterrable", "Indesterrable", cuando="continua"),
     hab("furia", "Puede atacar al entrar si controlas otro Minotauro", cuando="continua",
         condicion=_si("aliados_arquetipo", 2, arquetipo="Minotauro", incluyeFuente=True)),
     hab("jugarDesde", "Desde el Cementerio: destierra 1 de tu Cementerio y paga 2 para jugarlo",
         cuando="activada", fase="vigilia", turno="propio", zonaActivacion="cementerio", modo="sin_pagar",
         costo={"oros": 2, "desterrarCementerio": 1}, objetivo={"quien": "esta_carta", "zona": "cementerio"})],
)
_carta(
    "musa_caliope", "Musa Caliope", "Aliado", 1, 1, "Olímpico",
    "Cuando un Oro entre en juego bajo tu control, tu oponente bota 1 carta. Cuando una carta Musa entre o "
    "salga del juego, tu oponente bota 1 carta.",
    [hab("botar", "Entra un Oro tuyo: el oponente bota 1", cuando="propia_entra", disparoTipos=["Oro"],
         cantidad=1, objetivo=RIVAL),
     hab("botar", "Entra otra carta Musa tuya: el oponente bota 1", cuando="propia_entra",
         disparoArquetipo="Musa", cantidad=1, objetivo=RIVAL),
     hab("botar", "Sale otra carta Musa tuya: el oponente bota 1", cuando="propia_sale",
         disparoArquetipo="Musa", cantidad=1, objetivo=RIVAL),
     hab("botar", "Al entrar (ella es una Musa): el oponente bota 1", cuando="al_jugar", cantidad=1,
         objetivo=RIVAL),
     hab("botar", "Al salir (ella es una Musa): el oponente bota 1", cuando="al_salir_del_juego", cantidad=1,
         objetivo=RIVAL)],
    "Interpretación: ella misma cuenta como carta Musa al entrar y al salir; solo cuentan las Musas que tú controlas.",
)
_carta(
    "musa_urania", "Musa Urania", "Aliado", 2, 2, "Olímpico",
    "En tu Fase de Vigilia, una vez por turno, puedes pagar 1 Oro para mirar las 3 primeras cartas de tu "
    "Mazo Castillo, pon una carta que no sea Aliado o todos los Aliados Musa en tu Mano y baraja el resto.",
    [hab("mirarTope", "Paga 1: mira 3 y toma una carta que no sea Aliado", cuando="activada", fase="vigilia",
         turno="propio", limitePorTurno=1, grupoLimite="urania", grupoElegir="urania", costo={"oros": 1},
         cantidad=3, valor=1, zonaDestino="mano", restoA="barajar",
         objetivo={"quien": "propio", "zona": "mazo", "excluirTipos": ["Aliado"]}),
     hab("mirarTope", "Paga 1: mira 3 y toma todos los Aliados Musa", cuando="activada", fase="vigilia",
         turno="propio", limitePorTurno=1, grupoLimite="urania", grupoElegir="urania", costo={"oros": 1},
         cantidad=3, valor=3, zonaDestino="mano", restoA="barajar",
         objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"], "arquetipo": "Musa"})],
    "Dos modos de la misma habilidad: se mira una sola vez y se elige el modo viendo las cartas.",
)
_carta(
    "pelope", "Pelope", "Aliado", 2, 2, "Héroe",
    "Puede atacar cuando entra en juego. Si controlas 2 o más Aliados de raza Héroe, este Aliado gana 1 a la "
    "fuerza y es Indestructible. En tu Fase Final, puedes agrupar este Aliado.",
    [FURIA,
     hab("modificarFuerza", "+1 con 2 o más Héroes", cuando="continua", valor=1, objetivo=ESTA,
         condicion=_si("aliados_raza", 2, raza="Héroe")),
     hab("indestructible", "Indestructible con 2 o más Héroes", cuando="continua",
         condicion=_si("aliados_raza", 2, raza="Héroe")),
     hab("agrupar", "En tu Fase Final puedes agruparlo", cuando="al_inicio_fase", fase="final", turno="propio",
         opcional=True, objetivo=ESTA)],
)
_carta(
    "talos", "Talos", "Aliado", 2, 3, "Titán",
    "Mientras controles otro Titán, este Aliado es Indesterrable. Cuando sea destruido, puedes desterrar un "
    "Aliado de tu Cementerio para ponerlo en tu Mano.",
    [hab("indesterrable", "Indesterrable con otro Titán", cuando="continua",
         condicion=_si("aliados_raza", 2, raza="Titán")),
     hab("subirMano", "Al ser destruido: destierra un Aliado de tu Cementerio para volver a tu mano",
         cuando="al_ser_destruido", opcional=True,
         costo={"desterrarCementerio": 1, "filtro": {"tipos": ["Aliado"]}},
         objetivo={"quien": "esta_carta", "zona": "cementerio"})],
    "Interpretación: «ponerlo en tu Mano» es Talos (se paga desterrando otro Aliado del Cementerio).",
)
_carta(
    "taumante", "Taumante", "Aliado", 4, 4, "Titán",
    "En cada Fase de Agrupación, puedes elegir entre barajar una carta de tu Cementerio en tu Mazo Castillo, "
    "desterrar una carta de un Cementerio, o robar 1 carta.",
    [hab("robar", "Agrupación: roba 1", cuando="al_inicio_fase", fase="agrupacion", opcional=True,
         limitePorTurno=1, grupoLimite="taumante", cantidad=1, objetivo=PROPIO),
     hab("barajar", "Agrupación: baraja 1 de tu Cementerio", cuando="al_inicio_fase", fase="agrupacion",
         opcional=True, limitePorTurno=1, grupoLimite="taumante", cantidad=1,
         objetivo={"quien": "propio", "zona": "cementerio"}),
     hab("desterrar", "Agrupación: destierra 1 de un Cementerio", cuando="al_inicio_fase", fase="agrupacion",
         opcional=True, limitePorTurno=1, grupoLimite="taumante", cantidad=1,
         objetivo={"quien": "cualquiera", "zona": "cementerio"})],
    "Una sola de las tres por Agrupación, en la tuya y en la del oponente («en cada»).",
)
_carta(
    "tea", "Tea", "Aliado", 3, 2, "Titán",
    "Una vez por turno, puedes pagar 2 de Oro o desterrar un Aliado de tu Cementerio para que un Aliado en "
    "juego tenga fuerza 0 y no pueda recibir modificadores de fuerza hasta la Fase Final.",
    [hab("modificarFuerza", "Paga 2 o destierra un Aliado de tu Cementerio: un Aliado queda en fuerza 0",
         cuando="activada", limitePorTurno=1, costo={"oros": 2},
         costoAlternativo={"desterrarCementerio": 1, "filtro": {"tipos": ["Aliado"]}},
         modoFuerza="fijar", valor=0, congelar=True, duracion="hasta_fase_final",
         objetivo={"quien": "cualquiera", "tipos": ["Aliado"]})],
)
_carta(
    "telestris_la_amazona", "Telestris La Amazona", "Aliado", 3, 3, "Héroe",
    "Puede atacar cuando entra en juego. En tu Fase de Vigilia, una vez por turno, puedes buscar una carta "
    "Amazona o una Reina Hipólita en tu Mazo Castillo y ponerlo en tu Mano. Tus Aliados Amazona y Reina "
    "Hipólita ganan 1 a la fuerza.",
    [FURIA,
     hab("buscar", "Busca una carta Amazona", cuando="activada", fase="vigilia", turno="propio", opcional=True,
         limitePorTurno=1, grupoLimite="telestris", zonaDestino="mano",
         objetivo={"quien": "propio", "zona": "mazo", "arquetipo": "Amazona"}),
     hab("buscar", "Busca una Reina Hipólita", cuando="activada", fase="vigilia", turno="propio", opcional=True,
         limitePorTurno=1, grupoLimite="telestris", zonaDestino="mano",
         objetivo={"quien": "propio", "zona": "mazo", "nombre": "Reina Hipólita"}),
     hab("modificarFuerza", "+1 a tus Aliados Amazona", cuando="continua", valor=1,
         objetivo={"quien": "propio", "tipos": ["Aliado"], "arquetipo": "Amazona", "seleccion": "todos"}),
     hab("modificarFuerza", "+1 a tu Reina Hipólita", cuando="continua", valor=1,
         objetivo={"quien": "propio", "tipos": ["Aliado"], "nombre": "Reina Hipólita", "seleccion": "todos"})],
    "Ella misma es una Amazona: también gana +1. La búsqueda es una sola por turno (Amazona o Reina Hipólita).",
)

# ── Espada Sagrada ───────────────────────────────────────────────────────────
_carta(
    "draco_aguila", "Draco Águila", "Aliado", 1, 1, "Dragón",
    "Puedes tener más de 3 Draco Águila en tu Mazo Castillo. Imbloqueable. Cuando entra en juego, tu "
    "oponente bota 1 carta por cada Draco Águila que controles.",
    [IMBLOQUEABLE,
     hab("botar", "El oponente bota 1 por cada Draco Águila que controles", cuando="al_jugar",
         cantidadSegun="aliados_arquetipo", porCadaArquetipo="Draco Águila", cantidad=1, objetivo=RIVAL)],
    "El límite de 3 copias no rige para esta carta (validador de la app y del simulador), salvo que la Ban "
    "List le fije uno.",
)
_carta(
    "draco_de_inverness", "Draco De Inverness", "Aliado", 1, 1, "Dragón",
    "Puede atacar cuando entra en juego. Cuando es declarado atacante, si controlas 3 o más Aliados de raza "
    "Dragón, este Aliado gana 2 a la fuerza hasta la Fase Final.",
    [FURIA,
     hab("modificarFuerza", "+2 al atacar con 3 o más Dragones", cuando="al_atacar", valor=2,
         duracion="hasta_fase_final", objetivo=ESTA, condicion=_si("aliados_raza", 3, raza="Dragón"))],
)
_carta(
    "dragon_del_agua", "Dragón Del Agua", "Aliado", 5, 5, "Dragón",
    "Imbloqueable. Mientras este Aliado esté en juego, tus demás Aliados de raza Dragón no pueden ser "
    "afectados por Talismanes oponentes.",
    [IMBLOQUEABLE,
     hab("inmunidad", "Tus demás Dragones: inmunes a Talismanes oponentes", cuando="continua",
         objetivo={"quien": "oponente", "tipos": ["Talismán"]},
         protege={"raza": "Dragón", "tipos": ["Aliado"], "excluirEstaCarta": True})],
)
_carta(
    "espina_de_serpiente", "Espina De Serpiente", "Oro", None, None, "",
    "Cuando entra en juego, puedes elegir un Aliado oponente para que pierda 1 a la fuerza permanentemente. "
    "Puedes barajar este Oro en tu Mazo Castillo para que un Aliado oponente pierda 1 a la fuerza hasta la "
    "Fase Final.",
    [hab("modificarFuerza", "-1 permanente a un Aliado oponente", cuando="al_jugar", opcional=True, valor=-1,
         duracion="permanente", objetivo={"quien": "oponente", "tipos": ["Aliado"]}),
     hab("modificarFuerza", "Barájalo: -1 a un Aliado oponente hasta la Fase Final", cuando="activada",
         zonaActivacion="reserva_o_pagado", costo={"barajarEstaCarta": True}, valor=-1,
         duracion="hasta_fase_final", objetivo={"quien": "oponente", "tipos": ["Aliado"]})],
)
_carta(
    "fenex", "Fenex", "Aliado", 2, 2, "Faerie",
    "Cuando entra o sale del juego, tu oponente bota 1 carta. En tu Fase de Vigilia, una vez por turno y si "
    "este Aliado está en tu Cementerio, puedes pagar 1 Oro para subirlo a tu Mano.",
    [hab("botar", "Al entrar: el oponente bota 1", cuando="al_jugar", cantidad=1, objetivo=RIVAL),
     hab("botar", "Al salir: el oponente bota 1", cuando="al_salir_del_juego", cantidad=1, objetivo=RIVAL),
     hab("subirMano", "Desde el Cementerio: paga 1 y vuelve a tu mano", cuando="activada", fase="vigilia",
         turno="propio", limitePorTurno=1, zonaActivacion="cementerio", costo={"oros": 1},
         objetivo={"quien": "esta_carta", "zona": "cementerio"})],
)
_carta(
    "fiodhain", "Fiodhain", "Aliado", 2, 2, "Faerie",
    "Cuando entra en juego, puedes elegir un Aliado de tu Cementerio. Este Aliado tiene todas las "
    "habilidades de ese Aliado por el resto del juego.",
    [hab("copiarHabilidad", "Tiene las habilidades de un Aliado de tu Cementerio", cuando="al_jugar",
         opcional=True, duracion="permanente",
         objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"]})],
    "Ampliación del motor: la copia no expira en la Fase Final; dura mientras Fiodhain siga en juego. Las "
    "habilidades de «al entrar» del Aliado copiado no se disparan (Fiodhain ya entró).",
)
_carta(
    "fruto_fiodhain", "Fruto Fiodhain", "Oro", None, None, "",
    "Una vez por turno, cuando juegues un Talismán, puedes mirar las dos primeras cartas de tu Mazo Castillo "
    "y dejar cada una de ellas en la parte superior o inferior de tu Mazo Castillo. Sólo puedes activar un "
    "Fruto Fiodhain por turno.",
    [hab("mirarTope", "Al jugar un Talismán: mira 2 y déjalas arriba o al fondo", cuando="propia_juega",
         disparoTipos=["Talismán"], opcional=True, limitePorTurno=1, limitePorNombre=True, cantidad=2,
         restoA="elegir_tope_fondo", objetivo={"quien": "propio", "zona": "mazo"})],
    "Disparador nuevo del motor («cuando juegas una carta»). Aproximación: las dos cartas van juntas arriba "
    "o juntas al fondo (el texto deja decidir cada una).",
)
_carta(
    "goblin_berserker", "Goblin Berserker", "Aliado", 4, 4, "Faerie",
    "Puede atacar cuando entra en juego. Cuando entra en juego, puedes desterrar cualquier cantidad de "
    "cartas Goblin de tu Cementerio. Por cada carta desterrada, este Aliado gana 1 a la fuerza hasta la Fase Final.",
    [FURIA,
     hab("desterrar", "Destierra Goblins de tu Cementerio: +1 por cada uno", cuando="al_jugar", opcional=True,
         cantidad=99, objetivo={"quien": "propio", "zona": "cementerio", "arquetipo": "Goblin"},
         luego=[luego("modificarFuerza", valor=1, valorPorCada="carta_afectada", duracion="hasta_fase_final",
                      objetivo=ESTA)])],
)
_carta(
    "jared_el_mago", "Jared El Mago", "Aliado", 3, 2, "Faerie",
    "Sólo puedes tener un Jared el Mago en juego. Una vez por turno, cuando juegues un Talismán, puedes "
    "barajar un Aliado oponente de coste igual o menor al Talismán jugado.",
    [ERRANTE,
     hab("barajar", "Al jugar un Talismán: baraja un Aliado oponente de coste igual o menor", cuando="propia_juega",
         disparoTipos=["Talismán"], opcional=True, limitePorTurno=1,
         objetivo={"quien": "oponente", "tipos": ["Aliado"],
                   "coste": {"op": "<=", "valor": 0, "segun": "coste_disparadora"}})],
    "Disparador nuevo del motor («cuando juegas una carta»). Se resuelve después del Talismán.",
)
_carta(
    "lady_rachel", "Lady Rachel", "Aliado", 2, 3, "Caballero",
    "En tu Fase de Vigilia, una vez por turno, puedes destruir un Arma que controles para destruir una carta "
    "oponente en juego de coste 2 o menos.",
    [hab("destruir", "Destruye un Arma tuya: destruye una carta oponente de coste 2 o menos", cuando="activada",
         fase="vigilia", turno="propio", limitePorTurno=1,
         costo={"destruirPropias": 1, "filtro": {"tipos": ["Arma"]}},
         objetivo={"quien": "oponente", "costeMax": 2})],
    "Los Oros no tienen coste: no son objetivo.",
)
_carta(
    "martillo_de_galehaut", "Martillo De Galehaut", "Arma", 3, None, "",
    "Cuando entra en juego, puedes desterrar hasta dos cartas de cualquier Cementerio. El portador gana 1 a "
    "la fuerza por cada Arma y Aliado Sir en tu destierro.",
    [hab("desterrar", "Destierra hasta 2 cartas de cualquier Cementerio", cuando="al_jugar", opcional=True,
         cantidad=2, objetivo={"quien": "cualquiera", "zona": "cementerio"}),
     hab("modificarFuerza", "+1 al portador por cada Arma y Aliado Sir en tu destierro", cuando="continua",
         valor=1, valorPorCada="destierro_propio",
         porCadaFiltros=[{"tipos": ["Arma"]}, {"tipos": ["Aliado"], "arquetipo": "Sir"}], objetivo=ESTA)],
)
_carta(
    "nathair_teine", "Nathair-Teine", "Aliado", 2, 2, "Dragón",
    "Puede atacar cuando entra en juego. Cuando es declarado atacante, puedes elegir un Aliado de raza "
    "Dragón de coste 1 o menos en tu Cementerio y jugarlo sin pagar su coste en tu Línea de Ataque como un "
    "Aliado declarado atacante. En tu Fase Final, ese Aliado debe ser destruido.",
    [FURIA,
     hab("jugarDesde", "Al atacar: juega atacando un Dragón de coste 1 o menos de tu Cementerio",
         cuando="al_atacar", opcional=True, modo="sin_pagar",
         objetivo={"quien": "propio", "zona": "cementerio", "tipos": ["Aliado"], "raza": "Dragón", "costeMax": 1},
         luego=[luego("restringirCombate", modo="entra_atacando", duracion="hasta_fase_final",
                      objetivo={"quien": "propio", "referencia": "afectadas", "seleccion": "todos"}),
                luego("destruir", "siempre", momento="fase_final",
                      objetivo={"quien": "propio", "referencia": "afectadas", "seleccion": "todos"})])],
    "Función nueva del motor: el Aliado se suma al ataque en curso. No dispara su propio «al ser declarado "
    "atacante» (no fue declarado: entró atacando).",
)
_carta(
    "oberon", "Oberon", "Aliado", 4, 3, "Faerie",
    "Sólo puedes tener un Oberón en juego. Cuando entra en juego, puedes barajar una carta en juego que no "
    "sea Oro. Una vez por turno, puedes pagar 1 Oro o destruir este u otro Aliado que controles para robar 2 "
    "cartas. Luego, descarta 1 carta de tu Mano.",
    [ERRANTE,
     hab("barajar", "Baraja una carta en juego que no sea Oro", cuando="al_jugar", opcional=True,
         objetivo={"quien": "cualquiera", "excluirTipos": ["Oro"]}),
     hab("robar", "Paga 1 o destruye un Aliado tuyo: roba 2 y descarta 1", cuando="activada", limitePorTurno=1,
         costo={"oros": 1}, costoAlternativo={"destruirAliados": 1, "incluyeEstaCarta": True}, cantidad=2,
         objetivo=PROPIO, luego=[luego("descartar", "siempre", objetivo=PROPIO)])],
)
_carta(
    "sir_bleoberis", "Sir Bleoberis", "Aliado", 2, 3, "Caballero",
    "Cuando entra en juego, puedes destruir una carta oponente en juego que no sea Oro, de coste igual o "
    "menor a la cantidad de Armas que controles.",
    [hab("destruir", "Destruye una carta oponente de coste igual o menor a tus Armas", cuando="al_jugar",
         opcional=True,
         objetivo={"quien": "oponente", "excluirTipos": ["Oro"],
                   "coste": {"op": "<=", "valor": 0, "segun": "armas_propias"}})],
)
_carta(
    "sir_galehodin", "Sir Galehodin", "Aliado", 3, 2, "Caballero",
    "Sólo puedes tener un Sir Galehodin en juego. Mientras este Aliado esté en juego, jugar Aliados Sir te "
    "cuesta 1 Oro menos.",
    [ERRANTE,
     hab("modificarCoste", "Tus Aliados Sir cuestan 1 menos", cuando="continua", valor=-1,
         objetivo={"quien": "propio", "tipos": ["Aliado"], "arquetipo": "Sir"})],
    "«Sir» se compara como palabra completa (Osiris no es un Aliado Sir).",
)
_carta(
    "sir_owen", "Sir Owen", "Aliado", 3, 3, "Caballero",
    "Única. Cuando entra en juego, puedes robar 3 cartas. Luego, destierra una carta de tu Mano.",
    [hab("robar", "Roba 3; luego destierra una carta de tu mano", cuando="al_jugar", opcional=True, cantidad=3,
         objetivo=PROPIO, luego=[luego("desterrar", "siempre", objetivo={"quien": "propio", "zona": "mano"})])],
    "«Única» es regla de construcción (1 copia): falta marcarla como única en el catálogo.",
)
_carta(
    "sir_tor", "Sir Tor", "Aliado", 1, 1, "Caballero",
    "Imbloqueable. Puede atacar cuando entra en juego. Cuando es declarado atacante junto a 2 o más Aliados "
    "Sir, cada jugador bota 2 cartas. Luego, destierra una carta de tu Cementerio.",
    [IMBLOQUEABLE, FURIA,
     hab("botar", "Al atacar junto a 2 o más Sir: cada jugador bota 2; luego destierras 1 de tu Cementerio",
         cuando="al_atacar", cantidad=2, objetivo={"quien": "ambos"},
         condicion=_si("atacantes_arquetipo", 3, arquetipo="Sir"),
         luego=[luego("desterrar", "siempre", objetivo={"quien": "propio", "zona": "cementerio"})])],
    "«Junto a 2 o más Aliados Sir» = 3 atacantes Sir contándolo a él.",
)
_carta(
    "yddraig_ddall", "Yddraig Ddall", "Aliado", 2, 2, "Dragón",
    "Cuando entra en juego, si controlas 2 o más Aliados de raza Dragón, puedes barajar un Aliado de raza "
    "Dragón de tu Mano para buscar un Aliado de raza Dragón en tu Mazo Castillo y ponerlo en tu Mano.",
    [hab("barajar", "Con 2 o más Dragones: baraja un Dragón de tu mano para buscar otro", cuando="al_jugar",
         opcional=True, condicion=_si("aliados_raza", 2, raza="Dragón"),
         objetivo={"quien": "propio", "zona": "mano", "tipos": ["Aliado"], "raza": "Dragón"},
         luego=[luego("buscar", zonaDestino="mano",
                      objetivo={"quien": "propio", "zona": "mazo", "tipos": ["Aliado"], "raza": "Dragón"})])],
    "Él mismo cuenta para los 2 Dragones (ya está en juego cuando se revisa).",
)


def carta(cid: str) -> Carta:
    """La carta ya programada, como la ve el motor (para tests y pruebas)."""
    from .datos import carta_desde_doc

    d = CARTAS[cid]
    return carta_desde_doc(cid, {"nombre": d["nombre"], "tipo": d["tipo"], "coste": d["coste"],
                                 "fuerza": d["fuerza"], "raza": d["raza"], "habilidadTextoIA": d["texto"],
                                 "habilidades": d["habilidades"], "habilidadesRevisadas": True})


def validar() -> list[str]:
    """Acciones y momentos contra el vocabulario del editor (card_habilidad.dart)."""
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
    from .cola_agente import aplicar
    from .datos import db

    for cid, d in CARTAS.items():
        actual = db().collection("cards").document(cid).get()
        doc = actual.to_dict() or {}
        if not actual.exists:
            print(f"– {cid}: no existe en el catálogo, se omite")
            continue
        if doc.get("habilidadesRevisadas") is True and "--forzar" not in argv:
            print(f"– {cid}: ya está marcada como programada, no se toca")
            continue
        aplicar(cid, d["habilidades"], d["notas"])
        print(f"✓ {cid}: {len(d['habilidades'])} habilidad(es)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
