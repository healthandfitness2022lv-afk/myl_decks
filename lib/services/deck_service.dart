import 'package:cloud_firestore/cloud_firestore.dart';
import '/models/deck.dart';

class DeckService {
  final String uid;
  DeckService(this.uid);

  /// Ahora los mazos viven en: /users/{uid}/decks
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('decks');

  // Stream de mis mazos (ya no necesita where ownerId, pero lo mantenemos en los docs por compat)
  Stream<List<Deck>> watchMyDecks() {
    return _col
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => Deck.fromFirestore(d.id, d.data()).copyWith(ownerId: uid))
            .toList());
  }

  /// Contar mazos del usuario (usa Aggregate Query)
  Future<int> countDecks() async {
    final agg = await _col.count().get();
    return agg.count ?? 0;
  }

  /// Duplicar un mazo (misma subcolección /users/{uid}/decks)
  Future<String?> duplicate(
    String sourceId, {
    String? newName,
    bool resetToDraft = true,
  }) async {
    try {
      // 1) Leer origen (siempre bajo /users/{uid}/decks)
      final src = await _col.doc(sourceId).get();
      if (!src.exists) return null;
      final data = src.data()!;

      // (Opcional) chequeo lógico: el path ya garantiza que es mío
      if ((data['ownerId'] != null) && data['ownerId'] != uid) {
        throw Exception('No autorizado para duplicar este mazo');
      }

      // 2) Nombre
      final originalName = (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : 'Mazo';
      final baseName = (newName ?? 'Copia de $originalName').trim();

      // 3) Sufijo para evitar choques
      final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
      final uniqueName = '$baseName ($suffix)';

      // 4) Payload nuevo
      final payload = <String, dynamic>{
        'ownerId': uid, // compat / analíticas
        'name': uniqueName,
        'isRacial': data['isRacial'] ?? false,
        'race': data['race'],
        'edition': data['edition'],
        'status': resetToDraft
            ? DeckStatus.draft.name
            : (data['status'] as String? ?? DeckStatus.draft.name),
        'cards': List<dynamic>.from(data['cards'] ?? const []),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),

        // (Opcional) inicializa stats a 0 al duplicar
        'games': 0,
        'wins': 0,
        'losses': 0,
        'winsBy20': 0,
        'winsBy21': 0,
        'lossesBy02': 0,
        'lossesBy12': 0,
        'lastMatchAt': null,
      };

      // 5) Crear
      final ref = await _col.add(payload);
      return ref.id;
    } catch (e) {
      // ignore: avoid_print
      print('duplicate() error: $e');
      return null;
    }
  }

  Future<String> create(String name) async {
    final ref = _col.doc();
    await ref.set({
      'ownerId': uid, // compat / analíticas
      'name': name,
      'isRacial': false,
      'race': null,
      'edition': null,
      'status': DeckStatus.draft.name,
      'cards': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),

      // stats base
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

  // Guardar (merge). No tocamos createdAt; actualizamos updatedAt.
  Future<void> save(Deck deck) async {
    final map = deck.toMap()
      ..remove('id')
      ..remove('createdAt')
      ..addAll({
        'ownerId': uid, // compat / analíticas
        'status': deck.status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

    await _col.doc(deck.id).set(map, SetOptions(merge: true));
  }

  Future<Deck?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    // Inyectamos ownerId desde el contexto del service
    return Deck.fromFirestore(doc.id, doc.data()!).copyWith(ownerId: uid);
  }

  Future<List<Deck>> listMine() async {
    final qs = await _col.orderBy('updatedAt', descending: true).get();
    return qs.docs
        .map((d) => Deck.fromFirestore(d.id, d.data()).copyWith(ownerId: uid))
        .toList();
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
