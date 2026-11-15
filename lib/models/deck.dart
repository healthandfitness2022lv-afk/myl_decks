import 'package:cloud_firestore/cloud_firestore.dart';

enum DeckStatus { draft, published }

// Sentinel usado en copyWith para diferenciar "no pasado" de "explícitamente null".
const _unset = Object();

/// Formato de construcción del mazo.
/// - racial: aliados de una raza + soporte/oros de la misma edición (clásico).
/// - racialLibre: aliados de una raza + soporte/oros de cualquier edición.
///   Las cartas marcadas como "soloLibre" solo pueden usarse en este formato.
/// - full ("Formato Libre"): cualquier carta de cualquier raza/edición, sin
///   restricción. Incluye también las cartas "soloLibre".
enum DeckFormat { racial, racialLibre, full }

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

class DeckCardEntry {
  final String? cardId;
  final String name;
  final int count;
  final int? coste;
  final String? tipo;
  final String? rareza;
  final String? edicion;
  final List<String>? selectedVariants;
  final bool soloLibre;
  final bool unica;

  const DeckCardEntry({
    this.cardId,
    required this.name,
    required this.count,
    this.coste,
    this.tipo,
    this.rareza,
    this.edicion,
    this.selectedVariants,
    this.soloLibre = false,
    this.unica = false,
  });

  DeckCardEntry copyWith({
    String? cardId,
    String? name,
    int? count,
    int? coste,
    String? tipo,
    String? rareza,
    String? edicion,
    List<String>? selectedVariants,
    bool? soloLibre,
    bool? unica,
  }) {
    return DeckCardEntry(
      cardId: cardId ?? this.cardId,
      name: name ?? this.name,
      count: count ?? this.count,
      coste: coste ?? this.coste,
      tipo: tipo ?? this.tipo,
      rareza: rareza ?? this.rareza,
      edicion: edicion ?? this.edicion,
      selectedVariants: selectedVariants ?? this.selectedVariants,
      soloLibre: soloLibre ?? this.soloLibre,
      unica: unica ?? this.unica,
    );
  }

  /// La configuración del mazo no es dueña de la variante física. Este
  /// helper permite limpiar preferencias legacy sin perder datos de carta.
  DeckCardEntry withoutSelectedVariants() => DeckCardEntry(
    cardId: cardId,
    name: name,
    count: count,
    coste: coste,
    tipo: tipo,
    rareza: rareza,
    edicion: edicion,
    soloLibre: soloLibre,
    unica: unica,
  );

  Map<String, dynamic> toMap() => {
    'cardId': cardId,
    'name': name,
    'count': count,
    if (coste != null) 'coste': coste,
    if (tipo != null) 'tipo': tipo,
    if (rareza != null) 'rareza': rareza,
    if (edicion != null) 'edicion': edicion,
    if (selectedVariants != null) 'selectedVariants': selectedVariants,
    if (soloLibre) 'soloLibre': true,
    if (unica) 'unica': true,
  };

  factory DeckCardEntry.fromMap(Map<String, dynamic> m) => DeckCardEntry(
    cardId: m['cardId']?.toString(),
    name: (m['name'] ?? '').toString(),
    count: _safeInt(m['count']),
    coste: m['coste'] != null ? _safeInt(m['coste']) : null,
    tipo: m['tipo']?.toString(),
    rareza: m['rareza']?.toString(),
    edicion: m['edicion']?.toString(),
    selectedVariants:
        m['selectedVariants'] != null
            ? List<String>.from(
              (m['selectedVariants'] as List).map((x) => x.toString()),
            )
            : null,
    soloLibre: (m['soloLibre'] as bool?) ?? false,
    unica: (m['unica'] as bool?) ?? false,
  );
}

class Deck {
  /// Versión 2 usa una sola configuración (`cards`) y el inventario como fuente de
  /// verdad de las copias físicas. Los campos legacy se conservan solo para
  /// poder previsualizar y reanudar la migración.
  final int schemaVersion;
  final bool assemblyEnabled;

  /// Si es true, las copias asignadas a este mazo cuentan como disponibles
  /// para publicar en el marketplace (cartas sueltas o en lote), sin
  /// necesidad de desarmar el mazo primero. Se siguen mostrando como parte
  /// del mazo hasta que efectivamente se vendan.
  final bool sellable;
  final String id;
  final String ownerId;
  final String name;
  final bool isRacial;
  final String? race;
  final String? edition;
  final DeckStatus status;
  final List<DeckCardEntry> cards;
  final List<DeckCardEntry> sideboardCards;
  final List<DeckCardEntry> objectiveCards;
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
  final String? coverUrl;
  final String? coverCardId;
  final String? linkedDeckId;
  final DeckFormat format;

