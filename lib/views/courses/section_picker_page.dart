// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class SectionPickerPage extends StatelessWidget {
  const SectionPickerPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.coursesChooseSection,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Selector<CourseProvider,
          ({List<Section> sections, String? currentId})>(
        selector: (_, p) => (
          sections: p.sections,
          currentId: p.currentSectionId,
        ),
        builder: (context, data, _) {
          final courseProvider = context.read<CourseProvider>();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: data.sections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final section = data.sections[index];
              final isSelected = section.id == data.currentId;
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
    final colors = SectionVisuals.colorsFor(section.id);

    return Material(
      color: TurnaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: isSelected
                ? Border.all(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
                    width: 2,
                  )
                : null,
            boxShadow: TurnaTheme.softShadow,
          ),
          child: Row(
            children: [
              // Thematic section icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(
                    TurnaTheme.radiusMedium,
                  ),
                ),
                child: Icon(
                  SectionVisuals.iconFor(section.id),
                  size: 28,
                  color: colors.foreground,
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
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.description,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: TurnaTheme.textSecondaryColor(context),
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
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textHint.withValues(alpha: 0.5),
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
