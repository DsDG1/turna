/// `anki_course_tree_view` 的一行：一张卡在课程树中的位置（D3）。
class OfficialAnkiV2ViewRow {
  const OfficialAnkiV2ViewRow({
    required this.sourceId,
    required this.cardId,
    required this.noteId,
    required this.deckId,
    required this.wordId,
    required this.sectionKey,
    required this.sectionId,
    required this.unitId,
    this.unitKey = '',
    required this.lessonId,
    required this.lessonKey,
    required this.sourceHash,
    this.mappingVersion = 1,
  });

  final String sourceId;
  final int cardId;
  final int noteId;
  final int deckId;
  final String wordId;
  final String sectionKey;
  final String sectionId;
  final String unitId;

  /// Middle deck segment (`A::B::C` → `B`). Empty on rows written before
  /// schema v30; callers then fall back to [lessonKey].
  final String unitKey;
  final String lessonId;
  final String lessonKey;
  final String sourceHash;
  final int mappingVersion;
}

/// 课程维度聚合（目录条目 / 树壳用）。
class OfficialAnkiV2ViewSectionSummary {
  const OfficialAnkiV2ViewSectionSummary({
    required this.sourceId,
    required this.sectionId,
    required this.sectionKey,
    required this.cardCount,
    required this.lessonCount,
  });

  final String sourceId;
  final String sectionId;
  final String sectionKey;
  final int cardCount;
  final int lessonCount;
}
