// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/import_wizard/anki_import_controller.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/import_wizard/question_type.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/anki_notetype_mapping_editor.dart';
import 'package:turna/views/theme.dart';

/// Legacy preview step (maintainability plan §10.5): renders the sealed
/// [LegacyAnkiImportPreviewModel]. Pure view — every mutation goes through
/// controller intents. The question-type chips are the primary interaction;
/// collision strategy and grouping toggles are fixed to their defaults
/// (merge + smart grouping) and only summarized in the advanced card.
class LegacyAnkiImportPreview extends StatelessWidget {
  const LegacyAnkiImportPreview({
    super.key,
    required this.preview,
    required this.controller,
    required this.aiReady,
    required this.onEditMapping,
    required this.onIdentifyWithAi,
  });

  final LegacyAnkiImportPreviewModel preview;
  final AnkiImportController controller;
  final bool aiReady;
  final void Function(int mid, AnkiNotetype notetype) onEditMapping;
  final VoidCallback onIdentifyWithAi;

  @override
  Widget build(BuildContext context) {
    final collection = preview.collection;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _buildMappingSection(context, collection),
              const SizedBox(height: 12),
              _buildContentSection(context, collection),
              const SizedBox(height: 12),
              AdvancedOptionsCard(
                summary: AppStrings.ankiAdvancedOptionsSummary,
                children: [
                  _buildOrganizationSummary(context),
                  _buildLearningProgressSwitch(context),
                ],
              ),
            ],
          ),
        ),
        StickyImportBar(
          onPressed: _hasBlocking(collection) ? null : controller.commit,
          disabledHint: _hasBlocking(collection)
              ? AppStrings.ankiMappingFixBlocking
              : null,
        ),
      ],
    );
  }

  bool _hasBlocking(AnkiCollection collection) =>
      collection.notetypes.entries.any(
        (entry) =>
            legacyRecognitionAttention(preview, entry.key, entry.value) ==
            ImportRecognitionAttention.blocking,
      );

  /// Section 1: what each card type is — one row per notetype with a
  /// question-type chip selector as the primary control.
  Widget _buildMappingSection(
    BuildContext context,
    AnkiCollection collection,
  ) {
    final entries = collection.notetypes.entries.toList();
    final attention = {
      for (final entry in entries)
        entry.key: legacyRecognitionAttention(preview, entry.key, entry.value),
    };
    final blocking = attention.values
        .where((value) => value == ImportRecognitionAttention.blocking)
        .length;
    final advisory = attention.values
        .where((value) => value == ImportRecognitionAttention.advisory)
        .length;
    final issues = entries
        .where((entry) =>
            attention[entry.key] == ImportRecognitionAttention.blocking ||
            attention[entry.key] == ImportRecognitionAttention.advisory)
        .toList();
    final shownEntries = preview.showAllRecognition ? entries : issues;
    final statusColor = blocking > 0
        ? TurnaTheme.error
        : advisory > 0
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    return SectionCard(
      icon: Icons.auto_awesome_outlined,
      title: AppStrings.ankiPreviewSectionMapping,
      hint: AppStrings.ankiQuestionTypeSectionHint,
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
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                blocking > 0
                    ? AppStrings.ankiMappingSummaryBlocking(blocking)
                    : advisory > 0
                        ? AppStrings.ankiMappingSummaryNeedsCheck(
                            entries.length - advisory, advisory)
                        : AppStrings.ankiMappingSummaryAll(entries.length),
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
        if (shownEntries.isNotEmpty) const SizedBox(height: 6),
        for (final entry in shownEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NotetypeMappingRow(
              notetype: entry.value,
              mapping: preview.mappings[entry.key],
              recognition: preview.recognitionResults[entry.key],
              attention: attention[entry.key]!,
              cardCount: _cardCount(collection, entry.key),
              onTypeSelected: (type) => unawaited(
                _saveType(collection, entry.key, entry.value, type),
              ),
              onEdit: () => onEditMapping(entry.key, entry.value),
            ),
          ),
        if (advisory > 0 && aiReady) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: preview.isAiIdentifying ? null : onIdentifyWithAi,
            icon: preview.isAiIdentifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(
              preview.isAiIdentifying
                  ? AppStrings.ankiAiIdentifying
                  : AppStrings.ankiAiRetry,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.brandTeal,
              side: const BorderSide(color: TurnaTheme.brandTeal),
            ),
          ),
        ],
      ],
    );
  }

  /// Chip tap → override the auto-detected type, keeping field indexes.
  /// Persisted as a reusable rule by the controller.
  Future<void> _saveType(
    AnkiCollection collection,
    int mid,
    AnkiNotetype notetype,
    UserQuestionType type,
  ) async {
    final existing =
        preview.mappings[mid] ?? AnkiCardAdapter.inferMapping(notetype);
    final next = resolveMappingType(
      type,
      hasClozeMarkers: hasClozeMarkers(notetype, collection.notes),
    );
    if (next == existing.type) return;
    await controller.saveLegacyMapping(mid, existing.copyWith(type: next));
  }

  int _cardCount(AnkiCollection collection, int mid) {
    final noteIds = {
      for (final note in collection.notes)
        if (note.mid == mid) note.id,
    };
    if (noteIds.isEmpty) return 0;
    return collection.cards
        .where((card) => noteIds.contains(card.nid))
        .length;
  }

  Widget _buildContentSection(
    BuildContext context,
    AnkiCollection collection,
  ) {
    return SectionCard(
      icon: Icons.layers_rounded,
      title: AppStrings.ankiPreviewSectionContent,
      hint: AppStrings.ankiPreviewSectionContentHint,
      children: [
        StatStrip(
          items: [
            (AppStrings.ankiDecksLabel, collection.decks.length),
            (AppStrings.ankiNotesLabel, collection.notes.length),
            (AppStrings.ankiCardsLabel, collection.cards.length),
            (AppStrings.ankiMediaFilesLabel, collection.media.length),
          ],
        ),
        if (collection.decks.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Subheader(text: '牌组结构'),
          const SizedBox(height: 4),
          for (final deck in collection.decks.values)
            InfoRow(
              deck.name,
              AppStrings.ankiDeckCardCount(deck.cardCount),
            ),
        ],
      ],
    );
  }

  /// One-line summary of the detected unit/lesson grouping. Grouping
  /// behavior is fixed to smart-grouping-on; only low-confidence hints are
  /// worth surfacing.
  Widget _buildOrganizationSummary(BuildContext context) {
    final org = preview.organizationPreview;
    if (org != null && org.hasAny) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(
            AppStrings.ankiSmartGrouping,
            '${org.unitCount} 个单元 · ${org.lessonCount} 个课时',
          ),
          if (org.lowConfidenceSectionHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                org.lowConfidenceSectionHint!,
                style: TextStyle(
                  fontSize: 11,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ),
        ],
      );
    }
    return InfoRow(
      AppStrings.ankiOrganizationNone,
      AppStrings.ankiOrganizationNoneDesc,
    );
  }

  Widget _buildLearningProgressSwitch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
          side: BorderSide(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              AppStrings.ankiImportLearningProgress,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                preview.importLearningProgress
                    ? AppStrings.ankiImportLearningProgressOnDesc
                    : AppStrings.ankiImportLearningProgressOffDesc,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            value: preview.importLearningProgress,
            onChanged: controller.setImportLearningProgress,
          ),
        ),
      ),
    );
  }
}
