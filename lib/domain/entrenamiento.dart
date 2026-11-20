// lib/domain/entrenamiento.dart
//
// Modo Entrenamiento: una escalera de rivales (mazo + nivel de IA) con
// rating, y el rating del jugador que sube o baja con cada partida (Elo).
//
// La escalera la genera el simulador (`simulator/myl_sim/escalera.py`) y la
// publica en `config/escalera_entrenamiento`. El progreso del jugador vive en
// el campo `entrenamiento` de `users/{uid}`.

import 'dart:math' as math;

/// Cuántas partidas dura la fase de colocación (el rating se mueve más).
const partidasDeColocacion = 10;
const kColocacion = 48;
const kNormal = 24;

/// Rivales recientes que no se repiten al proponer el siguiente.
const rivalesSinRepetir = 3;

class RivalEscalera {
  /// Id del mazo y nivel de IA unidos por una barra: `mazo|nivel`.
  final String id;

  /// Id del mazo rival (se juega como `escalera:` + este id).
  final String deck;
  final String nombre;
  final String raza;

  /// Agro, Medio, Control o Combo.
  final String perfil;

  /// Nivel de IA, 1 a 5.
  final int nivel;
  final int rating;

  const RivalEscalera({
    required this.id,
    required this.deck,
    required this.nombre,
    required this.raza,
    required this.perfil,
    required this.nivel,
    required this.rating,
  });

  factory RivalEscalera.fromMap(Map<String, dynamic> m) => RivalEscalera(
    id: (m['id'] ?? '').toString(),
    deck: (m['deck'] ?? '').toString(),
    nombre: (m['nombre'] ?? 'Rival').toString(),
    raza: (m['raza'] ?? '').toString(),
    perfil: (m['perfil'] ?? '').toString(),
    nivel: ((m['nivel'] ?? 1) as num).toInt().clamp(1, 5),
    rating: ((m['rating'] ?? 1000) as num).round(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'deck': deck,
    'nombre': nombre,
    'raza': raza,
    'perfil': perfil,
    'nivel': nivel,
    'rating': rating,
  };
}

class Escalera {
  /// De más fácil a más difícil.
  final List<RivalEscalera> rivales;
  final int ratingInicial;
  final DateTime? creada;

  const Escalera({
    required this.rivales,
    required this.ratingInicial,
    this.creada,
  });

  factory Escalera.fromMap(Map<String, dynamic> m) {
    final rivales =
        (m['rivales'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => RivalEscalera.fromMap(e.cast<String, dynamic>()))
            .where((r) => r.id.isNotEmpty && r.deck.isNotEmpty)
            .toList()
          ..sort((a, b) => a.rating.compareTo(b.rating));
    return Escalera(
      rivales: rivales,
      ratingInicial:
          ((m['ratingInicial'] ??
                      (rivales.isEmpty ? 1000 : rivales.first.rating + 100))
                  as num)
              .round(),
      creada: DateTime.tryParse('${m['creado'] ?? ''}'),
    );
  }

  bool get vacia => rivales.isEmpty;
  int get techo => rivales.isEmpty ? ratingInicial : rivales.last.rating;
  int get piso => rivales.isEmpty ? ratingInicial : rivales.first.rating;
}

/// Una partida de entrenamiento ya contada en el rating.
class PartidaEntrenamiento {
  /// Id del documento de `ai_challenges`.
  final String desafio;
  final String rivalId;
  final String rivalNombre;
  final int rivalRating;
  final int nivel;
  final bool gano;
  final int ratingAntes;
  final int ratingDespues;
  final DateTime fecha;

  const PartidaEntrenamiento({
    required this.desafio,
    required this.rivalId,
    required this.rivalNombre,
    required this.rivalRating,
    required this.nivel,
    required this.gano,
    required this.ratingAntes,
    required this.ratingDespues,
    required this.fecha,
  });

  int get cambio => ratingDespues - ratingAntes;

  factory PartidaEntrenamiento.fromMap(Map<String, dynamic> m) =>
      PartidaEntrenamiento(
        desafio: (m['desafio'] ?? '').toString(),
        rivalId: (m['rivalId'] ?? '').toString(),
        rivalNombre: (m['rivalNombre'] ?? '').toString(),
        rivalRating: ((m['rivalRating'] ?? 0) as num).round(),
        nivel: ((m['nivel'] ?? 1) as num).toInt(),
        gano: m['gano'] == true,
        ratingAntes: ((m['antes'] ?? 0) as num).round(),
        ratingDespues: ((m['despues'] ?? 0) as num).round(),
        fecha: DateTime.fromMillisecondsSinceEpoch(
          ((m['fecha'] ?? 0) as num).toInt(),
        ),
      );

  Map<String, dynamic> toMap() => {
    'desafio': desafio,
    'rivalId': rivalId,
    'rivalNombre': rivalNombre,
    'rivalRating': rivalRating,
    'nivel': nivel,
    'gano': gano,
    'antes': ratingAntes,
    'despues': ratingDespues,
    'fecha': fecha.millisecondsSinceEpoch,
  };
}

/// Progreso del jugador (campo `entrenamiento` de su documento de usuario).
class ProgresoEntrenamiento {
  final int rating;
  final int partidas;
  final int ganadas;
  final int mejorRating;

  /// Últimas partidas, la más reciente primero (máximo [maxHistorial]).
  final List<PartidaEntrenamiento> historial;

  static const maxHistorial = 40;

  const ProgresoEntrenamiento({
    required this.rating,
    this.partidas = 0,
    this.ganadas = 0,
    int? mejorRating,
    this.historial = const [],
  }) : mejorRating = mejorRating ?? rating;

