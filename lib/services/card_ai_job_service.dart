import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/app_constants.dart';

/// Puente entre el catálogo y el worker local que lee el cuadro de habilidad.
/// La regla de Firestore también limita esta cola al dueño; esta comprobación
/// evita mostrar o crear solicitudes automáticas desde otras cuentas.
class CardAiJobService {
  static bool get puedeUsar =>
      (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase() ==
      AppConstants.ownerEmail;

  static bool _tieneTexto(Map<String, dynamic> data) {
    for (final campo in ['habilidadTextoIA', 'habilidad']) {
      final texto = '${data[campo] ?? ''}'.trim();
      if (RegExp(r'\p{L}', unicode: true).allMatches(texto).length >= 8) {
        return true;
      }
    }
    return false;
  }

  /// Se llama inmediatamente al asignar una imagen oficial. Si la carta aún
  /// no tiene texto, la lectura queda en cola sin pedir confirmación.
  static Future<void> encolarLecturaAutomatica(String cardId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !puedeUsar) return;

    final card =
        await FirebaseFirestore.instance.collection('cards').doc(cardId).get();
    final data = card.data();
    if (data == null ||
        '${data['officialImageUrl'] ?? ''}'.trim().isEmpty ||
        _tieneTexto(data)) {
      return;
    }

    await FirebaseFirestore.instance.collection('card_ai_jobs').add({
      'ownerUid': user.uid,
      'tipo': 'leer',
      'cardIds': [cardId],
      'automatico': true,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
