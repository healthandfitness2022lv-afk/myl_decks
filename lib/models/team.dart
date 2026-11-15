import 'package:cloud_firestore/cloud_firestore.dart';

enum TeamRole { owner, admin, captain, member }

TeamRole teamRoleFromString(Object? value) => switch (value) {
  'owner' => TeamRole.owner,
  'admin' => TeamRole.admin,
  'captain' => TeamRole.captain,
  _ => TeamRole.member,
};

class Team {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final DateTime? createdAt;

  const Team({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    this.createdAt,
  });

  factory Team.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Team(
      id: snapshot.id,
      name: (data['name'] ?? 'Team').toString(),
      // Compatibilidad con el esquema anterior de ligas.
      ownerId: (data['ownerId'] ?? data['adminUid'] ?? '').toString(),
      inviteCode: (data['inviteCode'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TeamMember {
  final String uid;
  final String displayName;
  final String photoUrl;
  final TeamRole role;
  final DateTime? joinedAt;

  const TeamMember({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    this.joinedAt,
  });

  factory TeamMember.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return TeamMember(
      uid: snapshot.id,
      displayName: (data['displayName'] ?? 'Jugador').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      role: teamRoleFromString(data['role']),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}
