import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_redo_flush.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_unlock_quota.dart';

void main() {
  test('ensureTodayNewQuota raises remaining new cards to the lesson size',
      () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 40, cards: 40);
    fake.newPerDayLimit = 20;
    fake.officialAnswers = 5;

    final extra = await fake.ensureTodayNewQuota(deckId: 1, neededNew: 40);
    expect(extra, 25);
    expect(fake.newPerDayLimit, 45);

    expect(await fake.ensureTodayNewQuota(deckId: 1, neededNew: 40), 0);
  });

  test('first-pass unlock quota groups cards by deck', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    fake.cards[2] = OfficialAnkiCardDescriptor(
      cardId: 2,
      noteId: 2,
      deckId: 7,
      templateOrd: 0,
    );
    fake.newPerDayLimit = 1;

    final extra = await OfficialAnkiLessonUnlockQuota(engine: fake)
        .ensureForCardIds(const [1, 2, 3]);
    expect(extra, greaterThan(0));
    expect(fake.newPerDayLimit, greaterThanOrEqualTo(2));
  });

  test('redo flush skips cards already rated today', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    fake.ratedTodayIds.add(1);

    final result = await OfficialAnkiLessonRedoFlush(engine: fake).flush([
      const OfficialAheadAnswer(cardId: 1, rating: 'again'),
      const OfficialAheadAnswer(cardId: 2, rating: 'good'),
    ]);

    expect(result.requested, 2);
    expect(result.skippedRatedToday, 1);
    expect(result.answered, 1);
    expect(result.failed, isFalse);
    expect(result.userShouldBeNotified, isFalse);
    expect(fake.aheadAnswers.single.cardId, 2);
  });

  test('redo flush failure is visible when the engine is missing', () async {
    final result = await const OfficialAnkiLessonRedoFlush().flush([
      const OfficialAheadAnswer(cardId: 9, rating: 'good'),
    ]);
    expect(result.failed, isTrue);
    expect(result.userShouldBeNotified, isTrue);
    expect(result.answered, 0);
  });
}
