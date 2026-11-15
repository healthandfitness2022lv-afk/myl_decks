enum SocialRole { owner, admin, moderator, captain, member }

SocialRole socialRoleFromString(Object? value) => switch (value) {
  'owner' => SocialRole.owner,
  'admin' => SocialRole.admin,
  'moderator' => SocialRole.moderator,
  'captain' => SocialRole.captain,
  _ => SocialRole.member,
};

class SocialPermissions {
  final String currentUid;
  final String ownerUid;
  final SocialRole role;
  final bool globalAdmin;

  const SocialPermissions({
    required this.currentUid,
    required this.ownerUid,
    required this.role,
    this.globalAdmin = false,
  });

  bool get canManage =>
      globalAdmin ||
      currentUid == ownerUid ||
      role == SocialRole.owner ||
      role == SocialRole.admin;

  bool get canModerate => canManage || role == SocialRole.moderator;

  bool canEditAuthor(String authorUid) =>
      canModerate || (currentUid.isNotEmpty && currentUid == authorUid);
}
