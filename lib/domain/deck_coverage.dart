import '../models/deck.dart';
import '../models/inventory.dart';
import 'deck_stock_groups.dart';
import 'inventory_planner.dart';

enum DeckCopyState { assigned, free, inOtherDeck, reservedForSale, missing }

class DeckCopyCoverage {
  final DeckCardEntry card;
  final int copyNumber;
  final DeckCopyState state;
  final String? variantId;

  const DeckCopyCoverage({
    required this.card,
    required this.copyNumber,
    required this.state,
    this.variantId,
  });

  /// La versión de cada copia ya no se registra por mazo: nunca se pide
  /// identificarla.
  bool get needsVariantIdentification => false;
}

class DeckCardCoverage {
  final DeckCardEntry card;
  final int required;
  final int assigned;
  final int free;
  final int inOtherDecks;
  final int reservedForSale;
  final int physicallyMissing;
  final List<DeckCopyCoverage> copies;

  const DeckCardCoverage({
    required this.card,
    required this.required,
    required this.assigned,
    required this.free,
    required this.inOtherDecks,
    required this.reservedForSale,
    required this.physicallyMissing,
    required this.copies,
  });

  int get unavailable => (required - assigned - free).clamp(0, required);
}

class DeckCoverage {
  final Deck deck;
  final List<DeckCardCoverage> cards;

  const DeckCoverage({required this.deck, required this.cards});

  int get required => cards.fold(0, (sum, item) => sum + item.required);
  int get assigned => cards.fold(0, (sum, item) => sum + item.assigned);
  int get physicallyMissing =>
      cards.fold(0, (sum, item) => sum + item.physicallyMissing);
  int get reservedForSale =>
      cards.fold(0, (sum, item) => sum + item.reservedForSale);

  /// Completo = tienes al menos las copias que pide cada carta.
  bool get isAssembled => assigned >= required;
  String get stateLabel => isAssembled ? 'Completo' : 'Incompleto';
}

/// Sanea para lectura las asignaciones legacy que reclaman más copias que el
/// total físico. El orden de los mazos decide qué ubicación se conserva.
List<InventoryItem> inventoryCappedByDeckPriority({
  required Iterable<InventoryItem> inventory,
  required Iterable<Deck> orderedDecks,
}) {
  final targets = buildDeckStockTargets(orderedDecks)..sort((a, b) {
    final aCounts = a.members.any(countsTowardCollectionCompleteness);
    final bCounts = b.members.any(countsTowardCollectionCompleteness);
    if (aCounts == bCounts) return 0;
    return aCounts ? -1 : 1;
  });
  return inventory.map((item) {
    var remaining = (item.total - item.reserved).clamp(0, item.total).toInt();
    final allocations = <String, int>{};
    for (final target in targets) {
      final required = target.cards
          .where((entry) => entryInventoryKey(entry) == item.key)
          .fold<int>(0, (total, entry) => total + entry.count);
      final pooled = item.allocatedTo(target.id);
      final legacy = target.members
          .map((deck) => item.allocatedTo(deck.id))
          .fold<int>(0, (largest, value) => value > largest ? value : largest);
      final claimed = (pooled > 0 ? pooled : legacy).clamp(0, required).toInt();
      final accepted = claimed.clamp(0, remaining).toInt();
      if (accepted > 0) allocations[target.id] = accepted;
      remaining -= accepted;
    }
    return item.copyWith(allocations: allocations);
  }).toList();
}

/// Calcula si puedes completar [deck] con tu colección. Las copias se
/// comparten entre mazos: cada mazo se compara contra el total de copias
/// que tienes de cada carta, sin importar la versión ni otros mazos.
DeckCoverage calculateDeckCoverage({
  required Deck deck,
  required Iterable<InventoryItem> inventory,
}) {
  final items = {for (final item in inventory) item.key: item};
  final grouped = <String, DeckCardEntry>{};
  for (final entry in deck.cards.where((entry) => entry.count > 0)) {
    final key = entryInventoryKey(entry);
    final old = grouped[key];
    grouped[key] =
        old == null ? entry : old.copyWith(count: old.count + entry.count);
  }

  final coverage = <DeckCardCoverage>[];
  for (final groupedEntry in grouped.entries) {
    final entry = groupedEntry.value;
    final owned = (items[groupedEntry.key]?.total ?? 0).clamp(0, entry.count);
    coverage.add(
      DeckCardCoverage(
        card: entry,
        required: entry.count,
        assigned: owned,
        free: 0,
        inOtherDecks: 0,
        reservedForSale: 0,
        physicallyMissing: entry.count - owned,
        copies: [
          for (var index = 0; index < entry.count; index++)
            DeckCopyCoverage(
              card: entry,
              copyNumber: index + 1,
              state:
                  index < owned
                      ? DeckCopyState.assigned
                      : DeckCopyState.missing,
            ),
        ],
      ),
    );
  }
  return DeckCoverage(deck: deck, cards: coverage);
}
