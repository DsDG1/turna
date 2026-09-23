/// Plain data class for Anki import metadata (decoupled from the Drift row).
class AnkiImportRecord {
  final String importId;
  final String sourcePath;
  final String sourceHash;
  final int importedAt;
  final int deckCount;
  final int noteCount;
  final int cardCount;
  final int mediaCount;
  final String notetypesJson;
  final bool aiEnhanced;
  final int version;
  final int? dailyNewLimit;
  final int? dailyReviewLimit;
  final String status;
  final int sourceCardCount;
  final bool importedScheduling;
  final String? lastError;

  const AnkiImportRecord({
    required this.importId,
    required this.sourcePath,
    required this.sourceHash,
    required this.importedAt,
    this.deckCount = 0,
    this.noteCount = 0,
    this.cardCount = 0,
    this.mediaCount = 0,
    this.notetypesJson = '{}',
    this.aiEnhanced = false,
    this.version = 1,
    this.dailyNewLimit,
    this.dailyReviewLimit,
    this.status = 'pending',
    this.sourceCardCount = 0,
    this.importedScheduling = false,
    this.lastError,
  });

  DateTime get importedAtDate =>
      DateTime.fromMillisecondsSinceEpoch(importedAt * 1000);
}
