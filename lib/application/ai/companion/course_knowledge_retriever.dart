import 'dart:math' as math;

import 'package:turna/domain/ai_companion/ai_citation.dart';
import 'package:turna/domain/repositories/i_course_knowledge_retriever.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

class CourseKnowledgeRetriever implements ICourseKnowledgeRetriever {
  CourseKnowledgeRetriever(this._repository);

  final ICourseRepository _repository;
  Set<String> _lastValidIds = const <String>{};

  @override
  Future<List<AiCitation>> retrieve(String query, {int limit = 5}) async {
    final tokens = _tokens(query);
    if (tokens.isEmpty) {
      _lastValidIds = const <String>{};
      return const <AiCitation>[];
    }
    final scored = <({double score, AiCitation citation})>[];
    final words = await _repository.vocabulary();
    for (final item in words) {
      final text = '${item.term} ${item.translation} ${item.tags.join(' ')}';
      final score = _score(tokens, text, exact: item.term);
      if (score > 0) {
        scored.add((
          score: score,
          citation: AiCitation(
            resourceId: item.id,
            type: AiCitationType.word,
            title: item.term,
            snippet: item.translation,
          ),
        ));
      }
    }
    final expressions = await _repository.expressions();
    for (final item in expressions) {
      final score = _score(
        tokens,
        '${item.term} ${item.translation} ${item.tags.join(' ')}',
        exact: item.term,
      );
      if (score > 0) {
        scored.add((
          score: score,
          citation: AiCitation(
            resourceId: item.id,
            type: AiCitationType.expression,
            title: item.term,
            snippet: item.translation,
          ),
        ));
      }
    }
    final grammar = await _repository.grammarPoints();
    for (final item in grammar) {
      final score = _score(
        tokens,
        '${item.title} ${item.explanation}',
        exact: item.title,
      );
      if (score > 0) {
        scored.add((
          score: score,
          citation: AiCitation(
            resourceId: item.id,
            type: AiCitationType.grammar,
            title: item.title,
            snippet: item.explanation.substring(
              0,
              math.min(220, item.explanation.length),
            ),
          ),
        ));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final result =
        scored.take(limit.clamp(1, 12)).map((e) => e.citation).toList();
    _lastValidIds = result.map((e) => e.resourceId).toSet();
    return result;
  }

  @override
  bool validateCitationIds(Iterable<String> ids) =>
      ids.every(_lastValidIds.contains);

  static double _score(Set<String> query, String candidate, {String? exact}) {
    final normalized = candidate.toLowerCase();
    final candidateTokens = _tokens(candidate);
    var score = 0.0;
    for (final token in query) {
      if (candidateTokens.contains(token)) {
        score += 2;
      } else if (normalized.contains(token)) {
        score += 1;
      }
    }
    if (exact != null && query.join(' ').contains(exact.toLowerCase())) {
      score += 4;
    }
    return score;
  }

  static Set<String> _tokens(String raw) => raw
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((e) => e.length > 1)
      .toSet();
}
