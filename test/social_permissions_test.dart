import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/social_permissions.dart';

void main() {
  group('SocialPermissions', () {
    test('solo propietarios y administradores gestionan un espacio', () {
      const member = SocialPermissions(
        currentUid: 'member',
        ownerUid: 'owner',
        role: SocialRole.member,
      );
      const owner = SocialPermissions(
        currentUid: 'owner',
        ownerUid: 'owner',
        role: SocialRole.owner,
      );

      expect(member.canManage, isFalse);
      expect(owner.canManage, isTrue);
    });

    test('moderadores pueden editar contenido pero no administrar', () {
      const moderator = SocialPermissions(
        currentUid: 'mod',
        ownerUid: 'owner',
        role: SocialRole.moderator,
      );

      expect(moderator.canManage, isFalse);
      expect(moderator.canEditAuthor('another-user'), isTrue);
    });

    test('administradores de team pueden gestionar sin ser propietarios', () {
      const admin = SocialPermissions(
        currentUid: 'admin',
        ownerUid: 'owner',
        role: SocialRole.admin,
      );

      expect(admin.canManage, isTrue);
      expect(admin.currentUid == admin.ownerUid, isFalse);
    });

    test('autores pueden editar su propio contenido', () {
      const member = SocialPermissions(
        currentUid: 'author',
        ownerUid: 'owner',
        role: SocialRole.member,
      );

      expect(member.canEditAuthor('author'), isTrue);
      expect(member.canEditAuthor('another-user'), isFalse);
    });
  });
}