  /// [inicial]: rating de partida si el jugador aún no entrena.
  factory ProgresoEntrenamiento.fromMap(dynamic m, {required int inicial}) {
    if (m is! Map) return ProgresoEntrenamiento(rating: inicial);
    final rating = ((m['rating'] ?? inicial) as num).round();
    return ProgresoEntrenamiento(
      rating: rating,
      partidas: ((m['partidas'] ?? 0) as num).toInt(),
      ganadas: ((m['ganadas'] ?? 0) as num).toInt(),
      mejorRating: ((m['mejor'] ?? rating) as num).round(),
      historial:
          (m['historial'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => PartidaEntrenamiento.fromMap(e.cast<String, dynamic>()))
              .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'rating': rating,
    'partidas': partidas,
    'ganadas': ganadas,
    'mejor': mejorRating,
    'historial': historial.map((p) => p.toMap()).toList(),
  };

  bool get enColocacion => partidas < partidasDeColocacion;
  bool yaContada(String desafio) => historial.any((p) => p.desafio == desafio);

  /// Racha actual de victorias (0 si la última fue derrota).
  int get racha => historial.takeWhile((p) => p.gano).length;

  /// Suma una partida terminada. Si ya estaba contada, no cambia nada.
  ProgresoEntrenamiento conPartida({
    required String desafio,
    required RivalEscalera rival,
    required bool gano,
    required DateTime fecha,
  }) {
    if (yaContada(desafio)) return this;
    final nuevo = nuevoRating(
      rating,
      rival.rating,
      gano: gano,
      partidas: partidas,
    );
    return ProgresoEntrenamiento(
      rating: nuevo,
      partidas: partidas + 1,
      ganadas: ganadas + (gano ? 1 : 0),
      mejorRating: math.max(mejorRating, nuevo),
      historial: [
        PartidaEntrenamiento(
          desafio: desafio,
          rivalId: rival.id,
          rivalNombre: rival.nombre,
          rivalRating: rival.rating,
          nivel: rival.nivel,
          gano: gano,
          ratingAntes: rating,
          ratingDespues: nuevo,
          fecha: fecha,
        ),
        ...historial,
      ].take(maxHistorial).toList(),
    );
  }
}

/// Probabilidad de ganar que el Elo le da al jugador.
double esperado(int jugador, int rival) =>
    1 / (1 + math.pow(10, (rival - jugador) / 400));

int factorK(int partidas) =>
    partidas < partidasDeColocacion ? kColocacion : kNormal;

/// Rating después de una partida. Ganar siempre suma al menos 1 y perder
/// siempre resta al menos 1.
int nuevoRating(
  int rating,
  int rival, {
  required bool gano,
  required int partidas,
}) {
  final delta = factorK(partidas) * ((gano ? 1 : 0) - esperado(rating, rival));
  final entero = gano ? math.max(1, delta.round()) : math.min(-1, delta.round());
  return rating + entero;
}

/// Puntos en juego contra un rival: (si gana, si pierde).
(int, int) puntosEnJuego(int rating, int rival, int partidas) => (
  nuevoRating(rating, rival, gano: true, partidas: partidas) - rating,
  nuevoRating(rating, rival, gano: false, partidas: partidas) - rating,
);

/// El rival que toca: el de rating más cercano al del jugador entre los que
/// no enfrentó en sus últimas partidas. En empate, el más difícil.
RivalEscalera? elegirRival(Escalera escalera, ProgresoEntrenamiento progreso) {
  if (escalera.vacia) return null;
  final recientes = {
    for (final p in progreso.historial.take(rivalesSinRepetir)) p.rivalId,
  };
  var candidatos =
      escalera.rivales.where((r) => !recientes.contains(r.id)).toList();
  if (candidatos.isEmpty) candidatos = escalera.rivales;
  candidatos.sort((a, b) {
    final da = (a.rating - progreso.rating).abs();
    final db = (b.rating - progreso.rating).abs();
    return da != db ? da.compareTo(db) : b.rating.compareTo(a.rating);
  });
  return candidatos.first;
}

/// Alternativas al rival propuesto: uno más fácil y uno más difícil.
List<RivalEscalera> alternativas(
  Escalera escalera,
  ProgresoEntrenamiento progreso,
  RivalEscalera propuesto,
) {
  final masFacil =
      escalera.rivales
          .where((r) => r.rating <= propuesto.rating - 60)
          .lastOrNull;
  final masDificil =
      escalera.rivales
          .where((r) => r.rating >= propuesto.rating + 60)
          .firstOrNull;
  return [if (masFacil != null) masFacil, if (masDificil != null) masDificil];
}

class Rango {
  final String nombre;

  /// Fracción de la escalera desde la que empieza (0–1).
  final double desde;
  const Rango(this.nombre, this.desde);
}

const rangos = [
  Rango('Aprendiz', 0),
  Rango('Escudero', 0.2),
  Rango('Guerrero', 0.4),
  Rango('Campeón', 0.6),
  Rango('Maestro', 0.8),
  Rango('Leyenda', 0.95),
];

/// Avance en la escalera: 0 = rival más fácil, 1 = rival más difícil.
double avanceEnEscalera(Escalera escalera, int rating) {
  final rango = escalera.techo - escalera.piso;
  if (rango <= 0) return 0;
  return ((rating - escalera.piso) / rango).clamp(0.0, 1.0);
}

Rango rangoDe(Escalera escalera, int rating) {
  final a = avanceEnEscalera(escalera, rating);
  return rangos.lastWhere((r) => a >= r.desde);
}
