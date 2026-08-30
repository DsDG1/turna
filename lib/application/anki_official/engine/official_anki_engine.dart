import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// One profile, one Collection owner. Implementations must serialize writes.
abstract class OfficialAnkiEngine {
  Future<OfficialAnkiEngineInfo> engineInfo();

  Future<void> openProfile(OfficialAnkiPaths paths);

  Future<void> closeCollection();

  Future<void> checkCollection();

  Future<String> createBackup();

  Future<void> restoreBackup(String backupId);

  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  });

  Future<OfficialAnkiProgress> latestProgress();

  Future<void> cancel();

  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  });

  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds);

  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  );

  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  });

  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  });

  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  });

  Future<List<OfficialAnkiDeckNode>> listDeckTree();

  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  });

  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  });

  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  });

  Future<void> setCurrentDeck(int deckId);

  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1});

  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
    String? clientMutationId,
  });

  Future<OfficialUndoStatus> getUndoStatus();

  Future<OfficialMutationResult> undo();

  Future<OfficialMutationResult> redo();

  Future<OfficialDeckCounts> countsForDeckToday(int deckId);

  Future<OfficialCongratsInfo> congratsInfo();

  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  });

  /// Hard-delete for one imported source: removes [noteIds] and every card
  /// that uses them from the official collection. Returns the number of
  /// cards removed. Note-scoped so decks shared with other sources keep the
  /// cards they own.
  Future<int> deleteNotes(List<int> noteIds);

  /// Removes only the listed cards and deletes a note only when the removal
  /// leaves it orphaned. This is the source-uninstall primitive: imported
  /// sources may share notes, or even cards, inside one Collection.
  Future<int> deleteCards(List<int> cardIds);

  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds);

  /// Explicit W8 scheduling policy primitive. Resets exactly [cardIds] to
  /// Official Anki's New queue; it is never called without user confirmation.
  Future<int> scheduleCardsAsNew(List<int> cardIds);

  /// Rate cards that may not be in today's due queue (lesson redo / 提前复习).
  /// Uses an Official filtered deck internally. Returns how many cards were
  /// actually answered. Fail-closed: missing capability throws.
  Future<OfficialAheadAnswerOutcome> answerAheadCards(
    List<OfficialAheadAnswer> answers,
  );

  /// Raise today's remaining new-card quota to at least [neededNew]
  /// (`extend_new`), without changing the deck preset `new_per_day`.
  /// Returns the extra quota applied (0 if already enough).
  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  });

  Future<void> dispose();
}
