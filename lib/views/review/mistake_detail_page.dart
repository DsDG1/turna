// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/courses/languages/dictionary.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/session_shell.dart';

/// 错题详情 ——「湿地雾光」R09 学习笔记式详情页。
///
/// 分段对照：**我的作答 / 正确表达 / 解析**三段，来源与时间作旁注；
/// 底部是稳定的「重练」主操作（[SessionPrimaryAction] → 错题练习页）。
/// 数据全部读自 [MistakeEntry] 与课程查表，不写任何仓储（「现在我会了」
/// 的重写记录除外，走既有 [MistakeProvider.recordRewrite]）。
@RoutePage()
class MistakeDetailPage extends StatelessWidget {
  const MistakeDetailPage({super.key, required this.entry});

  final MistakeEntry entry;

  @override
  Widget build(BuildContext context) {
    final word = entry.wordId != null ? vocabById[entry.wordId!] : null;
    final grammar = entry.grammarPointId != null
        ? grammarPointById[entry.grammarPointId!]
        : null;
    final question = word?.term ??
        grammar?.title ??
        (entry.interactionId.isNotEmpty
            ? entry.interactionId
            : AppStrings.reviewUnknownQuestion);
    final correct = word?.translation ?? entry.correctAnswer;

    // 解析：语法错题给语法讲解；词条类给词典释义（与释义相同的除外）。
    final String? analysis;
    if ((grammar?.explanation.isNotEmpty ?? false)) {
      analysis = grammar!.explanation;
    } else if (word == null && correct.isNotEmpty) {
      final meaning = getWordMeaning(correct);
      analysis = meaning == correct ? null : meaning;
    } else {
      analysis = null;
    }
    final typeLabel = grammar != null
        ? AppStrings.reviewGrammarLabel
        : word != null
            ? AppStrings.reviewWordsLabel
            : AppStrings.mistakeDashboardOtherType;

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(title: Text(AppStrings.mistakeDetailTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pageGutterMist,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 问题摘要 + 来源 / 时间旁注 ────────────────────────
              Text(question, style: AppTextStyles.sectionTitle(context)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$typeLabel · ${AppStrings.timeAgo(entry.timestamp)}',
                style: AppTextStyles.captionSm(context).copyWith(fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── 分段对照 ─────────────────────────────────────────
              _CompareSection(
                label: AppStrings.mistakeDetailMyAnswer,
                value: entry.userAnswer.isEmpty
                    ? AppStrings.reviewDash
                    : entry.userAnswer,
                valueColor: TurnaTheme.error,
              ),
              _CompareSection(
                label: AppStrings.mistakeDetailCorrect,
                value: correct.isEmpty ? AppStrings.reviewDash : correct,
                valueColor: TurnaTheme.brandTeal,
              ),
              if (analysis != null && analysis.isNotEmpty)
                _CompareSection(
                  label: AppStrings.mistakeDetailAnalysis,
                  value: analysis,
                ),

              // ── 次级动作（重写 / 复习语法） ────────────────────────
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    onPressed: () => context
                        .read<MistakeProvider>()
                        .recordRewrite(entry.id),
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 18),
                    label: Text(AppStrings.reviewGotItNow),
                  ),
                  if (entry.grammarPointId != null)
                    TextButton.icon(
                      onPressed: () async {
                        await context
                            .read<GrammarReviewProvider>()
                            .markDueNow(entry.grammarPointId!);
                        if (context.mounted) {
                          // 保真：与列表页旧入口同一导航语义。
                          unawaited(
                            context.router.push(const GrammarReviewRoute()),
                          );
                        }
                      },
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: Text(AppStrings.reviewReviewGrammar),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
      // ── 稳定的「重练」动作 ─────────────────────────────────────
      bottomNavigationBar: SessionActionBand(
        child: SessionPrimaryAction(
          label: AppStrings.mistakeDetailPractice,
          onPressed: () =>
              context.router.push(MistakePracticeRoute(entry: entry)),
          trailingIcon: Icons.play_arrow_rounded,
        ),
      ),
    );
  }
}

/// 对照段：小标签 + 正文，发丝线分隔。
class _CompareSection extends StatelessWidget {
  const _CompareSection({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            height: 1,
            color: TurnaTheme.dividerBg(context),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(label, style: AppTextStyles.caption(context)),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            value,
            style: AppTextStyles.bodyText(context).copyWith(
                  color: valueColor,
                  fontWeight: valueColor != null ? FontWeight.w600 : null,
                ),
          ),
        ],
      ),
    );
  }
}