  Deck({
    this.schemaVersion = 2,
    this.assemblyEnabled = true,
    this.sellable = false,
    required this.id,
    required this.ownerId,
    required this.name,
    this.isRacial = false,
    this.race,
    this.edition,
    this.status = DeckStatus.draft,
    this.cards = const [],
    this.sideboardCards = const [],
    this.objectiveCards = const [],
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
    this.coverUrl,
    this.coverCardId,
    this.linkedDeckId,
    this.format = DeckFormat.racial,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  double get winRate => games > 0 ? wins / games : 0.0;

  String get winRateLabel =>
      games > 0 ? '${(winRate * 100).toStringAsFixed(1)}%' : '-';

  bool get isUnified => schemaVersion >= 2;
  bool get isTarget => !isUnified && status == DeckStatus.published;
  bool get hasEmbeddedObjective => objectiveCards.isNotEmpty;

  bool get isRacialLibre => format == DeckFormat.racialLibre;
  bool get isFull => format == DeckFormat.full;

  Deck copyWith({
    int? schemaVersion,
    bool? assemblyEnabled,
    bool? sellable,
    String? id,
    String? ownerId,
    String? name,
    bool? isRacial,
    Object? race = _unset,
    Object? edition = _unset,
    DeckStatus? status,
    List<DeckCardEntry>? cards,
    List<DeckCardEntry>? sideboardCards,
    List<DeckCardEntry>? objectiveCards,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? games,
    int? wins,
    int? losses,
    int? winsBy20,
    int? winsBy21,
    int? lossesBy02,
    int? lossesBy12,
    Object? lastMatchAt = _unset,
    Object? coverUrl = _unset,
    Object? coverCardId = _unset,
    Object? linkedDeckId = _unset,
    DeckFormat? format,
  }) {
    return Deck(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      assemblyEnabled: assemblyEnabled ?? this.assemblyEnabled,
      sellable: sellable ?? this.sellable,
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      isRacial: isRacial ?? this.isRacial,
      race: race == _unset ? this.race : race as String?,
      edition: edition == _unset ? this.edition : edition as String?,
      status: status ?? this.status,
      cards: cards ?? this.cards,
      sideboardCards: sideboardCards ?? this.sideboardCards,
      objectiveCards: objectiveCards ?? this.objectiveCards,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      games: games ?? this.games,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      winsBy20: winsBy20 ?? this.winsBy20,
      winsBy21: winsBy21 ?? this.winsBy21,
      lossesBy02: lossesBy02 ?? this.lossesBy02,
      lossesBy12: lossesBy12 ?? this.lossesBy12,
      lastMatchAt:
          lastMatchAt == _unset ? this.lastMatchAt : lastMatchAt as DateTime?,
      coverUrl: coverUrl == _unset ? this.coverUrl : coverUrl as String?,
      coverCardId:
          coverCardId == _unset ? this.coverCardId : coverCardId as String?,
      linkedDeckId:
          linkedDeckId == _unset ? this.linkedDeckId : linkedDeckId as String?,
      format: format ?? this.format,
    );
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'assemblyEnabled': assemblyEnabled,
    'sellable': sellable,
    'ownerId': ownerId,
    'name': name,
    'isRacial': isRacial,
    'race': race,
    'edition': edition,
    'format': format.name,
    'cards': cards.map((e) => e.toMap()).toList(),
    'sideboardCards': sideboardCards.map((e) => e.toMap()).toList(),
    if (!isUnified) 'status': status.name,
    if (!isUnified)
      'objectiveCards': objectiveCards.map((e) => e.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'games': games,
    'wins': wins,
    'losses': losses,
    'winsBy20': winsBy20,
    'winsBy21': winsBy21,
    'lossesBy02': lossesBy02,
    'lossesBy12': lossesBy12,
    'lastMatchAt': lastMatchAt?.toIso8601String(),
    'coverUrl': coverUrl,
    'coverCardId': coverCardId,
    if (!isUnified) 'linkedDeckId': linkedDeckId,
  };

  static DeckFormat _parseFormat(dynamic raw) {
    if (raw == 'racialLibre') return DeckFormat.racialLibre;
    if (raw == 'full') return DeckFormat.full;
    return DeckFormat.racial;
  }

  factory Deck.fromMap(Map<String, dynamic> m) => Deck(
    schemaVersion:
        _safeInt(m['schemaVersion']) <= 0 ? 1 : _safeInt(m['schemaVersion']),
    assemblyEnabled: (m['assemblyEnabled'] as bool?) ?? true,
    sellable: (m['sellable'] as bool?) ?? false,
    id: (m['id'] ?? '').toString(),
    ownerId: (m['ownerId'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    isRacial: (m['isRacial'] ?? false) == true,
    race: m['race']?.toString(),
    edition: m['edition']?.toString(),
    format: _parseFormat(m['format']),
    status:
        (m['status'] == 'published') ? DeckStatus.published : DeckStatus.draft,
    cards:
        (m['cards'] as List<dynamic>? ?? [])
            .map((x) => DeckCardEntry.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
    sideboardCards:
        (m['sideboardCards'] as List<dynamic>? ?? [])
            .map((x) => DeckCardEntry.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
    objectiveCards:
        (m['objectiveCards'] as List<dynamic>? ?? [])
            .map((x) => DeckCardEntry.fromMap(Map<String, dynamic>.from(x)))
            .toList(),
    createdAt: _toDate(m['createdAt']),
    updatedAt: _toDate(m['updatedAt']),
    games: _safeInt(m['games']),
    wins: _safeInt(m['wins']),
    losses: _safeInt(m['losses']),
    winsBy20: _safeInt(m['winsBy20']),
    winsBy21: _safeInt(m['winsBy21']),
    lossesBy02: _safeInt(m['lossesBy02']),
    lossesBy12: _safeInt(m['lossesBy12']),
    lastMatchAt: _toDateNullable(m['lastMatchAt']),
    coverUrl: m['coverUrl']?.toString(),
    coverCardId: m['coverCardId']?.toString(),
    linkedDeckId: m['linkedDeckId']?.toString(),
  );

  factory Deck.fromFirestore(String id, Map<String, dynamic> m) =>
      Deck.fromMap({...m, 'id': id});
}
