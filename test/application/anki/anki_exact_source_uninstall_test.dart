// Exact-source identity tests (plan 34 R1-1/R1-7): section-id parsing must
// recover the COMPLETE sourceId — `split('-').first` style truncation
// turned every official source into the bogus `src`, breaking switching,
// ordering and uninstall precision.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/domain/course/course_scope.dart';

void main() {
  group('CourseCatalog.officialSourceIdFromSectionId', () {
    test('recovers the full src-<random> sourceId', () {
      expect(
        CourseCatalog.officialSourceIdFromSectionId(
          'official-anki-src-4f8b2c9d1e-s10',
        ),
        'src-4f8b2c9d1e',
      );
    });

    test('uses the LAST -s boundary, never split-first', () {
      // A sourceId that itself contains '-s' style segments.
      expect(
        CourseCatalog.officialSourceIdFromSectionId(
          'official-anki-src-stop-s42-s7',
        ),
        'src-stop-s42',
      );
    });

    test('rejects malformed ids', () {
      expect(
        CourseCatalog.officialSourceIdFromSectionId('anki-imp1-s1'),
        isNull,
      );
      expect(
        CourseCatalog.officialSourceIdFromSectionId('official-anki-'),
        isNull,
      );
      expect(
        CourseCatalog.officialSourceIdFromSectionId(
          'official-anki-src-1-snotanumber',
        ),
        isNull,
      );
    });
  });

  group('CourseCatalog.legacyImportIdFromSectionId', () {
    test('recovers import ids containing dashes', () {
      expect(
        CourseCatalog.legacyImportIdFromSectionId('anki-my-import-7-s3'),
        'my-import-7',
      );
      expect(
        CourseCatalog.legacyImportIdFromSectionId('anki-imp1-s1'),
        'imp1',
      );
    });
  });

  group('exact ownership (R1-3)', () {
    test('sectionBelongsToScope never matches a sibling source', () {
      const a = OfficialAnkiCourseScope(
        profileId: 'p',
        sourceId: 'src-4f8b2c9d1e',
      );
      const b = OfficialAnkiCourseScope(
        profileId: 'p',
        sourceId: 'src-99aa88bb77',
      );
      expect(
        CourseCatalog.sectionBelongsToScope(
          a,
          'official-anki-src-4f8b2c9d1e-s10',
        ),
        isTrue,
      );
      expect(
        CourseCatalog.sectionBelongsToScope(
          b,
          'official-anki-src-4f8b2c9d1e-s10',
        ),
        isFalse,
        reason: 'two sources sharing the src- prefix must stay isolated',
      );
      expect(
        CourseCatalog.sectionBelongsToScope(
          const BuiltinCourseScope('turkish'),
          'official-anki-src-4f8b2c9d1e-s10',
        ),
        isFalse,
      );
      expect(
        CourseCatalog.sectionBelongsToScope(
          const LegacyAnkiCourseScope('imp1'),
          'official-anki-imp1-s10',
        ),
        isFalse,
        reason: 'an official section never belongs to a legacy scope even '
            'when the import ids collide',
      );
    });
  });
}
