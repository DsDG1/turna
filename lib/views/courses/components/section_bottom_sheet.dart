// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// 章节切换底部弹层（R18 全局容器：拖手 / 标题 / 副题 / 关闭统一走
/// [showTurnaSheet]；面不透明——底下压着课程列表，半透明会透内容）。
Future<void> showSectionBottomSheet(BuildContext context) {
  return showTurnaSheet(
    context: context,
    title: AppStrings.coursesChooseSection,
    subtitle: AppStrings.coursesSectionSheetSubtitle(
      context.read<CourseProvider>().sections.length,
    ),
    isScrollControlled: true,
    body: const SectionBottomSheet(),
  );
}

/// Lightweight, modern modal bottom sheet for selecting course sections.
class SectionBottomSheet extends StatelessWidget {
  const SectionBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final a11y = context.watch<AccessibilityProvider>();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) || a11y.reducedMotion;

    return Consumer<CourseProvider>(
      builder: (context, courseProvider, _) {
        final sections = courseProvider.sections;
        final currentId = courseProvider.currentSectionId;

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMarginCompact,
            AppSpacing.xs,
            AppSpacing.pageMarginCompact,
            AppSpacing.lg + AppSpacing.xs,
          ),
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: sections.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sm + 2),
          itemBuilder: (context, index) {
            final section = sections[index];
            final isSelected = section.id == currentId;
            return _SectionSheetTile(
              section: section,
              isSelected: isSelected,
              reduceMotion: reduceMotion,
              onTap: () {
                courseProvider.switchToSection(section.id);
                Navigator.of(context).pop();
              },
            );
          },
        );
      },
    );
  }
}

class _SectionSheetTile extends StatelessWidget {
  final Section section;
  final bool isSelected;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _SectionSheetTile({
    required this.section,
    required this.isSelected,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SectionVisuals.colorsFor(section.id);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? TurnaTheme.brandTeal.withValues(alpha: 0.08)
            : TurnaTheme.cardBg(context),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(
          color: isSelected
              ? TurnaTheme.brandTeal.withValues(alpha: 0.45)
              : TurnaTheme.dividerBg(context),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: TurnaTheme.borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md + 2,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                // Thematic Icon Badge
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: TurnaIcon(
                    SectionVisuals.iconFor(section.id),
                    size: 22,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(width: AppSpacing.md + 2),
                // Section Title + Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      sectionNameWithLevel(
                        name: section.name,
                        level: section.level,
                        style: AppTextStyles.cardTitle(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? TurnaTheme.brandTeal
                              : TurnaTheme.textPrimaryColor(context),
                        ),
                      ),
                      if (section.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          section.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.captionSm(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Selected checkmark or arrow
                if (isSelected)
                  const TurnaIcon(
                    TurnaIconId.checkCircle,
                    color: TurnaTheme.brandTeal,
                    size: 20,
                  )
                else
                  TurnaIcon(
                    TurnaIconId.chevronRight,
                    color: TurnaTheme.textHintColor(context),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
