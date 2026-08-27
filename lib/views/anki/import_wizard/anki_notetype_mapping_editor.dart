import 'package:flutter/material.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';
import 'package:turna/application/anki/import_wizard/question_type.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/theme.dart';

/// Plain-language label for a user-facing question-type chip.
String userQuestionTypeLabel(UserQuestionType type) =>
    userQuestionTypeLabelOf(type);

/// Whether a recognition result represents the user's own pick (written back
/// by the controller with confidence 1.0) rather than an automatic verdict —
/// automatic ones carry the "自动" badge on the selected chip.
bool _isUserChoice(CardRecognitionResult? recognition) =>
    recognition?.source == CardRecognitionSource.persisted &&
    recognition!.confidence >= 1.0;

/// The one-row-per-chip question-type selector shared by the recognition
/// row and the mapping editor dialog. Tapping a chip immediately changes
/// the type; field indexes are kept as-is.
class QuestionTypeChips extends StatelessWidget {
  const QuestionTypeChips({
    super.key,
    required this.selected,
    required this.onSelected,
    this.autoBadge = false,
    this.dense = false,
  });

  final UserQuestionType selected;
  final ValueChanged<UserQuestionType> onSelected;

  /// Show the "自动" suffix on the selected chip (auto recognition, not yet
  /// user-touched).
  final bool autoBadge;

  /// Slightly tighter chips for use inside the editor dialog.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: dense ? 6 : 8,
      runSpacing: dense ? 6 : 8,
      children: [
        for (final type in UserQuestionType.values)
          ChoiceChip(
            key: Key('question-type-${type.name}'),
            label: Text(
              type == selected && autoBadge
                  ? '${userQuestionTypeLabel(type)} · ${AppStrings.ankiQuestionTypeAutoSuffix}'
                  : userQuestionTypeLabel(type),
            ),
            visualDensity: dense ? VisualDensity.compact : null,
            selected: type == selected,
            onSelected: (_) => onSelected(type),
          ),
      ],
    );
  }
}

/// One automatic notetype-mapping row. The notetype name is context; the
/// primary interaction is the question-type chip row. "调整字段" opens
/// [NotetypeMappingEditor] for front/back field overrides.
class NotetypeMappingRow extends StatelessWidget {
  final AnkiNotetype notetype;
  final NotetypeMapping? mapping;
  final CardRecognitionResult? recognition;
  final ImportRecognitionAttention attention;
  final int cardCount;
  final String? sampleFront;
  final String? sampleBack;
  final ValueChanged<UserQuestionType> onTypeSelected;
  final VoidCallback onEdit;

