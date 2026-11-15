import 'package:cloud_firestore/cloud_firestore.dart';

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
}

class InventoryItem {
  final String key;
  final String? cardId;
  final String name;
  final String? edition;
  final String? type;
  final int total;
  final Map<String, int> allocations;
  final Map<String, int> variantTotals;
  final Map<String, Map<String, int>> variantAllocations;
  final Map<String, InventoryReservation> reservations;

  const InventoryItem({
    required this.key,
    this.cardId,
    required this.name,
    this.edition,
    this.type,
    required this.total,
    this.allocations = const {},
    this.variantTotals = const {},
    this.variantAllocations = const {},
    this.reservations = const {},
  });

  int get assigned =>
      allocations.values.fold(0, (total, value) => total + value);
  int get reserved => reservations.values.fold(
    0,
    (sum, reservation) => sum + reservation.quantity,
  );
  int get free => total - assigned - reserved;

  /// Copias que no están dentro de ningún mazo. Incluye las que están
  /// publicadas: una publicación es una forma de vender stock suelto, no una
  /// ubicación física distinta.
  int get outsideDecks => (total - assigned).clamp(0, total);
  int variantAssigned(String variantId) =>
      (variantAllocations[variantId] ?? const {}).values.fold(
        0,
        (a, b) => a + b,
      );
  int get variantAssignedTotal => variantAllocations.values.fold(
    0,
    (sum, allocation) => sum + allocation.values.fold(0, (a, b) => a + b),
  );
  int variantReserved(String variantId) => reservations.values
      .where((reservation) => reservation.variantId == variantId)
      .fold(0, (sum, reservation) => sum + reservation.quantity);
  int variantFree(String variantId) {
    final exact =
        (variantTotals[variantId] ?? 0) -
        variantAssigned(variantId) -
        variantReserved(variantId);
    return exact < free ? exact : free;
  }

  int variantOutsideDecks(String variantId) {
    final exact = (variantTotals[variantId] ?? 0) - variantAssigned(variantId);
    return exact.clamp(0, outsideDecks);
  }

