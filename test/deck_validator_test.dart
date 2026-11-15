import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/validation/deck_validator.dart';
import 'package:myl_decks/models/ban_list_entry.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/services/ban_list_service.dart';

void main() {
  group('validateDeck with ban list', () {
    test('counts main deck and side deck together for copy limits', () {
      final deck = Deck(
        id: 'side-combined',
        ownerId: 'u1',
        name: 'Test',
        cards: const [
          DeckCardEntry(cardId: 'limited', name: 'Limitada', count: 2),
        ],
        sideboardCards: const [
          DeckCardEntry(cardId: 'limited', name: 'Limitada', count: 1),
        ],
      );
      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
        copyLimitsByKey: const {'limited': 2},
      );
      expect(result.okForDraft, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'COPIES_LIMIT'),
        isTrue,
      );
    });

    test('combines legacy entries without cardId with side deck entries', () {
      final deck = Deck(
        id: 'side-legacy',
        ownerId: 'u1',
        name: 'Test',
        cards: const [DeckCardEntry(name: 'Limitada', count: 2)],
        sideboardCards: const [
          DeckCardEntry(cardId: 'limited', name: 'Limitada', count: 1),
        ],
      );
      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
        copyLimitsByKey: const {'limitada': 2},
      );
      expect(
        result.issues.any((issue) => issue.code == 'COPIES_LIMIT'),
        isTrue,
      );
    });

    test('rejects more than ten side deck copies', () {
      final deck = Deck(
        id: 'side-limit',
        ownerId: 'u1',
        name: 'Test',
        sideboardCards: const [
          DeckCardEntry(cardId: 'a', name: 'A', count: 6),
          DeckCardEntry(cardId: 'b', name: 'B', count: 5),
        ],
      );
      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
      );
      expect(result.okForDraft, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'SIDEBOARD_OVER_10'),
        isTrue,
      );
    });

    test('blocks banned cards', () {
      final deck = Deck(
        id: 'd1',
        ownerId: 'u1',
        name: 'Test',
        cards: const [
          DeckCardEntry(cardId: 'card-1', name: 'Carta Prohibida', count: 1),
        ],
      );

      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
        copyLimitsByKey: const {'card-1': 0},
      );

      expect(result.okForDraft, isFalse);
      expect(result.issues.any((issue) => issue.code == 'BANNED_CARD'), isTrue);
    });

    test('honors custom copy limits', () {
      final deck = Deck(
        id: 'd1',
        ownerId: 'u1',
        name: 'Test',
        cards: const [
          DeckCardEntry(cardId: 'card-2', name: 'Carta Limitada', count: 2),
          DeckCardEntry(cardId: 'card-2', name: 'Carta Limitada', count: 1),
        ],
      );

      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
        copyLimitsByKey: const {'card-2': 2},
      );

      expect(result.okForDraft, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'COPIES_LIMIT'),
        isTrue,
      );
    });

    test('limits unique cards to one copy without a ban list entry', () {
      final deck = Deck(
        id: 'd1',
        ownerId: 'u1',
        name: 'Test',
        cards: const [
          DeckCardEntry(
            cardId: 'unique-1',
            name: 'Carta Única',
            count: 2,
            unica: true,
          ),
        ],
      );

      final result = validateDeck(
        deck: deck,
        catalogById: const {},
        catalogByName: const {},
      );

      expect(result.okForDraft, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'COPIES_LIMIT'),
        isTrue,
      );
    });

    test(
      'enforces prohibited and limited cards from a Full round snapshot',
      () {
        final limits = BanListService.copyLimitsFromSnapshot([
          const BanListEntry(
            id: 'full-banned',
            cardId: 'full-banned',
            cardName: 'Full Prohibida',
            maxCopies: 0,
          ).toSnapshotMap(),
          const BanListEntry(
            id: 'full-limited',
            cardId: 'full-limited',
            cardName: 'Full Limitada',
            maxCopies: 2,
          ).toSnapshotMap(),
        ]);
        final deck = Deck(
          id: 'full-deck',
          ownerId: 'admin',
          name: 'Full',
          cards: const [
            DeckCardEntry(
              cardId: 'full-banned',
              name: 'Full Prohibida',
              count: 1,
            ),
            DeckCardEntry(
              cardId: 'full-limited',
              name: 'Full Limitada',
              count: 3,
            ),
          ],
        );

        final result = validateDeck(
          deck: deck,
          catalogById: const {},
          catalogByName: const {},
          copyLimitsByKey: limits,
        );

        expect(
          result.issues.any((issue) => issue.code == 'BANNED_CARD'),
          isTrue,
        );
        expect(
          result.issues.any((issue) => issue.code == 'COPIES_LIMIT'),
          isTrue,
        );
      },
    );
  });
}
