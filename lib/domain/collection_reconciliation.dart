import '../models/deck.dart';
import '../models/inventory.dart';
import 'deck_stock_groups.dart';
import 'inventory_planner.dart';

/// Para una carga rápida sólo se puede inferir la variante sin preguntar si
/// la carta ya tiene exactamente una variante física declarada.
String? preferredVariantForQuickAdd(InventoryItem? item) {
  final variants =
      item?.variantTotals.entries
          .where((entry) => entry.value > 0)
          .map((entry) => entry.key)
          .toList() ??
      const <String>[];
  return variants.length == 1 ? variants.single : null;
}

/// Vista única de disponibilidad usada por mazos, colección y marketplace.
class CollectionAvailability {
  final String itemKey;
  final int total;
  final int assigned;
  final int reserved;
  final int unidentified;
  final int unidentifiedFree;
  final Map<String, int> freeByVariant;

  const CollectionAvailability({
    required this.itemKey,
    required this.total,
    required this.assigned,
    required this.reserved,
    required this.unidentified,
    required this.unidentifiedFree,
    required this.freeByVariant,
  });

  factory CollectionAvailability.fromItem(InventoryItem item) =>
      CollectionAvailability(
        itemKey: item.key,
        total: item.total,
        assigned: item.assigned,
        reserved: item.reserved,
        unidentified: item.unidentified,
        unidentifiedFree: item.unidentifiedFree,
        freeByVariant: {
          for (final id in item.variantTotals.keys)
            id: item.variantFree(id).clamp(0, item.total),
        },
      );

  int get free => (total - assigned - reserved).clamp(0, total);
  int get identifiedFree => freeByVariant.values.fold(0, (a, b) => a + b);
  int get sellable => identifiedFree.clamp(0, free);
  bool get hasUnidentifiedFree => unidentifiedFree > 0;
}

/// Carta que falta físicamente al comparar la demanda de los mazos activos
/// con la colección completa. Las copias libres sí cubren demanda; las
/// reservas del marketplace no pueden hacerlo mientras sigan reservadas.
class CollectionShortage {
  final String itemKey;
  final String? cardId;
  final String cardName;
  final String? edition;
  final String? type;
  final int quantity;
  final String deckId;
  final String deckOwnerId;
  final String deckName;
  final String deckEdition;
  final String deckRace;

  const CollectionShortage({
    required this.itemKey,
    this.cardId,
    required this.cardName,
    this.edition,
    this.type,
    required this.quantity,
    required this.deckId,
    required this.deckOwnerId,
    required this.deckName,
    required this.deckEdition,
    required this.deckRace,
  });
}

