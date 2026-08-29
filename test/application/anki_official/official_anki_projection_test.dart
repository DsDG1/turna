import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

OfficialAnkiMappingSuggestion _suggest(OfficialAnkiProjectionSchema schema) {
  return officialAnkiSuggestMapping(schema, const CardRecognizer());
}

void main() {
  test('structure + lexicon binds Front/Back/Audio with auto band', () {
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
        OfficialAnkiProjectionSample(
          noteId: 2,
          fields: ['world', '世界', '[sound:b.mp3]'],
        ),
      ],
    );
    final suggestion = _suggest(schema);
    expect(suggestion.status, OfficialAnkiMappingStatus.auto);
    expect(suggestion.archetype, 'basicPair');
    final prompt = suggestion.candidates
        .firstWhere((c) => c.role == FieldRole.prompt);
    expect(prompt.fieldName, 'Front');
    expect(prompt.confidence, greaterThanOrEqualTo(0.85));
    expect(prompt.evidence, contains('lexicon:exact (Front)'));
    expect(prompt.evidence, contains('sample:plain_text'));
    final audio = suggestion.candidates
        .firstWhere((c) => c.role == FieldRole.audio);
    expect(audio.evidence, contains('sample:sound_ref'));
  });

  test('custom vocab names bind through position and land in review', () {
    // Doc 37 R1: when the lexicon does not know the names, structure and
    // position still produce a usable binding — the band honestly says
    // "review" instead of faking confidence.
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 3,
      name: 'eggrolls-JLPT10k',
      kind: 'normal',
      fieldNames: ['VocabKanji', 'VocabDefSC', 'VocabAudio'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'egg',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['食べる', '吃', '[sound:x.mp3]'],
        ),
        OfficialAnkiProjectionSample(
          noteId: 2,
          fields: ['飲む', '喝', '[sound:y.mp3]'],
        ),
      ],
    );
    final suggestion = _suggest(schema);
    expect(suggestion.status, OfficialAnkiMappingStatus.review);
    expect(suggestion.archetype, 'basicPair');
    expect(suggestion.role(FieldRole.prompt)?.fieldName, 'VocabKanji');
    expect(suggestion.role(FieldRole.response)?.fieldName, 'VocabDefSC');
    expect(suggestion.role(FieldRole.audio)?.fieldName, 'VocabAudio');
  });

  test('templateFacts strengthen the pair to auto for unknown names', () {
    // Same unknown names, but the engine now tells us which fields each
    // template face references: the structural signal closes the gap the
    // lexicon left (contract 1.9 payoff).
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 3,
      name: 'eggrolls-JLPT10k',
      kind: 'normal',
      fieldNames: ['VocabKanji', 'VocabDefSC', 'VocabAudio'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'egg',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['食べる', '吃', '[sound:x.mp3]'],
        ),
        OfficialAnkiProjectionSample(
          noteId: 2,
          fields: ['飲む', '喝', '[sound:y.mp3]'],
        ),
      ],
      templateFacts: OfficialAnkiTemplateFacts(
        hash: 'facts-1',
        templates: [
          OfficialAnkiTemplateFact(
            ord: 0,
            name: 'Card 1',
            frontFields: [0],
            backFields: [0, 1, 2],
          ),
        ],
        reqs: [
          OfficialAnkiCardRequirement(cardOrd: 0, kind: 'ANY', fieldOrds: [0]),
        ],
      ),
    );
    final suggestion = _suggest(schema);
    expect(suggestion.status, OfficialAnkiMappingStatus.auto);
    expect(suggestion.role(FieldRole.prompt)?.fieldName, 'VocabKanji');
    expect(suggestion.role(FieldRole.response)?.fieldName, 'VocabDefSC');
    expect(suggestion.templateFactsHash, 'facts-1');
    expect(suggestion.recognizerVersion, 1);
    expect(suggestion.lexiconVersion, 1);
  });

  test('cloze Text/Extra does not require a separate answer field', () {
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 4,
      name: 'Cloze',
      kind: 'cloze',
      fieldNames: ['Text', 'Extra'],
      templateNames: ['Cloze'],
      schemaFingerprint: 'cz',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['The {{c1::sun}}', ''],
        ),
      ],
    );
    final suggestion = _suggest(schema);
    expect(suggestion.singleFieldMode, isTrue);
    expect(suggestion.status, OfficialAnkiMappingStatus.auto);
    expect(suggestion.archetype, 'cloze');
    expect(suggestion.role(FieldRole.prompt)?.fieldName, 'Text');
  });

  test('image occlusion binds the image fields without samples', () {
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 5,
      name: 'Image Occlusion',
      kind: 'normal',
      fieldNames: ['Header', 'Image', 'Occlusion', 'Back Extra'],
      templateNames: ['IO'],
      schemaFingerprint: 'io',
      samples: [],
    );
    final suggestion = _suggest(schema);
    // No samples: the default pair rule wins with a review band; the
    // occlusion/image fields bind through the lexicon.
    expect(suggestion.archetype, 'basicPair');
    expect(suggestion.status, OfficialAnkiMappingStatus.review);
    expect(suggestion.role(FieldRole.image), isNotNull);
    expect(suggestion.role(FieldRole.prompt)?.fieldName, 'Header');
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
    final mapping = _basicMapping();
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
      status: OfficialAnkiMappingStatus.manual,
      archetype: 'basicPair',
      recognitionConfidence: 1,
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 0.95,
          evidence: ['lexicon:exact'],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.response,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 0.94,
          evidence: ['lexicon:exact'],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.lessonLabel,
          fieldIndex: 2,
          fieldName: 'Lesson',
          confidence: 0.9,
          evidence: ['lexicon:exact'],
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
    expect(version['user_version'], kOfficialAnkiCatalogSchemaVersion);
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
      status: OfficialAnkiMappingStatus.review,
      candidates: [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 0.99,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.response,
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
      'SELECT mapping_json, user_confirmed, schema_fingerprint, status '
      'FROM anki_projection_mappings WHERE profile_id = ? AND notetype_id = 1',
      ['profile-a'],
    ).first;
    expect(stored['user_confirmed'], 1);
    expect(stored['schema_fingerprint'], 'fake-basic');
    expect(stored['status'], 'manual');
    expect(stored['mapping_json'] as String, contains('"evidence":["user"]'));
    expect(stored['mapping_json'] as String, contains('"fieldIndex":1'));
  });

  test('legacy mapping JSON parses through the role/status rename', () {
    final parsed = OfficialAnkiMappingSuggestion.fromJson(const {
      'status': 'needsConfirm',
      'direction': 'targetToNative',
      'candidates': [
        {
          'role': 'targetText',
          'fieldIndex': 0,
          'fieldName': 'Front',
          'confidence': 0.92,
          'evidence': ['name:front'],
        },
        {
          'role': 'optionPool',
          'fieldIndex': 2,
          'fieldName': 'Choices',
          'confidence': 0.88,
          'evidence': [],
        },
      ],
    });
    expect(parsed.status, OfficialAnkiMappingStatus.review);
    expect(parsed.direction, 'promptToResponse');
    expect(parsed.role(FieldRole.prompt)?.fieldName, 'Front');
    expect(parsed.role(FieldRole.options)?.fieldName, 'Choices');
    expect(parsed.recognizerVersion, 0);
    expect(parsed.cardArchetype, CardArchetype.basicPair);
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

  test('Chinese fields 正面 and 反面 bind through the zh lexicon', () {
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 2,
      name: '中文基础',
      kind: 'normal',
      fieldNames: ['正面', '反面', '发音', '例句'],
      templateNames: ['卡片 1'],
      schemaFingerprint: 'zh-fp',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['apple', '苹果', 'píngguǒ', 'This is an apple.'],
        ),
        OfficialAnkiProjectionSample(
          noteId: 2,
          fields: ['pear', '梨', 'lí', 'This is a pear.'],
        ),
      ],
    );
    final suggestion = _suggest(schema);
    expect(suggestion.status, OfficialAnkiMappingStatus.auto);
    expect(suggestion.archetype, 'basicPair');
    expect(
      suggestion.candidates
          .firstWhere((c) => c.role == FieldRole.prompt)
          .confidence,
      greaterThanOrEqualTo(0.85),
    );
    expect(
      suggestion.candidates
          .firstWhere((c) => c.role == FieldRole.response)
          .confidence,
      greaterThanOrEqualTo(0.85),
    );
    expect(suggestion.role(FieldRole.audio)?.fieldName, '发音');
    expect(suggestion.role(FieldRole.example)?.fieldName, '例句');
  });

  test('Basic 20 cards project to flip cards and 0 canonicalLinks', () {
    final rows = [
      for (var i = 1; i <= 20; i++)
        OfficialAnkiProjectionRow(
          cardId: i,
          noteId: i,
          noteGuid: 'guid-$i',
          notetypeId: 1,
          deckId: 1,
          deckPath: const ['Default'],
          templateOrdinal: 0,
          tags: const <String>[],
          fields: ['word-$i', 'meaning-$i'],
          sourceFingerprint: 'fp-$i',
        ),
    ];
    final mapping = _basicMapping().copyWith(enabledKinds: ['flip']);
    final plan = OfficialAnkiProjectionProjector().project(
      sourceId: 'src-basic',
      profileId: 'profile-a',
      rows: rows,
      mappings: {1: mapping},
    );
    expect(plan.items, hasLength(20));
    expect(plan.items.every((item) => item.kind == OfficialAnkiProjectionKind.flip), isTrue);
    expect(plan.items.any((item) => item.kind == OfficialAnkiProjectionKind.canonicalLink), isFalse);
  });

  test('untrusted mapping with low recognition confidence falls to canonicalLink', () {
    const row = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'g1',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['Default'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: ['cat', '猫'],
      sourceFingerprint: 'fp1',
    );
    final mapping = OfficialAnkiMappingSuggestion(
      candidates: const [],
      status: OfficialAnkiMappingStatus.review,
      archetype: 'basicPair',
      recognitionConfidence: 0.5,
    );
    final payloads = OfficialAnkiProjectionPayloads();
    final values = payloads.values(row, mapping);
    final kinds = payloads.kindsFor(values: values, mapping: mapping, typeAnswerEnabled: false);
    expect(kinds, [OfficialAnkiProjectionKind.canonicalLink]);
  });

  test('confirmed mapping keeps projecting flip without recognition fields', () {
    const row = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'g1',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['Default'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: ['cat', '猫'],
      sourceFingerprint: 'fp1',
    );
    // A legacy user-confirmed row: no archetype, no confidence, but the
    // manual status means the user owns it.
    final mapping = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.manual,
      candidates: const [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 1,
          evidence: ['user'],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.response,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 1,
          evidence: ['user'],
        ),
      ],
    );
    final payloads = OfficialAnkiProjectionPayloads();
    final values = payloads.values(row, mapping);
    final kinds = payloads.kindsFor(values: values, mapping: mapping, typeAnswerEnabled: false);
    expect(kinds, contains(OfficialAnkiProjectionKind.flip));
    expect(kinds, isNot(contains(OfficialAnkiProjectionKind.canonicalLink)));
  });

  test('Unparsed embedded options fallback to canonicalLink and never MCQ', () {
    const row = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'g1',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['Default'],
      templateOrdinal: 0,
      tags: <String>[],
      fields: ['Which is right?\nA. Only A\nB. Only B', 'Unparsable Answer Key'],
      sourceFingerprint: 'fp1',
    );
    final mapping = _basicMapping();
    final payloads = OfficialAnkiProjectionPayloads();
    final values = payloads.values(row, mapping);
    final kinds = payloads.kindsFor(values: values, mapping: mapping, typeAnswerEnabled: false);
    expect(kinds, [OfficialAnkiProjectionKind.canonicalLink]);
    expect(kinds, isNot(contains(OfficialAnkiProjectionKind.multipleChoice)));
  });

  test('option-pool notetype projects a real MCQ with aligned answer', () {
    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 7,
      name: '题库单选',
      kind: 'normal',
      fieldNames: ['题干', '选项', '答案'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'mcq',
      samples: [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['法国的首都？', '巴黎|伦敦|柏林|马德里', '巴黎'],
        ),
        OfficialAnkiProjectionSample(
          noteId: 2,
          fields: ['土耳其的首都？', '安卡拉|伊斯坦布尔|伊兹密尔', '安卡拉'],
        ),
      ],
    );
    final suggestion = _suggest(schema);
    expect(suggestion.archetype, 'choice');
    expect(suggestion.status, OfficialAnkiMappingStatus.auto);
    expect(suggestion.role(FieldRole.prompt)?.fieldName, '题干');
    expect(suggestion.role(FieldRole.options)?.fieldName, '选项');
    expect(suggestion.role(FieldRole.response)?.fieldName, '答案');
  });

  test('cloze markers inside a basicPair card upgrade that card to fillBlank',
      () {
    final mapping = _basicMapping();
    const row = OfficialAnkiProjectionRow(
      cardId: 1,
      noteId: 1,
      noteGuid: 'g1',
      notetypeId: 1,
      deckId: 1,
      deckPath: ['Default'],
      templateOrdinal: 1,
      tags: <String>[],
      fields: ['The capital is {{c1::Paris}} and the river is {{c2::Seine}}.', ''],
      sourceFingerprint: 'fp1',
    );
    final payloads = OfficialAnkiProjectionPayloads();
    final values = payloads.values(row, mapping);
    expect(values.archetype, CardArchetype.cloze);
    // Ordinal 1 selects the c2 deletion, not the first marker.
    expect(values.clozeAnswer, 'Seine');
    expect(values.clozeSentence, contains('_____'));
    final kinds = payloads.kindsFor(values: values, mapping: mapping, typeAnswerEnabled: false);
    expect(kinds, [OfficialAnkiProjectionKind.fillBlank]);
  });
}

OfficialAnkiMappingSuggestion _basicMapping() {
  return _suggest(
    const OfficialAnkiProjectionSchema(
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
    suggestion: _suggest(schema),
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
