import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_fingerprint.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_jobs.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/views/anki_official/official_anki_mapping_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog pages source cards with SQL cursor bounds', () {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final dao = OfficialAnkiSourceDao(catalog);
    dao.upsertSource(
      sourceId: 'a',
      profileId: 'p',
      sourceHash: 'ha',
      sourceSize: 1,
      displayName: 'a',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    dao.upsertSource(
      sourceId: 'b',
      profileId: 'p',
      sourceHash: 'hb',
      sourceSize: 1,
      displayName: 'b',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    dao.replaceCards(
      sourceId: 'a',
      cards: [
        for (final id in [5, 1, 3, 9])
          OfficialAnkiCardDescriptor(
            cardId: id,
            noteId: id,
            deckId: 1,
            templateOrd: 0,
          ),
      ],
    );
    dao.replaceCards(
      sourceId: 'b',
      cards: [
        OfficialAnkiCardDescriptor(
          cardId: 3,
          noteId: 3,
          deckId: 2,
          templateOrd: 0,
        ),
        OfficialAnkiCardDescriptor(
          cardId: 300,
          noteId: 300,
          deckId: 2,
          templateOrd: 0,
        ),
      ],
    );
    final first = dao.pageSourceCardIds(sourceId: 'a', limit: 2);
    expect(first.cardIds, [1, 3]);
    expect(first.hasMore, isTrue);
    final second = dao.pageSourceCardIds(
      sourceId: 'a',
      afterCardId: first.lastCardId,
      limit: 2,
    );
    expect(second.cardIds, [5, 9]);
    final third = dao.pageSourceCardIds(
      sourceId: 'a',
      afterCardId: second.lastCardId,
      limit: 2,
    );
    expect(third.cardIds, isEmpty);
    expect(third.hasMore, isFalse);
    final other = dao.pageSourceCardIds(sourceId: 'b', limit: 10);
    expect(other.cardIds, [3, 300]);
    expect(
      () => dao.pageSourceCardIds(sourceId: 'a', limit: 501),
      throwsA(isA<Object>()),
    );
  });

  test('0/1/199/200/201/500/501/5k pages stay bounded', () async {
    for (final count in [0, 1, 199, 200, 201, 500, 501, 5000]) {
      final env = _env(cards: count == 0 ? 0 : count);
      addTearDown(env.dispose);
      if (count == 0) {
        final empty = await env.service.projectSource();
        expect(empty.rowCount, 0);
        expect(env.counters.peakIdBuffer, lessThanOrEqualTo(500));
        continue;
      }
      final result = await env.service.projectSource();
      expect(result.failed, isFalse, reason: 'count $count');
      expect(result.rowCount, count);
      expect(env.counters.peakIdBuffer, lessThanOrEqualTo(500));
      expect(env.counters.officialSchedulerWrites, 0);
      expect(env.counters.legacyCalls, 0);
      if (count == 501) {
        expect(env.fake.projectionBatchSizes, [200, 200, 101]);
      }
      if (count == 201) {
        expect(env.fake.projectionBatchSizes, [200, 1]);
      }
    }
  });

  test('missing duplicate and stale fail closed and keep previous tree', () async {
    final env = _env(cards: 2);
    addTearDown(env.dispose);
    final first = await env.service.projectSource();
    expect(first.failed, isFalse);
    final before = await env.store.readOfficialProjectionSummary('src1');
    expect(before.itemCount, greaterThan(0));

    env.fake.missingOnRead.add(2);
    final missing = await env.service.projectSource(mappingVersion: 2);
    expect(missing.failed, isTrue);
    expect(missing.errorCode, 'PROJECTION_SOURCE_CHANGED');
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      before.itemCount,
    );

    env.fake.missingOnRead.clear();
    env.fake.emitDuplicateRows = true;
    final dup = await env.service.projectSource(mappingVersion: 3);
    expect(dup.failed, isTrue);
    expect(dup.errorCode, 'duplicate_row');
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      before.itemCount,
    );

    env.fake.emitDuplicateRows = false;
    env.fake.invalidateSnapshotOnRead = true;
    final stale = await env.service.projectSource(mappingVersion: 4);
    expect(stale.failed, isTrue);
    expect(stale.errorCode, 'PROJECTION_SOURCE_CHANGED');
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      before.itemCount,
    );
  });

  test('fingerprint ignores row order and binds schema mapping backend algorithm', () {
    const rowA = OfficialAnkiProjectionRow(
      cardId: 2,
      noteId: 2,
      noteGuid: 'g2',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['D'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: ['t', 'n'],
      sourceFingerprint: 'b',
    );
    const rowB = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'g1',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['D'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: ['t', 'n'],
      sourceFingerprint: 'a',
    );
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'schema-a',
    );
    const mapping = OfficialAnkiMappingSuggestion(
      candidates: [],
      status: OfficialAnkiMappingStatus.autoCandidate,
      userConfirmed: true,
    );
    String fp({
      required List<OfficialAnkiProjectionRow> rows,
      String schemaFp = 'schema-a',
      String backend = 'commit',
      int algorithm = 1,
    }) {
      return officialAnkiProjectionFingerprint(
        contractMajor: kOfficialAnkiContractMajor,
        contractMinor: kOfficialAnkiContractMinor,
        backendCommit: backend,
        profileId: 'p',
        sourceId: 's',
        orderedCardSetFingerprint: officialAnkiOrderedCardSetFingerprint([1, 2]),
        collectionGeneration: 1,
        schemas: [
          OfficialAnkiProjectionSchema(
            notetypeId: schema.notetypeId,
            name: schema.name,
            kind: schema.kind,
            fieldNames: schema.fieldNames,
            templateNames: schema.templateNames,
            schemaFingerprint: schemaFp,
          ),
        ],
        mappingVersion: 1,
        confirmedMappingHash: officialAnkiConfirmedMappingHash({1: mapping}),
        rows: rows,
        algorithmVersion: algorithm,
      );
    }

    expect(fp(rows: [rowA, rowB]), fp(rows: [rowB, rowA]));
    expect(fp(rows: [rowA, rowB], schemaFp: 'schema-b'), isNot(fp(rows: [rowA, rowB])));
    expect(fp(rows: [rowA, rowB], backend: 'other'), isNot(fp(rows: [rowA, rowB])));
    expect(fp(rows: [rowA, rowB], algorithm: 2), isNot(fp(rows: [rowA, rowB])));
  });

  test('cancel then a new job can start without dropping the last tree', () async {
    final env = _env(cards: 2);
    addTearDown(env.dispose);
    final first = await env.service.projectSource();
    expect(first.failed, isFalse);
    env.service.debugCancelImmediately = true;
    final cancelled = await env.service.projectSource(mappingVersion: 2);
    expect(cancelled.cancelled, isTrue);
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      greaterThan(0),
    );
    final source = OfficialAnkiSourceDao(env.catalog).findById('src1');
    expect(source?.state, 'active');
    env.service.debugCancelImmediately = false;
    final again = await env.service.projectSource(mappingVersion: 2);
    expect(again.cancelled, isFalse);
    expect(again.failed, isFalse);
    expect(
      env.jobs.find(again.jobId!)?.state,
      OfficialAnkiProjectionJobState.active,
    );
  });

  test('mid-publish fault keeps the previous generation', () async {
    final env = _env(cards: 2);
    addTearDown(env.dispose);
    await env.service.projectSource();
    final before = await env.store.readOfficialProjectionSummary('src1');
    env.store.debugFaultAfterStatements = 3;
    final failed = await env.service.projectSource(mappingVersion: 2);
    expect(failed.failed, isTrue);
    final after = await env.store.readOfficialProjectionSummary('src1');
    expect(after.itemCount, before.itemCount);
    expect(after.sectionIds, before.sectionIds);
    final contents = await env.course.select(env.course.lessonContents).get();
    expect(contents, isNotEmpty);
    final lesson = await env.repo.lessonById(contents.first.lessonId);
    expect(lesson.content.stages, isNotEmpty);
    expect(lesson.content.stages.first.items, isNotEmpty);
  });

  test('placement cannot target a non-official tree', () {
    final env = _env();
    addTearDown(env.dispose);
    expect(
      () => env.service.lockPlacement(
        cardId: 1,
        sectionKey: 'anki-import-s1',
        unitKey: 'anki-import-u1',
        lessonKey: 'anki-import-l1',
      ),
      throwsA(isA<Object>()),
    );
  });

  test('generated payloads round-trip the production Interaction parser', () {
    final mapper = OfficialAnkiProjectionMapper();
    final payloads = OfficialAnkiProjectionPayloads(mapper: mapper);
    const row = OfficialAnkiProjectionRow(
      cardId: 7,
      noteId: 7,
      noteGuid: 'g7',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['Lang'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: [
        'front',
        'back',
        '[sound:hello.mp3]',
        'wrong|front|other|third',
        '<img src="pic.png">',
      ],
      sourceFingerprint: 'fp',
    );
    final mapping = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.autoCandidate,
      userConfirmed: true,
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.targetText,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 1,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.nativeText,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 1,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.audio,
          fieldIndex: 2,
          fieldName: 'Audio',
          confidence: 1,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.optionPool,
          fieldIndex: 3,
          fieldName: 'Options',
          confidence: 1,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.image,
          fieldIndex: 4,
          fieldName: 'Image',
          confidence: 1,
          evidence: ['user'],
        ),
      ],
    );
    final values = payloads.values(row, mapping);
    expect(values.audio, 'hello.mp3');
    expect(values.image, 'pic.png');
    expect(values.options, containsAll(['wrong', 'other', 'third']));
    expect(mapper.shortText(row.fields[2]), isNot(contains('hello.mp3')));
    final kinds = payloads.kindsFor(
      values: values,
      mapping: mapping,
      typeAnswerEnabled: true,
    );
    expect(
      kinds,
      containsAll([
        OfficialAnkiProjectionKind.flip,
        OfficialAnkiProjectionKind.multipleChoice,
        OfficialAnkiProjectionKind.listenPick,
        OfficialAnkiProjectionKind.typeAnswer,
      ]),
    );
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src1',
      profileId: 'profile-a',
      rows: const [row],
      mappings: {1: mapping},
      typeAnswerEnabled: true,
    );
    expect(plan.items, isNotEmpty);
    for (final item in plan.items) {
      final parsed = Interaction.fromJson(Map<String, dynamic>.from(item.payload));
      if (parsed is ShowWord) {
        expect(parsed.wordId.startsWith('__unknown'), isFalse);
      }
      expect(item.payload.containsKey('runtimeType'), isTrue);
    }
    final json = OfficialAnkiCourseProjectionStore.lessonContentJson(plan.items);
    final decoded = jsonDecode(json);
    expect(decoded, isA<Map>());
    final content = LessonContent.fromJson(Map<String, dynamic>.from(decoded as Map));
    expect(content.stages.first.items, isNotEmpty);
    final lesson = Lesson(
      id: plan.items.first.lessonId,
      name: plan.items.first.lessonName,
      content: content,
    );
    expect(lesson.flattenedStages.first.items.length, plan.items.length);
  });

  test('CourseProvider flag matrix and canonicalLink fail closed', () {
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(OfficialAnkiCourseEntry.resetHooks);
    const official = Section(
      id: 'official-anki-src1-s1',
      name: 'Official',
      units: [],
    );
    const bundled = Section(id: 's-home', name: 'Home', units: []);
    OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
          courseEntry: false,
        );
    expect(
      OfficialAnkiCourseEntry.filterShells(const [official, bundled])
          .map((s) => s.id),
      ['s-home'],
    );
    OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
          courseEntry: true,
        );
    OfficialAnkiCourseEntry.activeSectionIds = () => {'official-anki-src1-s1'};
    expect(
      OfficialAnkiCourseEntry.filterShells(const [official, bundled])
          .map((s) => s.id),
      ['official-anki-src1-s1', 's-home'],
    );
    OfficialAnkiCourseEntry.activeSectionIds = () => <String>{};
    expect(
      OfficialAnkiCourseEntry.filterShells(const [official, bundled])
          .map((s) => s.id),
      ['s-home'],
    );
    expect(
      OfficialAnkiCourseEntry.resolveCanonicalLink(
        context: 'official-canonical-link:src1:1',
        flags: const OfficialAnkiFeatureFlags(),
      ),
      OfficialAnkiReviewTarget.error,
    );
    expect(
      OfficialAnkiReviewerRouter.officialMayUseLegacyRenderer(
        OfficialAnkiSourceKind.official,
      ),
      isFalse,
    );
  });

  testWidgets('mapping wizard edits restores skips and does not generate on save',
      (tester) async {
    var saved = false;
    var generated = false;
    var skipped = false;
    var restored = false;
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back', 'Audio'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fp',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 9,
          fields: ['hello', '你好', '[sound:a.mp3]'],
        ),
      ],
    );
    final suggestion = OfficialAnkiProjectionMapper().suggest(schema: schema);
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiMappingPage(
          notetypeName: 'Basic',
          suggestion: suggestion,
          schema: schema,
          affectedCardCount: 12,
          onConfirm: (_) => saved = true,
          onSkip: () => skipped = true,
          onRestore: () => restored = true,
          onGenerateCourse: () => generated = true,
        ),
      ),
    );
    expect(find.text('受影响卡片：12'), findsOneWidget);
    expect(find.byKey(const Key('mapping-sample-9')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mapping-save')));
    await tester.pump();
    expect(saved, isTrue);
    expect(generated, isFalse);
    await tester.tap(find.byKey(const Key('mapping-restore')));
    await tester.pump();
    expect(restored, isTrue);
    await tester.tap(find.byKey(const Key('mapping-skip')));
    await tester.pump();
    expect(skipped, isTrue);
    await tester.tap(find.byKey(const Key('mapping-generate')));
    await tester.pump();
    expect(generated, isTrue);
  });

  test('unconfirmed auto mapping does not publish a course tree', () async {
    final env = _Env(confirm: false);
    addTearDown(env.dispose);
    final result = await env.service.projectSource();
    expect(result.needsMapping, isTrue);
    expect(result.itemCount, 0);
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      0,
    );
  });

  test('schema change enters needs_review and keeps the old tree', () async {
    final env = _env();
    addTearDown(env.dispose);
    final first = await env.service.projectSource();
    expect(first.failed, isFalse);
    expect(first.needsMapping, isFalse);
    final before = await env.store.readOfficialProjectionSummary('src1');
    expect(before.itemCount, greaterThan(0));
    env.service.skipNotetype(
      schema: const OfficialAnkiProjectionSchema(
        notetypeId: 2,
        name: 'Other',
        kind: 'normal',
        fieldNames: ['A'],
        templateNames: ['C'],
        schemaFingerprint: 'x',
      ),
    );
    env.fake.projectionSchemaFingerprint = 'schema-changed';
    final reviewed = await env.service.projectSource();
    expect(reviewed.needsMapping, isTrue);
    expect(reviewed.failed, isFalse);
    final stored = env.catalog.handle.select(
      'SELECT status FROM anki_projection_mappings WHERE notetype_id = 1',
    ).first;
    expect(stored['status'], OfficialAnkiMappingStatus.needsReview.name);
    final after = await env.store.readOfficialProjectionSummary('src1');
    expect(after.itemCount, before.itemCount);
    expect(after.sectionIds, before.sectionIds);
    final skipped = env.catalog.handle.select(
      "SELECT status FROM anki_projection_mappings WHERE notetype_id = 2",
    ).first;
    expect(skipped['status'], 'skipped');
  });

  test('CourseProvider shows official section after publish and hides it after delete',
      () async {
    final env = _env();
    addTearDown(env.dispose);
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(() {
      OfficialAnkiCourseEntry.resetHooks();
      CourseLoader.clearDatabaseOverride();
    });
    final published = await env.service.projectSource();
    expect(published.failed, isFalse);
    expect(published.itemCount, greaterThan(0));
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
    final provider = CourseProvider();
    await provider.load();
    expect(
      provider.allSections
          .where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isNotEmpty,
    );
    expect(
      provider.sections.where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isNotEmpty,
    );
    await env.service.deleteProjection();
    await provider.reloadCourse();
    expect(
      provider.allSections
          .where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isEmpty,
    );
    expect(
      provider.sections.where((s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
      isEmpty,
    );
  });

  test('delete source A leaves source B and official mapping', () async {
    final env = _env(cards: 2);
    addTearDown(env.dispose);
    OfficialAnkiSourceDao(env.catalog).upsertSource(
      sourceId: 'src-b',
      profileId: 'profile-a',
      sourceHash: 'hb',
      sourceSize: 1,
      displayName: 'b',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(env.catalog).replaceCards(
      sourceId: 'src-b',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 1,
          noteId: 1,
          deckId: 1,
          templateOrd: 0,
          noteGuid: 'b1',
        ),
      ],
    );
    await env.service.projectSource();
    final other = OfficialAnkiCourseProjectionService(
      engine: env.fake,
      catalog: env.catalog,
      course: env.course,
      sourceId: 'src-b',
      profileId: 'profile-a',
      flags: env.service.flags,
    );
    _confirmFakeBasic(other);
    await other.projectSource();
    await env.service.deleteProjection();
    expect(
      (await env.store.readOfficialProjectionSummary('src1')).itemCount,
      0,
    );
    expect(
      (await env.store.readOfficialProjectionSummary('src-b')).itemCount,
      greaterThan(0),
    );
    expect(
      officialAnkiCatalogMappingCount(env.catalog.handle, 'profile-a'),
      greaterThan(0),
    );
  });

  test('fromEnvironment flags stay false and CourseProvider hides official', () {
    final flags = OfficialAnkiFeatureFlags.fromEnvironment();
    expect(flags.projection, isFalse);
    expect(flags.courseEntry, isFalse);
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(OfficialAnkiCourseEntry.resetHooks);
    OfficialAnkiCourseEntry.flagsOf = () => flags;
    final provider = CourseProvider();
    expect(provider.sections, isEmpty);
  });
}

Map<String, dynamic> jsonDecodeCompat(String raw) {
  return Map<String, dynamic>.from(
    (const JsonCodec().decode(raw) as Map),
  );
}

class _Env {
  _Env({int cards = 2, this.confirm = true}) {
    catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src1',
      profileId: 'profile-a',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 'src',
      state: 'active',
      backendCommit: '967aa0d578fc75181e292e95326f9b58698da25c',
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
    counters = OfficialAnkiProjectionCounters();
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
      counters: counters,
      store: store,
      jobs: jobs,
    );
    repo = CourseRepository(course);
    if (confirm) {
      _confirmFakeBasic(service);
    }
  }

  final bool confirm;
  late final OfficialAnkiDatabase catalog;
  late final CourseDatabase course;
  late final FakeOfficialAnkiEngine fake;
  late final OfficialAnkiProjectionCounters counters;
  late final OfficialAnkiCourseProjectionStore store;
  late final OfficialAnkiProjectionJobRepository jobs;
  late final OfficialAnkiCourseProjectionService service;
  late final CourseRepository repo;

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
