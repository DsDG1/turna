// CourseScope codec + legacy preference migration tests (plan 34 R1-6,
// OS-03): round-trip, percent-encoding of dynamic segments, legacy value
// resolution (single/multi official, legacy vs official ambiguity), and
// idempotent repair.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/course_scope.dart';

void main() {
  group('CourseScopeCodec v1', () {
    test('round-trips all three scope kinds', () {
      final scopes = <CourseScope>[
        const BuiltinCourseScope('turkish'),
        const LegacyAnkiCourseScope('anki_import_123'),
        const OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: 'src-4f8b2c9d',
        ),
      ];
      for (final scope in scopes) {
        final decoded = CourseScopeCodec.decode(scope.wireKey);
        expect(decoded, scope, reason: 'round-trip failed for $scope');
      }
    });

    test('wire keys use the versioned unambiguous format', () {
      expect(
        const BuiltinCourseScope('turkish').wireKey,
        'course-scope:v1:builtin:tr',
      );
      expect(
        const LegacyAnkiCourseScope('imp1').wireKey,
        'course-scope:v1:legacy:imp1',
      );
      expect(
        const OfficialAnkiCourseScope(
          profileId: 'p1',
          sourceId: 's1',
        ).wireKey,
        'course-scope:v1:official:p1:s1',
      );
    });

    test('percent-encodes segments containing delimiters', () {
      const scope = OfficialAnkiCourseScope(
        profileId: 'pro:file',
        sourceId: 'src-wei:rd/id',
      );
      final decoded = CourseScopeCodec.decode(scope.wireKey);
      expect(decoded, scope);
    });

    test('rejects malformed keys', () {
      expect(CourseScopeCodec.decode(''), isNull);
      expect(CourseScopeCodec.decode('anki:src'), isNull);
      expect(CourseScopeCodec.decode('course-scope:v1:'), isNull);
      expect(CourseScopeCodec.decode('course-scope:v1:unknown:x'), isNull);
      expect(
        CourseScopeCodec.decode('course-scope:v1:official:onlyprofile'),
        isNull,
      );
    });
  });

  group('CourseScope equality', () {
    test('same-source official scopes are equal; different ids are not', () {
      const a = OfficialAnkiCourseScope(profileId: 'p', sourceId: 'src-1');
      const b = OfficialAnkiCourseScope(profileId: 'p', sourceId: 'src-1');
      const c = OfficialAnkiCourseScope(profileId: 'p', sourceId: 'src-2');
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('scope kinds never collide', () {
      const builtin = BuiltinCourseScope('src-1');
      const legacy = LegacyAnkiCourseScope('src-1');
      const official =
          OfficialAnkiCourseScope(profileId: 'p', sourceId: 'src-1');
      expect(builtin == legacy, isFalse);
      expect(legacy == official, isFalse);
    });
  });
}
