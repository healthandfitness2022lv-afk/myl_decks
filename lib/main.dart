// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'auth_gate.dart'; // tu AuthGate
import 'models/current_user.dart'; // crea este archivo según lo sugerido

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Instancia compartida del CurrentUser (ChangeNotifier)
  final currentUser = CurrentUser();

  // Escuchar cambios de autenticación y poblar currentUser desde Firestore
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    try {
      if (user == null) {
        // Usuario desconectado -> limpiar estado
        currentUser.update(
          uid_: null,
          email_: null,
          role_: 'basico',
          displayName_: null,
          photoUrl_: null,
        );
      } else {
        // Usuario conectado -> leer doc users/{uid}
        final uid = user.uid;
        final docSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = docSnap.data() ?? {};

        // Extraer campos con tolerancia a nulos/tipos
        final role = (data['role'] as String?) ?? 'basico';
        final username = (data['username'] as String?) ?? user.displayName;
        final photoUrl = (data['photoUrl'] as String?) ?? user.photoURL;
        final email = user.email;

        currentUser.update(
          uid_: uid,
          email_: email,
          role_: role,
          displayName_: username,
          photoUrl_: photoUrl,
        );
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
    ChangeNotifierProvider<CurrentUser>.value(
      value: currentUser,
      child: const MyApp(),
    ),
  );
}

String? userOrNullUid({User? user}) => user == null ? null : user.uid;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MyL Decks',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const AuthGate(),
    );
  }
}
