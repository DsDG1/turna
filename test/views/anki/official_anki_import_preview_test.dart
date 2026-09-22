import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_done_step.dart';
import 'package:turna/views/anki/import_wizard/modern_anki_import_preview.dart';
import 'package:turna/views/anki/import_wizard/study_preset_selector.dart';

void main() {
  testWidgets('modern preview shows course overview, stats and deck tree',
      (tester) async {
    final controller = _StubController();
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Biology.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 42,
      noteCount: 42,
      decks: const [
        OfficialAnkiDeckNode(
            deckId: 1, name: 'Biology::Genetics::Mendel', level: 1),
      ],
      cardCountByDeck: const {1: 42},
      schemas: [
        OfficialAnkiProjectionSchema(
          notetypeId: 1,
          name: 'Basic',
          kind: 'normal',
          fieldNames: const ['Front', 'Back'],
          templateNames: const ['Card 1'],
          schemaFingerprint: 'fp',
          samples: const [
            OfficialAnkiProjectionSample(
              noteId: 1,
              fields: ['Trait', '性状'],
            ),
          ],
        ),
      ],
      suggestions: const {
        1: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.auto,
          archetype: 'basicPair',
          recognitionConfidence: 0.95,
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.prompt,
              fieldIndex: 0,
              fieldName: 'Front',
              confidence: 0.9,
              evidence: ['lexicon:exact (Front)'],
            ),
            OfficialAnkiFieldCandidate(
              role: FieldRole.response,
              fieldIndex: 1,
              fieldName: 'Back',
              confidence: 0.9,
              evidence: ['lexicon:exact (Back)'],
            ),
          ],
        ),
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
          error: null,
        ),
      ),
    ));

    // 1. 验证课程概览头部与卡片统计（标题用文件名，不再用树的第一个根）
    expect(find.text('Biology.apkg'), findsOneWidget);
    expect(find.text('42'), findsWidgets);
    expect(find.text('学习模式设定'), findsOneWidget);

    // 2. 验证学习模式三大卡片
    expect(find.text('智能互动练习'), findsWidgets);
    expect(find.text('经典闪卡翻面'), findsOneWidget);
    expect(find.text('原卡官方保真'), findsOneWidget);

    // 3. 验证多级目录树层级节点（题型行把目录顶到首屏之外）
    await tester.scrollUntilVisible(find.text('完整章节目录'), 400);
    expect(find.text('完整章节目录'), findsOneWidget);
    expect(find.text('Mendel'), findsOneWidget);

    // 4. 验证底部操作按钮
    expect(find.text('开始导入'), findsOneWidget);
  });

  testWidgets('switching study preset mode updates suggestions',
      (tester) async {
    final controller = _RecordingController();
    final schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: const ['Front', 'Back'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
      samples: const [],
    );
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Vocab.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 10,
      noteCount: 10,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Vocab', level: 1),
      ],
      cardCountByDeck: const {1: 10},
      schemas: [schema],
      suggestions: const {
        1: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.auto,
          archetype: 'basicPair',
          enabledKinds: ['multipleChoice', 'flip'],
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.prompt,
              fieldIndex: 0,
              fieldName: 'Front',
              confidence: 0.9,
              evidence: [],
            ),
            OfficialAnkiFieldCandidate(
              role: FieldRole.response,
              fieldIndex: 1,
              fieldName: 'Back',
              confidence: 0.9,
              evidence: [],
            ),
          ],
        ),
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    // 全局预设只改未确认行，不把该行标成 userConfirmed。
    await tester.tap(find.text('经典闪卡翻面'));
    await tester.pump();

    expect(controller.confirmedMappings, isEmpty);
    expect(controller.unconfirmedKinds, hasLength(1));
    expect(controller.unconfirmedKinds.single.$1.notetypeId, 1);
    expect(controller.unconfirmedKinds.single.$2, contains('flip'));
    expect(
      controller.unconfirmedKinds.single.$2,
      isNot(contains('multipleChoice')),
    );
  });

  testWidgets('blocking schema displays warning and allows in-place picking',
      (tester) async {
    final controller = _RecordingController();
    final schema = OfficialAnkiProjectionSchema(
      notetypeId: 99,
      name: 'ConfusingTemplate',
      kind: 'normal',
      fieldNames: const ['CustomCol1', 'CustomCol2'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
      samples: const [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: ['Sample Question', 'Sample Answer'],
        ),
      ],
    );

    // 没有 prompt 角色绑定，触发 blocking
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Exam.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 5,
      noteCount: 5,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Exam', level: 1),
      ],
      schemas: [schema],
      suggestions: const {
        99: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.review,
          archetype: 'basicPair',
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.ignored,
              fieldIndex: 0,
              fieldName: 'CustomCol1',
              confidence: 0.2,
              evidence: [],
            ),
          ],
        ),
      },
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    // 1. 验证阻断提示条显示
    await tester.ensureVisible(find.text('选正面'));
    expect(find.textContaining('需要指定正面字段'), findsOneWidget);
    expect(find.text('选正面'), findsOneWidget);
    expect(find.text('跳过这类'), findsOneWidget);

    // 2. 点击「选正面」弹出 BottomSheet
    await tester.tap(find.text('选正面'));
    await tester.pumpAndSettle();

    expect(find.text('选择卡片正面（ConfusingTemplate）'), findsOneWidget);
    expect(find.text('CustomCol1'), findsOneWidget);
    expect(find.text('CustomCol2'), findsOneWidget);

    // 3. 点击「CustomCol1」作为正面
    await tester.tap(find.text('CustomCol1'));
    await tester.pumpAndSettle();

    // 4. 验证 controller 收到了更新，且分配了 prompt
    expect(controller.confirmedMappings.isNotEmpty, isTrue);
    final updated = controller.confirmedMappings.last.$2;
    expect(updated.role(FieldRole.prompt)?.fieldName, 'CustomCol1');
    expect(updated.role(FieldRole.response)?.fieldName, 'CustomCol2');
  });

  testWidgets(
      'shows choice badge and clicking chapter node opens mcq preview sheet',
      (tester) async {
    final controller = _RecordingController();
    final schema = OfficialAnkiProjectionSchema(
      notetypeId: 10,
      name: 'ExamMCQ',
      kind: 'normal',
      fieldNames: const [
        'Question',
        'OptionA',
        'OptionB',
        'OptionC',
        'OptionD',
        'Answer'
      ],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp_mcq',
      samples: const [
        OfficialAnkiProjectionSample(
          noteId: 1,
          fields: [
            '我国第一部社会主义类型的宪法是哪一年颁布的？',
            '1949年',
            '1954年',
            '1978年',
            '1982年',
            'B',
          ],
        ),
      ],
    );

    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Politics.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 50,
      noteCount: 50,
      decks: const [
        OfficialAnkiDeckNode(
            deckId: 1, name: 'Politics::Constitution', level: 1),
      ],
      cardCountByDeck: const {1: 50},
      schemas: [schema],
      suggestions: const {
        10: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.auto,
          archetype: 'choice',
          enabledKinds: ['multipleChoice', 'flip'],
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.prompt,
              fieldIndex: 0,
              fieldName: 'Question',
              confidence: 0.9,
              evidence: [],
            ),
            OfficialAnkiFieldCandidate(
              role: FieldRole.response,
              fieldIndex: 5,
              fieldName: 'Answer',
              confidence: 0.9,
              evidence: [],
            ),
          ],
        ),
      },
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    // 1. 验证顶部显示了选择题识别徽章
    expect(find.text('选择题已自动识别'), findsOneWidget);

    // 2. 验证章节树显示了单选题标签
    await tester.ensureVisible(find.text('单选'));
    expect(find.text('单选'), findsOneWidget);

    // 3. 点击「单选」标签打开样题预览抽屉
    await tester.tap(find.text('单选'));
    await tester.pumpAndSettle();

    // 4. 验证抽屉内渲染了题干与选项，且正确选项有正确答案标识
    expect(find.text('题型效果预览（ExamMCQ）'), findsOneWidget);
    expect(find.text('我国第一部社会主义类型的宪法是哪一年颁布的？'), findsOneWidget);
    expect(find.text('1954年'), findsOneWidget);
    expect(find.text('正确答案'), findsOneWidget);

    // 5. 点击「完成」关闭抽屉
    await tester.ensureVisible(find.text('完成'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('题型效果预览（ExamMCQ）'), findsNothing);
  });

  testWidgets('deck inspect opens the notetype that owns that deck',
      (tester) async {
    final controller = _RecordingController();
    OfficialAnkiProjectionSchema schema(int id, String name) {
      return OfficialAnkiProjectionSchema(
        notetypeId: id,
        name: name,
        kind: 'normal',
        fieldNames: const ['Front', 'Back'],
        templateNames: const ['Card 1'],
        schemaFingerprint: '$id',
        samples: const [
          OfficialAnkiProjectionSample(noteId: 1, fields: ['a', 'b']),
        ],
      );
    }

    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Mixed.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 8,
      noteCount: 8,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Words', level: 0),
        OfficialAnkiDeckNode(deckId: 2, name: 'Gaps', level: 0),
      ],
      cardCountByDeck: const {1: 5, 2: 3},
      notetypeByDeck: const {1: 1, 2: 2},
      includedDeckIds: const {1, 2},
      schemas: [schema(1, 'Basic'), schema(2, 'Cloze')],
      suggestions: const {
        2: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.auto,
          archetype: 'cloze',
          candidates: <OfficialAnkiFieldCandidate>[],
        ),
      },
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    await tester.ensureVisible(find.text('填空'));
    await tester.tap(find.text('填空'));
    await tester.pumpAndSettle();
    expect(find.text('题型效果预览（Cloze）'), findsOneWidget);
  });

  testWidgets('one notetype dropdown does not confirm the other row',
      (tester) async {
    final controller = _RecordingController();
    OfficialAnkiProjectionSchema schema(int id, String name) {
      return OfficialAnkiProjectionSchema(
        notetypeId: id,
        name: name,
        kind: 'normal',
        fieldNames: const ['Front', 'Back'],
        templateNames: const ['Card 1'],
        schemaFingerprint: '$id',
      );
    }

    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Two.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 4,
      noteCount: 4,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'A', level: 0),
      ],
      includedDeckIds: const {1},
      schemas: [schema(1, 'Basic'), schema(2, 'Cloze')],
      suggestions: const {},
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    await tester.tap(find.byType(DropdownButton<StudyPresetMode>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('经典闪卡翻面').last);
    await tester.pumpAndSettle();

    expect(controller.studyModes, hasLength(1));
    expect(controller.studyModes.single.$1.notetypeId, 2);
    expect(controller.confirmedMappings, isEmpty);
  });

  testWidgets('skipping a blocking notetype enables commit', (tester) async {
    final controller = _RecordingController();
    final schema = OfficialAnkiProjectionSchema(
      notetypeId: 99,
      name: 'ConfusingTemplate',
      kind: 'normal',
      fieldNames: const ['CustomCol1', 'CustomCol2'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
    );
    final blocked = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Exam.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 5,
      noteCount: 5,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Exam', level: 0),
      ],
      includedDeckIds: const {1},
      schemas: [schema],
      suggestions: const {
        99: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.review,
          archetype: 'basicPair',
          candidates: <OfficialAnkiFieldCandidate>[],
        ),
      },
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: blocked,
          controller: controller,
        ),
      ),
    ));
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('跳过这类'));
    await tester.pump();
    expect(controller.skipped, [99]);

    final skipped = OfficialAnkiImportPreviewModel(
      plan: blocked.plan,
      filePath: blocked.filePath,
      sourceId: blocked.sourceId,
      sourceHash: blocked.sourceHash,
      cardCount: blocked.cardCount,
      noteCount: blocked.noteCount,
      decks: blocked.decks,
      includedDeckIds: blocked.includedDeckIds,
      schemas: blocked.schemas,
      suggestions: blocked.suggestions,
      skippedNotetypes: const {99},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: skipped,
          controller: controller,
        ),
      ),
    ));
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('unchecking a deck records it as excluded from the course',
      (tester) async {
    final controller = _RecordingController();
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'Decks.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 4,
      noteCount: 4,
      decks: const [
        OfficialAnkiDeckNode(deckId: 7, name: 'Keep', level: 0),
        OfficialAnkiDeckNode(deckId: 8, name: 'Skip', level: 0),
      ],
      cardCountByDeck: const {7: 2, 8: 2},
      includedDeckIds: const {7, 8},
      schemas: [
        OfficialAnkiProjectionSchema(
          notetypeId: 1,
          name: 'Basic',
          kind: 'normal',
          fieldNames: const ['Front', 'Back'],
          templateNames: const ['Card 1'],
          schemaFingerprint: 'fp',
        ),
      ],
      suggestions: const {},
    );

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModernAnkiImportPreview(
          preview: preview,
          controller: controller,
        ),
      ),
    ));

    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(2));
    await tester.tap(boxes.at(1));
    await tester.pump();
    expect(controller.toggledDecks, [(8, false)]);
  });

  testWidgets('done step states new notes, skipped notes, parts and media',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AnkiImportDoneStep(
        summary: const AnkiImportSummary(
          importId: 'src',
          sectionCount: 2,
          lessonCount: 4,
          cardCount: 10,
          wordEntryCount: 0,
          newNoteCount: 6,
          duplicateNoteCount: 2,
          partCount: 3,
          includeMedia: false,
        ),
        keptLearningProgress: true,
        onStartLearningNow: () {},
        onViewDecks: () {},
        onDone: () {},
      ),
    ));

    expect(find.text('本次新增 6 条笔记'), findsOneWidget);
    expect(find.text('已存在并跳过 2 条笔记'), findsOneWidget);
    expect(find.textContaining('分成 3 个部分'), findsOneWidget);
    expect(find.text(AppStrings.ankiDoneMediaSkipped), findsOneWidget);
    expect(find.text(AppStrings.ankiDoneReviewRule()), findsOneWidget);
  });
}

