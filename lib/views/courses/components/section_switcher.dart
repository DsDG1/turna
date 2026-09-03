// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/progress_provider.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/section_bottom_sheet.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/theme.dart';

/// Scroll-aware section entry used by the pinned course-tree header.
///
/// At the top of the page it renders as the full section card. As the course
/// tree scrolls, [collapseProgress] reduces it to a compact, always-available
/// section picker without running a separate time-based animation.
class SectionSwitcher extends StatelessWidget {
  final Section section;
  final double collapseProgress;

  const SectionSwitcher({
    required this.section,
    required this.collapseProgress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = collapseProgress.clamp(0.0, 1.0);
    final horizontal = _lerp(16, 12, t);
    final top = _lerp(16, 4, t);
    final bottom = _lerp(8, 4, t);

    return ColoredBox(
      color: TurnaTheme.scaffoldBg(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
        child: _SectionHeaderCard(
          section: section,
          collapseProgress: t,
          onTap: () => showSectionBottomSheet(context),
        ),
      ),
    );
  }

  static double _lerp(double begin, double end, double t) =>
      begin + (end - begin) * t;
}

/// Pins [SectionSwitcher] above the lazy unit list while allowing it to use
/// the spacious card presentation only when the page is at the top.
class SectionSwitcherHeaderDelegate extends SliverPersistentHeaderDelegate {
  static const double compactExtent = 56;
  static const double expandedExtent = 100;

  final Section section;

  const SectionSwitcherHeaderDelegate({required this.section});

  @override
  double get minExtent => compactExtent;

  @override
  double get maxExtent => expandedExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapseProgress =
        (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return SizedBox.expand(
      child: SectionSwitcher(
        section: section,
        collapseProgress: collapseProgress,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SectionSwitcherHeaderDelegate oldDelegate) =>
      !identical(oldDelegate.section, section) ||
      oldDelegate.section.id != section.id ||
      oldDelegate.section.name != section.name;
}

class _SectionHeaderCard extends StatelessWidget {
  final Section section;
  final double collapseProgress;
  final VoidCallback onTap;

  const _SectionHeaderCard({
    required this.section,
    required this.collapseProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SectionVisuals.colorsFor(section.id);
    final iconExtent = _lerp(48, 34);
    final iconSize = _lerp(24, 20);
    final gap = _lerp(14, 10);
    final radius = _lerp(TurnaTheme.radiusLarge, TurnaTheme.radiusMedium);
    final fontSize = _lerp(18, 15.5);
    final shadowAlpha = 1 - collapseProgress;
    final borderRadius = BorderRadius.circular(radius);

    final progress = context.select<ProgressProvider?, double>((p) {
      if (p == null || section.units.isEmpty) return 0.0;
      var total = 0;
      var completed = 0;
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          total++;
          if (p.isLessonCompleted(lesson.id)) completed++;
        }
      }
      return total == 0 ? 0.0 : completed / total;
    });

    return Semantics(
      button: true,
      label: '${AppStrings.coursesChooseSection}：${section.name}',
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: TurnaTheme.dividerBg(context).withValues(
              alpha: 0.6 + 0.4 * shadowAlpha,
            ),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: TurnaTheme.brandNavy.withValues(
                alpha: 0.07 * shadowAlpha,
              ),
              blurRadius: 10 * shadowAlpha,
              offset: Offset(0, 4 * shadowAlpha),
            ),
          ],
        ),
        child: Material(
          color: TurnaTheme.cardBg(context),
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _lerp(16, 12)),
                    child: Row(
                      children: [
                        Container(
                          width: iconExtent,
                          height: iconExtent,
                          decoration: BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(
                              _lerp(
                                TurnaTheme.radiusMedium,
                                TurnaTheme.radiusSmall,
                              ),
                            ),
                          ),
                          child: Icon(
                            SectionVisuals.iconFor(section.id),
                            size: iconSize,
                            color: colors.foreground,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: Text(
                            section.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: TurnaTheme.textPrimaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.unfold_more_rounded,
                          color: TurnaTheme.textHintColor(context),
                          size: _lerp(28, 22),
                        ),
                      ],
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 2.5,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? TurnaTheme.anatolianClay
                                : TurnaTheme.brandTeal,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _lerp(double begin, double end) =>
      begin + (end - begin) * collapseProgress;
}
