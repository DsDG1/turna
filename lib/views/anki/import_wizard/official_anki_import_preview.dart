import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki/import_wizard/anki_import_controller.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/theme.dart';

/// Official-first preview step (maintainability plan §10.5): deck list
/// from the official collection, per-notetype mapping confirmation, and
/// the dedupe hint instead of the four legacy collision strategies
/// (same-hash re-imports no-op in the saga).
class OfficialAnkiImportPreview extends StatelessWidget {
  const OfficialAnkiImportPreview({
    super.key,
    required this.preview,
    required this.controller,
    required this.error,
    required this.onOpenMapping,
  });

  final OfficialAnkiImportPreviewModel preview;
  final AnkiImportController controller;
  final String? error;
  final void Function(OfficialAnkiProjectionSchema schema) onOpenMapping;

  @override
  Widget build(BuildContext context) {
    final schemas = preview.schemas;
    final attention = {
      for (final schema in schemas)
        schema.notetypeId: officialRecognitionAttention(preview, schema),
    };
    final blocking = attention.values
        .where((value) => value == ImportRecognitionAttention.blocking)
        .length;
    final advisory = attention.values
        .where((value) => value == ImportRecognitionAttention.advisory)
        .length;
    final issues = schemas
        .where((schema) =>
            attention[schema.notetypeId] == ImportRecognitionAttention.blocking ||
            attention[schema.notetypeId] == ImportRecognitionAttention.advisory)
        .toList();
    final shownSchemas = preview.showAllRecognition ? schemas : issues;
    final statusColor = blocking > 0
        ? TurnaTheme.error
        : advisory > 0
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    final hasBlocking = attention.values
        .contains(ImportRecognitionAttention.blocking);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: TurnaTheme.error),
                  ),
                ),
              if (preview.needsMapping)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppStrings.ankiOfficialNeedsMapping,
                    style: const TextStyle(color: TurnaTheme.error),
                  ),
                ),
              SectionCard(
                icon: Icons.layers_rounded,
                title: AppStrings.ankiPreviewSectionContent,
                hint: AppStrings.ankiOfficialPreviewBody,
                children: [
                  StatStrip(
                    items: [
                      (AppStrings.ankiDecksLabel, preview.decks.length),
                      (AppStrings.ankiNotesLabel, preview.noteCount),
                      (AppStrings.ankiCardsLabel, preview.cardCount),
                    ],
                  ),
                  if (preview.decks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Subheader(text: '牌组结构'),
                    const SizedBox(height: 4),
                    for (final deck in preview.decks)
                      InfoRow(
                        deck.name,
                        AppStrings.ankiDeckCardCount(
                          deck.newCount + deck.learnCount + deck.reviewCount,
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.ankiOfficialDedupeHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.category_rounded,
                title: AppStrings.ankiPreviewSectionMapping,
                hint: AppStrings.ankiOfficialMappingHint,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        blocking > 0
                            ? Icons.error_outline_rounded
                            : advisory > 0
                                ? Icons.help_outline_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          blocking > 0
                              ? AppStrings.ankiMappingSummaryBlocking(blocking)
                              : advisory > 0
                                  ? AppStrings.ankiMappingSummaryNeedsCheck(
                                      schemas.length - advisory, advisory)
                                  : AppStrings.ankiMappingSummaryAll(
                                      schemas.length),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.toggleShowAllRecognition,
                        child: Text(
                          preview.showAllRecognition
                              ? AppStrings.commonCollapse
                              : AppStrings.ankiMappingViewAll,
                        ),
                      ),
                    ],
                  ),
                  if (shownSchemas.isNotEmpty) const SizedBox(height: 6),
                  for (final schema in shownSchemas)
                    Builder(builder: (context) {
                      final level = attention[schema.notetypeId]!;
                      final rowColor = switch (level) {
                        ImportRecognitionAttention.blocking => TurnaTheme.error,
                        ImportRecognitionAttention.advisory => TurnaTheme.warning,
                        ImportRecognitionAttention.recognized =>
                          TurnaTheme.brandTeal,
                        ImportRecognitionAttention.skipped =>
                          TurnaTheme.textHintColor(context),
                      };
                      final statusText = switch (level) {
                        ImportRecognitionAttention.blocking =>
                          AppStrings.ankiMappingMustFix,
                        ImportRecognitionAttention.advisory =>
                          AppStrings.ankiMappingNeedsCheck,
                        ImportRecognitionAttention.recognized =>
                          AppStrings.ankiMappingRecognizedAuto,
                        ImportRecognitionAttention.skipped =>
                          AppStrings.ankiOfficialMappingSkipped,
                      };
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(schema.name),
                        subtitle: Text(
                          statusText,
                          style: TextStyle(color: rowColor, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              level == ImportRecognitionAttention.blocking
                                  ? Icons.error_outline_rounded
                                  : level == ImportRecognitionAttention.advisory
                                      ? Icons.help_outline_rounded
                                      : level == ImportRecognitionAttention.skipped
                                          ? Icons.skip_next_outlined
                                          : Icons.check_circle_outline_rounded,
                              size: 18,
                              color: rowColor,
                            ),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                        onTap: () => onOpenMapping(schema),
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
        StickyImportBar(
          onPressed: hasBlocking ? null : controller.commit,
          disabledHint:
              hasBlocking ? AppStrings.ankiMappingFixBlocking : null,
        ),
      ],
    );
  }
}
