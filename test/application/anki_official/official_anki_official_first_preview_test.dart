import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

/// 预览牌组结构的真实卡数：deck tree 的 new/learn/review 是今日到期
/// 队列数，卡总数必须来自 staging 卡账本并按名字路径向父牌组累计。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late OfficialAnkiDatabase catalog;
  late CourseDatabase course;
  late FakeOfficialAnkiEngine engine;

  setUp(() {
    catalog = OfficialAnkiDatabase.memory();
    course = CourseDatabase(NativeDatabase.memory());
    engine = FakeOfficialAnkiEngine();
    engine.deckTree = const [
      OfficialAnkiDeckNode(deckId: 10, name: 'Deck A', level: 0),
      OfficialAnkiDeckNode(deckId: 11, name: 'Deck A::Sub', level: 1),
      OfficialAnkiDeckNode(deckId: 12, name: 'Solo', level: 0),
    ];
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
  });

  tearDown(() {
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
    catalog.close();
    course.close();
  });

  Future<OfficialAnkiOfficialFirstPreview> previewWithCards(
    List<OfficialAnkiCardDescriptor> cards,
  ) async {
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-preview',
      profileId: 'profile-preview',
      sourceHash: 'hash-preview',
      sourceSize: 10,
      displayName: 'P',
      state: 'active',
      backendCommit: 'pending',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog)
        .upsertCardBatch(sourceId: 'src-preview', cards: cards);
    return const OfficialAnkiOfficialFirstService().preparePreview(
      official: OfficialAnkiImportResult(
        sourceId: 'src-preview',
        attemptId: 'attempt-1',
        state: OfficialAnkiSourceState.previewReady,
        cardCount: cards.length,
        noteCount: cards.length,
      ),
      sourceHash: 'hash-preview',
      course: course,
    );
  }

  test('per-deck counts aggregate child decks into the parent row',
      () async {
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
}
