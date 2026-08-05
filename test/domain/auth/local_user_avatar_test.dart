// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';

void main() {
  group('LocalUser.avatarId', () {
    test('default LocalUser.local has null avatarId', () {
      expect(LocalUser.local.avatarId, isNull);
    });

    test('toJson / fromJson roundtrip preserves avatarId', () {
      const u = LocalUser(
        uid: 'local',
        email: '',
        displayName: 'Tester',
        photoUrl: '',
        avatarId: 'avatar_fox',
      );
      final round = LocalUser.fromJson(u.toJson());
      expect(round.avatarId, 'avatar_fox');
    });

    test('fromJson tolerates missing avatarId (backward compat)', () {
      // Old persisted payload (avatarId not present) should still parse.
      final json = LocalUser.local.toJson()..remove('avatarId');
      final parsed = LocalUser.fromJson(json);
      expect(parsed.avatarId, isNull);
      // Other fields should roundtrip cleanly.
      expect(parsed.displayName, LocalUser.local.displayName);
    });

    test('fromJson tolerates null avatarId', () {
      final json = LocalUser.local.toJson()..['avatarId'] = null;
      final parsed = LocalUser.fromJson(json);
      expect(parsed.avatarId, isNull);
    });

    test('copyWith(avatarId:) sets the field', () {
      final next = LocalUser.local.copyWith(avatarId: 'avatar_owl');
      expect(next.avatarId, 'avatar_owl');
    });

    test('copyWith() without avatarId preserves existing value', () {
      final withId = LocalUser.local.copyWith(avatarId: 'avatar_panda');
      final next = withId.copyWith(displayName: 'Renamed');
      expect(next.avatarId, 'avatar_panda');
      expect(next.displayName, 'Renamed');
    });

    test('copyWith(clearAvatarId: true) sets it back to null', () {
      final withId = LocalUser.local.copyWith(avatarId: 'avatar_lion');
      expect(withId.avatarId, 'avatar_lion');

      final cleared = withId.copyWith(clearAvatarId: true);
      expect(cleared.avatarId, isNull);
    });
  });

  group('AvatarCatalog.resolve', () {
    test('returns the matching entry for a known id', () {
      final a = AvatarCatalog.resolve('avatar_fox');
      expect(a.id, 'avatar_fox');
      expect(a.emoji, '🦊');
    });

    test('returns default avatar for null id', () {
      final a = AvatarCatalog.resolve(null);
      expect(a.id, kAvatarDefaultId);
    });

    test('returns default avatar for an unknown id', () {
      final a = AvatarCatalog.resolve('does_not_exist');
      expect(a.id, kAvatarDefaultId);
    });

    test('catalog always includes the default avatar', () {
      final hasDefault =
          AvatarCatalog.all.any((a) => a.id == kAvatarDefaultId);
      expect(hasDefault, isTrue);
    });

    test('all avatar ids are unique', () {
      final ids = AvatarCatalog.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every avatar has a non-empty emoji and name', () {
      for (final a in AvatarCatalog.all) {
        expect(a.emoji, isNotEmpty, reason: 'avatar ${a.id} has no emoji');
        expect(a.name, isNotEmpty, reason: 'avatar ${a.id} has no name');
      }
    });
  });
}