List<CollectionShortage> calculateCollectionShortages({
  required Iterable<Deck> decks,
  required Iterable<InventoryItem> inventory,
}) {
  final items = {for (final item in inventory) item.key: item};
  final targets =
      buildDeckStockTargets(
        decks.where(countsTowardCollectionCompleteness),
      ).where((target) => target.assemblyEnabled).toList();
  final demandByTarget = <String, Map<String, int>>{};
  final samplesByTarget = <String, Map<String, DeckCardEntry>>{};
  final allKeys = <String>{};

  for (final target in targets) {
    final demand = demandByTarget.putIfAbsent(target.id, () => <String, int>{});
    final samples = samplesByTarget.putIfAbsent(
      target.id,
      () => <String, DeckCardEntry>{},
    );
    for (final card in target.cards.where((card) => card.count > 0)) {
      final key = entryInventoryKey(card);
      demand[key] = (demand[key] ?? 0) + card.count;
      samples[key] = card;
      allKeys.add(key);
    }
  }

  final result = <CollectionShortage>[];
  for (final key in allKeys) {
    final item = items[key];
    // Las copias se comparten entre mazos: a cada mazo solo le falta lo
    // que supera el total de copias que tienes.
    final owned = item?.total ?? 0;
    for (final target in targets) {
      final required = demandByTarget[target.id]?[key] ?? 0;
      if (required == 0) continue;
      final missing = (required - owned).clamp(0, required);
      if (missing == 0) continue;
      final sample = samplesByTarget[target.id]![key]!;
      // En una familia vinculada se atribuye el faltante a la configuración
      // que exige el máximo para esta carta. Así la necesidad familiar se
      // muestra una sola vez, pero bajo un mazo real que puede abrirse.
      var representative = target.members.first;
      var representativeDemand = -1;
      for (final member in target.members.where(
        (member) => member.assemblyEnabled,
      )) {
        final memberDemand = member.cards
            .where((entry) => entryInventoryKey(entry) == key)
            .fold<int>(0, (total, entry) => total + entry.count);
        if (memberDemand > representativeDemand) {
          representative = member;
          representativeDemand = memberDemand;
        }
      }
      final deckEdition = switch (representative.format) {
        DeckFormat.racial =>
          (representative.edition ?? '').trim().isEmpty
              ? 'Sin edición'
              : representative.edition!.trim(),
        DeckFormat.racialLibre => 'Racial Libre',
        DeckFormat.full => 'Formato Full',
      };
      final rawRace = (representative.race ?? '').trim();
      final deckRace =
          rawRace.isNotEmpty
              ? rawRace
              : representative.format == DeckFormat.full
              ? 'Full'
              : 'Sin raza';
      result.add(
        CollectionShortage(
          itemKey: key,
          cardId: sample.cardId,
          cardName: sample.name,
          edition: sample.edicion,
          type: sample.tipo,
          quantity: missing,
          deckId: representative.id,
          deckOwnerId: representative.ownerId,
          deckName: representative.name,
          deckEdition: deckEdition,
          deckRace: deckRace,
        ),
      );
    }
  }
  result.sort((a, b) {
    final byDeck = a.deckName.toLowerCase().compareTo(b.deckName.toLowerCase());
    if (byDeck != 0) return byDeck;
    final byQuantity = b.quantity.compareTo(a.quantity);
    if (byQuantity != 0) return byQuantity;
    return a.cardName.toLowerCase().compareTo(b.cardName.toLowerCase());
  });
  return result;
}

class DeckAllocationConflict {
  final String itemKey;
  final String cardName;
  final int available;
  final Map<String, int> requestedByDeck;

  const DeckAllocationConflict({
    required this.itemKey,
    required this.cardName,
    required this.available,
    required this.requestedByDeck,
  });
}

class DeckSaleConflict {
  final String itemKey;
  final String cardName;
  final int reserved;
  final int neededForDecks;

  const DeckSaleConflict({
    required this.itemKey,
    required this.cardName,
    required this.reserved,
    required this.neededForDecks,
  });
}

class DeckReconciliationProposal {
  /// Asignación final inequívoca que puede aplicarse sin consultar.
  final Map<String, Map<String, int>> automaticAllocations;
  final List<DeckAllocationConflict> conflicts;
  final List<DeckSaleConflict> saleConflicts;
  final Map<String, Map<String, int>> shortagesByDeck;

  const DeckReconciliationProposal({
    required this.automaticAllocations,
    required this.conflicts,
    this.saleConflicts = const [],
    required this.shortagesByDeck,
  });

  bool get requiresReview => conflicts.isNotEmpty || saleConflicts.isNotEmpty;
}

class InventoryBatchChange {
  final String cardId;
  final String name;
  final String? edition;
  final String? type;
  final int quantity;
  final String? variantId;

  const InventoryBatchChange({
    required this.cardId,
    required this.name,
    this.edition,
    this.type,
    required this.quantity,
    this.variantId,
  });
}

class ListingBatchFailure {
  final String cardId;
  final String variantId;
  final String message;

  const ListingBatchFailure({
    required this.cardId,
    required this.variantId,
    required this.message,
  });
}

