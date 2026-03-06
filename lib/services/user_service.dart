import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class UserService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users');

  Future<AppUser> ensureUserDoc({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? email,
  }) async {
    final ref = _col.doc(uid);
    final snap = await ref.get();
    if (snap.exists) {
      final data = snap.data()!;
      return AppUser.fromMap(data, uid);
    } else {
      final user = AppUser(
        uid: uid,
        displayName: displayName,
        photoUrl: photoUrl,
        email: email,
        createdAt: DateTime.now(),
      );
      await ref.set(user.toMap());
      return user;
    }
  }

  Future<AppUser?> getUser(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromMap(snap.data()!, uid);
  }
}
