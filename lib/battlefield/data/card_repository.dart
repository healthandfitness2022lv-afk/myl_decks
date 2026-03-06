// lib/battlefield/data/card_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/normalize.dart';

/// Estructura de metadatos devuelta por el repo:
/// Map<cardIdOriginal, ({String? url, String tipo})>
class CardRepository {
  final _db = FirebaseFirestore.instance;

  // ---------- Helpers de extracción ----------

  String? _pickUrl(Map<String, dynamic>? m) {
    if (m == null) return null;
    final url = (m['officialImageUrl'] ??
        m['imageUrl'] ??
        m['officialImage'] ??
        m['officialImg'] ??
        m['img'] ??
        m['url']);
    final s = url?.toString();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  // ⬇️ NUEVO: normaliza ids con sufijos/variantes (p.ej. "ABC-001#alt")
  String _normalizeLookupId(String raw) {
    final s = raw.trim();
    final cut = RegExp(r'[:#\-]').firstMatch(s);
    return (cut != null) ? s.substring(0, cut.start).trim() : s;
  }

  // ⬇️ AMPLÍA pickTipo: chequea más campos y palabras clave
  String _pickTipo(Map<String, dynamic>? m) {
    if (m == null) return '';
    final candidates = [
      m['tipo'],
      m['type'],
      m['cardType'],
      m['categoria'],
      m['category'],
      m['clase'],
      m['supertipo'],
      m['supertype'],
      m['subtipo'],
      m['subtype'],
    ].where((x) => x != null).map((x) => x.toString()).toList();

    // join y normaliza (por si viene "Carta - Oro", etc.)
    final joined = candidates.join(' ').toLowerCase();
    if (joined.contains('oro') || joined.contains('oros')) return 'oro';

    // si no encontramos "oro", usa normalizeTipo normal
    return normalizeTipo(candidates.isNotEmpty ? candidates.first : '');
  }

  // ---------- API pública ----------

  /// Dado un listado de IDs (posiblemente con sufijos), devuelve un mapa con url y tipo.
  /// Hace 3 intentos: por docId, por 'id' (whereIn) y por 'codigo' (whereIn). Maneja bloques de 10.
  Future<Map<String, ({String? url, String tipo})>> fetchCardMetaForIds(
      List<String> ids) async {
    final metaById = <String, ({String? url, String tipo})>{};
    if (ids.isEmpty) return metaById;

    // 1) Intento por docId (prueba original y normalizado)
    for (final original in ids) {
      final norm = _normalizeLookupId(original);
      var found = false;
      for (final tryId in {original, norm}) {
        try {
          final doc = await _db.collection('cards').doc(tryId).get();
          if (doc.exists) {
            final data = doc.data();
            metaById[original] = (url: _pickUrl(data), tipo: _pickTipo(data));
            found = true;
            break;
          }
        } catch (_) {}
      }
      // si no lo encontró por docId, seguirá en las fases 2/3
      if (found) continue;
    }

    // 2) Intento por 'id' (whereIn) usando IDs normalizados
    final unresolved1 = ids.where((id) => !metaById.containsKey(id)).toList();
    final norm1 = unresolved1.map(_normalizeLookupId).toList();
    for (int i = 0; i < norm1.length; i += 10) {
      final chunk = norm1.sublist(i, (i + 10).clamp(0, norm1.length));
      try {
        final q =
            await _db.collection('cards').where('id', whereIn: chunk).get();
        for (final d in q.docs) {
          final m = d.data();
          final baseId = (m['id'] ?? d.id).toString();
          // mapea de vuelta al original que matcheó este baseId
          final idx = chunk.indexOf(baseId);
          if (idx >= 0) {
            final original = unresolved1[i + idx];
            metaById[original] = (url: _pickUrl(m), tipo: _pickTipo(m));
          }
        }
      } catch (_) {}
    }

    // 3) Intento por 'codigo' (whereIn) usando IDs normalizados
    final unresolved2 = ids.where((id) => !metaById.containsKey(id)).toList();
    final norm2 = unresolved2.map(_normalizeLookupId).toList();
    for (int i = 0; i < norm2.length; i += 10) {
      final chunk = norm2.sublist(i, (i + 10).clamp(0, norm2.length));
      try {
        final q =
            await _db.collection('cards').where('codigo', whereIn: chunk).get();
        for (final d in q.docs) {
          final m = d.data();
          final baseId = (m['codigo'] ?? d.id).toString();
          final idx = chunk.indexOf(baseId);
          if (idx >= 0) {
            final original = unresolved2[i + idx];
            metaById[original] = (url: _pickUrl(m), tipo: _pickTipo(m));
          }
        }
      } catch (_) {}
    }

    return metaById;
  }

  /// Resuelve el id de carta por nombre (usa 'nameLower' == nombre en minúsculas).
  Future<String?> resolveCardIdByName(String name) async {
    try {
      final q = await _db
          .collection('cards')
          .where('nameLower', isEqualTo: name.trim().toLowerCase())
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final m = q.docs.first.data();
        final id = (m['id'] ?? m['codigo'] ?? q.docs.first.id).toString();
        return id.isNotEmpty ? id : null;
      }
    } catch (_) {}
    return null;
  }
}
