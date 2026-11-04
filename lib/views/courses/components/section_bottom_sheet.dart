// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/core/theme.dart';

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

    return Consumer2<CourseProvider, ProgressProvider>(
      builder: (context, courseProvider, progressProvider, _) {
        final sections = courseProvider.sections;
        final currentId = courseProvider.currentSectionId;

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    final borderRadius = BorderRadius.circular(TurnaTheme.radiusMedium);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? TurnaTheme.brandTeal.withValues(alpha: 0.08)
            : TurnaTheme.cardBg(context),
        borderRadius: borderRadius,
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
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Thematic Icon Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                  ),
                  child: Icon(
                    SectionVisuals.iconFor(section.id),
                    size: 22,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(width: 14),
                // Section Title + Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      sectionNameWithLevel(
                        name: section.name,
                        level: section.level,
                        style: TextStyle(
                          fontSize: 15,
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
                          style: TextStyle(
                            fontSize: 12,
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Selected checkmark or arrow
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: TurnaTheme.brandTeal,
                    size: 20,
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
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
