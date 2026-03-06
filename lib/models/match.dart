class Match {
  final String id;
  final String playerA;
  final String deckA;
  final String playerB;
  final String deckB;
  final List<String> results; // ["A", "B", "A"]
  final String winner;
  final DateTime date;

  Match({
    required this.id,
    required this.playerA,
    required this.deckA,
    required this.playerB,
    required this.deckB,
    required this.results,
    required this.winner,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'playerA': playerA,
    'deckA': deckA,
    'playerB': playerB,
    'deckB': deckB,
    'results': results,
    'winner': winner,
    'date': date.toIso8601String(),
  };

  factory Match.fromMap(Map<String, dynamic> map, String id) => Match(
    id: id,
    playerA: map['playerA'],
    deckA: map['deckA'],
    playerB: map['playerB'],
    deckB: map['deckB'],
    results: List<String>.from(map['results'] ?? []),
    winner: map['winner'],
    date: DateTime.parse(map['date']),
  );
}
