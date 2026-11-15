import '../models/deck.dart';
import '../utils/text_normalize.dart';

String inventoryKey({String? cardId, required String name, String? edition}) {
  final id = cardId?.trim() ?? '';
  if (id.isNotEmpty) return 'card:$id';
  return 'legacy:${normalizeSearch(name)}|${normalizeSearch(edition ?? '')}';
}

String entryInventoryKey(DeckCardEntry entry) => inventoryKey(
  cardId: entry.cardId,
  name: entry.name,
  edition: entry.edicion,
);
