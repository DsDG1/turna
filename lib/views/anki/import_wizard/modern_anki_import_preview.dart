import 'dart:async';

import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_preview_header.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
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
    final suggestion = widget.preview.suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
    final isChoice = suggestion.cardArchetype.name == 'choice';
    final sample = schema.samples.firstOrNull;
    final isMulti = isChoice &&
        sample != null &&
        EmbeddedOptionsParser.parseCorrectIndices(
              sample.fields.length > 1 ? sample.fields[1] : '',
              EmbeddedOptionsParser.extractMultiFieldOptions(
                    schema.fieldNames,
                    sample.fields,
                  ) ??
                  EmbeddedOptionsParser.extractEmbeddedOptions(
                    sample.fields.firstOrNull ?? '',
                  )?.options ??
                  const [],
            ).length >=
            2;

    return isChoice
        ? (isMulti
            ? AppStrings.ankiPreviewKindMulti
            : AppStrings.ankiPreviewKindSingle)
        : (suggestion.cardArchetype.name == 'cloze'
            ? AppStrings.ankiPreviewKindCloze
            : AppStrings.ankiPreviewKindFlip);
  }

  StudyPresetMode _modeFor(OfficialAnkiProjectionSchema schema) {
    final suggestion = widget.preview.suggestions[schema.notetypeId];
    final kinds = suggestion?.enabledKinds.toSet() ?? const <String>{};
    if (kinds.length == 1 && kinds.contains('canonicalLink')) {
      return StudyPresetMode.fidelity;
    }
    if (kinds.contains('flip') && !kinds.contains('multipleChoice')) {
      return StudyPresetMode.classicFlip;
    }
    return StudyPresetMode.interactive;
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
              AnkiImportPreviewHeaderCard(preview: preview),
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
              for (final schema in preview.schemas)
                _NotetypeModeRow(
                  schema: schema,
                  mode: _modeFor(schema),
                  onChanged: (mode) => widget.controller.setNotetypeStudyMode(
                    schema,
                    _kindsFor(mode),
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
              const SizedBox(height: 16),
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

class _NotetypeModeRow extends StatelessWidget {
  const _NotetypeModeRow({
    required this.schema,
    required this.mode,
    required this.onChanged,
  });

  final OfficialAnkiProjectionSchema schema;
  final StudyPresetMode mode;
  final ValueChanged<StudyPresetMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              schema.name.isEmpty
                  ? AppStrings.ankiPreviewStudyMode
                  : schema.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DropdownButton<StudyPresetMode>(
            value: mode,
            items: [
              DropdownMenuItem(
                value: StudyPresetMode.interactive,
                child: Text(AppStrings.studyPresetInteractiveTitle),
              ),
              DropdownMenuItem(
                value: StudyPresetMode.classicFlip,
                child: Text(AppStrings.studyPresetClassicFlipTitle),
              ),
              DropdownMenuItem(
                value: StudyPresetMode.fidelity,
                child: Text(AppStrings.studyPresetFidelityTitle),
              ),
            ],
            onChanged: (mode) {
              if (mode != null) onChanged(mode);
            },
          ),
        ],
      ),
    );
  }
}
