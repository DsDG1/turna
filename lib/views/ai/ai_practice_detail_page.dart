// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_target_language_resolver.dart';
import 'package:turna/application/ai/practice/ai_practice_generator.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/ai/practice/ai_practice_quality.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_practice_actions.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_reading_layout.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// Course detail: the generated outline (unit → lesson → item count), the
/// content-verification report, and the generation history.
///
/// This is the page the library's "收纳结构" rests on: the row answers "what
/// is this", the detail page answers "what is inside it, was it checked, and
/// how many times was it generated". R14：阅读页纸面化（分区标题 + 纸面信息块），
/// 开始 / 重新生成收进底部动作带。
@RoutePage()
class AiPracticeDetailPage extends StatelessWidget {
  const AiPracticeDetailPage({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<AiPracticeJobQueue>();
    final course = queue.byId(courseId);
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: TurnaTopBar(
        centerTitle: true,
        showDivider: true,
        title: AppStrings.aiPracticeDetailTitle,
        actions: [
          if (course != null && course.isPlayable)
            IconButton(
              tooltip: course.pinned
                  ? AppStrings.aiPracticeUnfavorite
                  : AppStrings.aiPracticeFavorite,
              onPressed: () =>
                  togglePin(context, course, pinned: !course.pinned),
              icon: TurnaIcon(
                TurnaIconId.star,
                size: 20,
                color: course.pinned
                    ? TurnaTheme.anatolianClay
                    : TurnaTheme.textSecondaryColor(context),
              ),
            ),
        ],
      ),
      body: course == null
          ? Center(
              child: Text(
                AppStrings.aiPracticeRunnerEmpty,
                style: AppTextStyles.bodyText(context)
                    .copyWith(color: TurnaTheme.textSecondaryColor(context)),
              ),
            )
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageMargin,
                        AppSpacing.lg,
                        AppSpacing.pageMargin,
                        AppSpacing.lg,
                      ),
                      children: [
                        _Header(course: course),
                        if ((course.explanation ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _ExplanationSection(
                            explanation: course.explanation!.trim(),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        _QualitySection(course: course),
                        const SizedBox(height: AppSpacing.xl),
                        _OutlineSection(course: course),
                        if (course.versions.length > 1) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _HistorySection(course: course),
                        ],
                      ],
                    ),
                  ),
                  SessionActionBand(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageMargin,
                      AppSpacing.md,
                      AppSpacing.pageMargin,
                      AppSpacing.lg,
                    ),
                    child: course.isPlayable
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    retryAiPractice(context, course),
                                child: Text(AppStrings.aiPracticeRegenerate),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              SessionPrimaryAction(
                                label: AppStrings.aiPracticeStart,
                                onPressed: () =>
                                    openAiPractice(context, course),
                                trailingIcon: TurnaIconId.play,
                              ),
                            ],
                          )
                        : SessionPrimaryAction(
                            label: AppStrings.aiPracticeRegenerate,
                            onPressed: () => retryAiPractice(context, course),
                            trailingIcon: TurnaIconId.refresh,
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.course});

  final AiCourse course;

  @override
  Widget build(BuildContext context) {
    final expiry = _expiryText();
    final lang = AiTargetLanguageResolver.fromLanguageCode(course.languageCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          course.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textPrimaryColor(context),
              ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            _sourceLabel,
            if (!lang.isGeneric && lang.displayName != null) lang.displayName!,
            course.level,
            if (expiry != null) expiry,
          ].join(' · '),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: TurnaTheme.textSecondaryColor(context)),
        ),
        if (course.topic.trim().isNotEmpty &&
            course.topic.trim() != course.title) ...[
          const SizedBox(height: 8),
          Text(
            course.topic,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                  height: 1.5,
                ),
          ),
        ],
      ],
    );
  }

  String? _expiryText() {
    if (course.pinned) return AppStrings.aiPracticePermanentTag;
    final days = course.daysLeft(DateTime.now());
    if (days == null) return null;
    return days <= 0
        ? AppStrings.aiPracticeExpiringToday
        : AppStrings.aiPracticeExpiresInDays(days);
  }

  String get _sourceLabel => switch (course.source) {
        AiPracticeSource.mistakes => AppStrings.aiPracticeSourceMistakes,
        AiPracticeSource.weakWords => AppStrings.aiPracticeSourceWeakWords,
        AiPracticeSource.difficult => AppStrings.aiPracticeSourceDifficult,
        AiPracticeSource.custom => AppStrings.aiPracticeSourceCustom,
      };
}

