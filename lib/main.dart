// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'firebase_options.dart';
import 'models/current_user.dart'; // crea este archivo según lo sugerido
import 'services/error_log_service.dart';
import 'theme/app_theme.dart';
import 'router.dart';
import 'services/deck_service.dart';
import 'services/inventory_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // URLs limpias en web (/mazo/... en vez de /#/mazo/...).
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Persistencia offline: la app abre al instante con datos cacheados
  // (web incluida) y reduce lecturas de Firestore en cargas repetidas.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Captura errores no manejados en release y los guarda en `app_errors`.
  ErrorLogService.install();

  final currentUser = CurrentUser();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userDocSub;

  // Escuchar cambios de autenticación y poblar currentUser desde Firestore
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    await userDocSub?.cancel();
    try {
      if (user == null) {
        currentUser.clear();
      } else {
        final uid = user.uid;
        userDocSub = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots()
            .listen((docSnap) {
              final data = docSnap.data() ?? const <String, dynamic>{};
              currentUser.update(
                uid_: uid,
                email_: user.email,
                role_: (data['role'] as String?) ?? 'basico',
                displayName_:
                    (data['displayName'] as String?) ??
                    (data['username'] as String?) ??
                    user.displayName,
                photoUrl_: (data['photoUrl'] as String?) ?? user.photoURL,
              );
            });
        try {
          final inventory = InventoryService(uid);
          await inventory.migrateFromDecksIfNeeded(
            await DeckService(uid).listMine(),
          );
        } catch (error, stack) {
          debugPrint('No se pudo conciliar el inventario: $error\n$stack');
        }
      }
    } catch (e, st) {
      // Si algo falla al leer Firestore, al menos limpiamos y mostramos consola.
      // No rompas la app por un doc malformado.
      debugPrint('Error al cargar usuario desde Firestore: $e\n$st');
      currentUser.update(
        uid_: userOrNullUid(user: FirebaseAuth.instance.currentUser),
        email_: FirebaseAuth.instance.currentUser?.email,
        role_: 'basico',
        displayName_: FirebaseAuth.instance.currentUser?.displayName,
        photoUrl_: FirebaseAuth.instance.currentUser?.photoURL,
      );
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CurrentUser>.value(value: currentUser),
      ],
      child: const MyApp(),
    ),
  );
}

String? userOrNullUid({User? user}) => user == null ? null : user.uid;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'MyL Mazos',
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
