import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_lesson_content.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_unowned_card_reclaimer.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/official_anki_v2_view_store.dart';
import 'package:turna/domain/anki/official_anki_v2_view_models.dart';

import '../../../helpers/in_memory_course_db.dart';

/// Strict engine fake that fails reads as well as writes when the profile has
/// not been opened yet (mirrors Rust collection-not-open state).
class _StrictLifecycleFakeEngine extends FakeOfficialAnkiEngine {
  @override
  Future<OfficialAnkiConfigValue> getConfig(String key) async {
    if (requireCollectionOpen && openProfileId == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'read_before_open',
      );
    }
    return super.getConfig(key);
  }

  @override
  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) async {
    if (requireCollectionOpen && openProfileId == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'projection_before_open',
      );
    }
    return super.beginProjectionRead(
      cardSetFingerprint: cardSetFingerprint,
      mappingVersion: mappingVersion,
    );
  }
}

class _SequenceOpenFakeEngine extends FakeOfficialAnkiEngine {
  _SequenceOpenFakeEngine(this.outcomes);

  final List<OfficialAnkiException?> outcomes;
  int attempts = 0;

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) async {
    attempts++;
    final next = outcomes.isNotEmpty ? outcomes.removeAt(0) : null;
    if (next != null) throw next;
    await super.openProfile(paths);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late Directory root;
  late OfficialAnkiPaths paths;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-v2-convergence-');
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    paths = OfficialAnkiPaths(
      profileId: 'profile-v2-convergence',
      profileRoot: Directory(p.join(root.path, 'live'))
        ..createSync(recursive: true),
    );
  });

  tearDown(() async {
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    OfficialAnkiCompositionRoot.locatorPaths = null;
    OfficialAnkiCompositionRoot.debugEngineOverride = null;
    CourseLoader.clearDatabaseOverride();
    catalog.close();
    await course.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {/* best-effort temp cleanup */}
  });

  test(
      'ensureOfficialProfileOpen opens unopened engine and treats '
      'collectionAlreadyOpen as harmless no-op', () async {
    final engine = FakeOfficialAnkiEngine();
    expect(engine.openProfileId, isNull);

    await ensureOfficialProfileOpen(engine, paths);
    expect(engine.openProfileId, paths.profileId);
    expect(engine.openCount, 1);

    final alreadyOpen = _SequenceOpenFakeEngine([
      const OfficialAnkiException(
        code: OfficialAnkiErrorCode.collectionAlreadyOpen,
        messageKey: 'official_anki.collection_already_open',
      ),
    ]);
    await expectLater(ensureOfficialProfileOpen(alreadyOpen, paths), completes);
    expect(alreadyOpen.attempts, 1);

    final transientThenOk = _SequenceOpenFakeEngine([
      const OfficialAnkiException(
        code: OfficialAnkiErrorCode.collectionLocked,
        messageKey: 'official_anki.collection_locked',
      ),
      const OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulerBusy,
        messageKey: 'official_anki.scheduler_busy',
      ),
      null,
    ]);
    await ensureOfficialProfileOpen(
      transientThenOk,
      paths,
      baseDelay: const Duration(milliseconds: 1),
    );
    expect(transientThenOk.attempts, 3);
    expect(transientThenOk.openProfileId, paths.profileId);
  });

  test('maintenance runner opens an unopened engine before v2_source_delete',
      () async {
    final engine = _StrictLifecycleFakeEngine()..requireCollectionOpen = true;
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 1, cards: 1);
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-maint',
      profileId: paths.profileId,
      sourceHash: 'hash-maint',
      sourceSize: 10,
      displayName: 'Maint',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: 'src-maint', nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: 'src-maint',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 1,
          noteId: 1,
          deckId: 1,
          templateOrd: 0,
          notetypeId: 1,
        ),
      ],
    );

    await OfficialAnkiV2RetireService(
      catalog: catalog,
      paths: paths,
      viewStore: OfficialAnkiV2ViewStore(course),
      engine: null,
    ).beginRetire(sourceId: 'src-maint');

    expect(engine.openProfileId, isNull);
    final completed = await OfficialAnkiMaintenanceRunner(
      catalog: catalog,
      paths: paths,
      engine: engine,
      course: course,
    ).runPending(profileId: paths.profileId);

    expect(completed, greaterThanOrEqualTo(1));
    expect(engine.openProfileId, paths.profileId);
    expect(engine.cards, isEmpty);
    expect(sources.findById('src-maint'), isNull);
  });

  test('OfficialAnkiRepairExecutor opens an unopened engine before retiring',
      () async {
    final engine = _StrictLifecycleFakeEngine()..requireCollectionOpen = true;
    engine.seedPackage(packagePath: 'pkg.apkg', notes: 1, cards: 1);
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-repair',
      profileId: paths.profileId,
      sourceHash: 'hash-repair',
      sourceSize: 10,
      displayName: 'Repair',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: 'src-repair', nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: 'src-repair',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 1,
          noteId: 1,
          deckId: 1,
          templateOrd: 0,
          notetypeId: 1,
        ),
      ],
    );
    sources.markRetiring(sourceId: 'src-repair', nowMillis: 2);

    expect(engine.openProfileId, isNull);
    final report = await const OfficialAnkiRepairExecutor().run(
      course: course,
      catalog: catalog,
      engine: engine,
      sources: sources,
      paths: paths,
      profileId: paths.profileId,
    );

    expect(engine.openProfileId, paths.profileId);
    expect(report.resumedCleanups, 1);
    expect(engine.cards, isEmpty);
    expect(sources.findById('src-repair'), isNull);
  });

  test('unowned card reclaimer opens an unopened engine before purging',
      () async {
    final engine = _StrictLifecycleFakeEngine()..requireCollectionOpen = true;
    engine.cards[99] = const OfficialAnkiCardDescriptor(
      cardId: 99,
      noteId: 990,
      deckId: 1,
      templateOrd: 0,
      noteGuid: 'orphan',
      notetypeId: 1,
    );
    engine.cardsByNote[990] = [99];

    expect(engine.openProfileId, isNull);
    final deleted = await OfficialAnkiV2UnownedCardReclaimer(
      catalog: catalog,
      paths: paths,
      engine: engine,
    ).purge();

    expect(engine.openProfileId, paths.profileId);
    expect(deleted, 1);
    expect(engine.cards, isEmpty);
  });

  test('OfficialAnkiV2LessonContent opens an unopened engine before reading',
      () async {
    const sourceId = 'src-read-open';
    const lessonId = 'official-anki-src-read-open-l-1';
    final engine = _StrictLifecycleFakeEngine()..requireCollectionOpen = true;
    engine.cards[7] = const OfficialAnkiCardDescriptor(
      cardId: 7,
      noteId: 70,
      deckId: 10,
      templateOrd: 0,
      noteGuid: 'guid-7',
      notetypeId: 1,
    );
    final suggestion = OfficialAnkiMappingSuggestion(
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 1,
          evidence: [],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.response,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 1,
          evidence: [],
        ),
      ],
      status: OfficialAnkiMappingStatus.manual,
      notetypeId: 1,
      userConfirmed: true,
      enabledKinds: const ['flip'],
      direction: 'promptToResponse',
    );
    engine.configStore[OfficialAnkiV2ConfigKeys.importMapping(sourceId)] = {
      'schema': 1,
      'confirmed': [1],
      'skipped': [],
      'suggestions': jsonEncode({'1': suggestion.toJson()}),
    };

    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: paths.profileId,
      sourceHash: 'hash-read-open',
      sourceSize: 10,
      displayName: 'ReadOpen',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: sourceId, nowMillis: 1);

    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: const [
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 7,
          noteId: 70,
          deckId: 10,
          wordId: 'w-7',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-read-open-s-1',
          unitId: 'official-anki-src-read-open-u-1',
          lessonId: lessonId,
          lessonKey: 'Lesson A',
          sourceHash: 'hash-read-open',
        ),
      ],
      rebuiltAtMillis: 1,
    );

    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = paths;
    OfficialAnkiCompositionRoot.debugEngineOverride = engine;
    CourseLoader.overrideDatabase(() => course);

    expect(engine.openProfileId, isNull);
    final outcome = await OfficialAnkiV2LessonContent.lessonFor(lessonId);

    expect(engine.openProfileId, paths.profileId);
    expect(engine.openCount, 1);
    expect(outcome.failure, isNull);
    expect(outcome.lesson, isNotNull);
  });
}
