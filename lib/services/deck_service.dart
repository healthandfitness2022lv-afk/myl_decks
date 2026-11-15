import 'package:cloud_firestore/cloud_firestore.dart';
import '/models/deck.dart';
import 'inventory_service.dart';

class DeckService {
  final String uid;

  DeckService(this.uid);

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('decks');

  Future<void> _ensureInventory() async {
    await InventoryService(uid).migrateFromDecksIfNeeded(await listMine());
  }

  Stream<List<Deck>> watchMyDecks() {
    return _col
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (qs) =>
              qs.docs
                  .map(
                    (d) => Deck.fromFirestore(
                      d.id,
                      d.data(),
                    ).copyWith(ownerId: uid),
                  )
                  .toList(),
        );
  }

  Future<int> countDecks() async {
    final agg = await _col.count().get();
    return agg.count ?? 0;
  }

  Future<String> create(String name) async {
    final ref = _col.doc();
    await ref.set({
      'schemaVersion': 2,
      'assemblyEnabled': true,
      'ownerId': uid,
      'name': name,
      'isRacial': false,
      'race': null,
      'edition': null,
      'coverUrl': null,
      'coverCardId': null,
      'cards': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'games': 0,
      'wins': 0,
      'losses': 0,
      'winsBy20': 0,
      'winsBy21': 0,
      'lossesBy02': 0,
      'lossesBy12': 0,
      'lastMatchAt': null,
    });
    return ref.id;
  }

  Future<void> save(
    Deck deck, {
    Map<String, String?> conflictSelections = const {},
  }) async {
    final inventory = InventoryService(uid);
    const releaseSale = '__release_sale__';
    final releases =
        conflictSelections.entries
            .where(
              (entry) =>
                  entry.key.startsWith('sale:') && entry.value == releaseSale,
            )
            .map((entry) => entry.key.substring('sale:'.length))
            .toSet();
    if (releases.isNotEmpty) {
      await inventory.releaseMarketplaceReservations(releases);
    }
    if (!deck.isUnified && !deck.isTarget) await _ensureInventory();
    await inventory.saveDeckProjection(
      deck.copyWith(schemaVersion: deck.isUnified ? 2 : deck.schemaVersion),
      conflictSelections: Map.fromEntries(
        conflictSelections.entries.where((entry) => entry.value != releaseSale),
      ),
    );
  }

  Future<Deck?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Deck.fromFirestore(doc.id, doc.data()!).copyWith(ownerId: uid);
  }

  Future<List<Deck>> listMine() async {
    final qs = await _col.orderBy('updatedAt', descending: true).get();
    return qs.docs
        .map((d) => Deck.fromFirestore(d.id, d.data()).copyWith(ownerId: uid))
        .toList();
  }

  Future<void> delete(String id) async {
    final deck = await getById(id);
    if (deck == null) return;
    if (!deck.isUnified && !deck.isTarget) await _ensureInventory();
    await InventoryService(uid).deleteDeck(deck);
  }
}
