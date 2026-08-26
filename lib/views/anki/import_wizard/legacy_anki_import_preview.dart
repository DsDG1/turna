import 'package:flutter/material.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/import_wizard/anki_import_controller.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/anki_notetype_mapping_editor.dart';
import 'package:turna/views/theme.dart';

/// Legacy preview step (maintainability plan §10.5): renders the sealed
/// [LegacyAnkiImportPreviewModel]. Pure view — every mutation goes through
/// controller intents.
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
              _buildContentSection(context, collection),
              const SizedBox(height: 12),
              _buildMappingSection(context, collection),
              const SizedBox(height: 12),
              AdvancedOptionsCard(
                summary: '重复卡片：${strategyLabel(context, preview.strategy)}',
                children: [
                  _buildOrganizationBlock(context),
                  const SizedBox(height: 12),
                  _buildStrategySection(context),
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

  /// Preview of the unit/lesson organization detected from Anki tags and
  /// notetype fields, plus the smart-grouping toggle. Reads the cached
  /// organization preview recomputed by the controller on section toggle.
  Widget _buildOrganizationBlock(BuildContext context) {
    final org = preview.organizationPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Subheader(text: '组织结构'),
        const SizedBox(height: 4),
        if (org != null && org.hasAny) ...[
          if (preview.sectionBeta && org.sectionNames.isNotEmpty) ...[
            InfoRow('检测到 Section', org.sectionCountLabel),
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
          InfoRow(AppStrings.ankiDetectedUnits, '${org.unitCount}'),
          InfoRow(AppStrings.ankiDetectedLessons, '${org.lessonCount}'),
          InfoRow(
              AppStrings.ankiResolvedCards, '${org.resolvedCardCount}'),
        ] else
          InfoRow(AppStrings.ankiOrganizationNone,
              AppStrings.ankiOrganizationNoneDesc),
        const SizedBox(height: 4),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: preview.smartGrouping,
            onChanged: controller.setSmartGrouping,
            title: Text(
              AppStrings.ankiSmartGrouping,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              AppStrings.ankiSmartGroupingDesc,
              style: const TextStyle(fontSize: 12),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        // Plan 1 Phase 5 Beta: semantic Section grouping. Only affects this
        // new import; off by default.
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: preview.sectionBeta,
            onChanged: preview.smartGrouping
                ? controller.setSectionBeta
                : null,
            title: const Text(
              '自动分 Section（Beta）',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '按 Chapter/章 字段或 Unit 前缀把多个 Unit 归入 Section',
              style: TextStyle(fontSize: 12),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  /// Section 2: how each card type is identified — one row per notetype
  /// with a ✓/⚠ state. The AI re-identification button only appears when
  /// something needs a manual look.
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
      hint: AppStrings.ankiPreviewSectionMappingHint,
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
          NotetypeMappingRow(
            notetype: entry.value,
            mapping: preview.mappings[entry.key],
            recognition: preview.recognitionResults[entry.key],
            attention: attention[entry.key]!,
            onEdit: () => onEditMapping(entry.key, entry.value),
          ),
        if (advisory > 0 && aiReady) ...[
          const SizedBox(height: 12),
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

  /// Advanced: how collisions and learning progress are handled.
  Widget _buildStrategySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Subheader(text: '重复卡片怎么处理'),
        const SizedBox(height: 6),
        CollisionStrip(
          newCount: preview.newCount,
          existingCount: preview.existingCount,
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.ankiPreviewCollisionVisualHint,
          style: TextStyle(
            fontSize: 11,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
        const SizedBox(height: 12),
        RadioGroup<ImportStrategy>(
          groupValue: preview.strategy,
          onChanged: (value) {
            if (value != null) controller.setStrategy(value);
          },
          child: Column(
            children: [
              for (final s in ImportStrategy.values) ...[
                StrategyOption(
                  value: s,
                  groupValue: preview.strategy,
                  title: strategyLabel(context, s),
                  description: strategyDescription(context, s),
                  consequence: strategyConsequence(s),
                  isWarning: s == ImportStrategy.forceReplace,
                  onChanged: controller.setStrategy,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Material(
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
      ],
    );
  }
}