class ListingBatchResult {
  final List<String> successfulListingIds;
  final List<ListingBatchFailure> failures;

  const ListingBatchResult({
    this.successfulListingIds = const [],
    this.failures = const [],
  });

  bool get isComplete => failures.isEmpty;
}

/// Conserva ubicaciones válidas. El stock restante se asigna solo cuando hay
/// un único mazo candidato; si hay varios, produce un conflicto para revisión.
DeckReconciliationProposal buildDeckReconciliation({
  required Iterable<InventoryItem> inventory,
  required Iterable<Deck> decks,
}) {
  final activeDecks =
      physicalDeckProjections(
        decks,
      ).where((deck) => deck.assemblyEnabled).toList();
  final automatic = <String, Map<String, int>>{};
  final conflicts = <DeckAllocationConflict>[];
  final saleConflicts = <DeckSaleConflict>[];
  final shortages = <String, Map<String, int>>{};

  final demandByItem = <String, Map<String, int>>{};
  final names = <String, String>{};
  for (final deck in activeDecks) {
    for (final card in deck.cards.where((card) => card.count > 0)) {
      final key = entryInventoryKey(card);
      names[key] = card.name;
      final byDeck = demandByItem.putIfAbsent(key, () => <String, int>{});
      byDeck[deck.id] = (byDeck[deck.id] ?? 0) + card.count;
    }
  }
  final items = {for (final item in inventory) item.key: item};

  for (final demandEntry in demandByItem.entries) {
    final key = demandEntry.key;
    final item = items[key];
    final totalDemand = demandEntry.value.values.fold<int>(0, (a, b) => a + b);
    final usableWithoutSales = ((item?.total ?? 0) - (item?.reserved ?? 0))
        .clamp(0, item?.total ?? 0);
    if ((item?.reserved ?? 0) > 0 && totalDemand > usableWithoutSales) {
      saleConflicts.add(
        DeckSaleConflict(
          itemKey: key,
          cardName: names[key] ?? item?.name ?? key,
          reserved: item!.reserved,
          neededForDecks: (totalDemand - usableWithoutSales).clamp(
            0,
            item.reserved,
          ),
        ),
      );
    }
    var available = ((item?.total ?? 0) - (item?.reserved ?? 0)).clamp(
      0,
      item?.total ?? 0,
    );
    final finalByDeck = <String, int>{};
    final remainingDemand = <String, int>{};

    // Conservar primero lo que ya está físicamente ubicado.
    for (final demand in demandEntry.value.entries) {
      final kept = (item?.allocatedTo(demand.key) ?? 0)
          .clamp(0, demand.value)
          .clamp(0, available);
      if (kept > 0) finalByDeck[demand.key] = kept;
      available -= kept;
      final missing = demand.value - kept;
      if (missing > 0) remainingDemand[demand.key] = missing;
    }

    if (available > 0 && remainingDemand.length == 1) {
      final only = remainingDemand.entries.single;
      final take = only.value.clamp(0, available);
      if (take > 0) {
        finalByDeck[only.key] = (finalByDeck[only.key] ?? 0) + take;
        remainingDemand[only.key] = only.value - take;
        available -= take;
      }
    } else if (available > 0 && remainingDemand.length > 1) {
      conflicts.add(
        DeckAllocationConflict(
          itemKey: key,
          cardName: names[key] ?? item?.name ?? key,
          available: available,
          requestedByDeck: Map.unmodifiable(remainingDemand),
        ),
      );
    }

    automatic[key] = finalByDeck;
    for (final demand in remainingDemand.entries) {
      if (demand.value <= 0) continue;
      shortages.putIfAbsent(demand.key, () => <String, int>{})[key] =
          demand.value;
    }
  }

  return DeckReconciliationProposal(
    automaticAllocations: automatic,
    conflicts: conflicts,
    saleConflicts: saleConflicts,
    shortagesByDeck: shortages,
  );
}
