import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/ai/textbook/knowledge_merger.dart';
import 'package:varnamala/application/ai/textbook/knowledge_schema.dart';

void main() {
  ChapterResult chapterWith({
    List<Map<String, dynamic>> words = const [],
    List<Map<String, dynamic>> expressions = const [],
    List<Map<String, dynamic>> grammar = const [],
  }) {
    return ChapterResult(
      chapter: const TextbookChapter(
        title: 'Ch1',
        markdown: 'body',
        slug: 'ch1',
      ),
      knowledge: KnowledgePoints(
        words: words,
        expressions: expressions,
        grammarPoints: grammar,
      ),
    );
  }

  test('analyze counts new vs duplicate', () {
    final results = [
      chapterWith(
        words: [
          {'id': 'w-new'},
          {'id': 'w-old'},
        ],
        expressions: [
          {'id': 'e-old'},
        ],
      ),
    ];
    final report = const KnowledgeMerger().analyze(
      results,
      existingWordIds: {'w-old'},
      existingExpressionIds: {'e-old'},
      existingGrammarIds: {},
    );
    expect(report.newWords, 1);
    expect(report.duplicateWords, 1);
    expect(report.duplicateExpressions, 1);
    expect(report.newExpressions, 0);
    expect(report.totalNew, 1);
    expect(report.totalDuplicates, 2);
  });

  test('skipExisting drops colliding resources', () {
    final results = [
      chapterWith(
        words: [
          {'id': 'w-new', 'term': 'a'},
          {'id': 'w-old', 'term': 'b'},
        ],
      ),
    ];
    const KnowledgeMerger().apply(
      results,
      strategy: ImportStrategy.skipExisting,
      existingWordIds: {'w-old'},
      existingExpressionIds: {},
      existingGrammarIds: {},
    );
    expect(results.single.knowledge!.words.map((w) => w['id']), ['w-new']);
  });

  test('appendAsNew rewrites all resource ids', () {
    final results = [
      chapterWith(
        words: [
          {'id': 'w1', 'term': 'a'},
        ],
        expressions: [
          {'id': 'e1', 'term': 'b'},
        ],
      ),
    ];
    const KnowledgeMerger().apply(
      results,
      strategy: ImportStrategy.appendAsNew,
      existingWordIds: {},
      existingExpressionIds: {},
      existingGrammarIds: {},
    );
    final wId = results.single.knowledge!.words.single['id'] as String;
    final eId = results.single.knowledge!.expressions.single['id'] as String;
    expect(wId, startsWith('w1-'));
    expect(eId, startsWith('e1-'));
    expect(wId, isNot('w1'));
  });
}
