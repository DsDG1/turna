/// Strongly-typed card source indicating where a review card originates.
///
/// Invariant: Source cannot be inferred via ad-hoc string prefix checks in UI.
sealed class ReviewSource {
  const ReviewSource();
}

/// Built-in Turna course vocabulary or expression.
final class TurnaCourseSource extends ReviewSource {
  final String? sectionId;
  final String? unitId;
  final String? lessonId;

  const TurnaCourseSource({
    this.sectionId,
    this.unitId,
    this.lessonId,
  });

  @override
  String toString() => 'TurnaCourseSource(section: $sectionId, lesson: $lessonId)';
}

/// Legacy imported Anki card stored in Drift / SQLite tables.
final class LegacyAnkiSource extends ReviewSource {
  final String importId;
  final int? deckId;

  const LegacyAnkiSource({
    required this.importId,
    this.deckId,
  });

  @override
  String toString() => 'LegacyAnkiSource(importId: $importId, did: $deckId)';
}

/// Official Anki card residing in the official Rust/C++ collection.
final class OfficialAnkiSource extends ReviewSource {
  final String sourceId;
  final int deckId;
  final int cardId;

  const OfficialAnkiSource({
    required this.sourceId,
    required this.deckId,
    required this.cardId,
  });

  @override
  String toString() =>
      'OfficialAnkiSource(sourceId: $sourceId, did: $deckId, cid: $cardId)';
}
