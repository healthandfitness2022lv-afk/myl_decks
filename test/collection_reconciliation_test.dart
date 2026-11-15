import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/collection_reconciliation.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/inventory.dart';

void main() {
  Deck deck(String id, int count) => Deck(
    id: id,
    ownerId: 'u',
    name: id,
    cards: [DeckCardEntry(cardId: 'c1', name: 'Carta', count: count)],
  );

  test('carga rápida reutiliza una única variante existente', () {
    const item = InventoryItem(
      key: 'card:c1',
      cardId: 'c1',
      name: 'Carta',
      total: 3,
      variantTotals: {'foil': 3},
    );
    expect(preferredVariantForQuickAdd(item), 'foil');
    expect(
      preferredVariantForQuickAdd(
        item.copyWith(variantTotals: {'foil': 3, 'normal': 1}),
      ),
      isNull,
    );
  });

  test(
    'disponibilidad no cuenta reservas ni copias sin identificar para venta',
    () {
      const item = InventoryItem(
        key: 'card:c1',
        cardId: 'c1',
        name: 'Carta',
        total: 6,
        allocations: {'deck-a': 1},
        variantTotals: {'foil': 3},
        variantAllocations: {
          'foil': {'deck-a': 1},
        },
        reservations: {
          'listing': InventoryReservation(
            folderId: 'f',
            listingId: 'listing',
            variantId: 'foil',
            quantity: 1,
          ),
        },
      );
      final availability = CollectionAvailability.fromItem(item);
      expect(availability.free, 4);
      expect(availability.unidentifiedFree, 3);
      expect(availability.freeByVariant['foil'], 1);
      expect(availability.sellable, 1);
    },
  );

  test('asigna automáticamente cuando existe un solo mazo candidato', () {
    final proposal = buildDeckReconciliation(
      inventory: const [
        InventoryItem(key: 'card:c1', cardId: 'c1', name: 'Carta', total: 2),
      ],
      decks: [deck('deck-a', 2)],
    );
    expect(proposal.conflicts, isEmpty);
    expect(proposal.automaticAllocations['card:c1'], {'deck-a': 2});
  });

  test('consulta cuando dos mazos compiten por las mismas copias', () {
    final proposal = buildDeckReconciliation(
      inventory: const [
        InventoryItem(key: 'card:c1', cardId: 'c1', name: 'Carta', total: 2),
      ],
      decks: [deck('deck-a', 2), deck('deck-b', 2)],
    );
    expect(proposal.conflicts, hasLength(1));
    expect(proposal.conflicts.single.available, 2);
    expect(proposal.conflicts.single.requestedByDeck, {
      'deck-a': 2,
      'deck-b': 2,
    });
    expect(proposal.automaticAllocations['card:c1'], isEmpty);
  });

  test('conserva ubicaciones existentes antes de proponer un conflicto', () {
    final proposal = buildDeckReconciliation(
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 3,
          allocations: {'deck-a': 1},
        ),
      ],
      decks: [deck('deck-a', 2), deck('deck-b', 2)],
    );
    expect(proposal.automaticAllocations['card:c1'], {'deck-a': 1});
    expect(proposal.conflicts.single.available, 2);
    expect(proposal.conflicts.single.requestedByDeck, {
      'deck-a': 1,
      'deck-b': 2,
    });
  });

  test('detecta publicación que impide completar un mazo', () {
    final proposal = buildDeckReconciliation(
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 2,
          reservations: {
            'listing': InventoryReservation(
              folderId: 'f',
              listingId: 'listing',
              variantId: 'foil',
              quantity: 1,
            ),
          },
        ),
      ],
      decks: [deck('deck-a', 2)],
    );
    expect(proposal.saleConflicts, hasLength(1));
    expect(proposal.saleConflicts.single.neededForDecks, 1);
    expect(proposal.requiresReview, isTrue);
  });

  test('las copias libres completan el mazo que aún no estaba asignado', () {
    final shortages = calculateCollectionShortages(
      decks: [deck('Mazo A', 3), deck('Mazo B', 2)],
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 5,
          allocations: {'Mazo A': 3},
        ),
      ],
    );

    expect(shortages, isEmpty);
  });

  test('copias libres en la colección cubren los faltantes de un mazo', () {
    final shortages = calculateCollectionShortages(
      decks: [deck('Mazo A', 2)],
      inventory: const [
        InventoryItem(key: 'card:c1', cardId: 'c1', name: 'Carta', total: 2),
      ],
    );

    expect(shortages, isEmpty);
  });

  test('muestra solo las copias que faltan físicamente para los mazos', () {
    // Las copias se comparten: con 3, los dos mazos que piden 2 están
    // cubiertos; al que pide 4 le falta 1.
    final shortages = calculateCollectionShortages(
      decks: [deck('Mazo A', 2), deck('Mazo B', 4)],
      inventory: const [
        InventoryItem(
          key: 'card:c1',
          cardId: 'c1',
          name: 'Carta',
          total: 3,
          allocations: {'Mazo A': 2},
        ),
      ],
    );

    expect(shortages, hasLength(1));
    expect(shortages.single.quantity, 1);
    expect(shortages.single.deckName, 'Mazo B');
  });

  test('Full y Racial Libre no generan faltantes de completitud', () {
    final shortages = calculateCollectionShortages(
      decks: [
        deck('Racial edición', 2),
        deck('Racial libre', 4).copyWith(format: DeckFormat.racialLibre),
        deck('Full', 5).copyWith(format: DeckFormat.full),
      ],
      inventory: const [],
    );

    expect(shortages, hasLength(1));
    expect(shortages.single.deckName, 'Racial edición');
    expect(shortages.single.quantity, 2);
  });
}
