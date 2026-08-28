import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Worker-session adapter so production source management can project.
class OfficialAnkiSessionEngine implements OfficialAnkiEngine {
  OfficialAnkiSessionEngine(this.session);

  final OfficialAnkiSession session;

  OfficialAnkiException get _missing => const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.session_engine_unimplemented',
      );

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() => session.engineInfo();

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) =>
      session.ensureCollectionOpen();

  @override
  Future<void> closeCollection() async {}

  @override
  Future<void> checkCollection() async {}

  @override
  Future<String> createBackup() => throw _missing;

  @override
  Future<void> restoreBackup(String backupId) => throw _missing;

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) =>
      throw _missing;

  @override
  Future<OfficialAnkiProgress> latestProgress() => session.latestProgress();

  @override
  Future<void> cancel() => session.cancel();

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) {
    return session.searchCardsPage(
      search: search,
      pageSize: pageSize,
      pageToken: pageToken,
    );
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) =>
      throw _missing;

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) =>
      throw _missing;

  @override
  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) {
    return session.renderCard(
      cardId: cardId,
      browser: browser,
      includeAvTags: includeAvTags,
    );
  }

  @override
  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) {
    return session.compareTypedAnswer(
      cardId: cardId,
      marker: marker,
      provided: provided,
    );
  }

  @override
  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) {
    return session.extractClozeForTyping(text: text, ordinal: ordinal);
  }

  @override
  Future<List<OfficialAnkiDeckNode>> listDeckTree() => session.listDeckTree();

  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) {
    return session.getProjectionSchemas(
      notetypeIds: notetypeIds,
      includeSamples: includeSamples,
      sampleLimit: sampleLimit,
    );
  }

  @override
  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) {
    return session.beginProjectionRead(
      cardSetFingerprint: cardSetFingerprint,
      mappingVersion: mappingVersion,
    );
  }

  @override
  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) {
    return session.getProjectionRowsBatch(
      cardIds: cardIds,
      snapshotToken: snapshotToken,
    );
  }

  @override
  Future<void> setCurrentDeck(int deckId) => session.setCurrentDeck(deckId);

  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) {
    return session.getReviewQueue(fetchLimit: fetchLimit);
  }

  @override
  Future<OfficialReviewIntervalLabels> describeNextStates({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
  }) {
    return session.describeNextStates(
      sessionId: sessionId,
      queueEpoch: queueEpoch,
      answerToken: answerToken,
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
    return session.answerCard(
      sessionId: sessionId,
      queueEpoch: queueEpoch,
      answerToken: answerToken,
      cardId: cardId,
      rating: rating,
      millisecondsTaken: millisecondsTaken,
      answeredAtMillis: answeredAtMillis,
      clientMutationId: clientMutationId,
    );
  }

  @override
  Future<OfficialUndoStatus> getUndoStatus() => session.getUndoStatus();

  @override
  Future<OfficialMutationResult> undo() => session.undo();

  @override
  Future<OfficialMutationResult> redo() => session.redo();

  @override
  Future<OfficialDeckCounts> countsForDeckToday(int deckId) {
    return session.countsForDeckToday(deckId);
  }

  @override
  Future<OfficialCongratsInfo> congratsInfo() => session.congratsInfo();

  @override
  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) {
    return session.buryOrSuspendCards(
      action: action,
      cardIds: cardIds,
      deckId: deckId,
    );
  }

  @override
  Future<int> deleteNotes(List<int> noteIds) {
    return session.deleteNotes(noteIds);
  }

  @override
  Future<int> deleteCards(List<int> cardIds) {
    return session.deleteCards(cardIds);
  }

  @override
  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds) {
    return session.statsForCardsBatch(cardIds);
  }

  @override
  Future<int> scheduleCardsAsNew(List<int> cardIds) {
    return session.scheduleCardsAsNew(cardIds);
  }

  @override
  Future<int> answerAheadCards(List<OfficialAheadAnswer> answers) {
    return session.answerAheadCards(answers);
  }

  @override
  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  }) {
    return session.ensureTodayNewQuota(deckId: deckId, neededNew: neededNew);
  }

  @override
  Future<void> dispose() => session.dispose();
}
