// Official-source course scope tests (plan 34 R1): builtin isolation of
// Legacy + Official sections, full sourceId round-trip (no `src`
// truncation), one course entry per source, exact-ownership filtering, and
// `anki:src` preference repair for single/multi source installs.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart' hide Section;
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

/// An official projection section shell: 'official-anki-<sourceId>-s<deck>'.
Section _officialSection(String sourceId, String name, {int deck = 10}) {
  return Section(
    id: 'official-anki-$sourceId-s$deck',
    name: name,
    description: 'Official projection',
    level: 'OfficialAnki',
    prerequisiteSectionIds: const [],
    units: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late AnkiOwnerAuthorityDao dao;

  const srcA = 'src-4f8b2c9d1e';
  const srcB = 'src-99aa88bb77';

  setUp(() async {
    db = await seedInMemoryCourseDb();
    dao = AnkiOwnerAuthorityDao(db);
    final repo = CourseRepository(db);
    await repo.bulkInsertCourseTree(_officialSection(srcA, 'Deck A Top'));
    await repo
        .bulkInsertCourseTree(_officialSection(srcA, 'Deck A Sub', deck: 11));
    await repo.bulkInsertCourseTree(_officialSection(srcB, 'Deck B Top'));
    // One authority row per official source, active + official backend.
    for (final (sourceId, name) in const [
      (srcA, 'Deck A'),
      (srcB, 'Deck B'),
    ]) {
      await dao.upsertSource(
        courseId: 'course-$sourceId',
        profileId: 'profile-default-01',
        sourceId: sourceId,
        backendKind: 'official',
        displayName: name,
        sourceHash: 'hash-$sourceId',
        sourceFingerprint: 'fp-$sourceId',
        state: AnkiSourceVisibility.active,
      );
    }
    CourseLoader.invalidateCaches();

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(sp);
    await appPrefs.setString(PrefsConstants.courseScope, '');
    await appPrefs.setStringList(PrefsConstants.courseOrder, const []);

    // Course entry flags on (production profile), projections active.
    OfficialAnkiCourseEntry.flagsOf =
        () => OfficialAnkiFeatureFlags.productionAndroid;
    OfficialAnkiCourseEntry.activeSectionIds = () => {
          'official-anki-$srcA-s10',
          'official-anki-$srcA-s11',
          'official-anki-$srcB-s10',
        };
  });

  tearDown(() async {
    OfficialAnkiCourseEntry.resetHooks();
    await db.close();
  });

  test('builtin scope hides BOTH legacy and official Anki sections (R1-2)',
      () async {
    final provider = CourseProvider(appPrefs);
    await provider.load();

    expect(provider.scope, const BuiltinCourseScope('turkish'));
    expect(provider.sections, isNotEmpty);
    expect(
      provider.sections.any((s) =>
          s.level == 'Anki' ||
          s.level == 'OfficialAnki' ||
          OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isFalse,
      reason: 'the builtin language course must never show an Anki section',
    );
  });

  test('full src-<random> sourceId round-trips scope → filter → entries',
      () async {
    final provider = CourseProvider(appPrefs);
    await provider.load();

    await provider.setScope(OfficialAnkiCourseScope(
      profileId: 'profile-default-01',
      sourceId: srcA,
    ));

    expect(
      provider.scope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ),
    );
    // Only source A's sections, both decks of it.
    expect(provider.sections.map((s) => s.id).toSet(), {
      'official-anki-$srcA-s10',
      'official-anki-$srcA-s11',
    });

    // Restart keeps the exact full sourceId.
    final restored = CourseProvider(appPrefs);
    await restored.load();
    expect(
      restored.scope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ),
      reason: 'the persisted scope must carry the complete sourceId, never '
          'the truncated "src"',
    );
    expect(restored.sections, hasLength(2));
  });

  test('two official sources are two distinct course entries (R1-3)', () async {
    final provider = CourseProvider(appPrefs);
    await provider.load();

    final official = provider.catalogEntries
        .where((e) => e.officialSourceId != null)
        .toList();
    expect(official, hasLength(2));
    expect(official.map((e) => e.officialSourceId).toSet(), {srcA, srcB});
    expect(official.map((e) => e.displayName), ['Deck A', 'Deck B']);
  });

  test('selecting source B shows only B sections; A untouched (R1-3)',
      () async {
    final provider = CourseProvider(appPrefs);
    await provider.load();

    await provider.setScope(OfficialAnkiCourseScope(
      profileId: 'profile-default-01',
      sourceId: srcB,
    ));

    expect(
      provider.sections.map((s) => s.id),
      ['official-anki-$srcB-s10'],
    );
  });

  test(
      'legacy anki:<fullSourceId> scope value resolves to the official '
      'source (upgrade path)', () async {
    await appPrefs.setString(PrefsConstants.courseScope, 'anki:$srcB');

    final provider = CourseProvider(appPrefs);
    await provider.load();

    expect(
      provider.scope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcB,
      ),
    );
    expect(provider.sections, hasLength(1));
  });

  group('broken anki:src preference handling (R1-6 provider path)', () {
    test('with exactly one official source, anki:src re-binds to it', () async {
      // Retire source B so only A remains visible.
      await dao.commitVisibility(
        courseId: 'course-$srcB',
        state: AnkiSourceVisibility.retired,
      );
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:src');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ),
        reason: 'a truncated anki:src with one source re-binds to that '
            'source instead of guessing',
      );
    });

    test('with multiple official sources, anki:src falls back to builtin',
        () async {
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:src');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        const BuiltinCourseScope('turkish'),
        reason: 'ambiguity must fall back to builtin, never pick the first '
            'source',
      );
      expect(provider.sections.every((s) => s.level != 'OfficialAnki'), isTrue);
    });
  });
}
