"""Informes auditables de las decisiones comparadas en un entrenamiento."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import heapq
import json
from pathlib import Path
from uuid import uuid4

from .datos import CACHE, Mazo


def ruta_unica(base: Path, sufijo: str) -> Path:
    instante = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return base.with_name(f"{base.stem}_{instante}_{uuid4().hex[:8]}_{sufijo}")


def ruta_ejecucion(prefijo: str, seed: int) -> Path:
    base = CACHE / "entrenamiento" / "ejecuciones" / f"{prefijo}_{seed}.json"
    return ruta_unica(base, "resultado.json")


def huella_archivo(archivo: Path) -> str:
    resumen = hashlib.sha256()
    with archivo.open("rb") as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b""):
            resumen.update(bloque)
    return resumen.hexdigest()


def huella_motor() -> str:
    """Identifica el código de reglas y políticas usado al iniciar una ejecución."""
    raiz = Path(__file__).resolve().parent
    resumen = hashlib.sha256()
    for nombre in ("modelo.py", "motor.py", "habilidades.py", "jugadores.py", "simulacion.py",
                   "busqueda_bloqueos.py"):
        resumen.update(nombre.encode("utf-8") + b"\0")
        resumen.update((raiz / nombre).read_bytes())
    return resumen.hexdigest()[:16]


def _nombre_resultado(valor: float) -> str:
    return "ganó" if valor == 1 else "empató" if valor == 0.5 else "perdió"


def _nombres(metadata: dict) -> dict[str, str]:
    nombres = {}
    for clave in ("mazoA", "mazoB"):
        deck_id = (metadata.get(clave) or {}).get("id")
        ruta = CACHE / f"mazo_{deck_id}.json"
        if ruta.exists():
            mazo = Mazo.from_json(json.loads(ruta.read_text(encoding="utf-8")))
            nombres.update({c.id: c.nombre for c in mazo.cartas})
    return nombres


def guardar_informe_exploracion(archivo: Path, informe_md: Path | None = None) -> tuple[Path, Path]:
    """Resume partidas emparejadas que probaron una sola variación."""
    informe_md = informe_md or ruta_unica(archivo, "jugadas.md")
    informe_json = informe_md.with_suffix(".json")
    with archivo.open(encoding="utf-8") as f:
        metadata = json.loads(next(f))
        if metadata.get("tipo") != "metadata" or metadata.get("esquema") != 1:
            raise ValueError("Datos de exploración incompatibles")
        grupos: dict[tuple[str, str, str, str], dict] = {}
        partidas = sin_cambios = multiples = un_cambio = omitidos = ejemplos_guardados = 0
        for linea in f:
            fila = json.loads(linea)
            partidas += 1
            eventos = fila.get("eventos") or []
            if not eventos:
                sin_cambios += 1
                continue
            if len(eventos) != 1:
                multiples += 1
                continue
            un_cambio += 1
            evento = eventos[0]
            accion_base = evento.get("accionBase") or {}
            accion_alt = evento.get("accionAlternativa") or {}
            clave = (evento["base"], evento["alternativa"],
                     accion_base.get("portadorId", ""), accion_alt.get("portadorId", ""))
            if clave not in grupos and len(grupos) >= 50000:
                omitidos += 1
                continue
            grupo = grupos.setdefault(clave, {"base": clave[0], "alternativa": clave[1],
                                              "portadorBase": clave[2], "portadorAlternativa": clave[3],
                                              "casos": 0, "mejora": 0, "empeora": 0,
                                              "igual": 0, "puntosControl": 0.0,
                                              "puntosAlternativa": 0.0, "ejemplos": []})
            control, alternativa = float(fila["control"]), float(fila["explorado"])
            grupo["casos"] += 1
            grupo["puntosControl"] += control
            grupo["puntosAlternativa"] += alternativa
            grupo["mejora"] += alternativa > control
            grupo["empeora"] += alternativa < control
            grupo["igual"] += alternativa == control
            if len(grupo["ejemplos"]) < 3 and alternativa != control and ejemplos_guardados < 1000:
                grupo["ejemplos"].append({"seed": fila["seed"], "turno": evento["turno"],
                                          "control": control, "alternativa": alternativa,
                                          "vista": evento.get("vista")})
                ejemplos_guardados += 1
    nombres = _nombres(metadata)
    lista = []
    for grupo in grupos.values():
        n = grupo["casos"]
        grupo["nombreBase"] = nombres.get(grupo["base"], grupo["base"])
        grupo["nombreAlternativa"] = nombres.get(grupo["alternativa"], grupo["alternativa"])
        if grupo["portadorBase"]:
            grupo["nombreBase"] += " en " + nombres.get(grupo["portadorBase"], grupo["portadorBase"])
        if grupo["portadorAlternativa"]:
            grupo["nombreAlternativa"] += " en " + nombres.get(grupo["portadorAlternativa"], grupo["portadorAlternativa"])
        if grupo["base"] == grupo["alternativa"] and not (grupo["portadorBase"] or grupo["portadorAlternativa"]):
            grupo["nombreAlternativa"] += " (otra copia o detalle no registrado)"
        grupo["diferenciaPuntos"] = round((grupo["puntosAlternativa"] - grupo["puntosControl"]) / n, 4)
        lista.append(grupo)
    lista.sort(key=lambda x: (-x["casos"], -abs(x["diferenciaPuntos"])))
    resultado = {"tipo": "exploracion", "origen": archivo.name,
                 "origenSha256": huella_archivo(archivo),
                 "mazoA": metadata.get("mazoA"), "mazoB": metadata.get("mazoB"),
                 "motorHuella": metadata.get("motorHuella"),
                 "partidas": partidas, "sinCambios": sin_cambios,
                 "conVariosCambios": multiples, "conUnCambio": un_cambio,
                 "casosSoloEnDetalle": omitidos,
                 "comparaciones": lista}
    informe_md.parent.mkdir(parents=True, exist_ok=True)
    informe_json.write_text(json.dumps(resultado, ensure_ascii=False, indent=2), encoding="utf-8")
    lineas = [
        "# Jugadas comparadas en la exploración", "",
        f"Fuente: {archivo.name}. {partidas} partidas emparejadas; "
        f"{resultado['conUnCambio']} probaron una sola variación, {multiples} probaron varias "
        f"y {sin_cambios} no cambiaron la jugada.", "",
        f"Huella del motor: {metadata.get('motorHuella') or 'no registrada en esta ejecución'}.", "",
        "La tabla usa solo partidas con una variación. Compara el resultado final "
        "de la partida alternativa con el control de la misma semilla; las decisiones "
        "posteriores pueden divergir. Es una señal para investigar, no una prueba "
        "de que la carta por sí sola causó el resultado. Pocos casos implican alta incertidumbre.", "",
        "| Jugada de referencia | Alternativa | Casos | Mejor / igual / peor | Diferencia de puntos |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for x in lista[:30]:
        lineas.append(f"| {x['nombreBase']} | {x['nombreAlternativa']} | {x['casos']} | "
                      f"{x['mejora']} / {x['igual']} / {x['empeora']} | "
                      f"{x['diferenciaPuntos'] * 100:+.1f} pp |")
    if not lista:
        lineas.append("| Sin comparaciones de una sola variación | — | 0 | — | — |")
    if omitidos:
        lineas += ["", f"{omitidos} casos con patrones adicionales quedaron solo en el detalle para limitar memoria."]
    lineas += ["", "## Ejemplos para revisar", ""]
    for x in lista:
        if not x["ejemplos"]:
            continue
        e = x["ejemplos"][0]
        lineas.append(f"- Semilla {e['seed']}, turno {e['turno']}: {x['nombreBase']} → "
                      f"{x['nombreAlternativa']}; el control {_nombre_resultado(e['control'])} "
                      f"y la alternativa {_nombre_resultado(e['alternativa'])}.")
        if sum(1 for linea in lineas if linea.startswith("- Semilla")) >= 10:
            break
    lineas += ["", "El archivo JSON acompaña este informe con los grupos y hasta 1.000 ejemplos. "
               "Los registros antiguos pueden no incluir la mesa de cada decisión.", ""]
    informe_md.write_text("\n".join(lineas), encoding="utf-8")
    return informe_md, informe_json


def _texto_bloqueos(opcion: dict) -> str:
    bloqueos = opcion.get("bloqueos") or []
    def carta(b: dict, clave: str) -> str:
        uid = b.get(f"{clave}Uid")
        return f"{b[clave]} (#{uid})" if uid is not None else str(b[clave])
    return ", ".join(f"{carta(b, 'bloqueador')} bloquea a {carta(b, 'atacante')}"
                     for b in bloqueos) or "sin bloqueos adicionales"


def _patron_bloqueos(opcion: dict) -> str:
    bloqueos = opcion.get("bloqueos") or []
    return ", ".join(sorted(f"{b['bloqueador']} → {b['atacante']}" for b in bloqueos)) or "sin bloquear"


def rutas_informe_bloqueos(salida: Path) -> tuple[Path, Path]:
    resumen = ruta_unica(salida, "jugadas.md")
    detalle = resumen.with_name(resumen.name.removesuffix("_jugadas.md") + "_decisiones.jsonl")
    return detalle, resumen


def guardar_informe_bloqueos(informe: dict, decisiones, salida: Path) -> tuple[Path, Path]:
    """Guarda cada decisión y un resumen legible de sus diferencias simuladas."""
    detalle, resumen = rutas_informe_bloqueos(salida)
    detalle.parent.mkdir(parents=True, exist_ok=True)
    with detalle.open("w", encoding="utf-8") as f:
        f.write(json.dumps({"tipo": "metadata", **informe}, ensure_ascii=False) + "\n")
        for evento in decisiones:
            f.write(json.dumps(evento, ensure_ascii=False) + "\n")
    resumir_informe_bloqueos(informe, detalle, resumen)
    return detalle, resumen


def resumir_informe_bloqueos(informe: dict, detalle: Path, resumen: Path) -> None:
    """Lee el detalle por líneas y conserva solo diez ejemplos en memoria."""
    destacados = []
    total_decisiones = total_destacados = patrones_omitidos = 0
    patrones: dict[tuple[str, str, str], dict] = {}
    with detalle.open(encoding="utf-8") as archivo:
        next(archivo)
        for linea in archivo:
            evento = json.loads(linea)
            total_decisiones += 1
            analisis = evento["analisis"]
            elegida = next((x for x in analisis["opciones"] if x["elegida"]), None)
            referencia = next((x for x in analisis["opciones"] if x.get("referenciaHeuristica")), None)
            if not elegida or not referencia or elegida is referencia:
                continue
            validacion = analisis.get("validacionIndependiente") or {}
            diferencia = validacion.get("diferencia")
            independiente = diferencia is not None
            if diferencia is None:
                diferencia = elegida.get("diferenciaConReferencia")
            if diferencia is None:
                continue
            muestras = validacion.get("muestras", 0) if independiente else elegida["muestrasComparables"]
            total_destacados += 1
            dato = (evento, elegida, referencia, diferencia, muestras, independiente)
            orden = (int(independiente), abs(diferencia), muestras, total_destacados)
            if len(destacados) < 10:
                heapq.heappush(destacados, (orden, dato))
            elif orden > destacados[0][0]:
                heapq.heapreplace(destacados, (orden, dato))
            if not independiente:
                continue
            obligatorios = analisis.get("bloqueosObligatorios") or []
            clave = (_patron_bloqueos({"bloqueos": obligatorios}),
                     _patron_bloqueos(referencia), _patron_bloqueos(elegida))
            if clave not in patrones and len(patrones) >= 50000:
                patrones_omitidos += 1
                continue
            grupo = patrones.setdefault(clave, {"casos": 0, "suma": 0.0,
                                                "mejor": 0, "igual": 0, "peor": 0})
            grupo["casos"] += 1
            grupo["suma"] += diferencia
            grupo["mejor"] += diferencia > 0
            grupo["igual"] += diferencia == 0
            grupo["peor"] += diferencia < 0
    destacados = [x[1] for x in sorted(destacados, reverse=True)]
    lineas = [
        "# Bloqueos comparados", "",
        f"{informe['mazo']} contra {informe['rival']}: {informe['partidasValidas']} partidas, "
        f"{total_decisiones} decisiones guardadas y {total_destacados} elecciones distintas "
        "de la referencia heurística muestreada.", "",
        f"Huella del motor: {informe.get('motorHuella') or 'no registrada en esta ejecución'}.", "",
        "Cada comparación usa los mismos escenarios muestreados para ambas opciones. "
        "Cuando hay validación independiente se usan escenarios nuevos, distintos de los que "
        "eligieron el bloqueo. La diferencia sigue siendo una estimación local con pocas "
        "simulaciones y seleccionar casos extremos puede exagerar su efecto. El resultado real de la partida "
        "se informa como contexto y no se atribuye por sí solo a un bloqueo.", "",
        "Los números entre paréntesis distinguen copias de una carta durante esa partida.", "",
        "## Patrones observados", "",
        "Promedio de diferencias locales en situaciones distintas con validación independiente. "
        "Las mesas y cartas disponibles pueden variar; el número de situaciones es la muestra.", "",
        "| Obligatorios | Referencia | Elegida | Situaciones | Mejor / igual / peor | Diferencia media |",
        "| --- | --- | --- | ---: | ---: | ---: |",
    ]
    for (obligatorio, referencia, elegida), grupo in sorted(
            patrones.items(), key=lambda x: (-x[1]["casos"], -abs(x[1]["suma"] / x[1]["casos"])))[:15]:
        lineas.append(f"| {obligatorio} | {referencia} | {elegida} | {grupo['casos']} | "
                      f"{grupo['mejor']} / {grupo['igual']} / {grupo['peor']} | "
                      f"{grupo['suma'] / grupo['casos'] * 100:+.1f} pp |")
    if not patrones:
        lineas.append("| — | Sin validaciones independientes | — | 0 | — | — |")
    if patrones_omitidos:
        lineas += ["", f"{patrones_omitidos} situaciones quedaron solo en el detalle para limitar memoria."]
    lineas += ["", "## Situaciones para revisar", ""]
    for evento, elegida, referencia, diferencia, muestras, independiente in destacados[:10]:
        vista = evento["vista"]
        yo, rival = vista["yo"], vista["rival"]
        def nombres_zona(cartas):
            return ", ".join(x.get("nombre", "?") for x in cartas) or "ninguna"
        obligatorios = evento["analisis"].get("bloqueosObligatorios") or []
        validacion = evento["analisis"].get("validacionIndependiente") or {}
        tasa_elegida = validacion.get("estimacionElegida") if independiente else elegida["estimacionVictoria"]
        tasa_referencia = validacion.get("estimacionReferencia") if independiente else referencia["estimacionVictoria"]
        fuente = "validación independiente" if independiente else "muestras usadas para elegir"
        lineas += [
            f"### Semilla {evento['seedPartida']}, turno {evento['turno']}", "",
            f"Castillos: propio {vista['yo']['castillo']}, rival {vista['rival']['castillo']}. "
            f"Partida con búsqueda: {_nombre_resultado(evento['resultadoBusqueda'])}; "
            f"control: {_nombre_resultado(evento['resultadoControl'])}.", "",
            f"Defensa propia: {nombres_zona(yo.get('defensa', []))}. "
            f"Atacantes rivales: {nombres_zona(rival.get('ataque', []))}. "
            f"Oros disponibles: {len(yo.get('reserva', []))}.", "",
        ]
        if obligatorios:
            lineas += ["Bloqueos obligatorios: " + _texto_bloqueos({"bloqueos": obligatorios}) + ".", ""]
        lineas += [
            f"- Referencia: {_texto_bloqueos(referencia)}; "
            f"{tasa_referencia * 100:.0f}% en {muestras} simulaciones de {fuente}.",
            f"- Elegida: {_texto_bloqueos(elegida)}; "
            f"{tasa_elegida * 100:.0f}% en {muestras} simulaciones de {fuente}.",
            f"- Diferencia emparejada estimada: {diferencia * 100:+.1f} puntos "
            f"en {muestras} escenarios.", "",
        ]
    if not destacados:
        lineas += ["No hubo una elección distinta de la referencia con resultados comparables.", ""]
    lineas += [f"El detalle completo está en {detalle.name}.", ""]
    resumen.write_text("\n".join(lineas), encoding="utf-8")


def guardar_informe_imitacion(archivo: Path, modelo: dict, salida: Path) -> Path:
    """Describe los datos de imitación sin atribuir resultados a jugadas."""
    contador: Counter[tuple[str, str]] = Counter()
    with archivo.open(encoding="utf-8") as f:
        metadata = json.loads(next(f))
        for linea in f:
            fila = json.loads(linea)
            if fila.get("tipo") != "decision" or fila.get("lado") != modelo.get("ladoAprendido", "A"):
                continue
            accion = fila.get("elegida") or {}
            contador[(accion.get("tipo", "?"), accion.get("carta", ""))] += 1
    lineas = [
        "# Decisiones del entrenamiento por imitación", "",
        f"Fuente: {archivo.name}; política de referencia: {metadata.get('politica', '?')}.",
        f"Huella del motor: {metadata.get('motorHuella') or 'no registrada en esta ejecución'}.",
        f"Mejor coincidencia en decisiones reservadas: {modelo['mejorAcierto'] * 100:.1f}%.", "",
        "Estos datos solo registran la opción elegida y el resultado final. No prueban "
        "las alternativas desde el mismo estado, por lo que no permiten identificar "
        "qué jugada causó una victoria. Se muestran las decisiones más frecuentes.", "",
        "| Decisión | Carta | Veces |", "| --- | --- | ---: |",
    ]
    for (tipo, carta), n in contador.most_common(20):
        lineas.append(f"| {tipo} | {carta or '—'} | {n} |")
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    return salida


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Informar jugadas de una exploración")
    parser.add_argument("archivo", type=Path)
    parser.add_argument("--salida", type=Path)
    args = parser.parse_args(argv)
    md, datos = guardar_informe_exploracion(args.archivo, args.salida)
    print(f"Informe: {md}\nDatos: {datos}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
