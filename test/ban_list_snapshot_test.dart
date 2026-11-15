import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/ban_list_entry.dart';
import 'package:myl_decks/services/ban_list_service.dart';

void main() {
  test('Ban List snapshot preserves immutable round restrictions', () {
    const entry = BanListEntry(
      id: 'entry-1',
      cardId: 'card-1',
      cardName: 'Carta de prueba',
      maxCopies: 1,
      cardType: 'Aliado',
      edition: 'Primer Bloque',
      race: 'Dragón',
      soloLibre: true,
      coste: 2,
    );

    final snapshot = entry.toSnapshotMap();

    expect(snapshot['cardId'], 'card-1');
    expect(snapshot['cardName'], 'Carta de prueba');
    expect(snapshot['maxCopies'], 1);
    expect(snapshot['cardType'], 'Aliado');
    expect(snapshot['edition'], 'Primer Bloque');
    expect(snapshot['race'], 'Dragón');
    expect(snapshot['soloLibre'], isTrue);
    expect(snapshot['coste'], 2);
    expect(snapshot.containsKey('updatedAt'), isFalse);
  });

  test('each round format resolves its independent Ban List collection', () {
    expect(
      BanListService.forRoundFormatKey('racial_edicion').collectionName,
      'ban_list',
    );
    expect(
      BanListService.forRoundFormatKey('racial_libre').collectionName,
      'ban_list_libre',
    );
    expect(
      BanListService.forRoundFormatKey('full').collectionName,
      'ban_list_full',
    );
  });

  test('snapshot limits are reconstructed without consulting a live list', () {
    final snapshot = <Map<String, dynamic>>[
      const BanListEntry(
        id: 'full-banned',
        cardId: 'full-banned',
        cardName: 'Carta Full Prohibida',
        maxCopies: 0,
      ).toSnapshotMap(),
      const BanListEntry(
        id: 'full-limited',
        cardId: 'full-limited',
        cardName: 'Carta Full Limitada',
        maxCopies: 2,
      ).toSnapshotMap(),
    ];

    final limits = BanListService.copyLimitsFromSnapshot(snapshot);

    expect(limits['full-banned'], 0);
    expect(limits['carta full prohibida'], 0);
    expect(limits['full-limited'], 2);
    expect(limits['carta full limitada'], 2);
  });
}
