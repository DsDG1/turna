import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_internal_page.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_jobs.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/achievements_provider.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_completion_coordinator.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/anki_official/official_anki_canonical_link_view.dart';
import 'package:turna/views/anki_official/official_anki_source_management_page.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('projection courseEntry and scheduler flags default false', () {
    const flags = OfficialAnkiFeatureFlags();
    expect(flags.projection, isFalse);
    expect(flags.courseEntry, isFalse);
    expect(flags.scheduler, isFalse);
    expect(flags.allowsProjection, isFalse);
    expect(flags.allowsCourseEntry, isFalse);
    expect(flags.allowsOfficialScheduler, isFalse);
    expect(
      OfficialAnkiFeatureFlags.fromEnvironment().scheduler,
      isFalse,
    );
  });

  test('same-source create is rejected and needs_mapping resume keeps one writer',
      () {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src1',
      profileId: 'p',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 's',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    final jobs = OfficialAnkiProjectionJobRepository(catalog);
    final first = jobs.createJob(
      jobId: 'job-a',
      sourceId: 'src1',
      ownerToken: 'owner-a',
      nowMillis: 10,
    );
    jobs.heartbeat(
      jobId: first.jobId,
      ownerToken: 'owner-a',
      nowMillis: 11,
      state: OfficialAnkiProjectionJobState.needsMapping,
    );
    expect(
      () => jobs.createJob(
        jobId: 'job-b',
        sourceId: 'src1',
        ownerToken: 'owner-a',
        nowMillis: 12,
      ),
      throwsA(isA<Object>()),
    );
    expect(jobs.nonTerminalFor('src1'), hasLength(1));
    final resumed = jobs.resumeJob(
      jobId: first.jobId,
      ownerToken: 'owner-a',
      nowMillis: 13,
    );
    expect(resumed.jobId, first.jobId);
    expect(jobs.nonTerminalFor('src1'), hasLength(1));
    expect(
      () => jobs.createJob(
        jobId: 'job-c',
        sourceId: 'src1',
        ownerToken: 'owner-b',
        nowMillis: 14,
      ),
      throwsA(isA<Object>()),
    );
  });

  test('stale heartbeat can be claimed; cancel then new job is allowed', () {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src1',
      profileId: 'p',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 's',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    final jobs = OfficialAnkiProjectionJobRepository(catalog);
    final first = jobs.createJob(
      jobId: 'job-old',
      sourceId: 'src1',
      ownerToken: 'owner-a',
      nowMillis: 1,
    );
    jobs.requestCancel(
      jobId: first.jobId,
      ownerToken: 'owner-a',
      nowMillis: 2,
    );
    jobs.markCancelled(
      jobId: first.jobId,
      ownerToken: 'owner-a',
      nowMillis: 3,
    );
    final second = jobs.createJob(
      jobId: 'job-new',
      sourceId: 'src1',
      ownerToken: 'owner-b',
      nowMillis: 4,
    );
    expect(second.jobId, 'job-new');
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src2',
      profileId: 'p',
      sourceHash: 'h2',
      sourceSize: 1,
      displayName: 's2',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    final stale = jobs.createJob(
      jobId: 'job-stale-keep',
      sourceId: 'src2',
      ownerToken: 'owner-c',
      nowMillis: 1,
    );
    jobs.heartbeat(
      jobId: stale.jobId,
      ownerToken: 'owner-c',
      nowMillis: 1,
    );
    final claimed = jobs.claimStaleJob(
      sourceId: 'src2',
      ownerToken: 'owner-d',
      nowMillis: 1 + officialAnkiProjectionStaleHeartbeatMillis + 1,
      newJobId: 'job-claimed',
    );
    expect(claimed.jobId, 'job-claimed');
    expect(jobs.find('job-stale-keep')!.state, OfficialAnkiProjectionJobState.abandoned);
  });

  test('100 needs_mapping/generate cycles keep at most one non-terminal job',
      () async {
    final env = _Env(confirm: false);
    addTearDown(env.dispose);
    for (var i = 0; i < 100; i++) {
      if (i == 0) {
        final scan = await env.service.projectSource();
        expect(scan.needsMapping, isTrue);
      } else {
        env.catalog.handle.execute(
          "UPDATE anki_projection_mappings SET user_confirmed = 0, "
          "status = 'needsMapping'",
        );
        final scan = await env.service.projectSource();
        expect(scan.needsMapping, isTrue, reason: 'cycle $i');
      }
      expect(env.jobs.nonTerminalFor('src1'), hasLength(1));
      _confirmFakeBasic(env.service);
      final generated = await env.service.generateCourse();
      expect(generated.failed, isFalse, reason: 'cycle $i');
      expect(env.jobs.nonTerminalFor('src1'), isEmpty);
    }
  });

  test('non OfficialAnkiException leaves a terminal job', () async {
    final env = _env();
    addTearDown(env.dispose);
    env.service.debugThrowDuringProject = StateError('parser exploded');
    final result = await env.service.projectSource();
    expect(result.failed, isTrue);
    expect(result.errorCode, 'internalError');
    final job = env.jobs.find(result.jobId!);
    expect(job, isNotNull);
    expect(job!.isTerminal, isTrue);
    expect(job.state, OfficialAnkiProjectionJobState.failed);
  });

  test('catalog v5 migration abandons duplicate writers then unique index holds',
      () {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-dup',
      profileId: 'p',
      sourceHash: 'hd',
      sourceSize: 1,
      displayName: 'd',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    expect(
      catalog.handle.select(
        "SELECT name FROM sqlite_master WHERE name = 'anki_projection_one_active_writer'",
      ),
      isNotEmpty,
    );
    expect(catalog.handle.select('PRAGMA user_version').first['user_version'], 7);
  });

  test('identical mapping does not bump version; direction and kinds do', () {
    final env = _env();
    addTearDown(env.dispose);
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fake-basic',
    );
    final suggestion = OfficialAnkiProjectionMapper().suggest(schema: schema);
    env.service.confirmMapping(schema: schema, suggestion: suggestion);
    final first = _readMapping(env.catalog, 1);
    env.service.confirmMapping(schema: schema, suggestion: suggestion);
    final same = _readMapping(env.catalog, 1);
    expect(same.mappingVersion, first.mappingVersion);
    env.service.confirmMapping(
      schema: schema,
      suggestion: suggestion.copyWith(direction: 'nativeToTarget'),
    );
    final direction = _readMapping(env.catalog, 1);
    expect(direction.mappingVersion, first.mappingVersion + 1);
    env.service.confirmMapping(
      schema: schema,
      suggestion: direction.copyWith(enabledKinds: const ['flip']),
    );
    final kinds = _readMapping(env.catalog, 1);
    expect(kinds.mappingVersion, first.mappingVersion + 2);
    expect(
      officialAnkiSameCanonicalMapping(first, first.copyWith()),
      isTrue,
    );
  });

  test('schema change updates JSON columns fingerprint version atomically',
      () async {
    final env = _env();
    addTearDown(env.dispose);
    await env.service.projectSource();
    env.fake.projectionSchemaFingerprint = 'schema-changed';
    final reviewed = await env.service.projectSource();
    expect(reviewed.needsMapping, isTrue);
    final row = env.catalog.handle.select(
      'SELECT mapping_json, status, schema_fingerprint, mapping_version '
      'FROM anki_projection_mappings WHERE notetype_id = 1',
    ).first;
    expect(row['status'], OfficialAnkiMappingStatus.needsReview.name);
    expect(row['schema_fingerprint'], 'schema-changed');
    final json = OfficialAnkiMappingSuggestion.fromJson(
      Map<String, Object?>.from(jsonDecode(row['mapping_json'] as String) as Map),
    );
    expect(json.status, OfficialAnkiMappingStatus.needsReview);
    expect(json.schemaFingerprint, 'schema-changed');
    expect(json.mappingVersion, row['mapping_version']);
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      greaterThan(0),
    );
  });

  test('MC shuffle is stable, correctIndex is not constantly 0, 3 distractors required',
      () {
    final payloads = OfficialAnkiProjectionPayloads();
    const mapping = OfficialAnkiMappingSuggestion(
      candidates: [
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.targetText,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 1,
          evidence: ['t'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.nativeText,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 1,
          evidence: ['t'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.optionPool,
          fieldIndex: 2,
          fieldName: 'Options',
          confidence: 1,
          evidence: ['t'],
        ),
      ],
      status: OfficialAnkiMappingStatus.autoCandidate,
      enabledKinds: ['multipleChoice'],
    );
    final indexes = <int>{};
    for (var cardId = 1; cardId <= 100; cardId++) {
      final values = payloads.values(
        OfficialAnkiProjectionRow(
          cardId: cardId,
          noteId: cardId,
          noteGuid: 'g',
          notetypeId: 1,
          deckId: 1,
          deckPath: const ['D'],
          templateOrdinal: 0,
          tags: const [],
          fields: ['ans$cardId', 'native', 'w1|w2|w3|w4'],
          sourceFingerprint: 'fp-src',
        ),
        mapping,
      );
      expect(
        payloads.kindsFor(
          values: values,
          mapping: mapping,
          typeAnswerEnabled: false,
        ),
        [OfficialAnkiProjectionKind.multipleChoice],
      );
      final json = payloads.interactionJson(
        kind: OfficialAnkiProjectionKind.multipleChoice,
        item: OfficialAnkiProjectedItem(
          kind: OfficialAnkiProjectionKind.multipleChoice,
          cardId: cardId,
          wordId: 'w',
          sectionId: 's',
          unitId: 'u',
          lessonId: 'l',
          sectionName: 's',
          unitName: 'u',
          lessonName: 'l',
          payload: const {},
          sourceFingerprint: 'fp-src',
        ),
        values: values,
        sourceId: 'src',
      );
      final again = payloads.interactionJson(
        kind: OfficialAnkiProjectionKind.multipleChoice,
        item: OfficialAnkiProjectedItem(
          kind: OfficialAnkiProjectionKind.multipleChoice,
          cardId: cardId,
          wordId: 'w',
          sectionId: 's',
          unitId: 'u',
          lessonId: 'l',
          sectionName: 's',
          unitName: 'u',
          lessonName: 'l',
          payload: const {},
          sourceFingerprint: 'fp-src',
        ),
        values: values,
        sourceId: 'src',
      );
      expect(json['options'], again['options']);
      expect(json['correctIndex'], again['correctIndex']);
      expect((json['options'] as List).length, 4);
      indexes.add(json['correctIndex'] as int);
    }
    expect(indexes, isNot(equals({0})));
    expect(indexes.length, greaterThan(1));
    final tooFew = payloads.kindsFor(
      values: const OfficialAnkiRoleValues(
        target: 'a',
        native: 'b',
        pronunciation: '',
        example: '',
        audio: null,
        image: null,
        options: ['only'],
        truncatedRequired: false,
      ),
      mapping: mapping,
      typeAnswerEnabled: false,
    );
    expect(tooFew, isNot(contains(OfficialAnkiProjectionKind.multipleChoice)));
  });

  test('20 near-32KiB items split so each final Lesson JSON is <= 512 KiB', () {
    final projector = OfficialAnkiProjectionProjector();
    final mapping = OfficialAnkiMappingSuggestion(
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.targetText,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 1,
          evidence: ['t'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.nativeText,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 1,
          evidence: ['t'],
        ),
      ],
      status: OfficialAnkiMappingStatus.autoCandidate,
      userConfirmed: true,
    );
    final pad = 'x' * 28000;
    final rows = [
      for (var i = 1; i <= 20; i++)
        OfficialAnkiProjectionRow(
          cardId: i,
          noteId: i,
          noteGuid: 'g$i',
          notetypeId: 1,
          deckId: 1,
          deckPath: const ['Default'],
          templateOrdinal: 0,
          tags: const [],
          fields: ['$pad-$i', 'n$i'],
          sourceFingerprint: 'fp',
        ),
    ];
    final plan = projector.project(
      sourceId: 'src1',
      profileId: 'p',
      rows: rows,
      mappings: {1: mapping},
    );
    final byLesson = <String, List<OfficialAnkiProjectedItem>>{};
    for (final item in plan.items) {
      byLesson.putIfAbsent(item.lessonId, () => []).add(item);
    }
    expect(byLesson.length, greaterThan(1));
    for (final entry in byLesson.entries) {
      final encoded = utf8.encode(officialAnkiLessonJson(entry.value));
      expect(encoded.length, lessThanOrEqualTo(512 * 1024));
    }
    final again = projector.project(
      sourceId: 'src1',
      profileId: 'p',
      rows: rows,
      mappings: {1: mapping},
    );
    expect(
      again.items.map((item) => item.lessonId).toList(),
      plan.items.map((item) => item.lessonId).toList(),
    );
  });

  test('Course visibility uses manifest and stays consistent after publish',
      () async {
    final env = _env();
    addTearDown(env.dispose);
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(OfficialAnkiCourseEntry.resetHooks);
    final published = await env.service.projectSource();
    expect(published.failed, isFalse);
    final manifest = await env.course.customSelect(
      'SELECT source_id, source_fingerprint, item_count '
      'FROM official_anki_projection_manifest',
    ).get();
    expect(manifest, isNotEmpty);
    OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
          courseEntry: true,
        );
    OfficialAnkiCourseEntry.catalogOf = () => env.catalog;
    OfficialAnkiCourseEntry.courseOf = () => env.course;
    CourseLoader.overrideDatabase(() => env.course);
    addTearDown(CourseLoader.clearDatabaseOverride);
    final provider = CourseProvider();
    await provider.load();
    expect(
      provider.allSections
          .where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isNotEmpty,
    );
    await env.service.deleteProjection();
    await provider.reloadCourse();
    expect(
      provider.allSections
          .where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isEmpty,
    );
  });

  test('cold start locator opens catalog before CourseProvider.load', () async {
    final root = Directory.systemTemp.createTempSync('p3r-cold-');
    addTearDown(() => root.deleteSync(recursive: true));
    OfficialAnkiCompositionRoot.readOnlyCatalog?.close();
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    await OfficialAnkiCompositionRoot.initializeReadOnlyLocator(
      supportDir: root,
    );
    expect(OfficialAnkiCompositionRoot.readOnlyCatalog, isNotNull);
    expect(OfficialAnkiCourseEntry.catalogOf, isNotNull);
    OfficialAnkiCompositionRoot.readOnlyCatalog?.close();
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    OfficialAnkiCourseEntry.resetHooks();
  });

  test('production composition factory and source page do not use test hooks',
      () {
    final env = _env();
    addTearDown(env.dispose);
    final service = officialAnkiProductionProjectionService(
      engine: env.fake,
      catalog: env.catalog,
      course: env.course,
      sourceId: 'src1',
      profileId: 'profile-a',
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
    );
    expect(service.sourceId, 'src1');
    expect(
      OfficialAnkiSourceManagementPage.routeName,
      '/official-anki/sources',
    );
    expect(
      service.ownerToken,
      officialAnkiProjectionOwnerToken('profile-a'),
    );
    expect(
      OfficialAnkiCompositionRoot.createProjectionService(
        engine: env.fake,
        catalog: env.catalog,
        course: env.course,
        sourceId: 'src1',
        profileId: 'profile-a',
        flags: const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
        ),
      ).ownerToken,
      service.ownerToken,
    );
  });

  test('recreated page Generate resumes needs_mapping with profile owner',
      () async {
    final first = _Env(confirm: false);
    addTearDown(first.dispose);
    final scan = await first.service.projectSource();
    expect(scan.needsMapping, isTrue);
    final jobId = scan.jobId!;
    expect(first.jobs.find(jobId)!.ownerToken, first.service.ownerToken);

    final second = OfficialAnkiCompositionRoot.createProjectionService(
      engine: first.fake,
      catalog: first.catalog,
      course: first.course,
      sourceId: 'src1',
      profileId: 'profile-a',
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
    );
    expect(second.ownerToken, first.service.ownerToken);
    _confirmFakeBasic(second);
    final generated = await second.generateCourse(jobId: jobId);
    expect(generated.failed, isFalse);
    expect(generated.needsMapping, isFalse);
    expect(generated.itemCount, greaterThan(0));
    expect(first.jobs.find(jobId)!.isTerminal, isTrue);
    expect(first.jobs.nonTerminalFor('src1'), isEmpty);
  });

  test('buildSourceManagementPage is flag-gated and uses production deps',
      () async {
    final env = _env();
    addTearDown(env.dispose);
    expect(
      await officialAnkiBuildSourceManagementPage(
        engine: env.fake,
        catalog: env.catalog,
        course: env.course,
        profileId: 'profile-a',
        flags: const OfficialAnkiFeatureFlags(),
      ),
      isNull,
    );
    final page = await officialAnkiBuildSourceManagementPage(
      engine: env.fake,
      catalog: env.catalog,
      course: env.course,
      profileId: 'profile-a',
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
    );
    expect(page, isA<OfficialAnkiSourceManagementPage>());
    expect(page!.profileId, 'profile-a');
    expect(
      File('lib/application/anki_official/official_anki_internal_page.dart')
          .readAsStringSync()
          .contains('officialAnkiBuildSourceManagementPage'),
      isTrue,
    );
    expect(
      File('lib/application/anki_official/official_anki_internal_page.dart')
          .readAsStringSync()
          .contains('official-source-management-open'),
      isTrue,
    );
  });

  testWidgets('internal official-source entry opens source management behind flag',
      (tester) async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags();
    addTearDown(() {
      OfficialAnkiFeatureFlags.current =
          OfficialAnkiFeatureFlags.fromEnvironment();
    });
    await tester.pumpWidget(const MaterialApp(home: OfficialAnkiInternalPage()));
    expect(find.byKey(const Key('official-source-management-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-source-management-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('projection_off'), findsOneWidget);
    expect(find.byType(OfficialAnkiSourceManagementPage), findsNothing);
  });

  testWidgets('source management save does not generate; generate resumes job',
      (tester) async {
    final env = _Env(confirm: false);
    addTearDown(env.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiSourceManagementPage(
          engine: env.fake,
          catalog: env.catalog,
          course: env.course,
          profileId: 'profile-a',
          flags: const OfficialAnkiFeatureFlags(
            engine: true,
            import: true,
            catalogReady: true,
            runtimeCapable: true,
            projection: true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('official-source-src1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-source-generate-src1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(env.jobs.nonTerminalFor('src1'), hasLength(1));
    expect(env.jobs.nonTerminalFor('src1').first.isResumable, isTrue);
  });

  test('canonicalLink LessonViewModel submits once, advances, scheduler writes 0',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefs(await StreamingSharedPreferences.instance);
    await getIt.reset();
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    getIt.registerLazySingleton<SettingsProvider>(() => SettingsProvider(prefs));
    getIt.registerLazySingleton<AccessibilityProvider>(
      () => AccessibilityProvider(prefs),
    );
    addTearDown(getIt.reset);
    final vm = _lessonVm(prefs);
    OfficialAnkiSchedulerAudit.reset();
    final lesson = Lesson(
      id: 'l-canonical',
      name: 'Canonical',
      content: LessonContent(
        stages: [
          Stage(
            id: 's1',
            name: 'S',
            items: [
              Interaction.showWord(
                id: 'sw-1',
                wordId: 'official-anki-link-src1-c1',
                context: 'official-canonical-link:src1:1',
              ),
              Interaction.showWord(
                id: 'sw-2',
                wordId: 'w-next',
              ),
            ],
          ),
        ],
      ),
    );
    vm.loadLessonInstance(lesson, recordMistakes: false);
    expect(vm.currentInteraction, isA<ShowWord>());
    final completion = OfficialAnkiCanonicalCompletion();
    completion.acknowledgeOnce(vm.submitInteraction);
    completion.acknowledgeOnce(vm.submitInteraction);
    expect(completion.submitCount, 1);
    expect(vm.questionResults, hasLength(1));
    vm.advance();
    expect(vm.currentInteraction?.id, 'sw-2');
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    expect(OfficialAnkiSchedulerAudit.legacyCallsFromOfficialPath, 0);
  });
}

OfficialAnkiMappingSuggestion _readMapping(OfficialAnkiDatabase catalog, int id) {
  final row = catalog.handle.select(
    'SELECT mapping_json FROM anki_projection_mappings WHERE notetype_id = ?',
    [id],
  ).first;
  return OfficialAnkiMappingSuggestion.fromJson(
    Map<String, Object?>.from(jsonDecode(row['mapping_json'] as String) as Map),
  );
}

class _Env {
  _Env({this.confirm = true, int cards = 2}) {
    catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src1',
      profileId: 'profile-a',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 'src1',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    if (cards > 0) {
      OfficialAnkiSourceDao(catalog).replaceCards(
        sourceId: 'src1',
        cards: [
          for (var i = 1; i <= cards; i++)
            OfficialAnkiCardDescriptor(
              cardId: i,
              noteId: i,
              deckId: 1,
              templateOrd: 0,
              noteGuid: 'guid-$i',
            ),
        ],
      );
    }
    course = CourseDatabase(NativeDatabase.memory());
    fake = FakeOfficialAnkiEngine();
    if (cards > 0) {
      fake.seedPackage(packagePath: 'x.apkg', notes: cards, cards: cards);
    }
    store = OfficialAnkiCourseProjectionStore(course);
    jobs = OfficialAnkiProjectionJobRepository(catalog);
    service = OfficialAnkiCourseProjectionService(
      engine: fake,
      catalog: catalog,
      course: course,
      sourceId: 'src1',
      profileId: 'profile-a',
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
      store: store,
      jobs: jobs,
    );
    if (confirm) {
      _confirmFakeBasic(service);
    }
  }

  final bool confirm;
  late final OfficialAnkiDatabase catalog;
  late final CourseDatabase course;
  late final FakeOfficialAnkiEngine fake;
  late final OfficialAnkiCourseProjectionStore store;
  late final OfficialAnkiProjectionJobRepository jobs;
  late final OfficialAnkiCourseProjectionService service;

  void dispose() {
    catalog.close();
    course.close();
  }
}

_Env _env({int cards = 2}) => _Env(cards: cards);

void _confirmFakeBasic(OfficialAnkiCourseProjectionService service) {
  const schema = OfficialAnkiProjectionSchema(
    notetypeId: 1,
    name: 'Basic',
    kind: 'normal',
    fieldNames: ['Front', 'Back'],
    templateNames: ['Card 1'],
    schemaFingerprint: 'fake-basic',
  );
  service.confirmMapping(
    schema: schema,
    suggestion: OfficialAnkiProjectionMapper().suggest(schema: schema),
  );
}

LessonViewModel _lessonVm(AppPrefs prefs) {
  final linkStore = LessonLinkStore(prefs);
  final srsDao = emptySrsStateDao();
  return LessonViewModel(
    _FakeCourseProvider(),
    _FakeAudioController(),
    SrsProvider(prefs, linkStore, srsDao),
    MistakeProvider(prefs),
    GrammarReviewProvider(prefs, linkStore, srsDao),
    LessonCompletionCoordinator(
      GameProvider.forTesting(prefs),
      GemsProvider(prefs),
      _FakeAchievementsProvider(),
      _FakeStudyStatsProvider(prefs),
    ),
  );
}

class _FakeCourseProvider extends CourseProvider {
  @override
  Lesson? findLessonById(String id) => null;
}

class _FakeAudioController extends AudioController {
  _FakeAudioController()
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          getIt<SettingsProvider>(),
          getIt<AccessibilityProvider>(),
          _PassthroughVocabResolver(),
          audioPlayer: _FakeAudioPlayer(),
          speechPlayer: _FakeAudioPlayer(),
        );

  @override
  Future<void> playRandomErrorSound() async {}

  @override
  Future<void> playRandomLevelUpSound() async {}
}

class _PassthroughVocabResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) =>
      ResolvedVocabAudio(speakText: wordId);
}

class _FakeFlutterTts implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAchievementsProvider extends AchievementsProvider {
  _FakeAchievementsProvider() : super(_FakeAppPrefs());

  @override
  Future<void> checkLessonMilestones({
    required int lessonsCompleted,
    required int perfectLessons,
  }) async {}
}

class _FakeStudyStatsProvider extends StudyStatsProvider {
  _FakeStudyStatsProvider(AppPrefs appPrefs)
      : super(StudyLogRepository(appPrefs), MistakeProvider(appPrefs));

  @override
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  }) async {}
}

class _FakeAppPrefs implements AppPrefs {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
