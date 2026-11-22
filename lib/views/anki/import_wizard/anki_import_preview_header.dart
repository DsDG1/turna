import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// File name, deck counts, and archetype chips at the top of the import preview.
class AnkiImportPreviewHeaderCard extends StatelessWidget {
  const AnkiImportPreviewHeaderCard({super.key, required this.preview});

  final OfficialAnkiImportPreviewModel preview;

  @override
  Widget build(BuildContext context) {
    final fileName = preview.filePath.split(RegExp(r'[/\\]')).last;
    final rootName = fileName.isEmpty
        ? AppStrings.ankiPreviewDefaultRootName
        : fileName;
    final hasChoice = preview.schemas.any((s) {
      final sug = preview.suggestions[s.notetypeId];
      return sug?.cardArchetype.name == 'choice';
    });

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      // ADR 0062：导入预览头是内容卡 → 中性淡彩玻璃。
      decoration: TurnaTheme.glassDecoration(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: const TurnaIcon(
                  TurnaIconId.book,
                  color: TurnaTheme.brandTeal,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rootName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle(context)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.ankiPreviewParsedDecks(preview.decks.length),
                      style: AppTextStyles.captionSm(context),
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
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 6,
            children: [
              if (hasChoice)
                _ArchetypeChip(
                  icon: TurnaIconId.radioChecked,
                  label: AppStrings.ankiPreviewChoiceDetected,
                  color: TurnaTheme.brandTeal,
                )
              else
                _ArchetypeChip(
                  icon: TurnaIconId.cards,
                  label: AppStrings.ankiPreviewFlipCards,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              _ArchetypeChip(
                icon: TurnaIconId.eye,
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

  final TurnaIconId icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TurnaIcon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTextStyles.caption(context).copyWith(
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
