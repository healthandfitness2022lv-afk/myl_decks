import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ban_list_entry.dart';
import '../models/card_myl.dart';

class BanListService {
  /// Nombre de la colección Firestore. Racial Edición, Racial Libre y
  /// Formato Libre (full) mantienen listas independientes.
  BanListService({String collection = 'ban_list'})
    : _collectionName = collection;

  factory BanListService.racialLibre() =>
      BanListService(collection: 'ban_list_libre');

  factory BanListService.full() => BanListService(collection: 'ban_list_full');

  factory BanListService.forRoundFormatKey(String? formatKey) {
    final normalized = (formatKey ?? '').trim().toLowerCase();
    if (normalized.contains('libre')) return BanListService.racialLibre();
    if (normalized.contains('full')) return BanListService.full();
    return BanListService();
  }

  final String _collectionName;

  String get collectionName => _collectionName;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collectionName);

  Stream<List<BanListEntry>> watchEntries() {
    return _col.snapshots().map((qs) {
      final items =
          qs.docs
              .map((d) => BanListEntry.fromFirestore(d.id, d.data()))
              .toList();
      items.sort(
        (a, b) => a.cardName.toLowerCase().compareTo(b.cardName.toLowerCase()),
      );
      return items;
    });
  }

  Future<List<BanListEntry>> fetchEntries() async {
    final qs = await _col.get();
    final items =
        qs.docs.map((d) => BanListEntry.fromFirestore(d.id, d.data())).toList();
    items.sort(
      (a, b) => a.cardName.toLowerCase().compareTo(b.cardName.toLowerCase()),
    );
    return items;
  }

  Future<List<Map<String, dynamic>>> fetchSnapshot() async {
    final entries = await fetchEntries();
    return entries
        .map((entry) => entry.toSnapshotMap())
        .toList(growable: false);
  }

  /// Reconstruye los límites guardados en el snapshot inmutable de una fecha.
  /// Se indexa por id y por nombre para conservar compatibilidad con mazos
  /// históricos que no tengan `cardId`.
  static Map<String, int> copyLimitsFromSnapshot(
    List<Map<String, dynamic>> snapshot,
  ) {
    final out = <String, int>{};
    for (final raw in snapshot) {
      final entry = BanListEntry.fromSnapshotMap(raw);
      for (final key in entry.lookupKeys) {
        out[key] = entry.maxCopies.clamp(0, 3);
      }
    }
    return out;
  }

  Future<Map<String, int>> fetchCopyLimitsByKey() async {
    final entries = await fetchEntries();
    final out = <String, int>{};
    for (final entry in entries) {
      for (final key in entry.lookupKeys) {
        out[key] = entry.maxCopies.clamp(0, 3);
      }
    }
    return out;
  }

  Future<Map<String, int>> fetchCopyLimitsByCardId() async {
    final entries = await fetchEntries();
    return {
      for (final entry in entries)
        if (entry.cardId.trim().isNotEmpty)
          normalizeBanListKey(entry.cardId): entry.maxCopies.clamp(0, 3),
    };
  }

  Future<void> saveRestriction({
    required CardMyL card,
    required int maxCopies,
    String? imageUrl,
  }) async {
    if (maxCopies >= 3) {
      await removeRestriction(card.id);
      return;
    }

    await _col.doc(card.id).set({
      'cardId': card.id,
      'cardName': card.nombre,
      'maxCopies': maxCopies.clamp(0, 3),
      'cardType': card.tipo,
      'edition': card.edicion,
      'race': card.raza,
      'imageUrl': imageUrl,
      'soloLibre': card.soloLibre,
      'coste': card.coste,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeRestriction(String cardId) async {
    await _col.doc(cardId).delete();
  }

  /// Refresca cardName/cardType/edition/race/soloLibre en cada entrada de
  /// ban_list contra el doc actual de `cards`. Las entradas se guardan como
  /// snapshot al momento de restringir la carta y no se vuelven a tocar
  /// solas, así que si la carta se completa después (ej. se le carga la
  /// edición) la ban list queda desincronizada hasta correr esto.
  /// Devuelve cuántas entradas se actualizaron.
  Future<int> resyncWithCards() async {
    final entries = await fetchEntries();
    final cardsCol = FirebaseFirestore.instance.collection('cards');
    var updated = 0;
    var batch = FirebaseFirestore.instance.batch();
    var pending = 0;

    for (final entry in entries) {
      if (entry.cardId.trim().isEmpty) continue;
      final doc = await cardsCol.doc(entry.cardId).get();
      final data = doc.data();
      if (data == null) continue;

      final freshName = (data['nombre'] ?? '').toString();
      final freshType = (data['tipo'] ?? '').toString();
      final freshEdition = (data['edicion'] ?? '').toString();
      final freshRace = data['raza']?.toString();
      final freshSoloLibre = (data['soloLibre'] as bool?) ?? false;
      final freshCoste = (data['coste'] as num?)?.toInt();

      final changed =
          freshName != entry.cardName ||
          freshType != (entry.cardType ?? '') ||
          freshEdition != (entry.edition ?? '') ||
          freshRace != entry.race ||
          freshSoloLibre != entry.soloLibre ||
          freshCoste != entry.coste;
      if (!changed) continue;

      batch.set(_col.doc(entry.cardId), {
        'cardName': freshName,
        'cardType': freshType,
        'edition': freshEdition,
        'race': freshRace,
        'soloLibre': freshSoloLibre,
        'coste': freshCoste,
      }, SetOptions(merge: true));
      updated++;
      pending++;
      if (pending >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
    return updated;
  }
}
