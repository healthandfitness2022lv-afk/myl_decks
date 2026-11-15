import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/collection_reconciliation.dart';
import 'package:myl_decks/domain/deck_coverage.dart';
import 'package:myl_decks/domain/deck_stock_groups.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/inventory.dart';

void main() {
  Deck racial(
    String id, {
    String race = 'Caballero',
    String edition = 'Espada Sagrada',
    int common = 0,
    int exclusive = 0,
    bool active = true,
  }) => Deck(
    id: id,
    ownerId: 'u',
    name: id,
    format: DeckFormat.racial,
    race: race,
    edition: edition,
    assemblyEnabled: active,
    cards: [
      if (common > 0)
        DeckCardEntry(cardId: 'common', name: 'Común', count: common),
      if (exclusive > 0)
        DeckCardEntry(
          cardId: 'exclusive-$id',
          name: 'Exclusiva $id',
          count: exclusive,
        ),
    ],
  );

  test('misma edición y raza comparten una identidad estable', () {
    final a = racial('a');
    final b = racial('b', race: 'caballero', edition: 'Espada  Sagrada');

    expect(deckStockTargetId(a), deckStockTargetId(b));
    expect(isSharedStockTargetId(deckStockTargetId(a)), isTrue);
  });

  test('la familia toma el máximo por carta y une las exclusivas', () {
    final targets = buildDeckStockTargets([
      racial('a', common: 3, exclusive: 1),
      racial('b', common: 2, exclusive: 2),
    ]);

    expect(targets, hasLength(1));
    final counts = {
      for (final card in targets.single.cards) card.cardId: card.count,
    };
    expect(counts, {'common': 3, 'exclusive-a': 1, 'exclusive-b': 2});
  });

  test('una variante pausada no aporta demanda al pool', () {
    final target =
        buildDeckStockTargets([
          racial('a', common: 2),
          racial('b', common: 3, exclusive: 2, active: false),
        ]).single;

    expect(target.cards, hasLength(1));
    expect(target.cards.single.cardId, 'common');
    expect(target.cards.single.count, 2);
  });

  test('otra raza y los formatos libres mantienen destinos separados', () {
    final a = racial('a');
    final otherRace = racial('b', race: 'Dragón');
    final libre = racial('c').copyWith(format: DeckFormat.racialLibre);
    final full = racial('d').copyWith(format: DeckFormat.full);

    expect({
      deckStockTargetId(a),
      deckStockTargetId(otherRace),
      deckStockTargetId(libre),
      deckStockTargetId(full),
    }, hasLength(4));
  });

  test(
    'Racial Edición tiene prioridad sobre asignaciones de formatos libres',
    () {
      final racialDeck = racial('racial', common: 1);
      final optionalDeck = racial(
        'full',
        common: 1,
      ).copyWith(format: DeckFormat.full, createdAt: DateTime(2020));
      final familyId = deckStockTargetId(racialDeck);
      final capped =
          inventoryCappedByDeckPriority(
            inventory: [
              InventoryItem(
                key: 'card:common',
                cardId: 'common',
                name: 'Común',
                total: 1,
                allocations: {optionalDeck.id: 1, familyId: 1},
              ),
            ],
            orderedDecks: [optionalDeck, racialDeck],
          ).single;

      expect(capped.allocatedTo(familyId), 1);
      expect(capped.allocatedTo(optionalDeck.id), 0);
    },
  );

  test('la cobertura de ambas variantes lee una sola asignación familiar', () {
    final a = racial('a', common: 3);
    final b = racial('b', common: 2);
    final familyId = deckStockTargetId(a);
    final inventory = [
      InventoryItem(
        key: 'card:common',
        cardId: 'common',
        name: 'Común',
        total: 3,
        allocations: {familyId: 3},
      ),
    ];

    expect(
      calculateDeckCoverage(deck: a, inventory: inventory).isAssembled,
      isTrue,
    );
    expect(
      calculateDeckCoverage(deck: b, inventory: inventory).isAssembled,
      isTrue,
    );
  });

  test(
    'una copia en el pool cubre todos los mazos vinculados',
    () {
      final a = racial('a', common: 1);
      final b = racial('b', common: 1);
      final familyId = deckStockTargetId(a);
      final inventory = [
        InventoryItem(
          key: 'card:common',
          cardId: 'common',
          name: 'Común',
          total: 1,
          allocations: {familyId: 1},
          variantTotals: const {'normal': 1},
          variantAllocations: {
            'normal': {familyId: 1},
          },
        ),
      ];

      final coverageA = calculateDeckCoverage(deck: a, inventory: inventory);
      final coverageB = calculateDeckCoverage(deck: b, inventory: inventory);

      // La versión ya no se registra por mazo.
      expect(coverageA.assigned, 1);
      expect(coverageB.assigned, 1);
    },
  );

  test('cada configuración toma las copias que necesita del mismo pool', () {
    const pool = <String?>['normal', 'foil', 'promo'];
    final large = applySharedVariantPoolToDeckCards(
      cards: const [DeckCardEntry(cardId: 'common', name: 'Común', count: 3)],
      itemKey: 'card:common',
      variants: pool,
    );
    final small = applySharedVariantPoolToDeckCards(
      cards: const [DeckCardEntry(cardId: 'common', name: 'Común', count: 2)],
      itemKey: 'card:common',
      variants: pool,
    );

    expect(large.single.selectedVariants, ['normal', 'foil', 'promo']);
    expect(small.single.selectedVariants, ['normal', 'foil']);
    expect(
      small.single.selectedVariants!.every(
        large.single.selectedVariants!.contains,
      ),
      isTrue,
    );
  });

  test('faltantes físicos cuentan una sola vez la demanda máxima familiar', () {
    final a = racial('a', common: 3);
    final b = racial('b', common: 2);
    final shortages = calculateCollectionShortages(
      decks: [a, b],
      inventory: const [
        InventoryItem(
          key: 'card:common',
          cardId: 'common',
          name: 'Común',
          total: 2,
        ),
      ],
    );

    expect(shortages, hasLength(1));
    expect(shortages.single.quantity, 1);
    expect(shortages.single.deckEdition, 'Espada Sagrada');
    expect(shortages.single.deckRace, 'Caballero');
    expect(shortages.single.deckName, 'a');
  });

  test('la conciliación no hace competir variantes de una familia', () {
    final a = racial('a', common: 3);
    final b = racial('b', common: 2);
    final proposal = buildDeckReconciliation(
      inventory: const [
        InventoryItem(
          key: 'card:common',
          cardId: 'common',
          name: 'Común',
          total: 3,
        ),
      ],
      decks: [a, b],
    );

    expect(proposal.conflicts, isEmpty);
    expect(proposal.automaticAllocations['card:common'], {
      deckStockTargetId(a): 3,
    });
  });
}
