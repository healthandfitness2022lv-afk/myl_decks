import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/card_myl.dart';
import '../utils/text_normalize.dart';

/// Servicio para gestionar cartas MyL en Firestore.
/// Colección usada: `cards`
class CardService {
  final FirebaseFirestore _db;

  CardService([FirebaseFirestore? instance])
    : _db = instance ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('cards');

  /// Catálogo completo, leído una sola vez por sesión. Sirve para análisis
  /// (validar listas, estadísticas); las pantallas que editan cartas leen
  /// directo de Firestore.
  static Future<List<CardMyL>>? _catalogo;
  static Future<List<CardMyL>> catalogo() =>
      _catalogo ??= CardService().getAllCards().catchError((Object e) {
        _catalogo = null; // un error no debe quedar guardado
        throw e;
      });

  // -------------------------
  // Upsert: crea o actualiza
  // -------------------------
  /// Crear o reemplazar una carta (upsert).
  Future<void> addCard(CardMyL card) async {
    final docRef = _col.doc(card.id);

    // Partimos del mapa que provea el modelo, pero sobreescribimos y normalizamos
    final Map<String, dynamic> data = Map<String, dynamic>.from(card.toMap());

    // nombre_lower para búsquedas por prefijo (sin tildes, ver text_normalize.dart)
    data['nombre_lower'] = normalizeSearch((card.nombre).toString());

    // Timestamps
    data['updatedAt'] = FieldValue.serverTimestamp();

    final exists = (await docRef.get()).exists;
    if (!exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await docRef.set(data);
    } else {
      await docRef.set(data, SetOptions(merge: true));
    }
  }

  // -------------------------
  // Actualización parcial
  // -------------------------
  /// Actualizar parcialmente una carta.
  Future<void> updateCard(String id, Map<String, dynamic> patch) async {
    final docRef = _col.doc(id);
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(patch);

    // Si se modifica el nombre, actualizamos nombre_lower también
    if (normalized.containsKey('nombre')) {
      normalized['nombre_lower'] = normalizeSearch(
        (normalized['nombre'] ?? '').toString(),
      );
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
  Future<List<CardMyL>> searchByNamePrefix(
    String query, {
    int limit = 25,
  }) async {
    final q = normalizeSearch(query);
    if (q.isEmpty) return [];
    final snap =
        await _col
            .where('nombre_lower', isGreaterThanOrEqualTo: q)
            .where('nombre_lower', isLessThan: '$q\uf8ff')
            .limit(limit)
            .get();
    return snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList();
  }

  Stream<List<CardMyL>> watchByNamePrefix(String query, {int limit = 25}) {
    final q = normalizeSearch(query);
    if (q.isEmpty) return Stream.value(const []);
    return _col
        .where('nombre_lower', isGreaterThanOrEqualTo: q)
        .where('nombre_lower', isLessThan: '$q\uf8ff')
        .limit(limit)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList(),
        );
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
      final normalized = normalizeSearch(nombre);
      if (data['nombre_lower'] != normalized) {
        batch.update(d.reference, {'nombre_lower': normalized});
        ops++;
        if (ops >= batchSize) {
          await commitIfNeeded();
        }
      }
    }
    await commitIfNeeded();
  }

  // Fallback: búsqueda en memoria si no tienes `nombre_lower`.
  Future<List<CardMyL>> slowSearchByNamePrefix(
    String query, {
    int limit = 25,
  }) async {
    final q = normalizeSearch(query);
    if (q.isEmpty) return [];
    final all = await getAllCards();
    return all
        .where((c) => normalizeSearch(c.nombre).startsWith(q))
        .take(limit)
        .toList();
  }
}