class _ExplanationSection extends StatelessWidget {
  const _ExplanationSection({required this.explanation});

  final String explanation;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: AppStrings.aiPracticeDetailExplanation,
      accent: TurnaTheme.brandTeal,
      children: [
        Text(
          explanation,
          style: AppTextStyles.bodyText(context).copyWith(
            fontSize: 14,
            color: TurnaTheme.textSecondaryColor(context),
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _QualitySection extends StatelessWidget {
  const _QualitySection({required this.course});

  final AiCourse course;

  @override
  Widget build(BuildContext context) {
    final report = AiPracticeQualityReport.tryParse(course.qualityJson);
    final blockColor = report == null || report.passed
        ? TurnaTheme.brandTeal
        : TurnaTheme.error;
    return _Card(
      title: AppStrings.aiPracticeDetailQuality,
      accent: blockColor,
      children: [
        if (report == null)
          _muted(context, AppStrings.aiPracticeDetailNoReport)
        else ...[
          _muted(
            context,
            report.passed
                ? AppStrings.aiPracticeDetailQualityPassed
                : AppStrings.aiPracticeDetailQualityBlocked(
                    report.blocking.length,
                  ),
          ),
          if (report.advisory.isNotEmpty) ...[
            const SizedBox(height: 4),
            _muted(
              context,
              AppStrings.aiPracticeDetailQualityAdvisory(
                report.advisory.length,
              ),
            ),
          ],
          for (final issue in [...report.blocking, ...report.advisory].take(8))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '· ${issue.message}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: issue.advisory
                          ? TurnaTheme.textSecondaryColor(context)
                          : TurnaTheme.error,
                      height: 1.4,
                    ),
              ),
            ),
        ],
      ],
    );
  }
}

class _OutlineSection extends StatelessWidget {
  const _OutlineSection({required this.course});

  final AiCourse course;

