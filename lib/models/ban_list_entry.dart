import 'package:cloud_firestore/cloud_firestore.dart';

String normalizeBanListKey(String value) => value.trim().toLowerCase();

class BanListEntry {
  final String id;
  final String cardId;
  final String cardName;
  final int maxCopies;
  final String? cardType;
  final String? edition;
  final String? race;
  final String? imageUrl;
  final DateTime? updatedAt;
  final bool soloLibre;
  final int? coste;

  const BanListEntry({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.maxCopies,
    this.cardType,
    this.edition,
    this.race,
    this.imageUrl,
    this.updatedAt,
    this.soloLibre = false,
    this.coste,
  });

  bool get isBanned => maxCopies <= 0;

  List<String> get lookupKeys {
    final keys = <String>{};
    if (cardId.trim().isNotEmpty) keys.add(normalizeBanListKey(cardId));
    if (cardName.trim().isNotEmpty) keys.add(normalizeBanListKey(cardName));
    return keys.toList(growable: false);
  }

  String get statusLabel => isBanned ? 'Prohibida' : 'Max $maxCopies';

  /// Grupo a mostrar en la tabla: las cartas soloLibre (ej. sets crossover
  /// como Drácula) no pertenecen a una edición estándar por diseño, así que
  /// no deben caer en "Sin edicion" junto a cartas realmente incompletas.
  String get editionGroupLabel {
    if (edition != null && edition!.trim().isNotEmpty) return edition!;
    if (soloLibre) return 'Racial Libre';
    return 'Sin edicion';
  }

  Map<String, dynamic> toMap() => {
    'cardId': cardId,
    'cardName': cardName,
    'maxCopies': maxCopies,
    'cardType': cardType,
    'edition': edition,
    'race': race,
    'imageUrl': imageUrl,
    'soloLibre': soloLibre,
    'coste': coste,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Representación inmutable para guardar dentro de una fecha. A diferencia
  /// de [toMap], no incorpora timestamps del servidor ni depende después del
  /// documento mutable de la Ban List.
  Map<String, dynamic> toSnapshotMap() => {
    'cardId': cardId,
    'cardName': cardName,
    'maxCopies': maxCopies.clamp(0, 3),
    if (cardType != null) 'cardType': cardType,
    if (edition != null) 'edition': edition,
    if (race != null) 'race': race,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (soloLibre) 'soloLibre': true,
    if (coste != null) 'coste': coste,
  };

  factory BanListEntry.fromFirestore(String id, Map<String, dynamic> map) {
    final rawUpdatedAt = map['updatedAt'];
    DateTime? updatedAt;
    if (rawUpdatedAt is Timestamp) {
      updatedAt = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is String) {
      updatedAt = DateTime.tryParse(rawUpdatedAt);
    }

    return BanListEntry(
      id: id,
      cardId: (map['cardId'] ?? '').toString(),
      cardName: (map['cardName'] ?? '').toString(),
      maxCopies: (map['maxCopies'] as num?)?.toInt() ?? 0,
      cardType: map['cardType']?.toString(),
      edition: map['edition']?.toString(),
      race: map['race']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      updatedAt: updatedAt,
      soloLibre: (map['soloLibre'] as bool?) ?? false,
      coste: (map['coste'] as num?)?.toInt(),
    );
  }

  factory BanListEntry.fromSnapshotMap(Map<String, dynamic> map) {
    return BanListEntry(
      id: (map['cardId'] ?? map['cardName'] ?? '').toString(),
      cardId: (map['cardId'] ?? '').toString(),
      cardName: (map['cardName'] ?? '').toString(),
      maxCopies: ((map['maxCopies'] as num?)?.toInt() ?? 0).clamp(0, 3),
      cardType: map['cardType']?.toString(),
      edition: map['edition']?.toString(),
      race: map['race']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      soloLibre: (map['soloLibre'] as bool?) ?? false,
      coste: (map['coste'] as num?)?.toInt(),
    );
  }
}
