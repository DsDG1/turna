import 'dart:async';
import 'dart:collection';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Serializes all engine calls on one owner. Tests inject a fake inner engine.
class OfficialAnkiWorker implements OfficialAnkiEngine {
  OfficialAnkiWorker(this._inner);

  final OfficialAnkiEngine _inner;
  final Queue<Future<void> Function()> _queue =
      Queue<Future<void> Function()>();
  bool _draining = false;
  bool _disposed = false;
  String? _openProfileId;

  Future<T> _enqueue<T>(Future<T> Function() work) {
    if (_disposed) {
      return Future<T>.error(
        const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.engine_disposed',
        ),
      );
    }
    final completer = Completer<T>();
    _queue.add(() async {
      try {
        completer.complete(await work());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    _drain();
    return completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      await job();
    }
    _draining = false;
  }

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() => _enqueue(_inner.engineInfo);

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) {
    return _enqueue(() async {
      if (_openProfileId != null && _openProfileId != paths.profileId) {
        await _inner.closeCollection();
      }
      await _inner.openProfile(paths);
      _openProfileId = paths.profileId;
    });
  }

  @override
  Future<void> closeCollection() {
    return _enqueue(() async {
      await _inner.closeCollection();
      _openProfileId = null;
    });
  }

  @override
  Future<void> checkCollection() => _enqueue(_inner.checkCollection);

  @override
  Future<String> createBackup() => _enqueue(_inner.createBackup);

  @override
  Future<void> restoreBackup(String backupId) {
    return _enqueue(() => _inner.restoreBackup(backupId));
  }

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) {
    return _enqueue(
      () => _inner.importPackage(
        packagePath: packagePath,
        withScheduling: withScheduling,
        withDeckConfigs: withDeckConfigs,
      ),
    );
  }

  @override
  Future<OfficialAnkiProgress> latestProgress() => _inner.latestProgress();

  @override
  Future<void> cancel() => _inner.cancel();

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) {
    return _enqueue(
      () => _inner.searchCardsPage(
        search: search,
        pageSize: pageSize,
        pageToken: pageToken,
      ),
    );
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) {
    return _enqueue(() => _inner.getNoteCardsBatch(noteIds));
  }

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) {
    return _enqueue(() => _inner.getCardDescriptorsBatch(cardIds));
  }

  @override
  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) {
    return _enqueue(
      () => _inner.renderCard(
        cardId: cardId,
        browser: browser,
        includeAvTags: includeAvTags,
      ),
    );
  }

  @override
  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) {
    return _enqueue(
      () => _inner.compareTypedAnswer(
        cardId: cardId,
        marker: marker,
        provided: provided,
      ),
    );
  }

  @override
  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) {
    return _enqueue(
      () => _inner.extractClozeForTyping(text: text, ordinal: ordinal),
    );
  }

  @override
  Future<List<OfficialAnkiDeckNode>> listDeckTree() {
    return _enqueue(_inner.listDeckTree);
  }

  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) {
    return _enqueue(
      () => _inner.getProjectionSchemas(
        notetypeIds: notetypeIds,
        includeSamples: includeSamples,
        sampleLimit: sampleLimit,
      ),
    );
  }

  @override
  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) {
    return _enqueue(
      () => _inner.beginProjectionRead(
        cardSetFingerprint: cardSetFingerprint,
        mappingVersion: mappingVersion,
      ),
    );
  }

  @override
  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) {
    return _enqueue(
      () => _inner.getProjectionRowsBatch(
        cardIds: cardIds,
        snapshotToken: snapshotToken,
      ),
    );
  }

  @override
  Future<void> setCurrentDeck(int deckId) {
    return _enqueue(() => _inner.setCurrentDeck(deckId));
  }

  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) {
    return _enqueue(() => _inner.getReviewQueue(fetchLimit: fetchLimit));
  }

  @override
  Future<OfficialReviewIntervalLabels> describeNextStates({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
  }) {
    return _enqueue(
      () => _inner.describeNextStates(
        sessionId: sessionId,
        queueEpoch: queueEpoch,
        answerToken: answerToken,
      ),
    );
  }

  @override
  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
    String? clientMutationId,
  }) {
    return _enqueue(
      () => _inner.answerCard(
        sessionId: sessionId,
        queueEpoch: queueEpoch,
        answerToken: answerToken,
        cardId: cardId,
        rating: rating,
        millisecondsTaken: millisecondsTaken,
        answeredAtMillis: answeredAtMillis,
        clientMutationId: clientMutationId,
      ),
    );
  }

  @override
  Future<OfficialUndoStatus> getUndoStatus() {
    return _enqueue(_inner.getUndoStatus);
  }

  @override
  Future<OfficialMutationResult> undo() => _enqueue(_inner.undo);

  @override
  Future<OfficialMutationResult> redo() => _enqueue(_inner.redo);

  @override
  Future<OfficialDeckCounts> countsForDeckToday(int deckId) {
    return _enqueue(() => _inner.countsForDeckToday(deckId));
  }

  @override
  Future<OfficialCongratsInfo> congratsInfo() => _enqueue(_inner.congratsInfo);

  @override
  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) {
    return _enqueue(
      () => _inner.buryOrSuspendCards(
        action: action,
        cardIds: cardIds,
        deckId: deckId,
      ),
    );
  }

  @override
  Future<int> deleteNotes(List<int> noteIds) {
    return _enqueue(() => _inner.deleteNotes(noteIds));
  }

  @override
  Future<int> deleteCards(List<int> cardIds) {
    return _enqueue(() => _inner.deleteCards(cardIds));
  }

  @override
  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds) {
    return _enqueue(() => _inner.statsForCardsBatch(cardIds));
  }

  @override
  Future<int> scheduleCardsAsNew(List<int> cardIds) {
    return _enqueue(() => _inner.scheduleCardsAsNew(cardIds));
  }

  @override
  Future<OfficialAheadAnswerOutcome> answerAheadCards(
    List<OfficialAheadAnswer> answers,
  ) {
    return _enqueue(() => _inner.answerAheadCards(answers));
  }

  @override
  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  }) {
    return _enqueue(
      () => _inner.ensureTodayNewQuota(deckId: deckId, neededNew: neededNew),
    );
  }

  @override
  Future<void> dispose() {
    return _enqueue(() async {
      await _inner.dispose();
      _disposed = true;
    });
  }
}
