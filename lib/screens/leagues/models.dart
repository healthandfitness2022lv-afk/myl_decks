// lib/screens/leagues/models.dart
import '../../models/deck.dart';

// ── Formato de fecha ───────────────────────────────────────────────────────────

enum RoundFormat {
  racialEdicion,
  racialLibre,
  full;

  String get label {
    switch (this) {
      case RoundFormat.racialEdicion:
        return 'Racial Edición';
      case RoundFormat.racialLibre:
        return 'Racial Libre';
      case RoundFormat.full:
        return 'Formato Libre';
    }
  }

  String get firestoreKey {
    switch (this) {
      case RoundFormat.racialEdicion:
        return 'racial_edicion';
      case RoundFormat.racialLibre:
        return 'racial_libre';
      case RoundFormat.full:
        return 'full';
    }
  }

  static RoundFormat fromKey(String? key) {
    switch (key) {
      case 'racial_libre':
        return RoundFormat.racialLibre;
      case 'full':
        return RoundFormat.full;
      default:
        return RoundFormat.racialEdicion;
    }
  }
}

// ── Jugador ────────────────────────────────────────────────────────────────────

class LeaguePlayer {
  final String id;
  final String name;

  LeaguePlayer({required this.id, required this.name});

  factory LeaguePlayer.fromMap(String id, Map<String, dynamic> m) =>
      LeaguePlayer(id: id, name: (m['name'] as String?) ?? id);

  Map<String, dynamic> toMap() => {'name': name};
}

// ── Duelo de fecha ─────────────────────────────────────────────────────────────

class RoundMatch {
  final String playerAId;
  final String playerAName;
  final String? playerBId; // null = bye
  final String? playerBName;
  List<DeckCardEntry> deckA;
  List<DeckCardEntry> deckB;
  int? scoreA;
  int? scoreB;
  String? winnerId;
  // Id del jugador que ganó el dado (empezó jugando primero). Null = no
  // registrado (duelos históricos o bye).
  String? coinTossWinnerId;
  // Momento real (epoch ms) en que se cargó/editó el resultado de este
  // duelo puntual. Distinto de la fecha de la ronda (round.date), que es
  // cuándo se programó/creó toda la fecha: las fechas se juegan en orden
  // aleatorio, así que cada duelo puede resolverse en un día distinto.
  // Null en duelos históricos cargados antes de que existiera este campo.
  int? resultAt;

  RoundMatch({
    required this.playerAId,
    required this.playerAName,
    this.playerBId,
    this.playerBName,
    List<DeckCardEntry>? deckA,
    List<DeckCardEntry>? deckB,
    this.scoreA,
    this.scoreB,
    this.winnerId,
    this.coinTossWinnerId,
    this.resultAt,
  }) : deckA = deckA ?? [],
       deckB = deckB ?? [];

  factory RoundMatch.fromMap(Map<String, dynamic> m) {
    List<DeckCardEntry> parseCards(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(DeckCardEntry.fromMap)
          .toList();
    }

    return RoundMatch(
      playerAId: (m['playerAId'] as String?) ?? '',
      playerAName: (m['playerAName'] as String?) ?? '',
      playerBId: m['playerBId'] as String?,
      playerBName: m['playerBName'] as String?,
      deckA: parseCards(m['deckA']),
      deckB: parseCards(m['deckB']),
      // Los byes históricos se normalizan a victoria 2-0 aunque se hayan
      // guardado con el marcador antiguo 0-0.
      scoreA:
          m['playerBId'] == null && m['winnerId'] != null
              ? 2
              : m['scoreA'] as int?,
      scoreB: m['scoreB'] as int?,
      winnerId: m['winnerId'] as String?,
      coinTossWinnerId: m['coinTossWinnerId'] as String?,
      resultAt: (m['resultAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'playerAId': playerAId,
    'playerAName': playerAName,
    if (playerBId != null) 'playerBId': playerBId,
    if (playerBName != null) 'playerBName': playerBName,
    'deckA': deckA.map((e) => e.toMap()).toList(),
    'deckB': deckB.map((e) => e.toMap()).toList(),
    if (scoreA != null) 'scoreA': scoreA,
    if (scoreB != null) 'scoreB': scoreB,
    if (winnerId != null) 'winnerId': winnerId,
    if (coinTossWinnerId != null) 'coinTossWinnerId': coinTossWinnerId,
    if (resultAt != null) 'resultAt': resultAt,
  };

  bool get isBye => playerBId == null;
  bool get hasResult => winnerId != null;
  String? get coinTossWinnerName {
    if (coinTossWinnerId == null) return null;
    if (coinTossWinnerId == playerAId) return playerAName;
    if (coinTossWinnerId == playerBId) return playerBName;
    return null;
  }

  int get deckACount => deckA.fold(0, (s, e) => s + e.count);
  int get deckBCount => deckB.fold(0, (s, e) => s + e.count);
}

// ── Acumulado de temporada ─────────────────────────────────────────────────────

class LeagueStanding {
  final LeaguePlayer player;
  int points = 0;
  int matchesPlayed = 0;
  int matchesWon = 0;
  int matchesLost = 0;
  int matchesDraw = 0;
  int gamesWon = 0;
  int gamesLost = 0;

  LeagueStanding({required this.player});

  double get duelWinPct => matchesPlayed > 0 ? matchesWon / matchesPlayed : 0.0;
  double get gameWinPct {
    final total = gamesWon + gamesLost;
    return total > 0 ? gamesWon / total : 0.0;
  }
}
