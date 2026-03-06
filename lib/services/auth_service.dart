import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Stream<User?> authState() => _auth.authStateChanges();

  Future<User> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  Future<void> signOut() => _auth.signOut();

  User? get currentUser => _auth.currentUser;
}
