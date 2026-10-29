import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_lesson_content.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/course/interaction.dart';

import '../../../helpers/in_memory_course_db.dart';

/// ADR 0043 B6 第 5 读挂点（真机 F6）：v2 课时正文派生自卡。
///
/// 上夜教训（ADR 0044）：host 测试必须覆盖用户流
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
          raw.updatesSync
              .listen((update) => courseWrites.add(update.tableName));
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
    await getIt.reset();
  });

  test('flag on: derives flip content from view rows + engine fields',
      () async {
    catalogWrites.clear();
    courseWrites.clear();
    final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

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

  test('answer-linkage: derived ids resolve back to the view cards', () async {
    final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;
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
      expect(cardId, isNotNull, reason: '派生的 interaction 必须能解析回卡: ${item.id}');
      final wordId = item.id.substring(0, item.id.indexOf('-pflip-'));
      expect(cardId, byWord[wordId],
          reason: 'interaction → card 映射必须逐卡正确: ${item.id}');
    }
  });

  test('unknown presentation kind is ignored, card facts decide', () async {
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
    final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;
    expect(lesson, isNotNull);
    // ADR 0057 §1：未知的视图 kind 不再被当成 flip，也不拖垮整课时——
    // 卡级事实（这里是 basicPair）重新决定；本 fixture 下仍是 flip。
    expect(
      lesson!.content.stages.single.items.single.id,
      startsWith('w-7-pflip-'),
      reason: '未知 kind 不阻断派生，展示由卡级解析器重判',
    );
  });

  test('non-v2 lesson id falls through to null (v1 path continues)', () async {
    final outcome = await OfficialAnkiV2LessonContent.lessonFor(
      'some-v1-or-unknown-lesson',
    );
    expect(outcome.lesson, isNull);
    expect(outcome.failure, isNull, reason: '非 v2 课时是正常 miss，不是失败');
  });

  group('a saved adaptation plan is executed from the config area', () {
    CardAdaptationPlan plan({String planId = 'plan-lesson'}) {
      return CardAdaptationPlan(
        planId: planId,
        revision: 1,
        scope: const AdaptationScope(
          sourceId: sourceId,
          notetypeId: 1,
          templateOrdinal: 0,
        ),
        bindings: const <String, int>{'prompt': 0, 'answer': 1},
        front: const <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 0),
        ],
        back: const <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 1),
        ],
      );
    }

    test('a card override pins only that card to the original rendering',
        () async {
      await OfficialAnkiAdaptationStore(engine).writeCardOverride(
        sourceId: sourceId,
        cardId: 7,
        override: const AdaptationCardOverride.original(),
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final ids = [
        for (final item in lesson!.content.stages.single.items) item.id,
      ];
      expect(ids, contains(startsWith('w-7-pcanonicalLink-')));
      expect(
        ids.where((id) => id.startsWith('w-7-pflip-')),
        isEmpty,
        reason: '单卡覆盖只影响这张卡',
      );
      expect(
        ids.where((id) => id.startsWith('w-9-pflip-')),
        isNotEmpty,
        reason: '同组其它卡不受影响',
      );
    });

    test('a manifest whose revision is gone falls back to the original card',
        () async {
      final store = OfficialAnkiAdaptationStore(engine);
      await store.activate(
        sourceId: sourceId,
        scopeKey: adaptationScopeKey(1, 0),
        plan: plan(),
      );
      // 模拟「manifest 已切换，但方案体被删/损坏」：读端不得拼半份方案。
      await engine.setConfig(
        OfficialAnkiAdaptationConfigKeys.plan('plan-lesson', 1),
        null,
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final ids = [
        for (final item in lesson!.content.stages.single.items) item.id,
      ];
      expect(
        ids.where((id) => id.startsWith('w-7-pcanonicalLink-')),
        isNotEmpty,
      );
    });

    test('a broken plan does not stop the rest of the lesson', () async {
      final store = OfficialAnkiAdaptationStore(engine);
      await store.writeCardOverride(
        sourceId: sourceId,
        cardId: 7,
        override: const AdaptationCardOverride.plan(
          planId: 'ghost',
          revision: 9,
        ),
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final ids = [
        for (final item in lesson!.content.stages.single.items) item.id,
      ];
      expect(ids, contains(startsWith('w-7-pcanonicalLink-')));
      expect(ids, contains(startsWith('w-9-pflip-')));
    });

    test('a dictation plan really produces a dictation, per card', () async {
      // 正面字段带音频 + 短答案 → 这张卡满足听写前提（另一张不满足，见下）。
      engine.projectionRowOverrides[7] = const OfficialAnkiProjectionRow(
        cardId: 7,
        noteId: 70,
        noteGuid: 'guid-7',
        notetypeId: 1,
        deckId: 10,
        deckPath: ['Deck A'],
        templateOrdinal: 0,
        tags: [],
        fields: ['merhaba [sound:merhaba.mp3]', '你好'],
        sourceFingerprint: 'row-7-audio',
      );
      final audioSuggestion = OfficialAnkiMappingSuggestion(
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
          OfficialAnkiFieldCandidate(
            role: FieldRole.audio,
            fieldIndex: 0,
            fieldName: 'Front',
            confidence: 1,
            evidence: [],
          ),
        ],
        status: OfficialAnkiMappingStatus.manual,
        notetypeId: 1,
        userConfirmed: true,
        enabledKinds: const ['flip'],
        templateFaces: const [
          OfficialAnkiTemplateFaceFacts(
            ordinal: 0,
            frontFieldOrds: [0],
            backFieldOrds: [1],
          ),
        ],
      );
      seedMappingDecision(
        suggestionsJson: jsonEncode({'1': audioSuggestion.toJson()}),
      );
      await OfficialAnkiAdaptationStore(engine).activate(
        sourceId: sourceId,
        scopeKey: adaptationScopeKey(1, 0),
        plan: CardAdaptationPlan(
          planId: 'plan-dictation',
          revision: 1,
          scope: const AdaptationScope(
            sourceId: sourceId,
            notetypeId: 1,
            templateOrdinal: 0,
          ),
          bindings: const <String, int>{'prompt': 0, 'answer': 1},
          defaultExercise: 'dictation',
          front: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 0),
          ],
          back: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 1),
          ],
        ),
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final items = lesson!.content.stages.single.items;
      final adapted = items.firstWhere((item) => item.id.startsWith('w-7-'));
      expect(adapted, isA<Dictation>(), reason: '方案说这组做听写');
      final dictation = adapted as Dictation;
      expect(dictation.expected, 'merhaba');
      expect(dictation.audioAssets, ['merhaba.mp3']);
      expect(
        items.firstWhere((item) => item.id.startsWith('w-9-')),
        isA<AnkiCard>(),
        reason: '同组里没有正面音频的卡回落翻卡，而不是硬造听写',
      );
    });

    test('plan bindings override the recognizer roles', () async {
      await OfficialAnkiAdaptationStore(engine).activate(
        sourceId: sourceId,
        scopeKey: adaptationScopeKey(1, 0),
        plan: CardAdaptationPlan(
          planId: 'plan-swapped',
          revision: 1,
          scope: const AdaptationScope(
            sourceId: sourceId,
            notetypeId: 1,
            templateOrdinal: 0,
          ),
          // 用户/AI 说这一组反过来读：正面是释义。
          bindings: const <String, int>{'prompt': 1, 'answer': 0},
          front: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 1),
          ],
          back: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 0),
          ],
        ),
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final flip = lesson!.content.stages.single.items
          .firstWhere((item) => item.id.startsWith('w-7-')) as AnkiCard;
      expect(flip.front, '你好', reason: '方案绑定 prompt=字段1');
      expect(flip.back, 'hello');
    });

    test('a layout over unrenderable structure keeps the original card',
        () async {
      engine.projectionRowOverrides[7] = const OfficialAnkiProjectionRow(
        cardId: 7,
        noteId: 70,
        noteGuid: 'guid-7',
        notetypeId: 1,
        deckId: 10,
        deckPath: ['Deck A'],
        templateOrdinal: 0,
        tags: [],
        fields: ['<script>alert(1)</script>', '你好'],
        sourceFingerprint: 'row-7-script',
      );
      await OfficialAnkiAdaptationStore(engine).activate(
        sourceId: sourceId,
        scopeKey: adaptationScopeKey(1, 0),
        plan: CardAdaptationPlan(
          planId: 'plan-script',
          revision: 1,
          scope: const AdaptationScope(
            sourceId: sourceId,
            notetypeId: 1,
            templateOrdinal: 0,
          ),
          bindings: const <String, int>{'prompt': 0, 'answer': 1},
          front: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 0),
          ],
          back: const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 1),
          ],
        ),
      );

      final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;

      expect(lesson, isNotNull);
      final item = lesson!.content.stages.single.items
          .firstWhere((candidate) => candidate.id.startsWith('w-7-'));
      expect(
        item.id,
        startsWith('w-7-pcanonicalLink-'),
        reason: '脚本结构渲染不了，整张卡回原卡而不是渲染半份布局',
      );
    });
  });

  test('missing or corrupt mapping decision is fail-closed', () async {
    // 决策键整个缺失（K10 损坏按 missing 语义）。
    engine.configStore.clear();
    expect((await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson,
        isNull);

    // suggestionsJson 损坏：解码按空处理 → 全部卡无映射 → null，不抛，
    // 且 failure 说明是决策损坏（B1：可区分于普通 miss）。
    seedMappingDecision(suggestionsJson: '{corrupt json');
    final corruptOutcome =
        await OfficialAnkiV2LessonContent.lessonFor(lessonId);
    expect(corruptOutcome.lesson, isNull);
    expect(
      corruptOutcome.failure,
      OfficialAnkiV2LessonDeriveFailure.mappingDecisionCorrupt,
    );
  });

  test('engine absent: null, not a throw', () async {
    OfficialAnkiCompositionRoot.debugEngineOverride = null;
    final lesson = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;
    expect(lesson, isNull);
  });

  test('deterministic: deriving twice yields identical content', () async {
    final first = (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;
    final second =
        (await OfficialAnkiV2LessonContent.lessonFor(lessonId)).lesson;
    expect(
      jsonEncode(second!.content.toJson()),
      jsonEncode(first!.content.toJson()),
      reason: '确定性 shuffle 种子——重复派生稳定',
    );
  });
}
