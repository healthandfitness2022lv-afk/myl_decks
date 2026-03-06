import 'package:cloud_firestore/cloud_firestore.dart';

enum DeckStatus { draft, published }

// --------------------
// Helpers
// --------------------
int _safeInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime _toDate(dynamic v) {
  if (v == null) return DateTime.now();
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

DateTime? _toDateNullable(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

// --------------------
// Modelo DeckCardEntry
// --------------------
class DeckCardEntry {
  final String? cardId;
  final String name;
  final int count;

  final int? coste;
  final String? tipo;
  final String? rareza;
  final String? edicion;

  const DeckCardEntry({
    this.cardId,
    required this.name,
    required this.count,
    this.coste,
    this.tipo,
    this.rareza,
    this.edicion,
  });

  DeckCardEntry copyWith({
    String? cardId,
    String? name,
    int? count,
    int? coste,
    String? tipo,
    String? rareza,
    String? edicion,
  }) {
    return DeckCardEntry(
      cardId: cardId ?? this.cardId,
      name: name ?? this.name,
      count: count ?? this.count,
      coste: coste ?? this.coste,
      tipo: tipo ?? this.tipo,
      rareza: rareza ?? this.rareza,
      edicion: edicion ?? this.edicion,
    );
  }

  Map<String, dynamic> toMap() => {
        "cardId": cardId,
        "name": name,
        "count": count,
        if (coste != null) "coste": coste,
        if (tipo != null) "tipo": tipo,
        if (rareza != null) "rareza": rareza,
        if (edicion != null) "edicion": edicion,
      };

  factory DeckCardEntry.fromMap(Map<String, dynamic> m) => DeckCardEntry(
        cardId: m["cardId"]?.toString(),
        name: (m["name"] ?? '').toString(),
        count: _safeInt(m["count"]),
        coste: m["coste"] != null ? _safeInt(m["coste"]) : null,
        tipo: m["tipo"]?.toString(),
        rareza: m["rareza"]?.toString(),
        edicion: m["edicion"]?.toString(),
      );
}

// --------------------
// Modelo Deck
// --------------------
class Deck {
  final String id;
  final String ownerId;
  final String name;
  final bool isRacial;
  final String? race;
  final String? edition;
  final DeckStatus status;
  final List<DeckCardEntry> cards;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int games;
  final int wins;
  final int losses;
  final int winsBy20;
  final int winsBy21;
  final int lossesBy02;
  final int lossesBy12;
  final DateTime? lastMatchAt;

  // Oro inicial
  final String? initialGoldCardId;
  final String? initialGoldName;

  // 🔗 Nuevo: id del mazo vinculado (ej: Tengo vs Objetivo)
  final String? linkedDeckId;

  Deck({
    required this.id,
    required this.ownerId,
    required this.name,
    this.isRacial = false,
    this.race,
    this.edition,
    this.status = DeckStatus.draft,
    this.cards = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.games = 0,
    this.wins = 0,
    this.losses = 0,
    this.winsBy20 = 0,
    this.winsBy21 = 0,
    this.lossesBy02 = 0,
    this.lossesBy12 = 0,
    this.lastMatchAt,
    this.initialGoldCardId,
    this.initialGoldName,
    this.linkedDeckId, // 👈 agregado
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // --------------------
  // Getters útiles
  // --------------------
  double get winRate => games > 0 ? wins / games : 0.0;
  String get winRateLabel =>
      games > 0 ? '${(winRate * 100).toStringAsFixed(1)}%' : '—';

  bool get hasInitialGold =>
      (initialGoldCardId != null && initialGoldCardId!.isNotEmpty) ||
      (initialGoldName != null && initialGoldName!.trim().isNotEmpty);

  bool get isTarget => status == DeckStatus.published;

  // --------------------
  // Métodos
  // --------------------
  Deck copyWith({
    String? id,
    String? ownerId,
    String? name,
    bool? isRacial,
    String? race,
    String? edition,
    DeckStatus? status,
    List<DeckCardEntry>? cards,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? games,
    int? wins,
    int? losses,
    int? winsBy20,
    int? winsBy21,
    int? lossesBy02,
    int? lossesBy12,
    DateTime? lastMatchAt,
    String? initialGoldCardId,
    String? initialGoldName,
    String? linkedDeckId, // 👈 agregado
  }) {
    return Deck(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      isRacial: isRacial ?? this.isRacial,
      race: race ?? this.race,
      edition: edition ?? this.edition,
      status: status ?? this.status,
      cards: cards ?? this.cards,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      games: games ?? this.games,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      winsBy20: winsBy20 ?? this.winsBy20,
      winsBy21: winsBy21 ?? this.winsBy21,
      lossesBy02: lossesBy02 ?? this.lossesBy02,
      lossesBy12: lossesBy12 ?? this.lossesBy12,
      lastMatchAt: lastMatchAt ?? this.lastMatchAt,
      initialGoldCardId: initialGoldCardId ?? this.initialGoldCardId,
      initialGoldName: initialGoldName ?? this.initialGoldName,
      linkedDeckId: linkedDeckId ?? this.linkedDeckId, // 👈 agregado
    );
  }

  Map<String, dynamic> toMap() => {
        "id": id,
        "ownerId": ownerId,
        "name": name,
        "isRacial": isRacial,
        "race": race,
        "edition": edition,
        "status": status.name,
        "cards": cards.map((e) => e.toMap()).toList(),
        "createdAt": createdAt.toIso8601String(),
        "updatedAt": updatedAt.toIso8601String(),
        "games": games,
        "wins": wins,
        "losses": losses,
        "winsBy20": winsBy20,
        "winsBy21": winsBy21,
        "lossesBy02": lossesBy02,
        "lossesBy12": lossesBy12,
        "lastMatchAt": lastMatchAt?.toIso8601String(),
        "initialGoldCardId": initialGoldCardId,
        "initialGoldName": initialGoldName,
        "linkedDeckId": linkedDeckId, // 👈 agregado
      };

  factory Deck.fromMap(Map<String, dynamic> m) => Deck(
        id: (m["id"] ?? '').toString(),
        ownerId: (m["ownerId"] ?? '').toString(),
        name: (m["name"] ?? '').toString(),
        isRacial: (m["isRacial"] ?? false) == true,
        race: m["race"]?.toString(),
        edition: m["edition"]?.toString(),
        status: (m["status"] == "published")
            ? DeckStatus.published
            : DeckStatus.draft,
        cards: (m["cards"] as List<dynamic>? ?? [])
            .map((x) => DeckCardEntry.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
        createdAt: _toDate(m["createdAt"]),
        updatedAt: _toDate(m["updatedAt"]),
        games: _safeInt(m["games"]),
        wins: _safeInt(m["wins"]),
        losses: _safeInt(m["losses"]),
        winsBy20: _safeInt(m["winsBy20"]),
        winsBy21: _safeInt(m["winsBy21"]),
        lossesBy02: _safeInt(m["lossesBy02"]),
        lossesBy12: _safeInt(m["lossesBy12"]),
        lastMatchAt: _toDateNullable(m["lastMatchAt"]),
        initialGoldCardId: m["initialGoldCardId"]?.toString(),
        initialGoldName: m["initialGoldName"]?.toString(),
        linkedDeckId: m["linkedDeckId"]?.toString(), // 👈 agregado
      );

  factory Deck.fromFirestore(String id, Map<String, dynamic> m) => Deck(
        id: id,
        ownerId: (m["ownerId"] ?? '').toString(),
        name: (m["name"] ?? '').toString(),
        isRacial: (m["isRacial"] ?? false) == true,
        race: m["race"]?.toString(),
        edition: m["edition"]?.toString(),
        status: (m["status"] == "published")
            ? DeckStatus.published
            : DeckStatus.draft,
        cards: (m["cards"] as List<dynamic>? ?? [])
            .map((x) => DeckCardEntry.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
        createdAt: _toDate(m["createdAt"]),
        updatedAt: _toDate(m["updatedAt"]),
        games: _safeInt(m["games"]),
        wins: _safeInt(m["wins"]),
        losses: _safeInt(m["losses"]),
        winsBy20: _safeInt(m["winsBy20"]),
        winsBy21: _safeInt(m["winsBy21"]),
        lossesBy02: _safeInt(m["lossesBy02"]),
        lossesBy12: _safeInt(m["lossesBy12"]),
        lastMatchAt: _toDateNullable(m["lastMatchAt"]),
        initialGoldCardId: m["initialGoldCardId"]?.toString(),
        initialGoldName: m["initialGoldName"]?.toString(),
        linkedDeckId: m["linkedDeckId"]?.toString(), // 👈 agregado
      );
}
