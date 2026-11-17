"""Procesa las simulaciones pedidas desde la app.

La app crea simulations/{id} con:
    {ownerUid, deckA, deckB, n, seed, jugador, status: "pending", createdAt}
Este proceso (en el PC del dueño) toma las pendientes, las corre y escribe:
    status: running → done | error, progreso (0–1), resultado (informe), error

Uso, desde myl_decks/simulator/:
    .venv/Scripts/python -m myl_sim.worker          (queda escuchando)
    .venv/Scripts/python -m myl_sim.worker --una    (procesa lo pendiente y sale)
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import traceback
from pathlib import Path
from google.api_core.retry import Retry

from .datos import CACHE, cargar_ban_list, cargar_mazo, db, exigir_validos
from .desafio import SesionDesafio, reintentar_red
from .simulacion import narrar, simular

MAX_PARTIDAS = 20000
ESPERA = 3  # segundos entre revisiones
LATIDO = 30  # cada cuánto avisa que está vivo (simulator_status/worker)
_ultimo_latido = [0.0]
_desafios_activos: set[str] = set()
_jobs_ia_activos: set[str] = set()
_jobs_ml_activos: set[str] = set()
_RED_RETRY = Retry(initial=1, maximum=4, timeout=12)


def latido(forzar: bool = False) -> None:
    """Avisa a la app que el worker está corriendo (pantalla del simulador)."""
    from google.cloud import firestore
    import socket

    ahora = time.time()
    if not forzar and ahora - _ultimo_latido[0] < LATIDO:
        return
    _ultimo_latido[0] = ahora
    try:
        db().collection("simulator_status").document("worker").set(
            {"lastSeen": firestore.SERVER_TIMESTAMP, "host": socket.gethostname()},
            retry=_RED_RETRY,
            timeout=15,
        )
    except Exception:  # noqa: BLE001 - sin red no se cae el worker
        traceback.print_exc()


def procesar(doc) -> None:
    from google.cloud import firestore

    d = doc.to_dict() or {}
    ref = doc.reference
    # Tomar la tarea solo si sigue pendiente (por si hay dos workers).
    tomada = db().transaction()

    @firestore.transactional
    def tomar(tx):
        actual = ref.get(transaction=tx).to_dict() or {}
        if actual.get("status") != "pending":
            return False
        tx.update(ref, {"status": "running", "progreso": 0, "startedAt": firestore.SERVER_TIMESTAMP})
        return True

    if not tomar(tomada):
        return
    try:
        n = max(1, min(int(d.get("n", 1000)), MAX_PARTIDAS))
        owner = d["ownerUid"]
        ma = cargar_mazo(owner, d["deckA"])
        mb = cargar_mazo(owner, d["deckB"])
        # Con cartas sin marcar como programadas el motor las juega sin
        # habilidades: el resultado no sirve. La app manda a marcarlas.
        faltan = sorted({c for c, _ in ma.sin_programar() + mb.sin_programar()})
        if faltan:
            raise ValueError("Cartas sin marcar como programadas: " + ", ".join(faltan))
        exigir_validos(ma, mb, ban=cargar_ban_list(ma.formato))
        print(f"→ {ma.nombre} vs {mb.nombre} ({n} partidas)")
        ultimo = [0.0]

        def progreso(k: int, parcial) -> None:
            # En vivo: progreso y métricas parciales, como mucho cada 1,5 s.
            ahora = time.time()
            if ahora - ultimo[0] > 1.5:
                ultimo[0] = ahora
                ref.update({"progreso": k / n, "parcial": parcial()})
                latido()  # una simulación larga no lo hace parecer apagado

        t0 = time.time()
        seed, jugador = int(d.get("seed", 1)), str(d.get("jugador", "heuristico"))
        if n == 1:
            inicial = d.get("inicial")
            r = narrar(  # una partida narrada
                ma, mb, seed=seed, jugador=jugador, inicial=int(inicial) if inicial in (0, 1) else None
            )
        else:
            r = simular(ma, mb, n, seed=seed, jugador=jugador, progreso=progreso)
        r["segundos"] = round(time.time() - t0, 1)
        # Firestore no acepta tuplas anidadas: listas simples.
        for k in ("sinProgramarA", "sinProgramarB"):
            r[k] = [{"carta": c, "copias": n_} for c, n_ in r[k]]
        ref.update({"status": "done", "progreso": 1, "resultado": r, "finishedAt": firestore.SERVER_TIMESTAMP})
        print(f"  listo: winrate A {r['winrateA'] * 100:.1f}% en {r['segundos']} s")
    except Exception as e:  # noqa: BLE001 - se informa en la app
        traceback.print_exc()
        ref.update({"status": "error", "error": str(e)[:500]})


def pendientes():
    from google.cloud.firestore_v1.base_query import FieldFilter

    return db().collection("simulations").where(filter=FieldFilter("status", "==", "pending")).limit(5).stream(
        retry=_RED_RETRY, timeout=15
    )


def _guardar_lecciones(ref, data: dict, informe: dict, *, mazo_ia: str, mazo_humano: str,
                       nivel: int, ia_perdio: bool) -> None:
    """Errores de la IA y jugadas marcadas ✓/✗ → ia_lecciones (las convierto en
    reglas de la heurística con tests y lotes, como los reportes)."""
    from google.cloud import firestore

    for r in informe["revisiones"]:
        if not r["error"] and not r.get("sutil") and r.get("voto") is None:
            continue
        reintentar_red(lambda r=r: db().collection("ia_lecciones").document(f"{ref.id}_{r['paso']}").set({
            "desafio": ref.id,
            "ownerUid": data.get("ownerUid"),
            "deckHumano": data.get("deckHumano"),
            "deckIa": data.get("deckIa"),
            "mazoIa": mazo_ia,
            "mazoHumano": mazo_humano,
            "nivel": nivel,
            "iaPerdio": ia_perdio,
            "revision": r,
            "estado": "pendiente",
            "createdAt": firestore.SERVER_TIMESTAMP,
        }, merge=True))


def _aprender_del_humano(ref, data: dict, cartas, nombres, seed: int, registro: list, metodos,
                         resultado: dict, *, nivel: int) -> None:
    """Tus jugadas contra lo que habría hecho la IA en la misma posición: las
    que rinden claramente más (o que confirmaste) van a ia_lecciones."""
    from google.cloud import firestore

    from .aprendizaje_humano import informe as informe_humano, lecciones

    try:
        reintentar_red(lambda: ref.update({"aprendizajeEstado": "analizando"}))
        actual = reintentar_red(lambda: ref.get()).to_dict() or {}
        inf = informe_humano(cartas, nombres, seed, registro, metodos, resultado.get("ganadorLado"),
                             resultado.get("turnos"), confirmaciones=actual.get("confirmacionesHumano") or {})
        reintentar_red(lambda: ref.update({"aprendizajeHumano": inf, "aprendizajeEstado": "lista"}))
        for x in lecciones(inf):
            reintentar_red(lambda x=x: db().collection("ia_lecciones").document(f"{ref.id}_h{x['paso']}").set({
                "origen": "humano",
                "desafio": ref.id,
                "ownerUid": data.get("ownerUid"),
                "deckHumano": data.get("deckHumano"),
                "deckIa": data.get("deckIa"),
                "mazoHumano": nombres[0],
                "mazoIa": nombres[1],
                "nivel": nivel,
                "revision": x,
                "confirmacion": x.get("confirmacion"),
                "estado": "pendiente",
                "createdAt": firestore.SERVER_TIMESTAMP,
            }, merge=True))
    except Exception as e:  # noqa: BLE001 - la autopsia de la IA ya quedó guardada
        traceback.print_exc()
        reintentar_red(lambda: ref.update({"aprendizajeEstado": "error", "aprendizajeError": str(e)[:300]}))


def analizar_desafio(ref, sesion, data: dict, resultado: dict) -> None:
    """Autopsia al terminar: por qué perdió la IA y las jugadas marcadas ✓/✗."""
    try:
        # La grabación permite reproducir la partida más adelante (reanalizar).
        reintentar_red(lambda: ref.collection("grabacion").document("registro").set({
            "seed": sesion.seed, "registro": sesion.grabacion, "metodos": sesion.metodos,
            # Mazos tal como se jugaron: para fijar la posición como test aunque cambien.
            "mazos": [sesion.mazo_humano.to_json(), sesion.mazo_ia.to_json()],
        }))
        votos = (reintentar_red(lambda: ref.get()).to_dict() or {}).get("votosIa") or {}
        informe = sesion.autopsia(votos, resultado.get("ganadorLado"))
        reintentar_red(lambda: ref.update({"autopsia": informe, "autopsiaEstado": "lista"}))
        _guardar_lecciones(ref, data, informe, mazo_ia=sesion.mazo_ia.nombre,
                           mazo_humano=sesion.mazo_humano.nombre, nivel=sesion.nivel,
                           ia_perdio=resultado.get("ganadorLado") == 0)
        _aprender_del_humano(ref, data, (sesion.mazo_humano.cartas, sesion.mazo_ia.cartas),
                             (sesion.mazo_humano.nombre, sesion.mazo_ia.nombre), sesion.seed,
                             sesion.grabacion, sesion.metodos, resultado, nivel=sesion.nivel)
    except Exception as e:  # noqa: BLE001 - la partida ya quedó guardada
        traceback.print_exc()
        reintentar_red(lambda: ref.update({"autopsiaEstado": "error", "autopsiaError": str(e)[:300],
                                                 "aprendizajeEstado": "error", "aprendizajeError": str(e)[:300]}))


def reanalisis_pendientes():
    from google.cloud.firestore_v1.base_query import FieldFilter

    return db().collection("ai_challenges").where(filter=FieldFilter("autopsiaEstado", "==", "pedida")).limit(2).stream(
        retry=_RED_RETRY, timeout=15
    )


def reanalizar_desafio(doc) -> None:
    """La persona marcó jugadas ✓/✗ en la revisión: se vuelve a analizar con
    la grabación guardada (sin volver a jugar la partida)."""
    from .autopsia import informe as hacer_informe

    ref = doc.reference
    data = doc.to_dict() or {}
    if doc.id in _desafios_activos:
        return
    _desafios_activos.add(doc.id)

    def correr() -> None:
        try:
            reintentar_red(lambda: ref.update({"autopsiaEstado": "analizando", "aprendizajeEstado": "analizando"}))
            g = reintentar_red(lambda: ref.collection("grabacion").document("registro").get()).to_dict()
            if not g:
                raise ValueError("Este desafío no tiene grabación (es anterior a la autopsia)")
            owner = data["ownerUid"]
            if g.get("mazos"):
                # Los mazos tal como se jugaron: si después cambiaste el mazo,
                # la reproducción igual es la misma partida.
                from .datos import Mazo

                humano, ia = (Mazo.from_json(m) for m in g["mazos"])
            else:
                humano = reintentar_red(lambda: cargar_mazo(owner, data["deckHumano"]))
                ia = reintentar_red(lambda: cargar_mazo(owner, data["deckIa"]))
            resultado = data.get("resultado") or {}
            informe = hacer_informe((humano.cartas, ia.cartas), (humano.nombre, ia.nombre), g["seed"],
                                    g["registro"], g.get("metodos"), data.get("accionesIa") or [],
                                    data.get("votosIa") or {}, resultado.get("ganadorLado"))
            reintentar_red(lambda: ref.update({"autopsia": informe, "autopsiaEstado": "lista"}))
            _guardar_lecciones(ref, data, informe, mazo_ia=ia.nombre, mazo_humano=humano.nombre,
                               nivel=int(resultado.get("nivelIa") or data.get("nivel") or 5),
                               ia_perdio=resultado.get("ganadorLado") == 0)
            _aprender_del_humano(ref, data, (humano.cartas, ia.cartas), (humano.nombre, ia.nombre),
                                 g["seed"], g["registro"], g.get("metodos"), resultado,
                                 nivel=int(resultado.get("nivelIa") or data.get("nivel") or 5))
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            reintentar_red(lambda: ref.update({"autopsiaEstado": "error", "autopsiaError": str(e)[:300],
                                                 "aprendizajeEstado": "error", "aprendizajeError": str(e)[:300]}))
        finally:
            _desafios_activos.discard(doc.id)

    threading.Thread(target=correr, name=f"autopsia-{doc.id}", daemon=True).start()


def procesar_desafio(doc) -> None:
    """Inicia un hilo por desafío: ese hilo puede esperar respuestas humanas."""
    from google.cloud import firestore

    if doc.id in _desafios_activos:
        return
    ref = doc.reference
    tomada = db().transaction()

    @firestore.transactional
    def tomar(tx):
        actual = ref.get(transaction=tx).to_dict() or {}
        if actual.get("status") != "pending":
            return None
        tx.update(ref, {"status": "preparando", "startedAt": firestore.SERVER_TIMESTAMP})
        return actual

    data = tomar(tomada)
    if data is None:
        return
    _desafios_activos.add(doc.id)

    def correr() -> None:
        sesion = None
        try:
            if data.get("modo") == "duda":
                # Una duda de la IA: una sola decisión sobre el tablero (myl_sim.dudas).
                from .dudas import atender_desafio

                atender_desafio(ref, data)
                return
            owner = data["ownerUid"]
            humano = reintentar_red(lambda: cargar_mazo(owner, data["deckHumano"]))
            ia = reintentar_red(lambda: cargar_mazo(owner, data["deckIa"]))
            faltan = sorted({c for c, _ in humano.sin_programar() + ia.sin_programar()})
            if faltan:
                raise ValueError("Cartas sin marcar como programadas: " + ", ".join(faltan))
            exigir_validos(humano, ia, ban=reintentar_red(lambda: cargar_ban_list(humano.formato)))
            sesion = SesionDesafio(ref, humano, ia, seed=int(data.get("seed", 1)),
                                   buscar_bloqueos=data.get("buscarBloqueos") is True,
                                   nivel=int(data.get("nivel") or 5),
                                   pausa=1.4)  # cada jugada de la IA se ve en la mesa (más si cambia la mesa)
            resultado = sesion.jugar()
            repeticion = resultado.pop("repeticion")
            pasos = repeticion.pop("pasos")
            for indice in range(0, len(pasos), 80):
                reintentar_red(lambda indice=indice: ref.collection("repeticion").document(f"{indice // 80:04d}").set({
                    "indice": indice,
                    "pasos": pasos[indice:indice + 80],
                }))
            resultado["repeticion"] = {**repeticion, "cantidadPasos": len(pasos)}
            reintentar_red(lambda: ref.update({
                "status": "terminado", "resultado": resultado,
                "finishedAt": firestore.SERVER_TIMESTAMP,
                "autopsiaEstado": "analizando", "aprendizajeEstado": "analizando",
            }))
            analizar_desafio(ref, sesion, data, resultado)
        except Exception as e:  # noqa: BLE001 - el usuario debe ver el corte
            traceback.print_exc()
            estado = "abandonado" if str(e) == "Desafío abandonado por el jugador" else "error"
            reintentar_red(lambda: ref.update({"status": estado, "error": str(e)[:500]}))
            if sesion is not None and sesion.grabacion:
                # Una partida cortada (error del motor) también se puede
                # reproducir hasta el punto de un reporte en vivo.
                try:
                    reintentar_red(lambda: ref.collection("grabacion").document("registro").set({
                        "seed": sesion.seed, "registro": sesion.grabacion, "metodos": sesion.metodos,
                        "mazos": [sesion.mazo_humano.to_json(), sesion.mazo_ia.to_json()],
                        "cortada": True, "traza": traceback.format_exc()[-2000:],
                    }))
                except Exception:  # noqa: BLE001
                    traceback.print_exc()
        finally:
            _desafios_activos.discard(doc.id)

    threading.Thread(target=correr, name=f"desafio-{doc.id}", daemon=True).start()


def jobs_ia_pendientes():
    from google.cloud.firestore_v1.base_query import FieldFilter

    return db().collection("card_ai_jobs").where(filter=FieldFilter("status", "==", "pending")).limit(3).stream(
        retry=_RED_RETRY, timeout=15
    )


def procesar_job_ia(doc) -> None:
    """card_ai_jobs/{id}: {ownerUid, cardIds, tipo, status: "pending"}. En un
    hilo aparte (no frena simulaciones), por cada carta: tipo "leer"
    transcribe la habilidad; tipo "codigo" lee el código impreso de cada
    variante (codigos_cartas.py); tipo "programar" deja la propuesta en
    cards/{id}.propuestaIA (con "respuestas" del dueño a sus preguntas).
    Escribe resultados.{cardId} = {status, ... | error}."""
    from google.cloud import firestore

    if doc.id in _jobs_ia_activos:
        return
    ref = doc.reference

    @firestore.transactional
    def tomar(tx):
        actual = ref.get(transaction=tx).to_dict() or {}
        if actual.get("status") != "pending":
            return None
        tx.update(ref, {"status": "procesando", "startedAt": firestore.SERVER_TIMESTAMP})
        return actual

    data = tomar(db().transaction())
    if data is None:
        return
    _jobs_ia_activos.add(doc.id)

    def sin_creditos(error: Exception) -> bool:
        texto = str(error).lower()
        return "no credits remaining" in texto or "insufficient_quota" in texto

    def correr() -> None:
        from google.cloud.firestore_v1.field_path import FieldPath

        from . import ia_cartas

        ids = [str(c) for c in data.get("cardIds") or []][:60]
        tipo = data.get("tipo") or "leer"
        ok = 0
        try:
            for k, cid in enumerate(ids):
                print(f"IA {doc.id}: {tipo} {cid} ({k + 1}/{len(ids)})")
                try:
                    if tipo == "programar":
                        res = ia_cartas.programar(cid, str(data.get("respuestas") or ""))
                    elif tipo == "codigo":
                        from . import codigos_cartas

                        res = codigos_cartas.procesar_carta(cid)
                    else:
                        res = ia_cartas.procesar_carta(cid)
                    ok += 1
                except Exception as e:  # noqa: BLE001 - se informa por carta
                    # Sin saldo no es un error de esta carta. Detener el lote
                    # evita quemar toda la cola con el mismo 429; el job queda
                    # listo para reintentarse cuando se carguen créditos.
                    if sin_creditos(e):
                        reintentar_red(lambda e=e, k=k: ref.update({
                            "status": "blocked",
                            "error": "Sin créditos de OpenAI. Recarga saldo y reintenta este lote.",
                            "progreso": k / len(ids),
                            "blockedAt": firestore.SERVER_TIMESTAMP,
                        }))
                        return
                    traceback.print_exc()
                    res = {"status": "error", "error": str(e)[:400]}
                campo = FieldPath("resultados", cid).to_api_repr()  # ids con guiones
                reintentar_red(lambda res=res, campo=campo, k=k: ref.update({
                    campo: res, "progreso": (k + 1) / len(ids),
                }))
            reintentar_red(lambda: ref.update({
                "status": "listo", "ok": ok, "finishedAt": firestore.SERVER_TIMESTAMP,
            }))
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            reintentar_red(lambda: ref.update({"status": "error", "error": str(e)[:500]}))
        finally:
            _jobs_ia_activos.discard(doc.id)

    threading.Thread(target=correr, name=f"ia-{doc.id}", daemon=True).start()


def jobs_ml_pendientes():
    """Trabajos pesados pedidos desde el Laboratorio ML de la app."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    return db().collection("ml_jobs").where(
        filter=FieldFilter("status", "==", "pending")
    ).limit(2).stream(retry=_RED_RETRY, timeout=15)


