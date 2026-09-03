import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/deck_directory_tree_view.dart';
import 'package:turna/views/anki/import_wizard/mcq_preview_sheet.dart';
import 'package:turna/views/anki/import_wizard/quick_front_picker_sheet.dart';
import 'package:turna/views/anki/import_wizard/study_preset_selector.dart';
import 'package:turna/views/theme.dart';

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
    );
  }

  void _detectInitialMode() {
    final firstSuggestion = widget.preview.suggestions.values.firstOrNull;
    if (firstSuggestion == null) return;
    final kinds = firstSuggestion.enabledKinds.toSet();
    if (kinds.contains('canonicalLink') && kinds.length == 1) {
      _selectedMode = StudyPresetMode.fidelity;
    } else if (kinds.contains('flip') &&
        !kinds.contains('multipleChoice') &&
        !kinds.contains('fillBlank')) {
      _selectedMode = StudyPresetMode.classicFlip;
    } else {
      _selectedMode = StudyPresetMode.interactive;
    }
  }

  Map<int, String> _buildDeckArchetypeLabels() {
    final labels = <int, String>{};
    final defaultSchema = widget.preview.schemas.firstOrNull;
    if (defaultSchema == null) return labels;

    final suggestion = widget.preview.suggestions[defaultSchema.notetypeId] ??
        officialAnkiSuggestMapping(defaultSchema);
    final isChoice = suggestion.cardArchetype.name == 'choice';
    final sample = defaultSchema.samples.firstOrNull;
    final isMulti = isChoice &&
        sample != null &&
        EmbeddedOptionsParser.parseCorrectIndices(
          sample.fields.length > 1 ? sample.fields[1] : '',
          EmbeddedOptionsParser.extractMultiFieldOptions(
                defaultSchema.fieldNames,
                sample.fields,
              ) ??
              EmbeddedOptionsParser.extractEmbeddedOptions(
                sample.fields.firstOrNull ?? '',
              )?.options ??
              const [],
        ).length >=
            2;

    final label = isChoice
        ? (isMulti ? '多选' : '单选')
        : (suggestion.cardArchetype.name == 'cloze' ? '填空' : '翻卡');

    for (final deck in widget.preview.decks) {
      labels[deck.deckId] = label;
    }
    return labels;
  }

  void _onSelectStudyMode(StudyPresetMode mode) {
    if (_selectedMode == mode) return;
    setState(() => _selectedMode = mode);

    final enabledKinds = switch (mode) {
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

    for (final schema in widget.preview.schemas) {
      final current = widget.preview.suggestions[schema.notetypeId] ??
          officialAnkiSuggestMapping(schema);
      final updated = current.copyWith(
        enabledKinds: enabledKinds,
        status: OfficialAnkiMappingStatus.manual,
        userConfirmed: true,
      );
      widget.controller.confirmOfficialMapping(schema, updated);
    }
  }

  void _openInspectSheet(DeckTreeNode node) {
    final schema = widget.preview.schemas.firstOrNull;
    if (schema == null) return;
    final current = widget.preview.suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
    showMcqPreviewSheet(
      context: context,
      schema: schema,
      currentSuggestion: current,
      onConfirmed: (updated) {
        widget.controller.confirmOfficialMapping(schema, updated);
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TurnaTheme.error.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusMedium),
                      border: Border.all(
                          color: TurnaTheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: TurnaTheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.error!,
                            style: const TextStyle(color: TurnaTheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _buildCourseHeaderCard(preview),
              const SizedBox(height: 16),
              StudyPresetSelector(
                selectedMode: _selectedMode,
                onSelectMode: _onSelectStudyMode,
              ),
              const SizedBox(height: 16),
              if (hasBlocking) ...[
                _buildBlockingWarning(blockingSchemas),
                const SizedBox(height: 16),
              ],
              DeckDirectoryTreeView(
                deckTree: _deckTree,
                totalDecks: preview.decks.length,
                onToggle: () => setState(() {}),
                onInspectNode: _openInspectSheet,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        StickyImportBar(
          onPressed: hasBlocking ? null : widget.controller.commit,
          disabledHint: hasBlocking ? '请先指定待确认牌组的正面字段' : null,
        ),
      ],
    );
  }

  Widget _buildCourseHeaderCard(OfficialAnkiImportPreviewModel preview) {
    final rootName = _deckTree.isNotEmpty ? _deckTree.first.name : '导入课程';
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
                      '已解析 ${preview.decks.length} 个牌组章节，包含全部核心知识点',
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
              if (hasChoice) ...[
                _archetypeChip(
                  icon: Icons.radio_button_checked_rounded,
                  label: '选择题已自动识别',
                  color: TurnaTheme.brandTeal,
                ),
              ] else ...[
                _archetypeChip(
                  icon: Icons.flip_to_back_rounded,
                  label: '正反翻转卡',
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ],
              _archetypeChip(
                icon: Icons.touch_app_outlined,
                label: '点击章节可预览题目',
                color: TurnaTheme.brandNavy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _archetypeChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
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
                  '有 ${schemas.length} 个模板需要指定正面字段',
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
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final schema = schemas.first;
              final current = widget.preview.suggestions[schema.notetypeId] ??
                  officialAnkiSuggestMapping(schema);
              showQuickFrontPicker(
                context: context,
                schema: schema,
                currentSuggestion: current,
                onConfirmed: (updated) {
                  widget.controller.confirmOfficialMapping(schema, updated);
                },
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: TurnaTheme.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
              ),
            ),
            child: const Text('指定正面', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
