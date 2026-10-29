import 'dart:async';

import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/adaptation/notetype_presentation_preview.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_preview_header.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/components/notetype_mode_row.dart';
import 'package:turna/views/anki/import_wizard/components/smart_adaptation_host.dart';
import 'package:turna/views/anki/import_wizard/deck_directory_tree_view.dart';
import 'package:turna/views/anki/import_wizard/mcq_preview_sheet.dart';
import 'package:turna/views/anki/import_wizard/quick_front_picker_sheet.dart';
import 'package:turna/views/anki/import_wizard/study_preset_selector.dart';
import 'package:turna/core/theme.dart';

/// Resolves a deck node to the notetype that owns the most cards in it.
OfficialAnkiProjectionSchema? officialSchemaForPreviewNode({
  required List<OfficialAnkiProjectionSchema> schemas,
  required int? notetypeId,
}) {
  if (notetypeId == null) {
    return schemas.length == 1 ? schemas.first : null;
  }
  for (final schema in schemas) {
    if (schema.notetypeId == notetypeId) return schema;
  }
  return null;
}

/// 唯一的模式推断（ADR 0057 §1：预览不再有自己的规则表）。有样本时按
/// 解析器的逐卡结论聚合——「整组保持练习、整组翻卡、还是回原卡」由同一
/// 个解析器说了算；没有样本（尚未加载）才退回 enabledKinds 启发式。两条
/// 路径共用这一个函数，同一种输入不会再得出两个结论（A1）。
StudyPresetMode studyModeFromPreview(
  NotetypePresentationPreview preview,
  Set<String> enabledKinds,
) {
  if (preview.hasSamples) {
    if (preview.summary.structured == 0) return StudyPresetMode.fidelity;
    if (preview.flipOnly) return StudyPresetMode.classicFlip;
    return StudyPresetMode.interactive;
  }
  if (enabledKinds.length == 1 && enabledKinds.contains('canonicalLink')) {
    return StudyPresetMode.fidelity;
  }
  if (enabledKinds.contains('flip') &&
      !enabledKinds.contains('multipleChoice') &&
      !enabledKinds.contains('fillBlank')) {
    return StudyPresetMode.classicFlip;
  }
  return StudyPresetMode.interactive;
}

/// Modern Anki import preview: clean, course-oriented view focusing on
/// course asset statistics, multi-level chapter structure, and global
/// learning style presets. Replaces the algorithm-centric "what the card
/// looks like" four-piece preview.
class ModernAnkiImportPreview extends StatefulWidget {
  const ModernAnkiImportPreview({
    super.key,
    required this.preview,
    required this.controller,
    this.error,
  });

  final OfficialAnkiImportPreviewModel preview;
  final AnkiImportController controller;
  final String? error;

  @override
  State<ModernAnkiImportPreview> createState() =>
      _ModernAnkiImportPreviewState();
}

class _ModernAnkiImportPreviewState extends State<ModernAnkiImportPreview> {
  StudyPresetMode _selectedMode = StudyPresetMode.interactive;
  late List<DeckTreeNode> _deckTree;

  @override
  void initState() {
    super.initState();
    _rebuildTree();
    _detectInitialMode();
  }

