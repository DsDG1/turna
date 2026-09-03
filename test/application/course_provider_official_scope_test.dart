// Official-source course scope tests (plan 34 R1): builtin isolation of
// Legacy + Official sections, full sourceId round-trip (no `src`
// truncation), one course entry per source, exact-ownership filtering, and
// `anki:src` preference repair for single/multi source installs.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late OfficialAnkiDatabase catalog;

  const srcA = 'src-4f8b2c9d1e';
  const srcB = 'src-99aa88bb77';

  setUp(() async {
    db = await seedInMemoryCourseDb();
    catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    // The catalog ledger + course tree view a real v2 publish writes: one
    // active source row per official source (display name lives there), and
    // view rows for each of its sections — official section shells come
    // from the view alone (Step 6 removed the drift-table assembly).
    final sources = OfficialAnkiSourceDao(catalog);
    for (final (sourceId, name) in const [
      (srcA, 'Deck A'),
      (srcB, 'Deck B'),
    ]) {
      sources.upsertSource(
        sourceId: sourceId,
        profileId: 'profile-default-01',
        sourceHash: 'hash-$sourceId',
        sourceSize: 1,
        displayName: name,
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
    }
    await db.customStatement(
      "INSERT INTO anki_course_tree_view "
      "(source_id, card_id, note_id, deck_id, word_id, section_key, section_id, "
      " unit_id, lesson_id, lesson_key, presentation_kind, source_hash, "
      " mapping_version, rebuilt_at_millis) VALUES "
      "('$srcA', 1, 1, 10, 'w1', 'Deck A Top', 'official-anki-$srcA-s10', "
      "'official-anki-$srcA-s10-u1', 'official-anki-$srcA-s10-l1', 'lk', "
      "'flip', 'hash-$srcA', 1, 1),"
      "('$srcA', 2, 2, 11, 'w2', 'Deck A Sub', 'official-anki-$srcA-s11', "
      "'official-anki-$srcA-s11-u1', 'official-anki-$srcA-s11-l1', 'lk', "
      "'flip', 'hash-$srcA', 1, 1),"
      "('$srcB', 3, 3, 10, 'w3', 'Deck B Top', 'official-anki-$srcB-s10', "
      "'official-anki-$srcB-s10-u1', 'official-anki-$srcB-s10-l1', 'lk', "
      "'flip', 'hash-$srcB', 1, 1)",
    );
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
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    catalog.close();
    await db.close();
  });

  /// Step 6: retiring a v2 source = its catalog row leaves the active set
  /// (the old `anki_course_sources.visibility` authority row is gone).
  void retireSource(String sourceId) {
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: sourceId,
      profileId: 'profile-default-01',
      sourceHash: 'hash-$sourceId',
      sourceSize: 1,
      displayName: sourceId,
      state: 'retired',
      backendCommit: 'test',
      nowMillis: 2,
    );
  }

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
      'empty visibility set does not bounce an installed official source '
      'back to the built-in course', () async {
    OfficialAnkiCourseEntry.activeSectionIds = () => {};
    await appPrefs.setString(
      PrefsConstants.courseScope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ).wireKey,
    );

    final provider = CourseProvider(appPrefs);
    await provider.load();

    expect(
      provider.scope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ),
    );
    expect(provider.sections.map((s) => s.id).toSet(), {
      'official-anki-$srcA-s10',
      'official-anki-$srcA-s11',
    });
  });

  test(
      'official scope with no catalog entry still falls back to builtin',
      () async {
    OfficialAnkiCourseEntry.activeSectionIds = () => {};
    retireSource(srcA);
    retireSource(srcB);
    await appPrefs.setString(
      PrefsConstants.courseScope,
      OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ).wireKey,
    );

    final provider = CourseProvider(appPrefs);
    await provider.load();

    expect(provider.scope, const BuiltinCourseScope('turkish'));
    expect(
      provider.sections.any(
        (s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id),
      ),
      isFalse,
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
      // Retire source B in the catalog so only A remains visible; the
      // retired source must not come back through any fallback.
      retireSource(srcB);
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
