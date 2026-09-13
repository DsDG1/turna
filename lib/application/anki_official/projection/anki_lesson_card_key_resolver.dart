import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/mistake_review_assembler.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/interaction.dart';

/// Derive the SRS wordId from an Anki card interaction id.
///
/// Id conventions (retired Legacy assembler-era scheme, kept stable):
/// - Course lessons: `<wordId>-c<ord>` where wordId is
///   `anki-<importId>-c<cardId>`
/// - Review sessions: `anki-review-<wordId>`
///
/// Returns the wordId (`anki-<importId>-c<cardId>`) in both cases; ids that
/// match neither convention are returned unchanged.
String ankiWordIdFromInteractionId(String interactionId) {
  final id = interactionId.replaceFirst('anki-review-', '');
  final cIdx = id.lastIndexOf('-c');
  if (cIdx > 0 && int.tryParse(id.substring(cIdx + 2)) != null) {
    return id.substring(0, cIdx);
  }
  return id;
}

/// Resolves the canonical card key for an interaction of the current lesson
/// (projection index first, fail-closed; legacy id conventions second).
///
/// Extracted from [LessonViewModel] so the key-resolution rules live in one
/// place next to the projection index they depend on; the viewmodel and the
/// lesson-completion service share one instance (and its index cache).
class AnkiLessonCardKeyResolver {
  static const profileId = 'profile-default-01';

  /// P0 single source for the Official cards of the current lesson, loaded
  /// from the projection index. Null for lessons this database never
  /// projected (legacy imports, synthetic lessons).
  OfficialAnkiLessonCardIndex? _officialCardIndex;

  /// The lesson id the cached index belongs to.
  String? _indexLessonId;

  OfficialAnkiLessonCardIndex? get officialCardIndex => _officialCardIndex;

  /// Loads (or returns the cached) projection-index card map for [lessonId].
  /// Null means "not an Official projection lesson" — Official card
  /// resolution then fails closed instead of guessing from id strings.
  Future<OfficialAnkiLessonCardIndex?> ensureOfficialCardIndex(
    String lessonId,
  ) async {
    final cached = _officialCardIndex;
    if (cached != null && _indexLessonId == lessonId) return cached;
    final resolved = await OfficialAnkiLessonCardIndex.resolveForLesson(
      lessonId,
    );
    _officialCardIndex = resolved;
    _indexLessonId = lessonId;
    return resolved;
  }

  CanonicalCardKey? canonicalKeyForAnkiInteraction(
    Interaction interaction, {
    required String lessonId,
  }) {
    // Official projection lesson: wordId→cardId is a structured projection
    // index row, never a guess out of the id string (P0). Unresolved means
    // not anki-owned — fail closed rather than fall through to guessing.
    final index = _officialCardIndex;
    if (index != null) {
      final cardId = index.cardIdForInteraction(interaction);
      if (cardId == null) return null;
      return CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: index.sourceId,
        cardId: cardId,
      );
    }
    // Official tree lessons must resolve through the index; without it they
    // fail closed instead of mis-attributing the source from the loose id
    // conventions below (which legacy imported courses still rely on).
    if (CardIntroductionEligibility.officialSourceIdFromTreeId(lessonId) !=
        null) {
      return null;
    }
    // Legacy imported courses keep the stored-wordId convention the retired
    // Legacy assembler minted (`anki-{importId}-c{cardId}`).
    final rawId = ankiWordIdFromInteractionId(interaction.id);
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profileId,
          rawId: rawId,
        ) ??
        CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profileId,
          rawId: interaction.id,
        ) ??
        _keyFromLooseAnkiId(rawId) ??
        _keyFromLooseAnkiId(interaction.id);
  }

  CanonicalCardKey? _keyFromLooseAnkiId(String id) {
    final cardId = CardIntroductionEligibility.cardIdFromWordId(id);
    if (cardId == null) return null;
    final official = RegExp(r'^official-anki-(.+)-c\d+').firstMatch(id);
    if (official != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: official.group(1)!,
        cardId: cardId,
      );
    }
    final legacy = RegExp(r'^anki-(.+)-c\d+').firstMatch(id);
    if (legacy != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: profileId,
        sourceId: legacy.group(1)!,
        cardId: cardId,
      );
    }
    return null;
  }

  bool isAnkiOwnedId(String id) {
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profileId,
          rawId: id,
        ) !=
        null;
  }

  bool isAnkiOwnedInteraction(
    Interaction interaction,
    String? wordId, {
    required String lessonId,
  }) {
    if (lessonId == MistakeReviewAssembler.lessonId ||
        lessonId == WeakWordQuizAssembler.lessonId) {
      return false;
    }
    if (canonicalKeyForAnkiInteraction(interaction, lessonId: lessonId) !=
        null) {
      return true;
    }
    if (wordId != null && isAnkiOwnedId(wordId)) return true;
    return false;
  }
}