  @override
  void didUpdateWidget(covariant ModernAnkiImportPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.decks != widget.preview.decks ||
        oldWidget.preview.cardCountByDeck != widget.preview.cardCountByDeck ||
        oldWidget.preview.suggestions != widget.preview.suggestions) {
      _rebuildTree();
    }
  }

  void _rebuildTree() {
    _deckTree = buildDeckTree(
      widget.preview.decks,
      widget.preview.cardCountByDeck,
      archetypeLabelByDeck: _buildDeckArchetypeLabels(),
      notetypeByDeck: widget.preview.notetypeByDeck,
      includedDeckIds: widget.preview.includedDeckIds,
    );
  }

  void _detectInitialMode() {
    if (widget.preview.schemas.isEmpty) return;
    final modes = [
      for (final schema in widget.preview.schemas) _modeFor(schema),
    ];
    if (modes.every((mode) => mode == StudyPresetMode.fidelity)) {
      _selectedMode = StudyPresetMode.fidelity;
    } else if (modes.every((mode) =>
        mode == StudyPresetMode.classicFlip ||
        mode == StudyPresetMode.fidelity)) {
      _selectedMode = StudyPresetMode.classicFlip;
    } else {
      _selectedMode = StudyPresetMode.interactive;
    }
  }

  OfficialAnkiMappingSuggestion _effectiveSuggestion(
    OfficialAnkiProjectionSchema schema,
  ) {
    return widget.preview.suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
  }

  NotetypePresentationPreview _previewFor(
    OfficialAnkiProjectionSchema schema,
  ) {
    return resolveNotetypePresentationPreview(
      schema: schema,
      suggestion: _effectiveSuggestion(schema),
    );
  }

  Map<int, String> _buildDeckArchetypeLabels() {
    final labels = <int, String>{};
    for (final deck in widget.preview.decks) {
      final schema = officialSchemaForPreviewNode(
        schemas: widget.preview.schemas,
        notetypeId: widget.preview.notetypeByDeck[deck.deckId],
      );
      if (schema == null) continue;
      labels[deck.deckId] = _archetypeLabelForSchema(schema);
    }
    return labels;
  }

  String _archetypeLabelForSchema(OfficialAnkiProjectionSchema schema) {
    // 标签以解析器的逐卡主导结论为准（A1：不在组件里重新解析一遍选项
    // 结构）；解析器没有给出选择类结论时（映射没有 options 角色 / 尚无
    // 样本），退回 notetype 级原型——单选/多选的细分只在解析器真看得到
    // 选项时才下结论。
    final suggestion = _effectiveSuggestion(schema);
    final dominant = _previewFor(schema).dominantKind;
    if (dominant == OfficialAnkiProjectionKind.multipleChoice) {
      return AppStrings.ankiPreviewKindSingle;
    }
    if (dominant == OfficialAnkiProjectionKind.multiSelect) {
      return AppStrings.ankiPreviewKindMulti;
    }
    if (dominant == OfficialAnkiProjectionKind.fillBlank) {
      return AppStrings.ankiPreviewKindCloze;
    }
    return switch (suggestion.cardArchetype) {
      CardArchetype.choice => AppStrings.ankiPreviewKindSingle,
      CardArchetype.cloze => AppStrings.ankiPreviewKindCloze,
      _ => AppStrings.ankiPreviewKindFlip,
    };
  }

  StudyPresetMode _modeFor(OfficialAnkiProjectionSchema schema) {
    final suggestion = _effectiveSuggestion(schema);
    return studyModeFromPreview(
      _previewFor(schema),
      suggestion.enabledKinds.toSet(),
    );
  }

  /// 逐卡解析计数（ADR 0057 §11.2）：预览要能看到整组多少张保持练习、
  /// 多少张回原卡。全部保持练习时不显示，避免每行都是噪音。
  String? _countsLabelFor(OfficialAnkiProjectionSchema schema) {
    final summary = _previewFor(schema).summary;
    if (summary.total == 0) return null;
    final parts = <String>[
      if (summary.originalCard > 0)
        AppStrings.ankiPreviewBatchCounts(
          summary.structured,
          summary.originalCard,
        ),
      if (summary.needsCorrection > 0)
        AppStrings.ankiPreviewNeedsMappingCount(summary.needsCorrection),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }


  List<String> _kindsFor(StudyPresetMode mode) {
    return switch (mode) {
      StudyPresetMode.interactive => const <String>[
          'multipleChoice',
          'multiSelect',
          'fillBlank',
          'listenPick',
          'typeAnswer',
          'flip',
          'canonicalLink',
        ],
      StudyPresetMode.classicFlip => const <String>[
          'flip',
          'canonicalLink',
        ],
      StudyPresetMode.fidelity => const <String>[
          'canonicalLink',
        ],
    };
  }

  void _onSelectStudyMode(StudyPresetMode mode) {
    if (_selectedMode == mode) return;
    setState(() => _selectedMode = mode);
    final kinds = _kindsFor(mode);
    for (final schema in widget.preview.schemas) {
      if (widget.preview.confirmedNotetypes.contains(schema.notetypeId)) {
        continue;
      }
      widget.controller.applyUnconfirmedKinds(schema, kinds);
    }
  }

  Future<void> _openInspectSheet(DeckTreeNode node) async {
    final schema = officialSchemaForPreviewNode(
      schemas: widget.preview.schemas,
      notetypeId: node.notetypeId,
    );
    if (schema == null) return;
    await widget.controller.loadSamples(schema);
    if (!mounted) return;
    final fresh = widget.preview.schemas
            .where((item) => item.notetypeId == schema.notetypeId)
            .firstOrNull ??
        schema;
    final current = widget.preview.suggestions[fresh.notetypeId] ??
        officialAnkiSuggestMapping(schema);
    showMcqPreviewSheet(
      context: context,
      schema: fresh,
      currentSuggestion: current,
      onConfirmed: (updated) {
        widget.controller.confirmOfficialMapping(fresh, updated);
        setState(() => _rebuildTree());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final blockingSchemas = preview.schemas.where((schema) {
      return officialRecognitionTriage(preview, schema).blocking;
    }).toList();
    final hasBlocking = blockingSchemas.isNotEmpty;
    final noneIncluded = preview.includedDeckIds.isEmpty;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TurnaTheme.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                TurnaTheme.radiusMedium,
                              ),
                              border: Border.all(
                                color: TurnaTheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: TurnaTheme.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.error!,
                                    style: const TextStyle(
                                      color: TurnaTheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      AnkiImportPreviewHeaderCard(preview: preview),
                      const SizedBox(height: 16),
                      StudyPresetSelector(
                        selectedMode: _selectedMode,
                        onSelectMode: _onSelectStudyMode,
                      ),
                      const SizedBox(height: 16),
                      SmartAdaptationHost(
                        sourceId: preview.sourceId,
                        schemas: preview.schemas,
                        controller: widget.controller,
                        suggestions: preview.suggestions,
                      ),
                      const SizedBox(height: 16),
                      if (hasBlocking) ...[
                        _buildBlockingWarning(blockingSchemas),
                        const SizedBox(height: 16),
                      ],
                      for (final schema in preview.schemas)
                        NotetypeModeRow(
                          schema: schema,
                          mode: _modeFor(schema),
                          countsLabel: _countsLabelFor(schema),
                          onChanged: (mode) =>
                              widget.controller.setNotetypeStudyMode(
                            schema,
                            _kindsFor(mode),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DeckDirectoryTreeView(
                deckTree: _deckTree,
                totalDecks: preview.decks.length,
                onToggle: () => setState(() {}),
                onInspectNode: (node) => unawaited(_openInspectSheet(node)),
                onToggleIncluded: (node, included) {
                  final id = node.deckId;
                  if (id == null) return;
                  widget.controller.toggleDeckIncluded(id, included);
                  setState(_rebuildTree);
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        StickyImportBar(
          onPressed:
              hasBlocking || noneIncluded ? null : widget.controller.commit,
          disabledHint: hasBlocking
              ? AppStrings.ankiPreviewBlockingHint
              : (noneIncluded ? AppStrings.ankiPreviewBlockingHint : null),
        ),
      ],
    );
  }

  Widget _buildBlockingWarning(List<OfficialAnkiProjectionSchema> schemas) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: TurnaTheme.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.ankiPreviewBlockingTitle(schemas.length),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  schemas.map((s) => s.name).join('、'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
                for (final schema in schemas)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          schema.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.skipOfficialNotetype(schema),
                        child: Text(AppStrings.ankiPreviewSkipNotetype),
                      ),
                      TextButton(
                        onPressed: () {
                          final current =
                              widget.preview.suggestions[schema.notetypeId] ??
                                  officialAnkiSuggestMapping(schema);
                          showQuickFrontPicker(
                            context: context,
                            schema: schema,
                            currentSuggestion: current,
                            onConfirmed: (updated) {
                              widget.controller
                                  .confirmOfficialMapping(schema, updated);
                            },
                          );
                        },
                        child: Text(AppStrings.ankiPreviewPickFront),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
