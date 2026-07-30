// Project imports:
import 'package:varnamala/application/ai/textbook/knowledge_schema.dart';

/// Collision resolution strategies when importing a textbook section.
enum ImportStrategy { merge, skipExisting, forceReplace, appendAsNew }

/// Structured collision report for UI / previews.
class CollisionReport {
  const CollisionReport({
    this.newWords = 0,
    this.newExpressions = 0,
    this.newGrammar = 0,
    this.duplicateWords = 0,
    this.duplicateExpressions = 0,
    this.duplicateGrammar = 0,
  });

  final int newWords;
  final int newExpressions;
  final int newGrammar;
  final int duplicateWords;
  final int duplicateExpressions;
  final int duplicateGrammar;

  int get totalNew => newWords + newExpressions + newGrammar;
  int get totalDuplicates =>
      duplicateWords + duplicateExpressions + duplicateGrammar;

  /// Legacy map shape (for older call sites).
  Map<String, int> toMap() => {
        'newWords': newWords,
        'newExpressions': newExpressions,
        'newGrammar': newGrammar,
        'duplicateWords': duplicateWords,
        'duplicateExpressions': duplicateExpressions,
        'duplicateGrammar': duplicateGrammar,
      };
}

/// Analyzes and resolves collisions between extracted textbook knowledge and
/// existing course resources. Mirrors `tool/gui/src/backend/knowledge_merger.py`.
class KnowledgeMerger {
  const KnowledgeMerger();

  /// Returns a collision report without mutating [results].
  CollisionReport analyze(
    List<ChapterResult> results, {
    required Set<String> existingWordIds,
    required Set<String> existingExpressionIds,
    required Set<String> existingGrammarIds,
  }) {
    var newWords = 0;
    var newExpressions = 0;
    var newGrammar = 0;
    var duplicateWords = 0;
    var duplicateExpressions = 0;
    var duplicateGrammar = 0;

    for (final result in results) {
      if (!result.keep || result.knowledge == null) continue;
      final k = result.knowledge!;
      for (final w in k.words) {
        final id = w['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (existingWordIds.contains(id)) {
          duplicateWords++;
        } else {
          newWords++;
        }
      }
      for (final e in k.expressions) {
        final id = e['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (existingExpressionIds.contains(id)) {
          duplicateExpressions++;
        } else {
          newExpressions++;
        }
      }
      for (final g in k.grammarPoints) {
        final id = g['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (existingGrammarIds.contains(id)) {
          duplicateGrammar++;
        } else {
          newGrammar++;
        }
      }
    }

    return CollisionReport(
      newWords: newWords,
      newExpressions: newExpressions,
      newGrammar: newGrammar,
      duplicateWords: duplicateWords,
      duplicateExpressions: duplicateExpressions,
      duplicateGrammar: duplicateGrammar,
    );
  }

  /// Applies [strategy] to [results] (mutates knowledge maps in place).
  ///
  /// - [ImportStrategy.skipExisting]: drop resources whose ids already exist.
  /// - [ImportStrategy.appendAsNew]: suffix all resource ids for uniqueness.
  /// - [ImportStrategy.merge] / [ImportStrategy.forceReplace]: keep ids; DB
  ///   upsert handles overwrites for forceReplace at section level.
  void apply(
    List<ChapterResult> results, {
    required ImportStrategy strategy,
    required Set<String> existingWordIds,
    required Set<String> existingExpressionIds,
    required Set<String> existingGrammarIds,
  }) {
    if (strategy == ImportStrategy.skipExisting) {
      for (final result in results) {
        if (!result.keep || result.knowledge == null) continue;
        final k = result.knowledge!;
        result.knowledge = k.copyWith(
          words: k.words.where((w) {
            final id = w['id']?.toString() ?? '';
            return id.isNotEmpty && !existingWordIds.contains(id);
          }).toList(),
          expressions: k.expressions.where((e) {
            final id = e['id']?.toString() ?? '';
            return id.isNotEmpty && !existingExpressionIds.contains(id);
          }).toList(),
          grammarPoints: k.grammarPoints.where((g) {
            final id = g['id']?.toString() ?? '';
            return id.isNotEmpty && !existingGrammarIds.contains(id);
          }).toList(),
        );
      }
      return;
    }

    if (strategy == ImportStrategy.appendAsNew) {
      final suffix = DateTime.now().millisecondsSinceEpoch;
      for (final result in results) {
        if (!result.keep || result.knowledge == null) continue;
        final k = result.knowledge!;
        result.knowledge = k.copyWith(
          words: [
            for (final w in k.words)
              {...w, 'id': '${w['id']?.toString() ?? 'w'}-$suffix'},
          ],
          expressions: [
            for (final e in k.expressions)
              {...e, 'id': '${e['id']?.toString() ?? 'e'}-$suffix'},
          ],
          grammarPoints: [
            for (final g in k.grammarPoints)
              {...g, 'id': '${g['id']?.toString() ?? 'g'}-$suffix'},
          ],
        );
      }
      return;
    }

    // merge and forceReplace keep IDs as-is; section-level plan decides write.
  }
}