  Future<void> _regenerateLesson(BuildContext context, String lessonId) async {
    final queue = context.read<AiPracticeJobQueue>();
    TurnaSnackBar.show(context, AppStrings.aiPracticeRegeneratingLesson);
    try {
      await queue.regenerateLesson(course.id, lessonId);
      if (!context.mounted) return;
      final updated = queue.byId(course.id);
      if (updated?.errorMessage != null && updated!.errorMessage!.isNotEmpty) {
        TurnaSnackBar.show(
          context,
          AppStrings.aiPracticeLessonRegenerateFailed(updated.errorMessage!),
        );
      } else {
        TurnaSnackBar.show(context, AppStrings.aiPracticeLessonRegenerated);
      }
    } on AiPracticeGenerationException catch (e) {
      if (!context.mounted) return;
      TurnaSnackBar.show(
        context,
        AppStrings.aiPracticeLessonRegenerateFailed(e.message),
      );
    } catch (e) {
      if (!context.mounted) return;
      TurnaSnackBar.show(
        context,
        AppStrings.aiPracticeLessonRegenerateFailed(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<AiPracticeJobQueue>();
    final canRegenLesson = course.isPlayable && !queue.hasActiveJob;
    final units = _parseUnits(course.sectionJson);
    return _Card(
      title: AppStrings.aiPracticeDetailOutline,
      accent: TurnaTheme.brandSky,
      children: [
        if (units.isEmpty)
          _muted(context, AppStrings.aiPracticeDetailEmpty)
        else
          for (final unit in units)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                  ),
                  for (final lesson in unit.lessons)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              lesson.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: TurnaTheme.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                            ),
                          ),
                          Text(
                            AppStrings.aiPracticeDetailItems(lesson.itemCount),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: TurnaTheme.textSecondaryColor(context),
                                ),
                          ),
                          if (canRegenLesson && lesson.id.isNotEmpty)
                            IconButton(
                              onPressed: () =>
                                  _regenerateLesson(context, lesson.id),
                              tooltip: AppStrings.aiPracticeRegenerateLesson,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.only(left: 6),
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: TurnaIcon(
                                TurnaIconId.refresh,
                                size: 15,
                                color: TurnaTheme.textHintColor(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }

  /// `unit → [(lesson id, name, item count)]` from the stored section JSON.
  static List<_UnitOutline> _parseUnits(String? sectionJson) {
    if (sectionJson == null) return const [];
    try {
      final decoded = jsonDecode(sectionJson);
      if (decoded is! Map) return const [];
      final units = <_UnitOutline>[];
      for (final unit in (decoded['units'] as List? ?? const [])) {
        if (unit is! Map) continue;
        final lessons = <_LessonOutline>[];
        for (final lesson in (unit['lessons'] as List? ?? const [])) {
          if (lesson is! Map) continue;
          final content = lesson['content'];
          var count = 0;
          if (content is Map) {
            for (final stage in (content['stages'] as List? ?? const [])) {
              if (stage is Map) {
                count += (stage['items'] as List? ?? const []).length;
              }
            }
            for (final sub in (content['subLessons'] as List? ?? const [])) {
              if (sub is Map) {
                for (final stage in (sub['stages'] as List? ?? const [])) {
                  if (stage is Map) {
                    count += (stage['items'] as List? ?? const []).length;
                  }
                }
              }
            }
            if (count == 0 && content['pages'] is List) {
              count = (content['pages'] as List).length;
            }
          }
          lessons.add(
            _LessonOutline(
              id: lesson['id']?.toString() ?? '',
              name:
                  lesson['name']?.toString() ?? lesson['id']?.toString() ?? '',
              itemCount: count,
            ),
          );
        }
        units.add(
          _UnitOutline(
            name: unit['name']?.toString() ?? unit['id']?.toString() ?? '',
            lessons: lessons,
          ),
        );
      }
      return units;
    } catch (_) {
      // Corrupt section JSON — show empty outline fallback.
      return const [];
    }
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.course});

  final AiCourse course;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: AppStrings.aiPracticeDetailVersions,
      accent: TurnaTheme.anatolianClay,
      children: [
        for (var i = 0; i < course.versions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.aiPracticeDetailVersion(
                      course.versions.length - i,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ),
                Text(
                  _statusLabel(course.versions[i].status),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            course.versions[i].status == AiPracticeStatus.failed
                                ? TurnaTheme.error
                                : TurnaTheme.textSecondaryColor(context),
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _statusLabel(AiPracticeStatus status) => switch (status) {
        AiPracticeStatus.ready => AppStrings.aiPracticeReady,
        AiPracticeStatus.queued => AppStrings.aiPracticeQueued,
        AiPracticeStatus.running => AppStrings.aiPracticeGenerating,
        AiPracticeStatus.failed => AppStrings.aiPracticeFailed,
        AiPracticeStatus.interrupted => AppStrings.aiPracticeInterrupted,
      };
}

class _UnitOutline {
  const _UnitOutline({required this.name, required this.lessons});

  final String name;
  final List<_LessonOutline> lessons;
}

class _LessonOutline {
  const _LessonOutline({
    required this.id,
    required this.name,
    required this.itemCount,
  });

  final String id;
  final String name;
  final int itemCount;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TurnaReadingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: TurnaTheme.borderRadius,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTextStyles.cardTitle(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          ...children,
        ],
      ),
    );
  }
}

Widget _muted(BuildContext context, String text) {
  return Text(
    text,
    style: AppTextStyles.captionSm(context).copyWith(height: 1.5),
  );
}
