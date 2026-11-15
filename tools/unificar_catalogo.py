"""Unifica el catálogo de características (card_custom_features) en verbos
genéricos, según lo acordado con el dueño el 2026-11-06.

- Crea (o actualiza) las características genéricas `gen_*` con su
  descripción y acción del simulador.
- Las antiguas que se unifican quedan con `unificadaEn: <id genérica>`. No se
  borran ni se tocan las etiquetas de las cartas (caracteristicasRaw), así
  los filtros y estadísticas actuales siguen igual.
- Las que quedan como propias reciben su descripción y acción.

Uso (desde myl_decks/):
    simulator/.venv/Scripts/python tools/unificar_catalogo.py             (simulación)
    simulator/.venv/Scripts/python tools/unificar_catalogo.py --confirmar
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "simulator"))

from myl_sim.datos import db  # noqa: E402

GENERICAS = {
    "gen_destruir": ("Destruir", "destruir", "Removal",
        "Envía cartas en juego al Cementerio de su dueño. En cada carta se indica qué tipo, de quién, con qué coste/fuerza/raza y cuántas (o todas).",
        ["Destruir", "Destruir Aliado", "Destruir Totem", "Destruir Oro", "Removal masivo"]),
    "gen_desterrar": ("Desterrar", "desterrar", "Removal",
        "Envía cartas a la Zona de Destierro, desde el juego, el Mazo Castillo (incluido desde el tope) o el Cementerio. En cada carta se indica qué, de dónde y con qué limitaciones.",
        ["Destierro", "Desterrar Aliado", "Desterrar Totem", "Desterrar del Mazo", "Destierro Cementerio", "Desterrar del tope"]),
    "gen_botar": ("Botar", "botar", "Daño Directo",
        "Un jugador Bota N cartas de su Mazo Castillo al Cementerio (daño directo). En cada carta se indica si bota el oponente, tú o ambos.",
        ["Daño Directo", "Autodaño"]),
    "gen_descartar": ("Descartar", "descartar", "Quitar recursos",
        "Un jugador pone cartas de su mano en el Cementerio. En cada carta se indica quién descarta, cuántas y si las elige o son al azar.",
        ["Descarte", "Autodescarte"]),
    "gen_subir_mano": ("Subir a la mano", "subirMano", "Removal",
        "Devuelve una carta a la mano: una carta en juego a la mano de su dueño, o una carta de tu Cementerio a tu mano. En cada carta se indica desde dónde.",
        ["Subir a mano", "subir de cementerio a mano"]),
    "gen_barajar": ("Barajar", "barajar", "Control",
        "Baraja cartas en el Mazo Castillo de su dueño: desde el Cementerio, desde el juego o desde la mano (p. ej. la mano rival). En cada carta se indica desde dónde.",
        ["Baraje", "Barajar oponente", "Barajar desde la mano"]),
    "gen_mover": ("Mover", "mover", "Control",
        "Traslada una carta de una zona o línea a otra sin destruirla: al tope o al fondo del Mazo, a la Línea de Ataque, al Cementerio, u ordenar cartas del tope.",
        ["Poner al tope", "Poner al Fondo del Mazo", "Mover Linea de Ataque", "mover oponente a linea de ataque", "Poner Cartas en el Cementerio", "Ordenar Cartas"]),
    "gen_buscar": ("Buscar", "buscar", "Recursos",
        "Busca cartas en el Mazo, Cementerio o Destierro y las lleva a la mano (o a otra zona). Si busca en el Mazo, se baraja después.",
        ["Buscador", "Reclutar"]),
    "gen_jugar_desde": ("Jugar desde otra zona", "jugarDesde", "Recursos",
        "Permite jugar una carta desde una zona distinta de la mano (Cementerio, Mazo…), pagando o sin pagar su coste. Cuenta como jugarla: dispara habilidades y se puede anular.",
        ["Jugar Cartas Del Cementerio", "Sin Pagar su Coste", "Invocador", "Exhumar"]),
    "gen_mod_fuerza": ("Modificar fuerza", "modificarFuerza", "Bonificador",
        "Cambia la Fuerza de Aliados: sumar o restar N, fijar en N, duplicar o volver a la fuerza impresa (cancela bonificaciones). En cada carta se indica a quién y hasta cuándo.",
        ["Bonificador", "Autobonificador", "Reducir Fuerza", "Cancelar Bonificadores"]),
    "gen_control": ("Ganar control", "ganarControl", "Control",
        "Tomas el control de una carta oponente (Aliado, Oro…). En cada carta se indica qué carta, con qué coste/fuerza y hasta cuándo.",
        ["Control de aliados", "Control de Oro"]),
    "gen_mirar": ("Mirar", "mirar", "Control",
        "Miras información oculta: la mano del oponente o cartas del Mazo Castillo.",
        ["Mirar mano oponente", "Mirar Cartas Del Mazo"]),
    "gen_perder_habilidad": ("Perder habilidad", "perderHabilidad", "Quitar recursos",
        "Las cartas objetivo pierden su habilidad, hasta cuándo indique la carta.",
        ["Inhabilitar", "Perder Habilidad"]),
    "gen_restringir_combate": ("Restringir combate", "restringirCombate", "Control",
        "Cambia lo que un Aliado puede hacer en combate: no puede bloquear, no puede atacar, no puede ser bloqueado o puede bloquear imbloqueables.",
        ["No Bloquea", "Bloquea Imbloqueables"]),
    "gen_cancelar_ataque": ("Cancelar ataque o bloqueo", "cancelarAtaque", "Defensivo",
        "Cancela un ataque (los atacantes vuelven a la Línea de Defensa y se pasa a la Fase Final) o un bloqueo.",
        ["Evitar Ataque", "Evitar Bloqueo"]),
}

# Características que quedan como propias: (acción, descripción).
PROPIAS = {
    "Buscar en mazo y enviar a cementerio": ("buscar", "Busca una carta en el Mazo Castillo y la envía al Cementerio (o al Destierro)."),
    "Acelerar oro": ("ponerEnJuego", "Juega un Oro directamente desde el Mazo Castillo a tu Reserva de Oro."),
    "Generador de oros": ("generarOro", "Genera Oros virtuales que duran solo este turno; pueden servir solo para pagar ciertos tipos o razas."),
    "Reducir daño": ("reducirDano", "Reduce o anula el daño: el daño que recibirías queda en N o en 0, o un Aliado no hace daño este turno."),
    "Agrupar": ("agrupar", "Agrupa cartas fuera de la Fase de Agrupación: Aliados y/u Oros pagados vuelven a estar disponibles."),
    "No agrupar": ("noAgrupar", "Un jugador no agrupa Aliados y/u Oros en su próxima Fase de Agrupación."),
    "Restricción": ("restriccion", "Mientras se cumpla (p. ej. la carta está en la Reserva), no se puede realizar cierta acción: barajar, desterrar del Cementerio, jugar cierto tipo de carta…"),
    "Inmunidad": ("inmunidad", "No puede ser afectada por cierto tipo de cartas o habilidades (p. ej. Talismanes oponentes)."),
    "Prevención": ("prevenir", "Pagando un costo, evita que una carta sea Destruida o Desterrada (u otro efecto)."),
    "Anulación": ("anular", "Evita que una carta jugada entre en juego o se resuelva; va al Cementerio."),
    "Cancelación": ("otra", "Cancela una habilidad (D.A.R. 4.8)."),
    "Robo": ("robar", "Roba N cartas del Mazo Castillo."),
    "Reducir Coste": ("modificarCoste", "Cambia el coste de cartas (valor negativo = más barato)."),
    "Copia Habilidad": ("otra", "Copia la habilidad de otra carta."),
    "Convertir En Aliado": ("otra", "Una carta (Tótem, Oro, Arma) se considera Aliado con cierta fuerza, hasta cuándo indique (D.A.R. glosario 9)."),
    "Sin limite de armas": ("sinLimiteArmas", "Puede portar más de un Arma."),
    "Redireccionar": ("otra", "Redirige un efecto a otra carta (D.A.R. 4.9)."),
    "Control De Cementerio": ("otra", "Por definir con el dueño."),
    "Imbloqueable": ("imbloqueable", "No puede ser bloqueado."),
    "Indestructible": ("indestructible", "No puede ser Destruida por efectos ni en combate."),
    "Indesterrable": ("indesterrable", "No puede ser Desterrada."),
    "No Anulable": ("noAnulable", "No puede ser anulada."),
    "Furia": ("furia", "Puede atacar el turno en que entra en juego."),
    "Guardián": ("guardian", "No puede atacar."),
    "Errante": ("errante", "Solo puedes tener una copia de esta carta en juego."),
    "Retador": ("retador", "Al atacar, obliga a un Aliado oponente a bloquearlo."),
}


def main() -> int:
    confirmar = "--confirmar" in sys.argv
    col = db().collection("card_custom_features")
    por_nombre = {}
    for d in col.stream():
        nombre = str((d.to_dict() or {}).get("name", "")).strip()
        por_nombre.setdefault(nombre, d)

    faltan = []
    escrituras = []
    for gid, (nombre, accion, grupo, desc, antiguas) in GENERICAS.items():
        escrituras.append((col.document(gid), {
            "name": nombre, "group": grupo, "descripcion": desc, "accion": accion,
            "generica": True, "createdBy": "hecturnicolas@gmail.com",
        }, f"genérica {nombre}"))
        for a in antiguas:
            d = por_nombre.get(a)
            if d is None:
                faltan.append(a)
                continue
            escrituras.append((d.reference, {"unificadaEn": gid, "accion": accion}, f"  {a} → {nombre}"))
    for nombre, (accion, desc) in PROPIAS.items():
        d = por_nombre.get(nombre)
        if d is None:
            faltan.append(nombre)
            continue
        escrituras.append((d.reference, {"accion": accion, "descripcion": desc}, f"propia {nombre} ({accion})"))

    for _, _, texto in escrituras:
        print(texto)
    usados = {a for *_, ants in GENERICAS.values() for a in ants} | set(PROPIAS)
    sin_tocar = sorted(set(por_nombre) - usados)
    print(f"\nNo encontradas en el catálogo: {faltan or 'ninguna'}")
    print(f"Sin cambios: {sin_tocar or 'ninguna'}")
    if not confirmar:
        print("\nSimulación: no se escribió nada. Agrega --confirmar.")
        return 0
    batch = db().batch()
    for ref, data, _ in escrituras:
        batch.set(ref, data, merge=True)
    batch.commit()
    print(f"\nListo: {len(escrituras)} escrituras.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
