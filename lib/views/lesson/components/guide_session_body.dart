// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/guide_page.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/guide_block_view.dart';
import 'package:turna/views/lesson/components/lesson_presentation.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

class GuideSessionBody extends StatelessWidget {
  const GuideSessionBody({
    super.key,
    required this.lesson,
    required this.scrollController,
  });

  final Lesson lesson;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final profile = lessonPresentationProfile(lesson.template);
    return Column(
      children: [
        SessionSourceLine(icon: profile.icon, label: lesson.name),
        Expanded(
          child: Selector<LessonViewModel, ({int index, bool complete})>(
            selector: (_, vm) =>
                (index: vm.guidePageIndex, complete: vm.isComplete),
            builder: (context, selected, _) {
              final vm = context.read<LessonViewModel>();
              final page = vm.currentGuidePage;
              if (page == null) {
                return Center(child: Text(AppStrings.lessonNoContent));
              }
              return SingleChildScrollView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: TurnaPageContent(
                  maxWidth: profile.maxWidth,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageMargin,
                  ),
                  child: selected.complete
                      ? const _GuideCompletion()
                      : _GuidePageView(page: page),
                ),
              );
            },
          ),
        ),
        Selector<LessonViewModel, ({int index, bool complete})>(
          selector: (_, vm) =>
              (index: vm.guidePageIndex, complete: vm.isComplete),
          builder: (context, selected, _) {
            final vm = context.read<LessonViewModel>();
            return SessionActionBand(
              child: selected.complete
                  ? _GuideCompletionActions(page: vm.currentGuidePage)
                  : _GuidePageActions(
                      pageIndex: selected.index,
                      pageCount: vm.guidePageCount,
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _GuidePageView extends StatelessWidget {
  const _GuidePageView({required this.page});

  final GuidePage page;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(page.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page.kicker.isNotEmpty) ...[
          Text(
            page.kicker,
            style: AppTextStyles.caption(context)
                .copyWith(color: TurnaTheme.brandTeal),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(page.title, style: AppTextStyles.pageTitle(context)),
        if (page.intro.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            page.intro,
            style: AppTextStyles.bodyText(context).copyWith(
              height: 1.6,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        for (final block in page.blocks)
          GuideBlockView(key: ValueKey(block.id), block: block),
      ],
    );
  }
}

class _GuidePageActions extends StatelessWidget {
  const _GuidePageActions({required this.pageIndex, required this.pageCount});

  final int pageIndex;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<LessonViewModel>();
    final isLast = pageIndex >= pageCount - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionPrimaryAction(
          label: isLast
              ? AppStrings.guideFinishReading
              : AppStrings.guideNextPage,
          trailingIcon: isLast ? TurnaIconId.check : TurnaIconId.arrowForward,
          onPressed: vm.nextGuidePage,
        ),
        if (pageIndex > 0)
          TextButton.icon(
            onPressed: vm.previousGuidePage,
            icon: const TurnaIcon(TurnaIconId.arrowBack, size: 18),
            label: Text(AppStrings.guidePreviousPage),
          ),
      ],
    );
  }
}

class _GuideCompletion extends StatelessWidget {
  const _GuideCompletion();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
            ),
            child: const Center(
              child: TurnaIcon(
                TurnaIconId.explore,
                size: 48,
                color: TurnaTheme.brandTeal,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            AppStrings.guideCompleteTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.pageTitle(context),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.guideCompleteBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyText(context).copyWith(
              height: 1.6,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCompletionActions extends StatelessWidget {
  const _GuideCompletionActions({required this.page});

  final GuidePage? page;

  @override
  Widget build(BuildContext context) {
    final nextLessonId = page?.nextLessonId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SessionPrimaryAction(
          label: nextLessonId == null
              ? AppStrings.lessonBackToCourses
              : (page!.nextLabel ?? AppStrings.guideDefaultNext),
          trailingIcon: TurnaIconId.arrowForward,
          onPressed: () => _goNext(context),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: context.read<LessonViewModel>().restartGuide,
              icon: const TurnaIcon(TurnaIconId.restart, size: 18),
              label: Text(AppStrings.guideReadAgain),
            ),
            if (nextLessonId != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppStrings.lessonBackToCourses),
              ),
          ],
        ),
      ],
    );
  }

  void _goNext(BuildContext context) {
    final nextLessonId = page?.nextLessonId;
    if (nextLessonId == null || nextLessonId.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(
      context.router.push(
        NewLessonRoute(
          lessonId: nextLessonId,
          subLessonId: page?.nextSubLessonId,
        ),
      ),
    );
  }
}
