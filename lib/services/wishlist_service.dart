import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/collection_reconciliation.dart';
import '../domain/inventory_planner.dart';
import '../models/deck.dart';
import '../models/inventory.dart';

class WishlistService {
  final String uid;
  final FirebaseFirestore db;

  WishlistService(this.uid, [FirebaseFirestore? firestore])
    : db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _wishlist =>
      db.collection('users').doc(uid).collection('wishlist');

  String _docId(String key) => key.replaceAll('/', '_');

  Future<void> addManual(DeckCardEntry card, {int quantity = 1}) async {
    if (quantity <= 0) return;
    final key = entryInventoryKey(card);
    final ref = _wishlist.doc(_docId(key));
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final manual = (data['manualQty'] as num?)?.toInt() ?? 0;
      final shortage = (data['deckShortageQty'] as num?)?.toInt() ?? 0;
      tx.set(ref, {
        'identityKey': key,
        'cardId': card.cardId,
        'name': card.name,
        'edition': card.edicion,
        'type': card.tipo,
        'manualQty': manual + quantity,
        'deckShortageQty': shortage,
        'desiredQty': manual + quantity + shortage,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> setManualQuantity(String documentId, int quantity) async {
    final ref = _wishlist.doc(documentId);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) return;
      final shortage =
          (snapshot.data()?['deckShortageQty'] as num?)?.toInt() ?? 0;
      if (quantity <= 0 && shortage == 0) {
        tx.delete(ref);
      } else {
        tx.update(ref, {
          'manualQty': quantity.clamp(0, 9999),
          'desiredQty': quantity.clamp(0, 9999) + shortage,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Recalcula solo la porción automática. Nunca pisa deseos manuales.
  Future<void> recalculateDeckShortages({
    required List<Deck> decks,
    required List<InventoryItem> inventory,
  }) async {
    final sample = <String, DeckCardEntry>{};
    for (final deck in decks.where(
      (deck) => deck.isUnified && deck.assemblyEnabled,
    )) {
      for (final card in deck.cards) {
        final key = entryInventoryKey(card);
        sample[key] = card;
      }
    }
    final calculated = calculateCollectionShortages(
      decks: decks.where((deck) => deck.isUnified),
      inventory: inventory,
    );
    final shortage = <String, int>{};
    final shortageLocations = <String, List<CollectionShortage>>{};
    for (final entry in calculated) {
      // Copias compartidas: basta con cubrir el mazo que más pide.
      final current = shortage[entry.itemKey] ?? 0;
      if (entry.quantity > current) shortage[entry.itemKey] = entry.quantity;
      shortageLocations
          .putIfAbsent(entry.itemKey, () => <CollectionShortage>[])
          .add(entry);
    }
    final existing = await _wishlist.get();
    final existingByIdentity =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final document in existing.docs) {
      final data = document.data();
      final identity = (data['identityKey'] ?? '').toString();
      if (identity.isNotEmpty) existingByIdentity[identity] = document;
    }
    final identities = {...shortage.keys, ...existingByIdentity.keys};
    final catalogMetadata = <String, Map<String, dynamic>>{};
    await Future.wait(
      sample.values.where((card) => (card.cardId ?? '').isNotEmpty).map((
        card,
      ) async {
        final id = card.cardId!;
        if (catalogMetadata.containsKey(id)) return;
        final snapshot = await db.collection('cards').doc(id).get();
        catalogMetadata[id] = snapshot.data() ?? const {};
      }),
    );
    final batch = db.batch();
    for (final identity in identities) {
      final document = existingByIdentity[identity];
      final data = document?.data() ?? const <String, dynamic>{};
      final manual = (data['manualQty'] as num?)?.toInt() ?? 0;
      final automatic = shortage[identity] ?? 0;
      final ref = document?.reference ?? _wishlist.doc(_docId(identity));
      if (manual == 0 && automatic == 0) {
        if (document != null) batch.delete(ref);
        continue;
      }
      final card = sample[identity];
      final metadata = catalogMetadata[card?.cardId] ?? const {};
      final locations =
          shortageLocations[identity] ?? const <CollectionShortage>[];
      final identityDeckIds = locations.map((entry) => entry.deckId).toSet();
      final identityDeckNames =
          locations.map((entry) => entry.deckName).toSet();
      batch.set(ref, {
        'identityKey': identity,
        if (card != null) 'cardId': card.cardId,
        if (card != null) 'name': card.name,
        if (card != null) 'edition': card.edicion,
        if (card != null) 'type': card.tipo,
        'deckIds': identityDeckIds.toList(),
        'deckNames': identityDeckNames.toList(),
        'deckShortages': [
          for (final location in locations)
            {
              'deckId': location.deckId,
              'deckOwnerId': location.deckOwnerId,
              'deckName': location.deckName,
              'deckEdition': location.deckEdition,
              'deckRace': location.deckRace,
              'quantity': location.quantity,
            },
        ],
        if ((metadata['officialImageUrl'] ?? '').toString().isNotEmpty)
          'imageUrl': metadata['officialImageUrl'],
        'manualQty': manual,
        'deckShortageQty': automatic,
        'desiredQty': manual + automatic,
        'updatedAt': FieldValue.serverTimestamp(),
        if (document == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
