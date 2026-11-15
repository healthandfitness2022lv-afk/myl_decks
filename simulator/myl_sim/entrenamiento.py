"""Base local para generar episodios de aprendizaje desde autojuego.

No entrena un modelo todavía: crea datos auditables con la observación legal
del jugador, sus acciones disponibles, la elegida y el resultado final. Así
las futuras políticas no dependen de la mano ni del mazo oculto del rival.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any

from .datos import Mazo, huella_mazo
from .jugadores import Heuristico
from .motor import Partida
from .modelo import Instancia


ESQUEMA_EPISODIO = 1


def _instancia(x: Instancia, *, revelar: bool) -> dict[str, Any]:
    data: dict[str, Any] = {"tipo": x.tipo.value, "coste": x.carta.coste}
    if revelar:
        data.update({"id": x.carta.id, "nombre": x.nombre, "fuerza": x.carta.fuerza})
    return data


def vista_legal(p: Partida, yo: int) -> dict[str, Any]:
    """Estado visible para `yo`; nunca filtra identidades ocultas del rival."""
    def publico(jugador: int, propio: bool) -> dict[str, Any]:
        j = p.j(jugador)
        visibles = j.reserva + j.pagado + j.apoyo + j.defensa + j.ataque
        out = {
            "castillo": len(j.mazo),
            "mano": [_instancia(x, revelar=True) for x in j.mano] if propio else {"cantidad": len(j.mano)},
            "reserva": [_instancia(x, revelar=True) for x in j.reserva],
            "pagado": [_instancia(x, revelar=True) for x in j.pagado],
            "apoyo": [_instancia(x, revelar=True) for x in j.apoyo],
            "defensa": [_instancia(x, revelar=True) for x in j.defensa],
            "ataque": [_instancia(x, revelar=True) for x in j.ataque],
            "cementerio": [_instancia(x, revelar=True) for x in j.cementerio],
            "destierro": [_instancia(x, revelar=True) for x in j.destierro],
            "orosVirtuales": j.oros_virtuales,
        }
        # Evita que el linter/lector suponga que el mazo rival se entrega.
        assert all(x.en_juego for x in visibles)
        return out

    return {
        "turno": p.e.turno,
        "fase": p.e.fase,
        "activo": "yo" if p.e.activo == yo else "rival",
        "yo": publico(yo, True),
        "rival": publico(1 - yo, False),
    }


def _accion(jugada) -> dict[str, Any]:
    """Versión persistible de una Jugada, sin uid aleatorios de la partida."""
    out = {"tipo": jugada.tipo}
    if jugada.carta is not None:
        out["cartaId"] = jugada.carta.carta.id
        out["carta"] = jugada.carta.nombre
    if jugada.habilidad is not None:
        out["habilidad"] = jugada.habilidad
    if jugada.portador is not None:
        out["portadorId"] = jugada.portador.carta.id
        out["portador"] = jugada.portador.nombre
    return out


class GrabadorDecisiones:
    """Envuelve una política existente y registra sus decisiones principales."""

    def __init__(self, politica, eventos: list[dict[str, Any]]):
        self.politica = politica
        self.eventos = eventos

    def __getattr__(self, nombre):
        return getattr(self.politica, nombre)

    def elegir_jugada(self, p, yo, jugadas):
        elegida = self.politica.elegir_jugada(p, yo, jugadas)
        self.eventos.append({
            "tipoDecision": "jugada",
            "vista": vista_legal(p, yo),
            "legales": [_accion(x) for x in jugadas],
            "elegida": _accion(elegida),
        })
        return elegida


@dataclass(frozen=True)
class ResultadoRecoleccion:
    archivo: Path
    partidas: int
    decisiones: int
    huella_a: str
    huella_b: str


def generar_episodios(
    mazo_a: Mazo,
    mazo_b: Mazo,
    n: int,
    *,
    seed: int = 1,
    salida: Path,
) -> ResultadoRecoleccion:
    """Juega `n` partidas heurístico vs heurístico y guarda JSONL local."""
    from .informe_entrenamiento import huella_motor

    salida.parent.mkdir(parents=True, exist_ok=True)
    huella_a, huella_b = huella_mazo(mazo_a), huella_mazo(mazo_b)
    decisiones = 0
    with salida.open("w", encoding="utf-8") as f:
        cabecera = {
            "tipo": "metadata",
            "esquema": ESQUEMA_EPISODIO,
            "generado": datetime.now(timezone.utc).isoformat(),
            "motor": "myl_sim",
            "motorHuella": huella_motor(),
            "politica": "heuristico",
            "mazoA": {"id": mazo_a.id, "nombre": mazo_a.nombre, "huella": huella_a},
            "mazoB": {"id": mazo_b.id, "nombre": mazo_b.nombre, "huella": huella_b},
        }
        f.write(json.dumps(cabecera, ensure_ascii=False) + "\n")
        for k in range(n):
            eventos_a: list[dict[str, Any]] = []
            eventos_b: list[dict[str, Any]] = []
            partida = Partida(
                (mazo_a.cartas, mazo_b.cartas),
                (GrabadorDecisiones(Heuristico(seed * 100003 + 2 * k), eventos_a),
                 GrabadorDecisiones(Heuristico(seed * 100003 + 2 * k + 1), eventos_b)),
                nombres=(mazo_a.nombre, mazo_b.nombre),
                inicial=None,
                seed=seed * 1000003 + k,
            )
            registro = partida.jugar()
            for lado, eventos in enumerate((eventos_a, eventos_b)):
                recompensa = 1.0 if registro.ganador == lado else 0.5 if registro.ganador == -1 else 0.0
                for indice, evento in enumerate(eventos):
                    f.write(json.dumps({
                        "tipo": "decision",
                        "partida": k,
                        "lado": "A" if lado == 0 else "B",
                        "indice": indice,
                        "seed": seed * 1000003 + k,
                        "recompensa": recompensa,
                        **evento,
                    }, ensure_ascii=False) + "\n")
                    decisiones += 1
    return ResultadoRecoleccion(salida, n, decisiones, huella_a, huella_b)