AnkiImportExecutionPlan _plan() => const AnkiImportExecutionPlan(
      productMode: AnkiProductMode.officialAndroid,
      kind: AnkiImportExecutionKind.officialFirst,
      owner: AnkiImportOwner.official,
      platform: 'test',
      writesLegacyNoteStore: false,
      writesTurnaAnkiSrs: false,
      writesOfficialCollection: true,
      reason: 'test',
    );

class _StubController implements AnkiImportController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingController implements AnkiImportController {
  final confirmedMappings =
      <(OfficialAnkiProjectionSchema, OfficialAnkiMappingSuggestion)>[];
  final unconfirmedKinds = <(OfficialAnkiProjectionSchema, List<String>)>[];
  final studyModes = <(OfficialAnkiProjectionSchema, List<String>)>[];
  final skipped = <int>[];
  final toggledDecks = <(int, bool)>[];
  bool committed = false;

  @override
  void confirmOfficialMapping(
    OfficialAnkiProjectionSchema schema,
    OfficialAnkiMappingSuggestion suggestion,
  ) {
    confirmedMappings.add((schema, suggestion));
  }

  @override
  void applyUnconfirmedKinds(
    OfficialAnkiProjectionSchema schema,
    List<String> enabledKinds,
  ) {
    unconfirmedKinds.add((schema, enabledKinds));
  }

  @override
  void setNotetypeStudyMode(
    OfficialAnkiProjectionSchema schema,
    List<String> enabledKinds,
  ) {
    studyModes.add((schema, enabledKinds));
  }

  @override
  Future<void> loadSamples(OfficialAnkiProjectionSchema schema) async {}

  @override
  void skipOfficialNotetype(OfficialAnkiProjectionSchema schema) {
    skipped.add(schema.notetypeId);
  }

  @override
  void toggleDeckIncluded(int deckId, bool included) {
    toggledDecks.add((deckId, included));
  }

  @override
  Future<void> commit() async {
    committed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
