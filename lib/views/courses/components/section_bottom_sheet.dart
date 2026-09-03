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
import 'package:turna/views/theme.dart';

/// Shows a frosted-glass bottom sheet for quick section switching on the home screen.
Future<void> showSectionBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (modalContext) => const SectionBottomSheet(),
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
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.75;

    return Consumer2<CourseProvider, ProgressProvider>(
      builder: (context, courseProvider, progressProvider, _) {
        final sections = courseProvider.sections;
        final currentId = courseProvider.currentSectionId;

        return Container(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(TurnaTheme.radiusXLarge),
            ),
            boxShadow: TurnaTheme.cardShadow,
            border: Border(
              top: BorderSide(
                color: TurnaTheme.glassBorder(context),
                width: 1.2,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: TurnaTheme.dividerBg(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title and subtitle
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.coursesChooseSection,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: TurnaTheme.textPrimaryColor(context),
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${sections.length} ${AppStrings.coursesUnitProgress(0, 0).split(' ').lastOrNull ?? ''}'
                                  .trim(),
                              style: TextStyle(
                                fontSize: 12,
                                color: TurnaTheme.textHintColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Section list
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                  ),
                ),
              ],
            ),
          ),
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
            : TurnaTheme.surfaceColor(context),
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
                      Text(
                        section.name,
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
