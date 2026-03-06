// lib/screens/tournaments/models.dart
class Player {
  final String id;
  final String displayName;
  final String ownerUid;
  final String deckId;
  final String deckName;
  final String race;

  Player({
    required this.id,
    required this.displayName,
    required this.ownerUid,
    required this.deckId,
    required this.deckName,
    required this.race,
  });
}

class PlayerStats {
  final Player player;
  int points = 0;
  int matchesPlayed = 0;
  int matchesWon = 0;
  int matchesLost = 0;
  int gamesWon = 0;
  int gamesLost = 0;

  PlayerStats({required this.player});

  void reset() {
    points = 0;
    matchesPlayed = 0;
    matchesWon = 0;
    matchesLost = 0;
    gamesWon = 0;
    gamesLost = 0;
  }
}

class Pair {
  final Player a;
  final Player? b;
  Pair(this.a, this.b);
}

class MatchResult {
  final Player a;
  final Player? b;
  final int scoreA;
  final int scoreB;
  final String winnerId;

  MatchResult(this.a, this.b, this.scoreA, this.scoreB, this.winnerId);

  String summary() {
    if (b == null) return '${a.deckName} (bye)';
    return '${a.deckName} ${scoreA}-${scoreB} ${b!.deckName} -> winner ${winnerId == a.id ? a.deckName : b!.deckName}';
  }
}
