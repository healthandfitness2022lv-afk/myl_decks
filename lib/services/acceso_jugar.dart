// lib/services/acceso_jugar.dart
//
// Quién ve la sección «Jugar» (simulador, Desafío IA, Entrenamiento,
// laboratorio y lo que gana según el simulador). Héctor 18-11: «exclusivo
// para quien yo decida, de momento solo yo».
//
// - El dueño de la app (AppConstants.ownerEmail) siempre tiene acceso.
// - Para dar acceso a otro jugador: agregar su uid a la lista `uids` del
//   documento `config/acceso_jugar` (Firestore). Solo un administrador puede
//   escribir `config/` (regla existente); cualquiera puede leerlo, por eso
//   ahí van uids y no correos.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_constants.dart';

class AccesoJugar {
  AccesoJugar._();

  static const documento = 'config/acceso_jugar';

  /// ¿Tiene acceso con estos datos? (lógica pura, para tests).
  static bool permitido({
    required String? uid,
    required String? email,
    Iterable<Object?> uidsHabilitados = const [],
  }) {
    if ((email ?? '').trim().toLowerCase() == AppConstants.ownerEmail) {
      return true;
    }
    if (uid == null || uid.isEmpty) return false;
    return AppConstants.superAdminUids.contains(uid) ||
        uidsHabilitados.any((x) => '$x' == uid);
  }

  /// Acceso del usuario con sesión, al día con `config/acceso_jugar`.
  static Stream<bool> delUsuario() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(false);
    if (permitido(uid: user.uid, email: user.email)) return Stream.value(true);
    return FirebaseFirestore.instance
        .doc(documento)
        .snapshots()
        .map(
          (d) => permitido(
            uid: user.uid,
            email: user.email,
            uidsHabilitados: (d.data()?['uids'] as List?) ?? const [],
          ),
        )
        .handleError((_) => false);
  }
}

/// Muestra `child` solo a quien tiene acceso a «Jugar»; al resto, nada
/// (o `sinAcceso`).
class SoloJugar extends StatelessWidget {
  const SoloJugar({super.key, required this.child, this.sinAcceso});

  final Widget child;
  final Widget? sinAcceso;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: AccesoJugar.delUsuario(),
    builder:
        (context, snap) =>
            snap.data == true
                ? child
                : (sinAcceso ?? const SizedBox.shrink()),
  );
}

/// Pantalla para una ruta de «Jugar» abierta por enlace sin tener acceso.
class JugarNoDisponible extends StatelessWidget {
  const JugarNoDisponible({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Jugar')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Esta sección todavía no está abierta para tu cuenta.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ),
    ),
  );
}

/// Envuelve una ruta de «Jugar»: espera el permiso y, sin acceso, avisa.
class JugarGuard extends StatelessWidget {
  const JugarGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: AccesoJugar.delUsuario(),
    builder: (context, snap) {
      if (!snap.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snap.data! ? child : const JugarNoDisponible();
    },
  );
}
