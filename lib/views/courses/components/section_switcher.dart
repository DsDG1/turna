// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/course_provider.dart';
import 'package:words625/views/theme.dart';

/// A section switcher chip displayed at the top-left of the course tree.
///
/// Shows the current section name with a dropdown arrow. Tapping opens a
/// [PopupMenuButton] listing all available sections.
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<CourseProvider>(
      builder: (context, provider, _) {
        final currentName = provider.currentSection?.name ?? 'Section 1';

        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: PopupMenuButton<int>(
            offset: const Offset(0, 40),
            color: VarnamalaTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
            ),
            onSelected: (index) => provider.switchToSection(index),
            itemBuilder: (context) {
              return List.generate(provider.sections.length, (index) {
                final section = provider.sections[index];
                final isSelected = index == provider.currentSectionIndex;
                return PopupMenuItem<int>(
                  value: index,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isSelected
                            ? VarnamalaTheme.peacockTeal
                            : VarnamalaTheme.textHint,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        section.name,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                          color: isSelected
                              ? VarnamalaTheme.peacockTeal
                              : VarnamalaTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              });
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(VarnamalaTheme.radiusRound),
                border: Border.all(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    size: 16,
                    color: VarnamalaTheme.peacockTeal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    currentName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: VarnamalaTheme.peacockTeal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: VarnamalaTheme.peacockTeal,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
