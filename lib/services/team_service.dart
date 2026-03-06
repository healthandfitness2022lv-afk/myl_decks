import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class TeamService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  String _inviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> createTeam(String name) async {
    final ref = _db.collection('teams').doc();
    final code = _inviteCode();
    await ref.set({
      'name': name.trim(),
      'ownerId': uid,
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final user = _auth.currentUser!;
    final memberRef = ref.collection('members').doc(uid);
    await memberRef.set({
      'role': 'owner',
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(uid).collection('teams').doc(ref.id).set({
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  Future<String?> joinByCode(String code) async {
    code = code.trim().toUpperCase();
    final q = await _db.collection('teams').where('inviteCode', isEqualTo: code).limit(1).get();
    if (q.docs.isEmpty) return null;
    final teamId = q.docs.first.id;

    // ya es miembro?
    final isMember = await _db.collection('teams').doc(teamId).collection('members').doc(uid).get();
    if (isMember.exists) return teamId;

    final user = _auth.currentUser!;
    await _db.collection('teams').doc(teamId).collection('members').doc(uid).set({
      'role': 'member',
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(uid).collection('teams').doc(teamId).set({
      'role': 'member',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    return teamId;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myTeams() {
    return _db.collection('users').doc(uid).collection('teams').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> team(String teamId) {
    return _db.collection('teams').doc(teamId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> members(String teamId) {
    return _db.collection('teams').doc(teamId).collection('members').orderBy('joinedAt').snapshots();
  }

  Future<void> leaveTeam(String teamId) async {
    final teamRef = _db.collection('teams').doc(teamId);
    final teamSnap = await teamRef.get();
    if (!teamSnap.exists) return;

    final memRef = teamRef.collection('members').doc(uid);
    final mem = await memRef.get();
    if (!mem.exists) return;

    // si es owner y hay otros miembros: impide salir (o transfiere propietario)
    if ((mem.data()?['role'] == 'owner')) {
      final others = await teamRef.collection('members').get();
      if (others.docs.length > 1) {
        throw Exception('Transfiere la propiedad antes de salir.');
      }
      // si está solo, permitir borrar el team
      await memRef.delete();
      await _db.collection('users').doc(uid).collection('teams').doc(teamId).delete();
      await teamRef.delete();
      return;
    }

    await memRef.delete();
    await _db.collection('users').doc(uid).collection('teams').doc(teamId).delete();
  }
}
