/// A single textbook chapter split from the source document.
class TextbookChapter {
  const TextbookChapter({
    required this.title,
    required this.markdown,
    required this.slug,
  });

  final String title;
  final String markdown;
  final String slug;
}

/// Extracted teachable knowledge from one chapter.
class KnowledgePoints {
  const KnowledgePoints({
    this.words = const [],
    this.expressions = const [],
    this.grammarPoints = const [],
  });

  final List<Map<String, dynamic>> words;
  final List<Map<String, dynamic>> expressions;
  final List<Map<String, dynamic>> grammarPoints;

  bool get isEmpty => words.isEmpty && expressions.isEmpty && grammarPoints.isEmpty;

  int get length => words.length + expressions.length + grammarPoints.length;

  KnowledgePoints copyWith({
    List<Map<String, dynamic>>? words,
    List<Map<String, dynamic>>? expressions,
    List<Map<String, dynamic>>? grammarPoints,
  }) =>
      KnowledgePoints(
        words: words ?? this.words,
        expressions: expressions ?? this.expressions,
        grammarPoints: grammarPoints ?? this.grammarPoints,
      );
}

/// Result of extracting knowledge from a chapter, including any error.
class ChapterResult {
  ChapterResult({
    required this.chapter,
    this.keep = true,
    this.knowledge,
    this.error,
  });

  final TextbookChapter chapter;
  bool keep;
  KnowledgePoints? knowledge;
  String? error;

  bool get hasKnowledge => knowledge != null && !knowledge!.isEmpty;
}

/// Coerces a decoded JSON object into a [KnowledgePoints] instance.
/// Tolerant of missing keys and partial shapes.
KnowledgePoints coerceKnowledgePoints(dynamic value) {
  if (value is! Map<String, dynamic>) return const KnowledgePoints();

  List<Map<String, dynamic>> extractList(String key) {
    final raw = value[key];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) item,
    ];
  }

  return KnowledgePoints(
    words: extractList('words'),
    expressions: extractList('expressions'),
    grammarPoints: extractList('grammarPoints'),
  );
}