def procesar_job_ml(doc) -> None:
    """Ejecuta una matriz local sin bloquear simulaciones ni desafíos.

    La colección es una cola mínima: el navegador crea el pedido y este
    proceso, que conserva los datos de entrenamiento en el PC, lo resuelve.
    """
    from google.cloud import firestore

    if doc.id in _jobs_ml_activos:
        return
    ref = doc.reference

    @firestore.transactional
    def tomar(tx):
        actual = ref.get(transaction=tx).to_dict() or {}
        if actual.get("status") != "pending":
            return None
        tx.update(ref, {"status": "running", "progreso": 0,
                        "startedAt": firestore.SERVER_TIMESTAMP})
        return actual

    data = tomar(db().transaction())
    if data is None:
        return
    _jobs_ml_activos.add(doc.id)

    def correr() -> None:
        try:
            tipo = str(data.get("tipo") or "")
            from . import trabajos

            if tipo in trabajos.TIPOS:
                # Matriz del meta, optimizador y evaluador de cartas: CLI en otro proceso.
                print(f"ML {doc.id}: {tipo}")
                marca = [0.0]

                def linea(texto: str) -> None:
                    if time.time() - marca[0] >= 2:
                        marca[0] = time.time()
                        ref.update({"parcial": {"ultimaLinea": texto[:300]}})
                        latido()

                t0 = time.time()
                resumen, ruta = trabajos.ejecutar(tipo, data, doc.id, linea)
                resumen["segundos"] = round(time.time() - t0, 1)
                ref.update({"status": "done", "progreso": 1, "resultado": resumen,
                            "localPath": str(ruta.resolve()),
                            "finishedAt": firestore.SERVER_TIMESTAMP})
                print(f"  {tipo} listo ({resumen['segundos']} s)")
                return
            if tipo != "matriz":
                raise ValueError(f"Tipo de trabajo ML no soportado: {tipo}")
            owner = str(data["ownerUid"])
            base_id = str(data["deckBase"])
            formato = str(data.get("formato") or "racial")
            n = max(1, min(int(data.get("n", 1000)), MAX_PARTIDAS))
            seed = int(data.get("seed", 1))
            print(f"ML {doc.id}: matriz {base_id}, formato {formato}, {n} partidas")
            ultimo = [0.0]

            def avance(indice, total, base_nombre, rival_nombre, fila) -> None:
                ahora = time.time()
                # La última actualización siempre se guarda, aunque haya sido rápida.
                if ahora - ultimo[0] >= 1.2 or indice == total:
                    ultimo[0] = ahora
                    ref.update({
                        "progreso": indice / total,
                        "parcial": {
                            "completados": indice, "total": total,
                            "ultimoRival": rival_nombre,
                            "ultimoWinrate": fila["winrate"],
                        },
                    })
                    latido()

            from .matriz_meta import ejecutar_matriz
            t0 = time.time()
            resultado = ejecutar_matriz(owner, base_id, formato=formato,
                                        partidas=n, seed=seed, progreso=avance)
            resultado["segundos"] = round(time.time() - t0, 1)
            carpeta = CACHE / "entrenamiento" / "ml_jobs"
            carpeta.mkdir(parents=True, exist_ok=True)
            ruta = carpeta / f"{doc.id}_matriz.json"
            ruta.write_text(json.dumps(resultado, ensure_ascii=False, indent=2), encoding="utf-8")
            resumen = {
                "base": resultado["base"],
                "cruces": resultado["cruces"],
                "partidasPorCruce": n,
                "formatoRivales": formato,
                "segundos": resultado["segundos"],
            }
            ref.update({"status": "done", "progreso": 1, "resultado": resumen,
                        "localPath": str(ruta.resolve()),
                        "finishedAt": firestore.SERVER_TIMESTAMP})
            print(f"  matriz lista: {resultado['base']['nombre']} ({len(resultado['cruces'])} cruces)")
        except Exception as e:  # noqa: BLE001 - se ve directamente en la app
            traceback.print_exc()
            ref.update({"status": "error", "error": str(e)[:500]})
        finally:
            _jobs_ml_activos.discard(doc.id)

    threading.Thread(target=correr, name=f"ml-{doc.id}", daemon=True).start()


