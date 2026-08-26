import 'package:flutter/material.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/theme.dart';

/// Canonical types shown in the import mapping editor. Legacy aliases
/// ([NotetypeMappingType.multiSelect], [NotetypeMappingType.typeAnswer]) are
/// omitted so the dropdown never lists two identical labels.
const List<NotetypeMappingType> kUserSelectableMappingTypes = [
  NotetypeMappingType.ankiCard,
  NotetypeMappingType.wordEntry,
  NotetypeMappingType.expression,
  NotetypeMappingType.cloze,
  NotetypeMappingType.multipleChoice,
  NotetypeMappingType.fillBlank,
  NotetypeMappingType.listenPick,
];

/// One automatic notetype-mapping row. Tapping the row (or its trailing
/// edit icon) opens [NotetypeMappingEditor] so the user can override the
/// auto-detected type and front/back fields.
class NotetypeMappingRow extends StatelessWidget {
  final AnkiNotetype notetype;
  final NotetypeMapping? mapping;
  final CardRecognitionResult? recognition;
  final ImportRecognitionAttention attention;
  final VoidCallback onEdit;

  const NotetypeMappingRow({
    super.key,
    required this.notetype,
    required this.mapping,
    required this.attention,
    required this.onEdit,
    this.recognition,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (attention) {
      ImportRecognitionAttention.blocking => TurnaTheme.error,
      ImportRecognitionAttention.advisory => TurnaTheme.warning,
      ImportRecognitionAttention.recognized => TurnaTheme.brandTeal,
      ImportRecognitionAttention.skipped => TurnaTheme.textHintColor(context),
    };
    final status = switch (attention) {
      ImportRecognitionAttention.blocking => AppStrings.ankiMappingMustFix,
      ImportRecognitionAttention.advisory => AppStrings.ankiMappingNeedsCheck,
      ImportRecognitionAttention.recognized => AppStrings.ankiMappingRecognizedAuto,
      ImportRecognitionAttention.skipped => AppStrings.ankiOfficialMappingSkipped,
    };
    final warnings = recognition?.warnings ?? const <String>[];
    final detail = warnings.isEmpty ? null : warnings.first;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: onEdit,
        title: Text(
          notetype.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          detail != null && attention != ImportRecognitionAttention.recognized
              ? '${mappingTypeLabel(mapping?.type ?? NotetypeMappingType.ankiCard)} · $detail'
              : mappingTypeLabel(
                  mapping?.type ?? NotetypeMappingType.ankiCard,
                ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
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
            Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Editable notetype-mapping dialog for one notetype. Lets the user override
/// the auto-detected card type and the front/back field indices, with a live
/// sample preview (first note of that mid). Returns the edited
/// [NotetypeMapping] via [Navigator.pop] when saved, or `null` when cancelled
/// / dismissed - the caller decides whether to apply the change.
class NotetypeMappingEditor extends StatefulWidget {
  final AnkiNotetype notetype;
  final AnkiNote? note;
  final NotetypeMapping? initialMapping;

  const NotetypeMappingEditor({
    super.key,
    required this.notetype,
    required this.note,
    required this.initialMapping,
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

  /// Clamp field indices and collapse legacy type aliases so the dropdown
  /// value is always one of [kUserSelectableMappingTypes].
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
              widget.notetype.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
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
                  _fieldLabel(context, AppStrings.ankiMappingFieldType),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<NotetypeMappingType>(
                    initialValue: canonicalizeMappingType(_draft.type),
                    isExpanded: true,
                    decoration: _dropdownDecoration(context),
                    items: [
                      for (final t in kUserSelectableMappingTypes)
                        DropdownMenuItem(
                          value: t,
                          child: Text(mappingTypeLabel(t)),
                        ),
                    ],
                    onChanged: (t) {
                      if (t == null) return;
                      final next = canonicalizeMappingType(t);
                      if (next == _draft.type) return;
                      setState(() => _draft = _draft.copyWith(type: next));
                    },
                  ),
                  const SizedBox(height: 12),
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
              DropdownMenuItem(value: i, child: Text(fields[i])),
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
