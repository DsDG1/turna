import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/core/theme.dart';

/// File name, deck counts, and archetype chips at the top of the import preview.
class AnkiImportPreviewHeaderCard extends StatelessWidget {
  const AnkiImportPreviewHeaderCard({super.key, required this.preview});

  final OfficialAnkiImportPreviewModel preview;

  @override
  Widget build(BuildContext context) {
    final fileName = preview.filePath.split(RegExp(r'[/\\]')).last;
    final rootName =
        fileName.isEmpty ? AppStrings.ankiPreviewDefaultRootName : fileName;
    final hasChoice = preview.schemas.any((s) {
      final sug = preview.suggestions[s.notetypeId];
      return sug?.cardArchetype.name == 'choice';
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: TurnaTheme.brandNavy.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rootName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.ankiPreviewParsedDecks(preview.decks.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StatStrip(
            items: [
              (AppStrings.ankiDecksLabel, preview.decks.length),
              (AppStrings.ankiCardsLabel, preview.cardCount),
              (AppStrings.ankiNotesLabel, preview.noteCount),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (hasChoice)
                _ArchetypeChip(
                  icon: Icons.radio_button_checked_rounded,
                  label: AppStrings.ankiPreviewChoiceDetected,
                  color: TurnaTheme.brandTeal,
                )
              else
                _ArchetypeChip(
                  icon: Icons.flip_to_back_rounded,
                  label: AppStrings.ankiPreviewFlipCards,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              _ArchetypeChip(
                icon: Icons.touch_app_outlined,
                label: AppStrings.ankiPreviewTapSectionHint,
                color: TurnaTheme.brandNavy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchetypeChip extends StatelessWidget {
  const _ArchetypeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
