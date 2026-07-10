// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class SectionPickerPage extends StatelessWidget {
  const SectionPickerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Choose a Section',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Consumer<CourseProvider>(
        builder: (context, courseProvider, _) {
          final sections = courseProvider.sections;
          final currentId = courseProvider.currentSectionId;

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final section = sections[index];
              final isSelected = section.id == currentId;
              return _SectionCard(
                section: section,
                isSelected: isSelected,
                onTap: () {
                  courseProvider.switchToSection(section.id);
                  Navigator.of(context).pop();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Section section;
  final bool isSelected;
  final VoidCallback onTap;

  const _SectionCard({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final level = section.level ?? '';
    final levelColors = _levelColors(level);

    return Material(
      color: VarnamalaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: isSelected
                ? Border.all(
                    color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
                    width: 2,
                  )
                : null,
            boxShadow: VarnamalaTheme.softShadow,
          ),
          child: Row(
            children: [
              // Level badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: levelColors.background,
                  borderRadius: BorderRadius.circular(
                    VarnamalaTheme.radiusMedium,
                  ),
                ),
                child: Center(
                  child: Text(
                    level,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: levelColors.foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Section name + description
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? VarnamalaTheme.peacockTeal
                            : VarnamalaTheme.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.description,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: VarnamalaTheme.textSecondaryColor(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Selection indicator
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: isSelected
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.textHint.withValues(alpha: 0.5),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({Color background, Color foreground}) _levelColors(String level) {
    switch (level) {
      case 'A1':
        return (
          background: VarnamalaTheme.success.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.successDark,
        );
      case 'A2':
        return (
          background: VarnamalaTheme.peacockCyan.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.peacockTeal,
        );
      case 'B1':
        return (
          background: VarnamalaTheme.warning.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.warning,
        );
      case 'B2':
        return (
          background: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.leagueAmethyst,
        );
      default:
        return (
          background: VarnamalaTheme.tintSoft,
          foreground: VarnamalaTheme.textSecondary,
        );
    }
  }
}
