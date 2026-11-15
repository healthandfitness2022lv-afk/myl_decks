import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/deck.dart';

void main() {
  test('v2 serializa una configuración sin campos Tengo/Objetivo legacy', () {
    final map =
        Deck(
          id: 'd',
          ownerId: 'u',
          name: 'Mazo',
          objectiveCards: const [DeckCardEntry(name: 'Legacy', count: 1)],
          linkedDeckId: 'old',
          status: DeckStatus.published,
        ).toMap();
    expect(map['schemaVersion'], 2);
    expect(map['assemblyEnabled'], isTrue);
    expect(map.containsKey('status'), isFalse);
    expect(map.containsKey('objectiveCards'), isFalse);
    expect(map.containsKey('linkedDeckId'), isFalse);
  });

  test('documentos anteriores siguen disponibles para vista previa', () {
    final deck = Deck.fromMap({
      'name': 'Viejo',
      'status': 'published',
      'cards': <Map<String, dynamic>>[],
      'objectiveCards': [
        {'name': 'Carta', 'count': 1},
      ],
      'linkedDeckId': 'base',
    });
    expect(deck.schemaVersion, 1);
    expect(deck.isTarget, isTrue);
    expect(deck.objectiveCards, hasLength(1));
    expect(deck.linkedDeckId, 'base');
  });

  test('side deck se serializa y documentos antiguos usan lista vacía', () {
    final deck = Deck(
      id: 'd',
      ownerId: 'u',
      name: 'Con side',
      sideboardCards: const [
        DeckCardEntry(cardId: 'side-1', name: 'Alternativa', count: 2),
      ],
    );
    final restored = Deck.fromMap(deck.toMap());
    expect(restored.sideboardCards, hasLength(1));
    expect(restored.sideboardCards.single.count, 2);

    final legacy = Deck.fromMap({'name': 'Sin side', 'cards': []});
    expect(legacy.sideboardCards, isEmpty);
  });
}
