import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community.dart';

class CommunityRepository {
  CommunityRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _posts(String communityId) =>
      _db.collection('communities').doc(communityId).collection('posts');

  Stream<List<CommunityPost>> watchPosts(String communityId) => _posts(
        communityId,
      )
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(CommunityPost.fromSnapshot).toList(),
      );

  Future<void> createPost({
    required String communityId,
    required String title,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Debes iniciar sesión.');
    await _posts(communityId).add({
      'title': title.trim(),
      'text': text.trim(),
      'authorUid': user.uid,
      'authorName': user.displayName ?? user.email ?? 'Usuario',
      'createdAt': FieldValue.serverTimestamp(),
      'comments': 0,
      'likes': 0,
      'dislikes': 0,
    });
  }
}
