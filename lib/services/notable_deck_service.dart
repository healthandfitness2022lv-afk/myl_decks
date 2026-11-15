import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/deck.dart';

/// Biblioteca de listas competitivas: una copia fija del mazo y su contexto.
/// No toca inventario ni las estadísticas personales del mazo de origen.
class NotableDeckService {
  static const prefix = 'notable:';
  final String uid;
  NotableDeckService(this.uid);

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('notable_decks');

  Stream<List<Deck>> watch() => _col.orderBy('updatedAt', descending: true).snapshots().map(
        (qs) => qs.docs.map((d) {
          final data = d.data();
          return Deck.fromFirestore(d.id, data).copyWith(
            id: '$prefix${d.id}',
            ownerId: (data['submittedBy'] ?? '').toString(),
          );
        }).toList(),
      );

  Future<void> publish({
    required Deck deck,
    required String tournament,
    required String result,
    String player = '',
    String notes = '',
  }) async {
    await _col.add({
      ...deck.toMap(),
      'sourceDeckId': deck.id,
      'submittedBy': uid,
      'tournament': tournament.trim(),
      'result': result.trim(),
      'player': player.trim(),
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String prefixedId) =>
      _col.doc(prefixedId.replaceFirst(prefix, '')).delete();
}
