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
  Future<void> openProfile(OfficialAnkiPaths paths) => session.ensureCollectionOpen();

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
  Future<void> setCurrentDeck(int deckId) => throw _missing;

  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) =>
      throw _missing;

  @override
  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
  }) =>
      throw _missing;

  @override
  Future<OfficialUndoStatus> getUndoStatus() => throw _missing;

  @override
  Future<OfficialMutationResult> undo() => throw _missing;

  @override
  Future<OfficialMutationResult> redo() => throw _missing;

  @override
  Future<OfficialDeckCounts> countsForDeckToday(int deckId) => throw _missing;

  @override
  Future<OfficialCongratsInfo> congratsInfo() => throw _missing;

  @override
  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) =>
      throw _missing;

  @override
  Future<void> dispose() => session.dispose();
}