  /// Cuánto de [variantId] está asignado a mazos marcados como "vendible"
  /// ([sellableDeckIds]) — esas copias siguen dentro del mazo pero cuentan
  /// como disponibles para publicar en el marketplace sin desarmarlo.
  int variantAllocatedToSellableDecks(
    String variantId,
    Set<String> sellableDeckIds,
  ) {
    if (sellableDeckIds.isEmpty) return 0;
    return (variantAllocations[variantId] ?? const {}).entries
        .where((entry) => sellableDeckIds.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
  }

  /// Cuánto de [variantId] se puede usar para publicar en el marketplace:
  /// lo libre real más lo asignado a mazos vendibles (que no cuenta dos
  /// veces: ya está descontado de [variantFree] por estar "asignado").
  int variantAvailableForSale(String variantId, Set<String> sellableDeckIds) {
    final base = variantFree(variantId);
    final fromSellableDecks = variantAllocatedToSellableDecks(
      variantId,
      sellableDeckIds,
    );
    return (base + fromSellableDecks).clamp(0, variantTotals[variantId] ?? 0);
  }

  int get unidentified =>
      total - variantTotals.values.fold(0, (sum, quantity) => sum + quantity);

  /// Cuánto de las copias "sin variante identificada" está realmente libre
  /// (no asignado a un mazo ni reservado en una publicación). A diferencia
  /// de [variantFree], que mira una variante puntual, esto mira el pool sin
  /// identificar — comparte disponibilidad con [free] a nivel de la carta.
  int get unidentifiedFree {
    final unidentifiedAssigned = (assigned - variantAssignedTotal).clamp(
      0,
      unidentified,
    );
    final unidentifiedReserved = reservations.values
        .where((reservation) => reservation.variantId.trim().isEmpty)
        .fold<int>(0, (total, reservation) => total + reservation.quantity);
    return (unidentified - unidentifiedAssigned - unidentifiedReserved).clamp(
      0,
      free,
    );
  }

  int get unidentifiedOutsideDecks {
    final unidentifiedAssigned = (assigned - variantAssignedTotal).clamp(
      0,
      unidentified,
    );
    return (unidentified - unidentifiedAssigned).clamp(0, outsideDecks);
  }

  /// Disponibilidad de una fila del inventario que puede estar mostrando
  /// una variante declarada fusionada con el pool sin identificar (ver
  /// "variante asumida" en la pantalla de Inventario): si
  /// [includesUnidentified] es true, suma ambas fuentes sin pasarse del
  /// total libre real de la carta.
  int freeForRow({
    required String? variantId,
    bool includesUnidentified = false,
  }) {
    if (variantId == null) return unidentifiedFree;
    final exact = variantFree(variantId);
    if (!includesUnidentified) return exact;
    return (exact + unidentifiedFree).clamp(0, free);
  }

  int outsideDecksForRow({
    required String? variantId,
    bool includesUnidentified = false,
  }) {
    if (variantId == null) return unidentifiedOutsideDecks;
    final exact = variantOutsideDecks(variantId);
    if (!includesUnidentified) return exact;
    return (exact + unidentifiedOutsideDecks).clamp(0, outsideDecks);
  }

  int allocatedTo(String deckId) => allocations[deckId] ?? 0;
  bool get isValid =>
      total >= 0 &&
      allocations.values.every((v) => v >= 0) &&
      variantTotals.values.every((v) => v >= 0) &&
      reservations.values.every((v) => v.quantity > 0) &&
      unidentified >= 0 &&
      free >= 0 &&
      variantAssignedTotal <= assigned &&
      variantAllocations.keys.every(variantTotals.containsKey) &&
      variantTotals.keys.every((id) => variantFree(id) >= 0);

  /// Cuánto de la carta (todas las variantes juntas) está asignado a mazos
  /// marcados como "vendible".
  int allocatedToSellableDecks(Set<String> sellableDeckIds) {
    if (sellableDeckIds.isEmpty) return 0;
    return allocations.entries
        .where((entry) => sellableDeckIds.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
  }

  /// Igual que [isValid], pero permite que `free` sea negativo hasta el
  /// límite exacto de lo que está cubierto por copias asignadas a mazos
  /// vendibles ([sellableDeckIds]) — esas copias siguen "en el mazo" pero
  /// ya están reservadas para venta. El déficit nunca puede superar ese
  /// cupo: sigue detectando cualquier otra inconsistencia real.
  bool isValidAllowingSellableOverlap(Set<String> sellableDeckIds) {
    if (!(total >= 0 &&
        allocations.values.every((v) => v >= 0) &&
        variantTotals.values.every((v) => v >= 0) &&
        reservations.values.every((v) => v.quantity > 0) &&
        unidentified >= 0 &&
        variantAssignedTotal <= assigned &&
        variantAllocations.keys.every(variantTotals.containsKey))) {
      return false;
    }
    final sellableCovered = allocatedToSellableDecks(sellableDeckIds);
    if (free < 0 && -free > sellableCovered) return false;
    for (final variantId in variantTotals.keys) {
      final deficit = -variantFree(variantId);
      if (deficit <= 0) continue;
      final coveredForVariant = variantAllocatedToSellableDecks(
        variantId,
        sellableDeckIds,
      );
      if (deficit > coveredForVariant) return false;
    }
    return true;
  }

  InventoryItem copyWith({
    int? total,
    Map<String, int>? allocations,
    Map<String, int>? variantTotals,
    Map<String, Map<String, int>>? variantAllocations,
    Map<String, InventoryReservation>? reservations,
  }) => InventoryItem(
    key: key,
    cardId: cardId,
    name: name,
    edition: edition,
    type: type,
    total: total ?? this.total,
    allocations: allocations ?? this.allocations,
    variantTotals: variantTotals ?? this.variantTotals,
    variantAllocations: variantAllocations ?? this.variantAllocations,
    reservations: reservations ?? this.reservations,
  );

  Map<String, dynamic> toMap() => {
    'key': key,
    'cardId': cardId,
    'name': name,
    'edition': edition,
    'type': type,
    'total': total,
    'allocations': allocations,
    'variantTotals': variantTotals,
    'variantAllocations': variantAllocations,
    'reservations': reservations.map(
      (key, value) => MapEntry(key, value.toMap()),
    ),
  };

  factory InventoryItem.fromMap(String id, Map<String, dynamic> map) =>
      InventoryItem(
        key: (map['key'] ?? id).toString(),
        cardId: map['cardId']?.toString(),
        name: (map['name'] ?? '').toString(),
        edition: map['edition']?.toString(),
        type: map['type']?.toString(),
        total: _int(map['total']),
        allocations: Map<String, int>.fromEntries(
          (map['allocations'] as Map? ?? const {}).entries.map(
            (e) => MapEntry('${e.key}', _int(e.value)),
          ),
        ),
        variantTotals: Map<String, int>.fromEntries(
          (map['variantTotals'] as Map? ?? const {}).entries.map(
            (e) => MapEntry('${e.key}', _int(e.value)),
          ),
        ),
        variantAllocations: Map<String, Map<String, int>>.fromEntries(
          (map['variantAllocations'] as Map? ?? const {}).entries.map(
            (entry) => MapEntry(
              '${entry.key}',
              Map<String, int>.fromEntries(
                (entry.value as Map? ?? const {}).entries.map(
                  (allocation) =>
                      MapEntry('${allocation.key}', _int(allocation.value)),
                ),
              ),
            ),
          ),
        ),
        reservations: Map<String, InventoryReservation>.fromEntries(
          (map['reservations'] as Map? ?? const {}).entries.map(
            (entry) => MapEntry(
              '${entry.key}',
              InventoryReservation.fromMap(
                Map<String, dynamic>.from(entry.value as Map),
              ),
            ),
          ),
        ),
      );
}

class InventoryReservation {
  final String folderId;
  final String listingId;
  final String variantId;
  final int quantity;

  const InventoryReservation({
    required this.folderId,
    required this.listingId,
    required this.variantId,
    required this.quantity,
  });

  Map<String, dynamic> toMap() => {
    'folderId': folderId,
    'listingId': listingId,
    'variantId': variantId,
    'quantity': quantity,
  };

  factory InventoryReservation.fromMap(Map<String, dynamic> map) =>
      InventoryReservation(
        folderId: (map['folderId'] ?? '').toString(),
        listingId: (map['listingId'] ?? '').toString(),
        variantId: (map['variantId'] ?? '').toString(),
        quantity: _int(map['quantity']),
      );
}

enum TransferPlanStatus {
  draft,
  active,
  readyToReturn,
  returned,
  kept,
  cancelled,
}

enum TransferMoveStatus { pending, applied, returned }

class TransferMove {
  final String id;
  final String cardKey;
  final String cardName;
  final String? fromDeckId;
  final String? toDeckId;
  final int quantity;
  final List<String> variantIds;
  final TransferMoveStatus status;

  const TransferMove({
    required this.id,
    required this.cardKey,
    required this.cardName,
    this.fromDeckId,
    this.toDeckId,
    required this.quantity,
    this.variantIds = const [],
    this.status = TransferMoveStatus.pending,
  });

  TransferMove copyWith({TransferMoveStatus? status}) => TransferMove(
    id: id,
    cardKey: cardKey,
    cardName: cardName,
    fromDeckId: fromDeckId,
    toDeckId: toDeckId,
    quantity: quantity,
    variantIds: variantIds,
    status: status ?? this.status,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cardKey': cardKey,
    'cardName': cardName,
    'fromDeckId': fromDeckId,
    'toDeckId': toDeckId,
    'quantity': quantity,
    'variantIds': variantIds,
    'status': status.name,
  };

  factory TransferMove.fromMap(Map<String, dynamic> map) => TransferMove(
    id: (map['id'] ?? '').toString(),
    cardKey: (map['cardKey'] ?? '').toString(),
    cardName: (map['cardName'] ?? '').toString(),
    fromDeckId: map['fromDeckId']?.toString(),
    toDeckId: map['toDeckId']?.toString(),
    quantity: _int(map['quantity']),
    variantIds: List<String>.from(map['variantIds'] ?? const []),
    status: TransferMoveStatus.values.firstWhere(
      (v) => v.name == map['status'],
      orElse: () => TransferMoveStatus.pending,
    ),
  );
}

class PlanShortage {
  final String targetDeckId;
  final String cardKey;
  final String cardName;
  final int quantity;
  const PlanShortage({
    required this.targetDeckId,
    required this.cardKey,
    required this.cardName,
    required this.quantity,
  });
  Map<String, dynamic> toMap() => {
    'targetDeckId': targetDeckId,
    'cardKey': cardKey,
    'cardName': cardName,
    'quantity': quantity,
  };
  factory PlanShortage.fromMap(Map<String, dynamic> map) => PlanShortage(
    targetDeckId: (map['targetDeckId'] ?? '').toString(),
    cardKey: (map['cardKey'] ?? '').toString(),
    cardName: (map['cardName'] ?? '').toString(),
    quantity: _int(map['quantity']),
  );
}

class TransferPlan {
  final String id;
  final String name;
  final List<String> targetDeckIds;
  final Map<String, String> destinationDeckIds;
  final Map<String, Map<String, int>> initialAllocations;
  final List<TransferMove> moves;
  final List<PlanShortage> shortages;
  final TransferPlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TransferPlan({
    required this.id,
    required this.name,
    required this.targetDeckIds,
    required this.destinationDeckIds,
    required this.initialAllocations,
    required this.moves,
    required this.shortages,
    this.status = TransferPlanStatus.draft,
    required this.createdAt,
    required this.updatedAt,
  });

  int get completedMoves =>
      moves.where((m) => m.status != TransferMoveStatus.pending).length;

  TransferPlan copyWith({
    List<TransferMove>? moves,
    TransferPlanStatus? status,
    DateTime? updatedAt,
  }) => TransferPlan(
    id: id,
    name: name,
    targetDeckIds: targetDeckIds,
    destinationDeckIds: destinationDeckIds,
    initialAllocations: initialAllocations,
    moves: moves ?? this.moves,
    shortages: shortages,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'targetDeckIds': targetDeckIds,
    'destinationDeckIds': destinationDeckIds,
    'initialAllocations': initialAllocations,
    'moves': moves.map((m) => m.toMap()).toList(),
    'shortages': shortages.map((s) => s.toMap()).toList(),
    'status': status.name,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory TransferPlan.fromMap(String id, Map<String, dynamic> map) =>
      TransferPlan(
        id: id,
        name: (map['name'] ?? 'Plan').toString(),
        targetDeckIds: List<String>.from(map['targetDeckIds'] ?? const []),
        destinationDeckIds: Map<String, String>.from(
          map['destinationDeckIds'] ?? const {},
        ),
        initialAllocations: Map<String, Map<String, int>>.fromEntries(
          (map['initialAllocations'] as Map? ?? const {}).entries.map(
            (e) => MapEntry(
              '${e.key}',
              Map<String, int>.fromEntries(
                (e.value as Map).entries.map(
                  (x) => MapEntry('${x.key}', _int(x.value)),
                ),
              ),
            ),
          ),
        ),
        moves:
            (map['moves'] as List? ?? const [])
                .map((e) => TransferMove.fromMap(Map<String, dynamic>.from(e)))
                .toList(),
        shortages:
            (map['shortages'] as List? ?? const [])
                .map((e) => PlanShortage.fromMap(Map<String, dynamic>.from(e)))
                .toList(),
        status: TransferPlanStatus.values.firstWhere(
          (v) => v.name == map['status'],
          orElse: () => TransferPlanStatus.draft,
        ),
        createdAt: _date(map['createdAt']),
        updatedAt: _date(map['updatedAt']),
      );
}
