import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/inventory.dart';

void main() {
  group('InventoryItem marketplace reservations', () {
    test('free stock excludes deck allocations and listing reservations', () {
      const item = InventoryItem(
        key: 'card:a',
        cardId: 'a',
        name: 'Carta A',
        total: 6,
        allocations: {'deck-1': 2},
        variantTotals: {'foil': 4},
        variantAllocations: {
          'foil': {'deck-1': 1},
        },
        reservations: {
          'listing-1': InventoryReservation(
            folderId: 'folder-1',
            listingId: 'listing-1',
            variantId: 'foil',
            quantity: 2,
          ),
        },
      );

      expect(item.assigned, 2);
      expect(item.reserved, 2);
      expect(item.free, 2);
      // Una copia publicada sigue siendo stock suelto del catálogo. Solo
      // deja de serlo cuando se ubica físicamente en un mazo.
      expect(item.outsideDecks, 4);
      expect(item.variantFree('foil'), 1);
      expect(item.variantOutsideDecks('foil'), 3);
      expect(item.isValid, isTrue);
    });

    test('rejects a reservation larger than exact variant stock', () {
      const item = InventoryItem(
        key: 'card:a',
        cardId: 'a',
        name: 'Carta A',
        total: 3,
        variantTotals: {'foil': 1},
        reservations: {
          'listing-1': InventoryReservation(
            folderId: 'folder-1',
            listingId: 'listing-1',
            variantId: 'foil',
            quantity: 2,
          ),
        },
      );

      expect(item.variantFree('foil'), -1);
      expect(item.isValid, isFalse);
    });

    test('round trips reservation and variant allocations', () {
      const original = InventoryItem(
        key: 'card:a',
        cardId: 'a',
        name: 'Carta A',
        total: 4,
        allocations: {'deck-1': 1},
        variantTotals: {'normal': 4},
        variantAllocations: {
          'normal': {'deck-1': 1},
        },
        reservations: {
          'listing-1': InventoryReservation(
            folderId: 'folder-1',
            listingId: 'listing-1',
            variantId: 'normal',
            quantity: 2,
          ),
        },
      );

      final decoded = InventoryItem.fromMap(original.key, original.toMap());
      expect(decoded.variantAllocations, original.variantAllocations);
      expect(decoded.reservations['listing-1']?.quantity, 2);
      expect(decoded.isValid, isTrue);
    });
  });
}
