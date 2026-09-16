import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

/// 预览牌组结构的真实卡数：deck tree 的 new/learn/review 是今日到期
/// 队列数，卡总数必须来自 staging 引擎的卡描述符并按名字路径向父
/// 牌组累计（live catalog 的 anki_source_cards 在 commit 前恒空）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;

  setUp(() {
    course = CourseDatabase(NativeDatabase.memory());
    engine = FakeOfficialAnkiEngine();
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Deck A', level: 0),
      OfficialAnkiDeckNode(deckId: 11, name: 'Deck A::Sub', level: 1),
      OfficialAnkiDeckNode(deckId: 12, name: 'Solo', level: 0),
    ];
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
  });

  tearDown(() {
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
    course.close();
  });

  Future<OfficialAnkiOfficialFirstPreview> previewWithCards(
    List<OfficialAnkiCardDescriptor> cards,
  ) async {
    // preparePreview 只向 staging 引擎取数：seed note→card 映射与描述符，
    // 模拟 staging importPackage 之后的集合内容。
    final noteIds = <int>{};
    for (final card in cards) {
      engine.cards[card.cardId] = card;
      engine.cardsByNote
          .putIfAbsent(card.noteId, () => <int>[])
          .add(card.cardId);
      noteIds.add(card.noteId);
    }
    return const OfficialAnkiOfficialFirstService().preparePreview(
      official: OfficialAnkiImportResult(
        sourceId: 'src-preview',
        attemptId: 'attempt-1',
        state: OfficialAnkiSourceState.previewReady,
        cardCount: cards.length,
        noteCount: noteIds.length,
        associatedNoteIds: noteIds.toList(),
      ),
      sourceHash: 'hash-preview',
      course: course,
    );
  }

  test('per-deck counts aggregate child decks into the parent row', () async {
    final preview = await previewWithCards(const [
      OfficialAnkiCardDescriptor(
        cardId: 1,
        noteId: 1,
        deckId: 11, // Deck A::Sub
        templateOrd: 0,
        notetypeId: 1,
      ),
      OfficialAnkiCardDescriptor(
        cardId: 2,
        noteId: 2,
        deckId: 11,
        templateOrd: 0,
        notetypeId: 1,
      ),
      OfficialAnkiCardDescriptor(
        cardId: 3,
        noteId: 3,
        deckId: 12, // Solo
        templateOrd: 0,
        notetypeId: 1,
      ),
    ]);

    expect(preview.cardCountByDeck[11], 2, reason: '叶子牌组 = 自身卡数');
    expect(preview.cardCountByDeck[10], 2,
        reason: '父牌组行 = 子树累计（deck tree 的到期数做不到这点）');
    expect(preview.cardCountByDeck[12], 1);
    expect(preview.cardCountByDeck.containsKey(999), isFalse);
  });

  test('decks are scoped to the imported source deck tree', () async {
    final preview = await previewWithCards(const [
      OfficialAnkiCardDescriptor(
        cardId: 1,
        noteId: 1,
        deckId: 12, // Solo
        templateOrd: 0,
        notetypeId: 1,
      ),
    ]);
    expect(preview.decks.map((d) => d.name), ['Solo']);
  });

  test('preparePreview fails closed without a staging engine', () async {
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
    await expectLater(
      const OfficialAnkiOfficialFirstService().preparePreview(
        official: const OfficialAnkiImportResult(
          sourceId: 'src-x',
          attemptId: 'a-x',
          state: OfficialAnkiSourceState.previewReady,
          cardCount: 0,
          noteCount: 0,
        ),
        sourceHash: 'h',
        course: course,
      ),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.capabilityMissing,
        ),
      ),
    );
  });
}
