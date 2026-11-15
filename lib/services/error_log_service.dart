// lib/services/error_log_service.dart
// Reporte ligero de errores de producción a Firestore (colección `app_errors`).
// Sin dependencias externas: suficiente para enterarse de crashes reales.
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ErrorLogService {
  ErrorLogService._();

  static const int _maxPerSession = 20; // evita loops de spam
  static int _reported = 0;
  static final Set<int> _seenHashes = {};

  /// Instala los handlers globales. Llamar una vez desde main().
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      _report(details.exceptionAsString(), details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _report(error.toString(), stack);
      return true; // no relanzar
    };
  }

  static Future<void> _report(String message, StackTrace? stack) async {
    // En debug solo consola; reportamos únicamente builds de release.
    if (kDebugMode) return;
    if (_reported >= _maxPerSession) return;

    // Deduplicar el mismo error repetido en la sesión.
    final hash = message.hashCode ^ (stack?.toString().hashCode ?? 0);
    if (!_seenHashes.add(hash)) return;
    _reported++;

    try {
      await FirebaseFirestore.instance.collection('app_errors').add({
        'message': message.length > 1500 ? message.substring(0, 1500) : message,
        'stack': (stack?.toString() ?? '').split('\n').take(30).join('\n'),
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Nunca dejar que el reporte de un error cause otro error.
    }
  }
}