def desafios_pendientes():
    from google.cloud.firestore_v1.base_query import FieldFilter

    return db().collection("ai_challenges").where(filter=FieldFilter("status", "==", "pending")).limit(3).stream(
        retry=_RED_RETRY, timeout=15
    )


def interrumpir_desafios_huerfanos() -> None:
    """Un estado en memoria no sobrevive a reiniciar el worker.

    Es preferible avisarlo explícitamente que dejar una pantalla esperando una
    respuesta que ningún proceso podrá consumir.
    """
    from google.cloud.firestore_v1.base_query import FieldFilter

    for doc in db().collection("ai_challenges").where(
        filter=FieldFilter("status", "in", ["preparando", "jugando", "esperando"])
    ).stream(retry=_RED_RETRY, timeout=15):
        doc.reference.update({
            "status": "error",
            "error": "El worker se reinició; crea un nuevo desafío.",
        })


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--una", action="store_true", help="procesar lo pendiente y salir")
    ap.add_argument("--conservar-activos", action="store_true",
                    help="iniciar junto al worker anterior sin interrumpir desafíos en curso")
    args = ap.parse_args(argv)
    # En segundo plano o redirigida, la consola de Windows es cp1252 y un
    # "→" en un print botaba la simulación ('charmap' codec).
    for flujo in (sys.stdout, sys.stderr):
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8", errors="replace")
    print("Worker del simulador escuchando simulations/ (Ctrl+C para salir)")
    inicio_pendiente = not args.conservar_activos
    while True:
        try:
            latido(forzar=inicio_pendiente)
            if inicio_pendiente:
                interrumpir_desafios_huerfanos()
                inicio_pendiente = False
            for doc in pendientes():
                procesar(doc)
            for doc in desafios_pendientes():
                procesar_desafio(doc)
            for doc in reanalisis_pendientes():
                reanalizar_desafio(doc)
            for doc in jobs_ia_pendientes():
                procesar_job_ia(doc)
            for doc in jobs_ml_pendientes():
                procesar_job_ml(doc)
            if args.una:
                return 0
            time.sleep(ESPERA)
        except Exception:  # noqa: BLE001 - una caída de Firestore no mata al worker
            traceback.print_exc()
            time.sleep(5)


if __name__ == "__main__":
    raise SystemExit(main())
