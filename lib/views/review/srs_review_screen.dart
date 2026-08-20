import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/languages/expressions.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger_resolver.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/review/unified_review_page.dart';

/// Today's Turna SRS queue rendered by the shared course-style review shell.
///
/// Anki-owned cards are excluded by [SrsProvider.getDueWords] and
/// [SrsProvider.getDueExpressions]; unresolved internal IDs are skipped rather
/// than exposed as card text.
@RoutePage()
class SrsReviewPage extends StatefulWidget {
  const SrsReviewPage({super.key});

  @override
  State<SrsReviewPage> createState() => _SrsReviewPageState();
}

class _SrsReviewPageState extends State<SrsReviewPage> {
  List<ReviewItem>? _items;
  ReviewLedgerResolver? _ledgerResolver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items != null) return;

    final srs = context.read<SrsProvider>();
    final due = <SrsWord>[
      ...srs.getDueWords(),
      ...srs.getDueExpressions(),
    ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

    final items = <ReviewItem>[];
    for (final scheduled in due) {
      final word = scheduled.type == SrsItemType.word
          ? vocabById[scheduled.wordId]
          : null;
      final expression = scheduled.type == SrsItemType.expression
          ? expressionsById[scheduled.wordId]
          : null;
      final front = word?.term ?? expression?.term;
      final back = word?.translation ?? expression?.translation;
      if (front == null || back == null) continue;

      const source = TurnaCourseSource();
      items.add(
        ReviewItem(
          sessionItemId: 'srs-review-${scheduled.wordId}',
          source: source,
          content: StandardCourseCardContent(
            frontText: front,
            frontPronunciation:
                word?.pronunciation ?? expression?.pronunciation,
            backText: back,
            lessonName: scheduled.type == SrsItemType.word
                ? srs.getLessonNameForWord(scheduled.wordId)
                : srs.getLessonNameForExpression(scheduled.wordId),
          ),
          capabilities: ReviewCapabilities.standardCourse,
          schedulingKey: ReviewSchedulingKey(
            rawId: scheduled.wordId,
            source: source,
          ),
        ),
      );
    }

    _items = items;
    _ledgerResolver = ReviewLedgerResolver(
      turnaLedger: TurnaReviewLedger(srs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final resolver = _ledgerResolver;
    if (items == null || resolver == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return UnifiedReviewPage(
      items: items,
      ledgerResolver: resolver,
      title: AppStrings.reviewSrsAppBarTitle,
    );
  }
}
