import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/card_myl.dart';

/// Servicio para gestionar cartas MyL en Firestore.
/// Colección usada: `cards`
class CardService {
  final FirebaseFirestore _db;

  CardService([FirebaseFirestore? instance]) : _db = instance ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('cards');

  // -------------------------
  // Upsert: crea o actualiza
  // -------------------------
  /// Crear o reemplazar una carta (upsert).
  /// Garantiza que arrays como `caracteristicasRaw` y `tags` siempre
  /// se envíen (aunque estén vacíos) evitando que Firestore
  /// conserve valores antiguos al usar merge.
  Future<void> addCard(CardMyL card) async {
    final docRef = _col.doc(card.id);

    // Partimos del mapa que provea el modelo, pero sobreescribimos y normalizamos
    final Map<String, dynamic> data = Map<String, dynamic>.from(card.toMap());

    // nombre_lower para búsquedas por prefijo
    data['nombre_lower'] = (card.nombre).toString().toLowerCase();

    // Asegurar arrays: siempre enviar (aunque vacíos)
    data['caracteristicasRaw'] =
        (card.caracteristicasRaw).map((e) => e.toString()).toList();

    data['tags'] = _normalizeTagsForStorage(card.tags);

    // Timestamps
    data['updatedAt'] = FieldValue.serverTimestamp();

    final exists = (await docRef.get()).exists;
    if (!exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await docRef.set(data);
    } else {
      // Usamos merge: true pero como enviamos siempre las keys críticas,
      // las listas serán reemplazadas por las nuevas (incluso si son vacías).
      await docRef.set(data, SetOptions(merge: true));
    }
  }

  // -------------------------
  // Actualización parcial
  // -------------------------
  /// Actualizar parcialmente una carta.
  /// Si `patch` contiene `caracteristicasRaw` o `tags` las normaliza
  /// para evitar inconsistencias (y para que enviar [] borre la lista).
  Future<void> updateCard(String id, Map<String, dynamic> patch) async {
    final docRef = _col.doc(id);
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(patch);

    // Si se modifica el nombre, actualizamos nombre_lower también
    if (normalized.containsKey('nombre')) {
      normalized['nombre_lower'] = (normalized['nombre'] ?? '').toString().toLowerCase();
    }

    // Normalizar caracteristicasRaw si viene en el patch (incluso si es [])
    if (normalized.containsKey('caracteristicasRaw')) {
      final raw = normalized['caracteristicasRaw'];
      normalized['caracteristicasRaw'] =
          (raw == null) ? <String>[] : List<String>.from((raw as Iterable).map((e) => e.toString()));
    }

    // Normalizar tags si viene en el patch
    if (normalized.containsKey('tags')) {
      normalized['tags'] = _normalizeTagsForStorage(normalized['tags']);
    }

    // Siempre usar set merge para ser tolerante a doc inexistente
    normalized['updatedAt'] = FieldValue.serverTimestamp();
    await docRef.set(normalized, SetOptions(merge: true));
  }

  // -------------------------
  // Eliminación / Lectura
  // -------------------------
  Future<void> deleteCard(String id) async => await _col.doc(id).delete();

  Future<CardMyL?> getCard(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return CardMyL.fromMap(snap.data()!, snap.id);
  }

  Future<List<CardMyL>> getAllCards() async {
    final snap = await _col.get();
    return snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList();
  }

  // -------------------------
  // Búsqueda por prefijo
  // -------------------------
  Future<List<CardMyL>> searchByNamePrefix(String query, {int limit = 25}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final snap = await _col
        .where('nombre_lower', isGreaterThanOrEqualTo: q)
        .where('nombre_lower', isLessThan: '$q\uf8ff')
        .limit(limit)
        .get();
    return snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList();
  }

  Stream<List<CardMyL>> watchByNamePrefix(String query, {int limit = 25}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return Stream.value(const []);
    return _col
        .where('nombre_lower', isGreaterThanOrEqualTo: q)
        .where('nombre_lower', isLessThan: '$q\uf8ff')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList());
  }

  // -------------------------
  // Backfill utilitario
  // -------------------------
  Future<void> backfillNombreLower({int batchSize = 400}) async {
    final snap = await _col.get();
    WriteBatch batch = _db.batch();
    int ops = 0;

    Future<void> commitIfNeeded() async {
      if (ops > 0) {
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }
    }

    for (final d in snap.docs) {
      final data = d.data();
      final nombre = (data['nombre'] ?? '').toString();
      final lower = nombre.toLowerCase();
      if (data['nombre_lower'] != lower) {
        batch.update(d.reference, {'nombre_lower': lower});
        ops++;
        if (ops >= batchSize) {
          await commitIfNeeded();
        }
      }
    }
    await commitIfNeeded();
  }

  // Fallback: búsqueda en memoria si no tienes `nombre_lower`.
  Future<List<CardMyL>> slowSearchByNamePrefix(String query, {int limit = 25}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final all = await getAllCards();
    return all.where((c) => c.nombre.toLowerCase().startsWith(q)).take(limit).toList();
  }

  // -------------------------
  // Helpers privados
  // -------------------------
  /// Normaliza cualquier representación de tags a una lista de maps
  /// apta para almacenar en Firestore. Acepta:
  /// - Set<CardTag>, List<CardTag>
  /// - List<String>, Set<String>
  /// - List<Map<String,dynamic>>
  /// - null -> []
  List<Map<String, dynamic>> _normalizeTagsForStorage(dynamic tags) {
    if (tags == null) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];

    // Si ya viene como Iterable
    if (tags is Iterable) {
      for (final t in tags) {
        final mm = _serializeTagToMap(t);
        out.add(mm);
      }
      return out;
    }

    // Si es único (no iterable) lo serializamos igual
    return <Map<String, dynamic>>[_serializeTagToMap(tags)];
  }

  /// Intenta serializar un tag a Map<String,dynamic>.
  /// Maneja:
  /// - si ya es Map -> lo normaliza
  /// - si tiene toMap() -> lo usa
  /// - si tiene propiedades key/label -> las extrae
  /// - si es String -> {'key': string, 'label': string}
  Map<String, dynamic> _serializeTagToMap(dynamic tag) {
    try {
      if (tag == null) return {'key': '', 'label': ''};

      // Si ya es Map
      if (tag is Map<String, dynamic>) {
        final key = (tag['key'] ?? tag['id'] ?? tag['k'] ?? tag['label'] ?? tag.values.first ?? '').toString();
        final label = (tag['label'] ?? tag['name'] ?? key).toString();
        return {'key': key, 'label': label};
      }

      // Si tiene toMap()
      try {
        final maybe = (tag as dynamic).toMap();
        if (maybe is Map<String, dynamic>) {
          final key = (maybe['key'] ?? maybe['id'] ?? maybe['k'] ?? maybe['label'] ?? maybe.values.first ?? '').toString();
          final label = (maybe['label'] ?? maybe['name'] ?? key).toString();
          return {'key': key, 'label': label};
        }
      } catch (_) {}

      // Si tiene propiedades key/label
      try {
        final key = (tag as dynamic).key ?? (tag as dynamic).id;
        final label = (tag as dynamic).label ?? (tag as dynamic).name ?? key;
        if (key != null) {
          return {'key': key.toString(), 'label': (label ?? key).toString()};
        }
      } catch (_) {}

      // Fallback: string
      final s = tag.toString();
      return {'key': s, 'label': s};
    } catch (_) {
      final s = tag?.toString() ?? '';
      return {'key': s, 'label': s};
    }
  }
}
