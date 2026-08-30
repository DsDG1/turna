// Doc 39 P4: round-trip tests for the unified worker message protocol.
// Every retained op must survive the
// command `{type, id, reply, …}` → reply `{ok, result}` → typed-DTO cast
// cycle with its typed result intact — the protocol that replaced the
// per-op hand serialization on both sides.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

void main() {
  test('session-level ops round-trip typed results through the worker', () async {
    final root = Directory.systemTemp.createTempSync('turna-proto-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-proto01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final session = await OfficialAnkiSession.spawn(
      paths: paths,
      catalogPath: '${root.path}/catalog.sqlite',
      useFake: true,
    );
    addTearDown(session.dispose);

    final pkg = File(
      'test/fixtures/anki_official/packages/01-basic-unicode.apkg',
    );
    final imported = await session.importFile(
      packagePath: pkg.path,
      displayName: 'proto-unicode',
    );
    expect(imported, isA<OfficialAnkiImportResult>());
    expect(imported.state, OfficialAnkiSourceState.previewReady);

    final info = await session.engineInfo();
    expect(info, isA<OfficialAnkiEngineInfo>());
    expect(info.capabilities, isNotEmpty);

    final progress = await session.latestProgress();
    expect(progress.stage, isA<String>());

    final decks = await session.listDeckTree();
    expect(decks, isA<List<OfficialAnkiDeckNode>>());

    final schemas = await session.getProjectionSchemas();
    expect(schemas, isA<List<OfficialAnkiProjectionSchema>>());

    final page = await session.searchCardsPage(search: '');
    expect(page, isA<OfficialAnkiCardPage>());

    // Error path: a typed OfficialAnkiException crosses the envelope
    // with its code intact (the fake rejects this cloze shape).
    await expectLater(
      session.extractClozeForTyping(text: '{{c1::word}}', ordinal: 0),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.typedClozeEmpty,
        ),
      ),
    );

    // Void ops: the reply envelope carries no result slot.
    await session.setCurrentDeck(1);
    await session.ensureCollectionOpen();

    // Non-queue scheduler ops the fake serves without seeded cards.
    final counts = await session.countsForDeckToday(1);
    expect(counts, isA<OfficialDeckCounts>());

    final congrats = await session.congratsInfo();
    expect(congrats, isA<OfficialCongratsInfo>());

    final quota = await session.ensureTodayNewQuota(deckId: 1, neededNew: 0);
    expect(quota, isA<int>());

    // Snapshot family through the worker (fake path).
    final snapshot = await session.beginProjectionRead(
      cardSetFingerprint: 'fp-proto',
    );
    expect(snapshot, isA<OfficialAnkiProjectionSnapshot>());
    final rows = await session.getProjectionRowsBatch(
      cardIds: const [1],
      snapshotToken: snapshot.snapshotToken,
    );
    expect(rows, isA<OfficialAnkiProjectionPage>());
  });

  test('scheduler dispatch returns typed DTOs for every op', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);

    final queue = (await dispatchOfficialAnkiScheduler(fake, {
      'op': 'getReviewQueue',
      'fetchLimit': 1,
    })) as OfficialReviewQueue;
    expect(queue, isA<OfficialReviewQueue>());

    final answered = (await dispatchOfficialAnkiScheduler(fake, {
      'op': 'answerCard',
      'sessionId': queue.sessionId,
      'queueEpoch': queue.queueEpoch,
      'answerToken': queue.cards.single.answerToken,
      'cardId': queue.cards.single.cardId,
      'rating': 'good',
      'millisecondsTaken': 900,
    })) as OfficialAnswerResult;
    expect(answered, isA<OfficialAnswerResult>());
    expect(answered.committed, isTrue);

    final status = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'getUndoStatus',
    });
    expect(status, isA<OfficialUndoStatus>());

    final undone = await dispatchOfficialAnkiScheduler(fake, {'op': 'undo'});
    expect(undone, isA<OfficialMutationResult>());

    final redone = await dispatchOfficialAnkiScheduler(fake, {'op': 'redo'});
    expect(redone, isA<OfficialMutationResult>());

    final counts = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'countsForDeckToday',
      'deckId': 1,
    });
    expect(counts, isA<OfficialDeckCounts>());

    final congrats = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'congratsInfo',
    });
    expect(congrats, isA<OfficialCongratsInfo>());

    final stats = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'statsForCardsBatch',
      'cardIds': [answered.cardId],
    });
    expect(stats, isA<OfficialAnkiStatsBatch>());

    final removed = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'deleteNotes',
      'noteIds': [answered.cardId],
    });
    expect(removed, isA<int>());

    final scheduled = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'scheduleCardsAsNew',
      'cardIds': [answered.cardId],
    });
    expect(scheduled, isA<int>());

    final ahead = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'answerAheadCards',
      'answers': [
        {'cardId': answered.cardId, 'rating': 'easy', 'millisecondsTaken': 10},
      ],
    });
    expect(ahead, isA<OfficialAheadAnswerOutcome>());

    final quota = await dispatchOfficialAnkiScheduler(fake, {
      'op': 'ensureTodayNewQuota',
      'deckId': 1,
      'neededNew': 0,
    });
    expect(quota, isA<int>());

    // Void op returns null result.
    expect(
      await dispatchOfficialAnkiScheduler(fake, {
        'op': 'setCurrentDeck',
        'deckId': 1,
      }),
      isNull,
    );

    // Unknown op still fails closed through the exception path.
    await expectLater(
      dispatchOfficialAnkiScheduler(fake, {'op': 'not-an-op'}),
      throwsA(isA<OfficialAnkiException>()),
    );
  });
}
