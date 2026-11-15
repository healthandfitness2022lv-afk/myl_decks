import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String chatIdFor(String firstUid, String secondUid) {
    return firstUid.compareTo(secondUid) <= 0
        ? '${firstUid}_$secondUid'
        : '${secondUid}_$firstUid';
  }

  Future<String> createOrGet(String otherUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null) throw StateError('Debes iniciar sesión.');
    final id = chatIdFor(me, otherUid);
    await _db.collection('chats').doc(id).set({
      'participants': [me, otherUid],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  Stream<List<ChatMessage>> watchMessages(String chatId) => _db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(ChatMessage.fromSnapshot).toList());

  Future<void> send(String chatId, String text) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Debes iniciar sesión.');
    final value = text.trim();
    if (value.isEmpty) return;
    final chat = _db.collection('chats').doc(chatId);
    final message = chat.collection('messages').doc();
    final batch = _db.batch();
    batch.set(message, {
      'id': message.id,
      'from': uid,
      'text': value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(chat, {
      'lastMessage': value,
      'lastAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
