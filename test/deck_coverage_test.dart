import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/deck_coverage.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/inventory.dart';

void main() {
  Deck deck({bool active = true}) => Deck(
    id: 'deck-a',
    ownerId: 'u',
    name: 'Objetivo',
    assemblyEnabled: active,
    cards: const [DeckCardEntry(cardId: 'c1', name: 'Carta', count: 5)],
  );

  test('cuenta todas tus copias, compartidas con otros mazos', () {
    final coverage = calculateDeckCoverage(
      deck: deck(),
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 5,
          allocations: {'deck-a': 1, 'deck-b': 1},
          reservations: {
            'listing': InventoryReservation(
              folderId: 'f',
              listingId: 'listing',
              variantId: 'v',
              quantity: 1,
            ),
          },
        ),
      ],
    );
    // Las copias se comparten entre mazos: las 5 que tienes cubren este
    // mazo aunque otro mazo o una venta también las usen.
    final card = coverage.cards.single;
    expect(card.assigned, 5);
    expect(card.physicallyMissing, 0);
    expect(card.copies.map((copy) => copy.state), [
      for (var i = 0; i < 5; i++) DeckCopyState.assigned,
    ]);
    expect(coverage.isAssembled, isTrue);
  });

  test('ignora variantes para cubrir la configuración', () {
    final coverage = calculateDeckCoverage(
      deck: deck(),
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 5,
          allocations: {'deck-a': 5},
          variantTotals: {'foil': 2, 'base': 3},
          variantAllocations: {
            'foil': {'deck-a': 2},
            'base': {'deck-a': 3},
          },
        ),
      ],
    );
    expect(coverage.isAssembled, isTrue);
    expect(coverage.assigned, 5);
  });

  test('nunca pide identificar la versión de una copia', () {
    final coverage = calculateDeckCoverage(
      deck: deck(),
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 3,
          allocations: {'deck-a': 3},
          variantTotals: {'foil': 1},
          variantAllocations: {
            'foil': {'deck-a': 1},
          },
        ),
      ],
    );

    expect(
      coverage.cards.single.copies.where(
        (copy) => copy.needsVariantIdentification,
      ),
      isEmpty,
    );
    // Tienes 3 de las 5: faltan 2.
    expect(coverage.cards.single.physicallyMissing, 2);
  });

  test('sin copias el mazo queda incompleto', () {
    final coverage = calculateDeckCoverage(
      deck: deck(active: false),
      inventory: const [],
    );
    expect(coverage.stateLabel, 'Incompleto');
    expect(coverage.isAssembled, isFalse);
  });
}