  const NotetypeMappingRow({
    super.key,
    required this.notetype,
    required this.mapping,
    required this.attention,
    required this.cardCount,
    required this.onTypeSelected,
    required this.onEdit,
    this.recognition,
    this.sampleFront,
    this.sampleBack,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (attention) {
      ImportRecognitionAttention.blocking => TurnaTheme.error,
      ImportRecognitionAttention.advisory => TurnaTheme.warning,
      ImportRecognitionAttention.recognized => TurnaTheme.brandTeal,
      ImportRecognitionAttention.skipped => TurnaTheme.textHintColor(context),
    };
    final status = importAttentionStatusLabel(attention);
    final warnings = recognition?.warnings ?? const <String>[];
    final detail = warnings.isEmpty ? null : warnings.first;
    final selected =
        userQuestionTypeOf(mapping?.type ?? NotetypeMappingType.ankiCard);
    final typeLabel = userQuestionTypeLabel(selected);
    return Container(
      key: Key('mapping-row-${notetype.id}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: attention == ImportRecognitionAttention.blocking
              ? TurnaTheme.error.withValues(alpha: 0.4)
              : TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.ankiMappingCards(cardCount),
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ],
          ),
          if (sampleFront != null || sampleBack != null) ...[
            const SizedBox(height: 6),
            Text(
              '${sampleFront ?? AppStrings.ankiMappingEmptySample}'
              '  →  '
              '${sampleBack ?? AppStrings.ankiMappingEmptySample}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppStrings.ankiMappingSourceName(notetype.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                attention == ImportRecognitionAttention.blocking
                    ? Icons.error_outline_rounded
                    : attention == ImportRecognitionAttention.advisory
                        ? Icons.help_outline_rounded
                        : Icons.check_circle_outline_rounded,
                color: color,
                size: 17,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          QuestionTypeChips(
            selected: selected,
            onSelected: onTypeSelected,
            autoBadge: !_isUserChoice(recognition),
          ),
          if (detail != null &&
              attention != ImportRecognitionAttention.recognized) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('mapping-row-edit-${notetype.id}'),
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: Text(AppStrings.ankiMappingAdjustFields),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: TurnaTheme.textSecondaryColor(context),
                textStyle: const TextStyle(fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable notetype-mapping dialog for one notetype. Question-type chips at
/// the top are the primary control; front/back field selectors and the
/// recognition reason live under "更多调整". Returns the edited
/// [NotetypeMapping] via [Navigator.pop] when saved, or `null` when
/// cancelled / dismissed - the caller decides whether to apply the change.
class NotetypeMappingEditor extends StatefulWidget {
  final AnkiNotetype notetype;
  final AnkiNote? note;
  final NotetypeMapping? initialMapping;

  /// Whether this notetype's notes carry cloze markers — decides whether a
  /// 填空题 chip tap maps to the cloze or the type-the-answer interaction.
  final bool hasClozeMarkers;

  const NotetypeMappingEditor({
    super.key,
    required this.notetype,
    required this.note,
    required this.initialMapping,
    this.hasClozeMarkers = false,
  });

  @override
  State<NotetypeMappingEditor> createState() => _NotetypeMappingEditorState();
}

class _NotetypeMappingEditorState extends State<NotetypeMappingEditor> {
  late NotetypeMapping _draft;

  @override
  void initState() {
    super.initState();
    _draft = _normalizeMapping(
      widget.initialMapping ?? AnkiCardAdapter.inferMapping(widget.notetype),
    );
  }

  /// Clamp field indices and collapse legacy type aliases so the chip state
  /// always reflects a canonical type.
  NotetypeMapping _normalizeMapping(NotetypeMapping m) {
    final canonical = canonicalizeMappingType(m.type);
    final next = canonical == m.type ? m : m.copyWith(type: canonical);
    return _clampFields(next);
  }

  /// Clamp front/back indices to the notetype's actual field range so the
  /// dropdowns always have a valid selection (a 1-field notetype would
  /// otherwise keep the default backFieldIndex=1).
  NotetypeMapping _clampFields(NotetypeMapping m) {
    final n = widget.notetype.fieldNames.length;
    if (n == 0) return m;
    final maxIdx = n - 1;
    final front = m.frontFieldIndex.clamp(0, maxIdx);
    final back = m.backFieldIndex.clamp(0, maxIdx);
    if (front == m.frontFieldIndex && back == m.backFieldIndex) return m;
    return m.copyWith(frontFieldIndex: front, backFieldIndex: back);
  }

  void _selectType(UserQuestionType type) {
    final next = resolveMappingType(
      type,
      hasClozeMarkers: widget.hasClozeMarkers,
    );
    if (next == _draft.type) return;
    setState(() => _draft = _normalizeMapping(_draft.copyWith(type: next)));
  }

  void _swapFields() {
    setState(() {
      _draft = _draft.copyWith(
        frontFieldIndex: _draft.backFieldIndex,
        backFieldIndex: _draft.frontFieldIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.notetype.fieldNames;
    final showFields =
        mappingUsesFrontBackFields(_draft.type) && fields.isNotEmpty;
    final noteFields = widget.note?.fields ?? const <String>[];
    String fieldValue(int idx) => (idx >= 0 && idx < noteFields.length)
        ? AnkiCardAdapter.stripHtmlPublic(noteFields[idx])
        : '-';

    return AlertDialog(
      title: Text(AppStrings.ankiMappingEditTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.ankiMappingEditTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                AppStrings.ankiMappingSourceName(widget.notetype.name),
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ),
            Text(
              AppStrings.ankiQuestionTypeSectionTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            QuestionTypeChips(
              selected: userQuestionTypeOf(_draft.type),
              onSelected: _selectType,
              dense: true,
            ),
            const SizedBox(height: 14),
            if (widget.note == null)
              Text(
                '-',
                style: TextStyle(color: TurnaTheme.textHintColor(context)),
              )
            else ...[
              PreviewField(
                label: AppStrings.ankiNotetypeSampleFront,
                value: fieldValue(_draft.frontFieldIndex),
              ),
              const SizedBox(height: 8),
              PreviewField(
                label: AppStrings.ankiNotetypeSampleBack,
                value: fieldValue(_draft.backFieldIndex),
              ),
            ],
            if (showFields && fields.length > 1) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: OutlinedButton.icon(
                  key: const Key('legacy-mapping-swap'),
                  onPressed: _swapFields,
                  icon: const Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text(AppStrings.ankiMappingSwapSides),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('legacy-mapping-more'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  AppStrings.ankiMappingMoreAdjustments,
                  style: const TextStyle(fontSize: 14),
                ),
                children: [
                  if (showFields) ...[
                    _fieldSelector(
                      context,
                      label: AppStrings.ankiMappingFieldFront,
                      value: _draft.frontFieldIndex,
                      fields: fields,
                      onChanged: (i) => setState(() =>
                          _draft = _draft.copyWith(frontFieldIndex: i ?? 0)),
                    ),
                    const SizedBox(height: 10),
                    _fieldSelector(
                      context,
                      label: AppStrings.ankiMappingFieldBack,
                      value: _draft.backFieldIndex,
                      fields: fields,
                      onChanged: (i) => setState(() =>
                          _draft = _draft.copyWith(backFieldIndex: i ?? 0)),
                    ),
                  ] else
                    _autoFieldsHint(context),
                  if (_draft.reason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ReasonDisclosure(reason: _draft.reason),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => _draft = _normalizeMapping(
                  AnkiCardAdapter.inferMapping(widget.notetype),
                ));
          },
          child: Text(AppStrings.ankiMappingResetAuto),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(AppStrings.commonCancel),
        ),
        FilledButton(
          key: const Key('mapping-edit-confirm'),
          onPressed: () => Navigator.of(context).pop(_draft),
          child: Text(AppStrings.ankiMappingConfirmCorrect),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textSecondaryColor(context),
      ),
    );
  }

  Widget _fieldSelector(
    BuildContext context, {
    required String label,
    required int value,
    required List<String> fields,
    required ValueChanged<int?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel(context, label),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: _dropdownDecoration(context),
          items: [
            for (var i = 0; i < fields.length; i++)
              DropdownMenuItem(
              value: i,
              child: Text(userFacingFieldName(fields[i])),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _autoFieldsHint(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: TurnaTheme.textHintColor(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            AppStrings.ankiMappingFieldsAutoHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ),
      ],
    );
  }

  InputDecoration _dropdownDecoration(BuildContext context) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: TurnaTheme.tintLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        borderSide: BorderSide.none,
      ),
    );
  }
}
