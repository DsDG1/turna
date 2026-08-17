import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

void main() {
  test('mapping goldens use names and samples only', () {
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back', 'Audio'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fp',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['hello', '你好', '[sound:a.mp3]'],
        ),
      ],
    );
    final suggestion = OfficialAnkiProjectionMapper().suggest(schema: schema);
    expect(suggestion.status, OfficialAnkiMappingStatus.autoCandidate);
    final target = suggestion.candidates
        .firstWhere((c) => c.role == OfficialAnkiFieldRole.targetText);
    expect(target.confidence, greaterThanOrEqualTo(0.90));
    expect(target.evidence, contains('name:front'));
    expect(target.evidence, contains('sample:plain_text'));
    final audio = suggestion.candidates
        .firstWhere((c) => c.role == OfficialAnkiFieldRole.audio);
    expect(audio.evidence, contains('sample:official_av'));
    expect(
      OfficialAnkiProjectionMapper().shortText('<b>Hi</b> [sound:a.mp3]'),
      'Hi',
    );
  });

  test('20-card lessons and Recovered section', () {
    final rows = [
      for (var i = 1; i <= 21; i++)
        OfficialAnkiProjectionRow(
          cardId: i,
          noteId: i,
          noteGuid: 'g$i',
          notetypeId: 1,
          deckId: 10,
          deckPath: const ['Language', 'Unit 1'],
          templateOrdinal: 0,
          tags: const <String>[],
          fields: const ['t', 'n'],
          sourceFingerprint: 'f$i',
        ),
      const OfficialAnkiProjectionRow(
        cardId: 99,
        noteId: 99,
        noteGuid: 'g99',
        notetypeId: 1,
        deckId: 0,
        deckPath: [],
        templateOrdinal: 0,
        tags: <String>[],
        fields: ['t', 'n'],
        sourceFingerprint: 'f99',
      ),
      const OfficialAnkiProjectionRow(
        cardId: 100,
        noteId: 100,
        noteGuid: 'g100',
        notetypeId: 1,
        deckId: 0,
        deckPath: ['A', 'A'],
        templateOrdinal: 0,
        tags: <String>[],
        fields: ['t', 'n'],
        sourceFingerprint: 'f100',
      ),
    ];
    final mapping = OfficialAnkiProjectionMapper().suggest(
      schema: const OfficialAnkiProjectionSchema(
        notetypeId: 1,
        name: 'Basic',
        kind: 'normal',
        fieldNames: ['Front', 'Back'],
        templateNames: ['Card 1'],
        schemaFingerprint: 'fp',
        samples: [
          OfficialAnkiProjectionSample(noteId: 1, fields: ['t', 'n']),
        ],
      ),
    );
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src1',
      profileId: 'profile-a',
      rows: rows,
      mappings: {1: mapping},
    );
    final languageLessons =
        plan.items.map((i) => i.lessonId).where((id) => id.contains('-l')).toSet();
    expect(languageLessons.length, greaterThanOrEqualTo(2));
    expect(plan.issues.where((i) => i.code == 'recovered_deck').length, 2);
    expect(
      plan.items.any((i) => i.sectionId.endsWith('-s0')),
      isTrue,
    );
    expect(
      officialAnkiWordId(profileId: 'profile-a', cardId: 1),
      officialAnkiWordId(profileId: 'profile-a', cardId: 1),
    );
    expect(
      officialAnkiWordId(profileId: 'profile-a', cardId: 1),
      isNot(contains('src1')),
    );
  });

  test('sibling subdecks share one Section and keep distinct Units', () {
    final mapping = _basicMapping();
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src1',
      profileId: 'profile-a',
      mappings: {1: mapping},
      topDeckIds: const {'Language': 7},
      rows: const [
        OfficialAnkiProjectionRow(
          cardId: 1,
          noteId: 1,
          noteGuid: 'g1',
          notetypeId: 1,
          deckId: 11,
          deckPath: ['Language', 'Unit 1'],
          templateOrdinal: 0,
          tags: <String>[],
          fields: ['t', 'n'],
          sourceFingerprint: 'a',
        ),
        OfficialAnkiProjectionRow(
          cardId: 2,
          noteId: 2,
          noteGuid: 'g2',
          notetypeId: 1,
          deckId: 12,
          deckPath: ['Language', 'Unit 2'],
          templateOrdinal: 0,
          tags: <String>[],
          fields: ['t', 'n'],
          sourceFingerprint: 'b',
        ),
      ],
    );
    expect(plan.items, hasLength(2));
    expect(plan.items[0].sectionId, plan.items[1].sectionId);
    expect(plan.items[0].sectionId, officialAnkiSectionId(sourceId: 'src1', topDeckId: 7));
    expect(plan.items[0].unitId, isNot(plan.items[1].unitId));
    expect(plan.items[0].sectionName, 'Language');
  });

  test('unit:: and lesson:: tags win over the 20-card split', () {
    final mapping = _basicMapping();
    final rows = [
      for (var i = 1; i <= 25; i++)
        OfficialAnkiProjectionRow(
          cardId: i,
          noteId: i,
          noteGuid: 'g$i',
          notetypeId: 1,
          deckId: 10,
          deckPath: const ['Language', 'Unit 1'],
          templateOrdinal: 0,
          tags: const ['lesson::greetings', 'unit::intro'],
          fields: const ['t', 'n'],
          sourceFingerprint: 'f$i',
        ),
    ];
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src1',
      profileId: 'profile-a',
      rows: rows,
      mappings: {1: mapping},
    );
    expect(plan.items.map((item) => item.lessonId).toSet(), hasLength(1));
    expect(plan.items.map((item) => item.unitId).toSet(), hasLength(1));
    expect(plan.items.first.lessonName, 'greetings');
    expect(plan.items.first.unitName, 'intro');
  });

  test('confirmed lessonLabel field groups cards into one lesson', () {
    final mapping = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.autoCandidate,
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.targetText,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 0.95,
          evidence: ['name:front'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.nativeText,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 0.94,
          evidence: ['name:back'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.lessonLabel,
          fieldIndex: 2,
          fieldName: 'Lesson',
          confidence: 0.9,
          evidence: ['name:lesson'],
        ),
      ],
    );
    final rows = [
      for (var i = 1; i <= 25; i++)
        OfficialAnkiProjectionRow(
          cardId: i,
          noteId: i,
          noteGuid: 'g$i',
          notetypeId: 1,
          deckId: 10,
          deckPath: const ['Language', 'Unit 1'],
          templateOrdinal: 0,
          tags: const <String>[],
          fields: const ['t', 'n', 'Greetings'],
          sourceFingerprint: 'f$i',
        ),
    ];
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src1',
      profileId: 'profile-a',
      rows: rows,
      mappings: {1: mapping},
    );
    expect(plan.items.map((item) => item.lessonId).toSet(), hasLength(1));
    expect(plan.items.first.lessonName, 'Greetings');
  });

  test('projection service no-op, failed publish, delete rebuild, flags', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
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
    final course = CourseDatabase(NativeDatabase.memory());
    addTearDown(course.close);
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    final counters = OfficialAnkiProjectionCounters();
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      projection: true,
    );
    expect(const OfficialAnkiFeatureFlags().projection, isFalse);
    expect(const OfficialAnkiFeatureFlags().courseEntry, isFalse);
    expect(const OfficialAnkiFeatureFlags().renderer, isFalse);
    final service = OfficialAnkiCourseProjectionService(
      engine: fake,
      catalog: catalog,
      course: course,
      sourceId: 'src1',
      profileId: 'profile-a',
      flags: flags,
      counters: counters,
    );
    _seedCards(catalog, 'src1', 2);
    _confirmFakeBasic(service);
    final first = await service.projectSource();
    expect(first.noop, isFalse);
    expect(first.itemCount, greaterThan(0));
    expect(counters.officialSchedulerWrites, 0);
    expect(counters.legacyCalls, 0);
    final second = await service.projectSource();
    expect(second.noop, isTrue);
    final failed = await service.projectSource(
      mappingVersion: 2,
      failPublish: true,
    );
    expect(failed.failed, isTrue);
    final still = await course.customSelect(
      'SELECT COUNT(*) AS n FROM official_anki_projection_index WHERE source_id = ?',
      variables: [Variable('src1')],
    ).getSingle();
    expect(still.data['n'], greaterThan(0));
    await service.deleteProjection();
    final empty = await course.customSelect(
      'SELECT COUNT(*) AS n FROM official_anki_projection_index WHERE source_id = ?',
      variables: [Variable('src1')],
    ).getSingle();
    expect(empty.data['n'], 0);
    final rebuilt = await service.projectSource(mappingVersion: 2);
    expect(rebuilt.itemCount, first.itemCount);
    expect(
      officialAnkiCatalogMappingCount(catalog.handle, 'profile-a'),
      greaterThan(0),
    );
  });

  test('catalog v2 to v3 keeps sources and CourseDatabase v16 is derived only', () {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-keep',
      profileId: 'p',
      sourceHash: 'hh',
      sourceSize: 2,
      displayName: 'keep',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 2,
    );
    final version = catalog.handle.select('PRAGMA user_version').first;
    expect(version['user_version'], 5);
    final sources = catalog.handle.select('SELECT source_id FROM anki_sources');
    expect(sources.first['source_id'], 'src-keep');
    expect(
      catalog.handle.select(
        "SELECT name FROM sqlite_master WHERE name = 'anki_projection_mappings'",
      ),
      isNotEmpty,
    );
  });

  test('cancel does not publish a half-built tree', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-c',
      profileId: 'p',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 'c',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    final course = CourseDatabase(NativeDatabase.memory());
    addTearDown(course.close);
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final service = OfficialAnkiCourseProjectionService(
      engine: fake,
      catalog: catalog,
      course: course,
      sourceId: 'src-c',
      profileId: 'p',
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
    );
    OfficialAnkiSourceDao(catalog).replaceCards(
      sourceId: 'src-c',
      cards: const [
        OfficialAnkiCardDescriptor(
          cardId: 1,
          noteId: 1,
          deckId: 1,
          templateOrd: 0,
          noteGuid: 'g1',
        ),
      ],
    );
    service.debugCancelImmediately = true;
    final result = await service.projectSource();
    expect(result.cancelled, isTrue);
    final count = await course.customSelect(
      'SELECT COUNT(*) AS n FROM official_anki_projection_index',
    ).getSingle();
    expect(count.data['n'], 0);
  });

  test('user-confirmed mapping JSON is not overwritten on reimport', () async {
    final env = _serviceEnv();
    addTearDown(env.dispose);
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fake-basic',
    );
    const confirmed = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.needsConfirm,
      candidates: [
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.targetText,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 0.99,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: OfficialAnkiFieldRole.nativeText,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 0.99,
          evidence: ['user'],
        ),
      ],
    );
    env.service.confirmMapping(schema: schema, suggestion: confirmed);
    await env.service.projectSource();
    await env.service.projectSource();
    final stored = env.catalog.handle.select(
      'SELECT mapping_json, user_confirmed, schema_fingerprint '
      'FROM anki_projection_mappings WHERE profile_id = ? AND notetype_id = 1',
      ['profile-a'],
    ).first;
    expect(stored['user_confirmed'], 1);
    expect(stored['schema_fingerprint'], 'fake-basic');
    expect(stored['mapping_json'] as String, contains('"evidence":["user"]'));
    expect(stored['mapping_json'] as String, contains('"fieldIndex":1'));
  });

  test('projectSource pages the full allowlist and publishes the union', () async {
    final env = _serviceEnv(cards: 501);
    addTearDown(env.dispose);
    final result = await env.service.projectSource();
    expect(result.failed, isFalse);
    expect(env.fake.projectionBatchCalls, 3);
    expect(env.fake.projectionBatchSizes, [200, 200, 101]);
    expect(result.rowCount, 501);
    final index = await env.course.customSelect(
      'SELECT COUNT(*) AS n FROM official_anki_projection_index WHERE source_id = ?',
      variables: [Variable('src1')],
    ).getSingle();
    expect(index.data['n'], 501);
    final sections = await env.course.select(env.course.sections).get();
    expect(sections, isNotEmpty);
    final lessons = await env.course.select(env.course.lessons).get();
    expect(lessons, isNotEmpty);
    final contents = await env.course.select(env.course.lessonContents).get();
    expect(contents, isNotEmpty);
    expect(contents.first.contentJson.contains('qfmt'), isFalse);
    expect(contents.first.contentJson.contains('afmt'), isFalse);
  });

  test('locked placement overrides survive a rebuild', () async {
    final env = _serviceEnv();
    addTearDown(env.dispose);
    await env.service.projectSource();
    final first = await env.course.customSelect(
      'SELECT section_id, unit_id, lesson_id FROM official_anki_projection_index '
      'WHERE source_id = ? AND card_id = 1',
      variables: [Variable('src1')],
    ).getSingle();
    env.service.lockPlacement(
      cardId: 1,
      sectionKey: first.read<String>('section_id'),
      unitKey: first.read<String>('unit_id'),
      lessonKey: first.read<String>('lesson_id'),
    );
    env.fake.projectionRowOverrides[1] = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'guid-1',
      notetypeId: 1,
      deckId: 99,
      deckPath: const ['Other', 'Moved'],
      templateOrdinal: 0,
      tags: const <String>[],
      fields: const ['hello', '你好'],
      sourceFingerprint: 'moved-1',
    );
    final rebuilt = await env.service.projectSource();
    expect(rebuilt.noop, isFalse);
    final again = await env.course.customSelect(
      'SELECT section_id, unit_id, lesson_id FROM official_anki_projection_index '
      'WHERE source_id = ? AND card_id = 1',
      variables: [Variable('src1')],
    ).getSingle();
    expect(again.read<String>('section_id'), first.read<String>('section_id'));
    expect(again.read<String>('unit_id'), first.read<String>('unit_id'));
    expect(again.read<String>('lesson_id'), first.read<String>('lesson_id'));
    final tree = await env.course.customSelect(
      'SELECT COUNT(*) AS n FROM sections WHERE id = ?',
      variables: [Variable(first.read<String>('section_id'))],
    ).getSingle();
    expect(tree.data['n'], 1);
  });
}

OfficialAnkiMappingSuggestion _basicMapping() {
  return OfficialAnkiProjectionMapper().suggest(
    schema: const OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fp',
      samples: [
        OfficialAnkiProjectionSample(noteId: 1, fields: ['t', 'n']),
      ],
    ),
  );
}

class _ServiceEnv {
  _ServiceEnv({int cards = 2}) {
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
    _seedCards(catalog, 'src1', cards);
    course = CourseDatabase(NativeDatabase.memory());
    fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: cards, cards: cards);
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
    );
    _confirmFakeBasic(service);
  }

  late final OfficialAnkiDatabase catalog;
  late final CourseDatabase course;
  late final FakeOfficialAnkiEngine fake;
  late final OfficialAnkiCourseProjectionService service;

  void dispose() {
    catalog.close();
    course.close();
  }
}

_ServiceEnv _serviceEnv({int cards = 2}) => _ServiceEnv(cards: cards);

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

void _seedCards(OfficialAnkiDatabase catalog, String sourceId, int cards) {
  OfficialAnkiSourceDao(catalog).replaceCards(
    sourceId: sourceId,
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

