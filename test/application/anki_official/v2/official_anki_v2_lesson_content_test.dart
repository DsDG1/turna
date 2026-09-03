import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_course_read.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_lesson_content.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';

import '../../../helpers/in_memory_course_db.dart';

/// step4.md B6 第 5 读挂点（真机 F6）：v2 课时正文派生自卡。
///
/// 上夜教训（v2-first-device-findings.md §四）：host 测试必须覆盖用户流
/// ——本文件的核心断言不是「派生出了东西」，而是「派生出的 interaction
/// 能被复习链解析回正确的卡」（答题↔卡联动）+ 零写入纪律。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;
  final catalogWrites = <String>{};
  final courseWrites = <String>{};

  const sourceId = 'src-v2-content';
  const lessonId = 'official-anki-src-v2-content-l-abc-p1';

  const v2On = OfficialAnkiFeatureFlags.productionAndroid;

  OfficialAnkiMappingSuggestion suggestion() => OfficialAnkiMappingSuggestion(
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

  void seedMappingDecision({String suggestionsJson = 'pending'}) {
    engine.configStore[OfficialAnkiV2ConfigKeys.importMapping(sourceId)] = {
      'schema': 1,
      'confirmed': [1],
      'skipped': [],
      'suggestions': suggestionsJson == 'pending'
          ? jsonEncode({'1': suggestion().toJson()})
          : suggestionsJson,
    };
  }

  setUp(() async {
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.updatesSync.listen((update) => courseWrites.add(update.tableName));
        },
      ),
    );
    catalog.handle.updatesSync.listen(
      (update) => catalogWrites.add(update.tableName),
    );
    if (!getIt.isRegistered<CourseDatabase>()) {
      getIt.registerSingleton<CourseDatabase>(course);
    }
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = OfficialAnkiPaths(
      profileId: 'profile-v2-content',
      profileRoot: Directory.systemTemp.createTempSync('turna-v2-content-'),
    );

    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: sourceId,
      profileId: 'profile-v2-content',
      sourceHash: 'hash-content',
      sourceSize: 10,
      displayName: 'Content',
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
          sectionId: 'official-anki-src-v2-content-s-1',
          unitId: 'official-anki-src-v2-content-u-1',
          lessonId: lessonId,
          lessonKey: 'Lesson A',
          presentationKind: 'flip',
          sourceHash: 'hash-content',
        ),
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 9,
          noteId: 90,
          deckId: 10,
          wordId: 'w-9',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-content-s-1',
          unitId: 'official-anki-src-v2-content-u-1',
          lessonId: lessonId,
          lessonKey: 'Lesson A',
          presentationKind: 'flip',
          sourceHash: 'hash-content',
        ),
      ],
      rebuiltAtMillis: 1,
    );

    engine = FakeOfficialAnkiEngine();
    engine.cards[7] = OfficialAnkiCardDescriptor(
      cardId: 7,
      noteId: 70,
      deckId: 10,
      templateOrd: 0,
      noteGuid: 'guid-7',
      notetypeId: 1,
    );
    engine.cards[9] = OfficialAnkiCardDescriptor(
      cardId: 9,
      noteId: 90,
      deckId: 10,
      templateOrd: 0,
      noteGuid: 'guid-9',
      notetypeId: 1,
    );
    OfficialAnkiCompositionRoot.debugEngineOverride = engine;
    seedMappingDecision();
  });

  tearDown(() async {
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    OfficialAnkiCompositionRoot.locatorPaths = null;
    OfficialAnkiCompositionRoot.debugEngineOverride = null;
    OfficialAnkiV2LessonContent.flagsOf =
        () => OfficialAnkiFeatureFlags.current;
    OfficialAnkiV2CourseRead.flagsOf =
        () => OfficialAnkiFeatureFlags.current;
    await getIt.reset();
  });

  test('flag on: derives flip content from view rows + engine fields',
      () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    catalogWrites.clear();
    courseWrites.clear();
    final lesson = await OfficialAnkiV2LessonContent.lessonFor(lessonId);

    expect(lesson, isNotNull, reason: 'v2 课时必须派生出正文（F6）');
    expect(lesson!.id, lessonId);
    expect(lesson.name, 'Lesson A');
    expect(lesson.content.stages, hasLength(1));
    final stage = lesson.content.stages.single;
    expect(stage.id, 'official-stage-0');
    expect(stage.items, hasLength(2));
    // item id 由视图行 wordId 铸造（officialAnkiItemId），kind 在 id 里可见。
    expect(stage.items.first.id, startsWith('w-7-pflip-'));
    expect(stage.items.last.id, startsWith('w-9-pflip-'));
    // 假引擎投影行的字段 ['hello','你好'] 经映射决策进 front/back。
    expect((stage.items.first as AnkiCard).front, 'hello');
    expect((stage.items.first as AnkiCard).back, '你好');

    // 零写入纪律：派生是纯读面（catalog / course.db 均零写入）。
    expect(catalogWrites, isEmpty, reason: '派生不得写 catalog');
    expect(courseWrites, isEmpty, reason: '派生不得写 course.db');
  });

  test('answer-linkage: derived ids resolve back to the view cards',
      () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    OfficialAnkiV2CourseRead.flagsOf = () => v2On;
    final lesson = await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    expect(lesson, isNotNull);

    // 复习链 P0 解析面（复习页/练习中心共用的 lesson card index）。
    final index = await OfficialAnkiLessonCardIndex.resolveForLesson(lessonId);
    expect(index, isNotNull, reason: 'v2 分支应命中视图');
    final byWord = {
      'w-7': 7,
      'w-9': 9,
    };
    for (final item in lesson!.content.stages.single.items) {
      final cardId = index!.cardIdForInteractionId(item.id);
      expect(cardId, isNotNull,
          reason: '派生的 interaction 必须能解析回卡: ${item.id}');
      final wordId =
          item.id.substring(0, item.id.indexOf('-pflip-'));
      expect(cardId, byWord[wordId],
          reason: 'interaction → card 映射必须逐卡正确: ${item.id}');
    }
  });

  test('unknown presentation kind degrades to showWord', () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    await OfficialAnkiV2ViewStore(course).replaceAll(
      rows: const [
        OfficialAnkiV2ViewRow(
          sourceId: sourceId,
          cardId: 7,
          noteId: 70,
          deckId: 10,
          wordId: 'w-7',
          sectionKey: 'Deck A',
          sectionId: 'official-anki-src-v2-content-s-1',
          unitId: 'official-anki-src-v2-content-u-1',
          lessonId: lessonId,
          lessonKey: 'Lesson A',
          presentationKind: 'not-a-kind',
          sourceHash: 'hash-content',
        ),
      ],
      rebuiltAtMillis: 2,
    );
    final lesson = await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    expect(lesson, isNotNull);
    expect(
      lesson!.content.stages.single.items.single.id,
      startsWith('w-7-pshowWord-'),
      reason: '损坏/未知的 kind 降 showWord，不拖垮整课时',
    );
  });

  test('non-v2 lesson id falls through to null (v1 path continues)',
      () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    final lesson = await OfficialAnkiV2LessonContent.lessonFor(
      'some-v1-or-unknown-lesson',
    );
    expect(lesson, isNull);
  });

  test('missing or corrupt mapping decision is fail-closed', () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;

    // 决策键整个缺失（K10 损坏按 missing 语义）。
    engine.configStore.clear();
    expect(await OfficialAnkiV2LessonContent.lessonFor(lessonId), isNull);

    // suggestionsJson 损坏：解码按空处理 → 全部卡无映射 → null，不抛。
    seedMappingDecision(suggestionsJson: '{corrupt json');
    expect(await OfficialAnkiV2LessonContent.lessonFor(lessonId), isNull);
  });

  test('engine absent: null, not a throw', () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    OfficialAnkiCompositionRoot.debugEngineOverride = null;
    final lesson = await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    expect(lesson, isNull);
  });

  test('deterministic: deriving twice yields identical content', () async {
    OfficialAnkiV2LessonContent.flagsOf = () => v2On;
    final first = await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    final second = await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    expect(
      jsonEncode(second!.content.toJson()),
      jsonEncode(first!.content.toJson()),
      reason: '确定性 shuffle 种子——重复派生稳定',
    );
  });
}
