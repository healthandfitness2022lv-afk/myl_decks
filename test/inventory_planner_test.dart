import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/inventory_planner.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/inventory.dart';

Deck target(String id, Map<String, int> cards) => Deck(
  id: id,
  ownerId: 'u',
  name: id,
  status: DeckStatus.published,
  cards:
      cards.entries
          .map((e) => DeckCardEntry(cardId: e.key, name: e.key, count: e.value))
          .toList(),
);

void main() {
  test('free stock and allocated stock create minimal moves', () {
    const item = InventoryItem(
      key: 'card:a',
      cardId: 'a',
      name: 'A',
      total: 4,
      allocations: {'source': 2},
    );
    final result = buildInventoryPlan(
      inventory: [item],
      orderedTargets: [
        target('t', {'a': 3}),
      ],
      destinationByTarget: {'t': 'dest'},
    );
    expect(result.shortages, isEmpty);
    expect(result.moves.length, 2);
    expect(result.moves.fold<int>(0, (s, m) => s + m.quantity), 3);
  });

  test('target order owns scarce copies', () {
    const item = InventoryItem(key: 'card:a', cardId: 'a', name: 'A', total: 3);
    final result = buildInventoryPlan(
      inventory: [item],
      orderedTargets: [
        target('first', {'a': 2}),
        target('second', {'a': 2}),
      ],
      destinationByTarget: {'first': 'd1', 'second': 'd2'},
    );
    expect(result.targets.first.isBuildable, isTrue);
    expect(result.targets.last.shortages.single.quantity, 1);
  });

  test('copies already in destination do not move', () {
    const item = InventoryItem(
      key: 'card:a',
      cardId: 'a',
      name: 'A',
      total: 2,
      allocations: {'dest': 2},
    );
    final result = buildInventoryPlan(
      inventory: [item],
      orderedTargets: [
        target('t', {'a': 2}),
      ],
      destinationByTarget: {'t': 'dest'},
    );
    expect(result.targets.single.alreadyBuilt, isTrue);
    expect(result.moves, isEmpty);
  });

  test('surplus leaves destination and can feed another target', () {
    const item = InventoryItem(
      key: 'card:a',
      cardId: 'a',
      name: 'A',
      total: 3,
      allocations: {'d1': 3},
    );
    final result = buildInventoryPlan(
      inventory: [item],
      orderedTargets: [
        target('first', {'a': 1}),
        target('second', {'a': 2}),
      ],
      destinationByTarget: {'first': 'd1', 'second': 'd2'},
    );
    expect(result.shortages, isEmpty);
    expect(result.moves.first.fromDeckId, 'd1');
    expect(result.moves.first.toDeckId, isNull);
    expect(result.moves.first.quantity, 2);
    expect(result.moves.last.toDeckId, 'd2');
    expect(result.moves.last.quantity, 2);
  });

  test('legacy identity is stable and includes edition', () {
    expect(
      inventoryKey(name: 'Águila Solar', edition: 'Helénica'),
      inventoryKey(name: 'aguila solar', edition: 'helenica'),
    );
    expect(
      inventoryKey(name: 'Águila Solar', edition: 'Helénica'),
      isNot(inventoryKey(name: 'Águila Solar', edition: 'Otra')),
    );
  });

  test('variants are informative and interchangeable for planning', () {
    const item = InventoryItem(
      key: 'card:a',
      cardId: 'a',
      name: 'A',
      total: 2,
      variantTotals: {'foil': 1, 'normal': 1},
    );
    final result = buildInventoryPlan(
      inventory: [item],
      orderedTargets: [
        target('t', {'a': 2}),
      ],
      destinationByTarget: {'t': 'dest'},
    );
    expect(result.targets.single.isBuildable, isTrue);
    expect(result.moves.single.quantity, 2);
  });

  test('pausing all decks proposes releases without changing allocations', () {
    const inventory = [
      InventoryItem(
        key: 'card:a',
        cardId: 'a',
        name: 'A',
        total: 2,
        allocations: {'paused': 2},
      ),
    ];
    final result = buildInventoryPlan(
      inventory: inventory,
      orderedTargets: const [],
      destinationByTarget: const {},
      releaseUnselectedDecks: true,
    );
    expect(result.moves, hasLength(1));
    expect(result.moves.single.fromDeckId, 'paused');
    expect(result.moves.single.toDeckId, isNull);
    expect(inventory.single.allocatedTo('paused'), 2);
  });
}
