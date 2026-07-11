// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/courses/components/section_visuals.dart';
import 'package:varnamala/views/theme.dart';

/// A compact, tappable section header card displayed at the top of the course tree.
///
/// Shows only the current section name and a thematic icon. The full description
/// is visible on the [SectionPickerPage].
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Only rebuild when the current section identity changes — not on every
    // CourseProvider body-load notification for other sections.
    return Selector<CourseProvider, Section?>(
      selector: (_, provider) => provider.currentSection,
      builder: (context, section, _) {
        if (section == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _SectionHeaderCard(
            section: section,
            onTap: () => context.router.push(const SectionPickerRoute()),
          ),
        );
      },
    );
  }
}

class _SectionHeaderCard extends StatelessWidget {
  final Section section;
  final VoidCallback onTap;

  const _SectionHeaderCard({
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SectionVisuals.colorsFor(section.id);

    return Material(
      color: VarnamalaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            boxShadow: VarnamalaTheme.softShadow,
          ),
          child: Row(
            children: [
              // Thematic section icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(
                    VarnamalaTheme.radiusMedium,
                  ),
                ),
                child: Icon(
                  SectionVisuals.iconFor(section.id),
                  size: 24,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 14),
              // Section name only
              Expanded(
                child: Text(
                  section.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: VarnamalaTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                color: VarnamalaTheme.textHint.withValues(alpha: 0.6),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
