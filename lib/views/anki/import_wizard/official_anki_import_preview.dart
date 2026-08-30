import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_view_helpers.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/theme.dart';

/// Official-first preview step: deck list from the official collection and
/// the per-notetype recognition "four-piece" (doc 37 §4) — sample card by
/// binding, archetype chip + confidence band, expandable evidence, and a
/// tap-through to the override editor.
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
    final triage = {
      for (final schema in schemas)
        schema.notetypeId: officialRecognitionTriage(preview, schema),
    };
    final blocking = triage.values.where((value) => value.blocking).length;
    final advisory = triage.values.where((value) => value.advisory).length;
    final issues = schemas
        .where((schema) =>
            triage[schema.notetypeId]!.blocking ||
            triage[schema.notetypeId]!.advisory)
        .toList();
    final shownSchemas = preview.showAllRecognition ? schemas : issues;
    final statusColor = blocking > 0
        ? TurnaTheme.error
        : advisory > 0
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    final hasBlocking = triage.values.any((value) => value.blocking);
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
                    _RecognitionCard(
                      schema: schema,
                      suggestion: preview.suggestions[schema.notetypeId],
                      triage: triage[schema.notetypeId]!,
                      confirmed: preview.confirmedNotetypes
                          .contains(schema.notetypeId),
                      onTap: () => onOpenMapping(schema),
                    ),
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

class _RecognitionCard extends StatelessWidget {
  const _RecognitionCard({
    required this.schema,
    required this.suggestion,
    required this.triage,
    required this.confirmed,
    required this.onTap,
  });

  final OfficialAnkiProjectionSchema schema;
  final OfficialAnkiMappingSuggestion? suggestion;
  final OfficialRecognitionTriage triage;
  final bool confirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (suggestion == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('无法识别'),
        subtitle: Text(
          AppStrings.ankiMappingSourceName(schema.name),
          style: TextStyle(
            color: TurnaTheme.textHintColor(context),
            fontSize: 11,
          ),
        ),
        trailing: const Icon(Icons.error_outline_rounded,
            size: 18, color: TurnaTheme.error),
        onTap: onTap,
      );
    }
    final s = suggestion!;
    final sample = schema.samples.firstOrNull;
    final promptIndex = s.role(FieldRole.prompt)?.fieldIndex;
    final responseIndex = s.role(FieldRole.response)?.fieldIndex;
    final sampleFront = sample == null || promptIndex == null
        ? null
        : importSamplePreview(
            promptIndex < sample.fields.length
                ? sample.fields[promptIndex]
                : '',
          );
    final sampleBack = sample == null || responseIndex == null
        ? null
        : importSamplePreview(
            responseIndex < sample.fields.length
                ? sample.fields[responseIndex]
                : '',
          );
    final rowColor = triage.blocking
        ? TurnaTheme.error
        : triage.advisory
            ? TurnaTheme.warning
            : triage.skipped
                ? TurnaTheme.textHintColor(context)
                : TurnaTheme.brandTeal;
    final statusText = triage.blocking
        ? AppStrings.ankiMappingStatusBlocking
        : triage.advisory
            ? AppStrings.ankiMappingStatusAdvisory
            : triage.skipped
                ? AppStrings.ankiOfficialMappingSkipped
                : AppStrings.ankiMappingStatusRecognized;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: rowColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                    border: Border.all(color: rowColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    officialRecognitionChipLabel(s),
                    key: Key('recognition-chip-${schema.notetypeId}'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: rowColor,
                    ),
                  ),
                ),
                if (confirmed) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_outlined,
                      size: 14, color: TurnaTheme.brandTeal),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sampleFront != null || sampleBack != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${sampleFront ?? '（空）'}  →  ${sampleBack ?? '（空）'}',
                    key: Key('recognition-sample-${schema.notetypeId}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  AppStrings.ankiMappingSourceName(schema.name),
                  style: TextStyle(
                    color: TurnaTheme.textHintColor(context),
                    fontSize: 11,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: rowColor, fontSize: 12),
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Icon(
              triage.blocking
                  ? Icons.error_outline_rounded
                  : triage.advisory
                      ? Icons.help_outline_rounded
                      : triage.skipped
                          ? Icons.skip_next_outlined
                          : Icons.check_circle_outline_rounded,
              size: 18,
              color: rowColor,
            ),
            onTap: onTap,
          ),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('recognition-evidence-${schema.notetypeId}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '为什么这么识别',
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
              children: [
                for (final line in officialRecognitionEvidenceLines(s))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        color: TurnaTheme.textHintColor(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
