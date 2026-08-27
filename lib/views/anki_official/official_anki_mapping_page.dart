import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_exercise_presets.dart';
import 'package:turna/application/anki_import/anki_import_view_helpers.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/theme.dart';

/// Editable mapping wizard, phrased for non-experts: what the cards look
/// like, which field plays which role (in plain Chinese), and which
/// exercise types will be generated. Saving does not generate a course.
@RoutePage()
class OfficialAnkiMappingPage extends StatefulWidget {
  const OfficialAnkiMappingPage({
    super.key,
    required this.notetypeName,
    required this.suggestion,
    this.schema,
    this.affectedCardCount = 0,
    this.onConfirm,
    this.onSkip,
    this.onRestore,
    this.onGenerateCourse,
    this.onChanged,
  });

  final String notetypeName;
  final OfficialAnkiMappingSuggestion suggestion;
  final OfficialAnkiProjectionSchema? schema;
  final int affectedCardCount;
  final ValueChanged<OfficialAnkiMappingSuggestion>? onConfirm;
  final VoidCallback? onSkip;
  final VoidCallback? onRestore;
  final VoidCallback? onGenerateCourse;
  final ValueChanged<OfficialAnkiMappingSuggestion>? onChanged;

  @override
  State<OfficialAnkiMappingPage> createState() =>
      OfficialAnkiMappingPageState();
}

/// Plain-language labels for the raw enum values. Users never need to see
/// `targetText`/`autoCandidate`/`confidence=0.95`.
const Map<OfficialAnkiFieldRole, String> _roleLabels = {
  OfficialAnkiFieldRole.targetText: '正面',
  OfficialAnkiFieldRole.nativeText: '背面',
  OfficialAnkiFieldRole.pronunciation: '读音',
  OfficialAnkiFieldRole.audio: '音频',
  OfficialAnkiFieldRole.image: '图片',
  OfficialAnkiFieldRole.exampleTarget: '例句',
  OfficialAnkiFieldRole.exampleNative: '例句翻译',
  OfficialAnkiFieldRole.unitLabel: '单元',
  OfficialAnkiFieldRole.lessonLabel: '课时',
  OfficialAnkiFieldRole.optionPool: '选项',
};

const Map<OfficialAnkiFieldRole, IconData> _roleIcons = {
  OfficialAnkiFieldRole.targetText: Icons.text_fields_outlined,
  OfficialAnkiFieldRole.nativeText: Icons.translate_outlined,
  OfficialAnkiFieldRole.pronunciation: Icons.record_voice_over_outlined,
  OfficialAnkiFieldRole.audio: Icons.volume_up_outlined,
  OfficialAnkiFieldRole.image: Icons.image_outlined,
  OfficialAnkiFieldRole.exampleTarget: Icons.format_quote_outlined,
  OfficialAnkiFieldRole.exampleNative: Icons.format_quote,
  OfficialAnkiFieldRole.unitLabel: Icons.folder_outlined,
  OfficialAnkiFieldRole.lessonLabel: Icons.list_alt_outlined,
  OfficialAnkiFieldRole.optionPool: Icons.checklist_outlined,
};

const Map<OfficialAnkiMappingStatus, String> _statusLabels = {
  OfficialAnkiMappingStatus.autoCandidate: '已按卡片内容匹配，可直接导入',
  OfficialAnkiMappingStatus.needsConfirm: '看一下样卡正反面是否反了',
  OfficialAnkiMappingStatus.needsMapping: '还看不清正面和背面，选一下即可',
  OfficialAnkiMappingStatus.needsReview: '建议看一眼样卡',
  OfficialAnkiMappingStatus.skipped: '已跳过',
};

String _presetLabel(OfficialExercisePreset preset) {
  switch (preset) {
    case OfficialExercisePreset.auto:
      return AppStrings.ankiOfficialExerciseAuto;
    case OfficialExercisePreset.choice:
      return AppStrings.ankiOfficialExerciseChoice;
    case OfficialExercisePreset.fillBlank:
      return AppStrings.ankiOfficialExerciseFillBlank;
    case OfficialExercisePreset.listen:
      return AppStrings.ankiOfficialExerciseListen;
    case OfficialExercisePreset.flip:
      return AppStrings.ankiOfficialExerciseFlip;
  }
}

class OfficialAnkiMappingPageState extends State<OfficialAnkiMappingPage> {
  late OfficialAnkiMappingSuggestion _current;
  late OfficialAnkiMappingSuggestion _suggestion;

  @override
  void initState() {
    super.initState();
    _suggestion = widget.suggestion;
    _current = widget.suggestion;
  }

  OfficialAnkiMappingSuggestion get current => _current;

  void restoreSuggestion() {
    setState(() => _current = _suggestion);
    widget.onRestore?.call();
    widget.onChanged?.call(_current);
  }

  void assignRole(OfficialAnkiFieldRole role, int fieldIndex) {
    final name = widget.schema?.fieldNames ??
        [for (final c in _current.candidates) c.fieldName];
    final fieldName =
        fieldIndex >= 0 && fieldIndex < name.length ? name[fieldIndex] : '';
    final next = [
      for (final candidate in _current.candidates)
        if (candidate.role != role) candidate,
      OfficialAnkiFieldCandidate(
        role: role,
        fieldIndex: fieldIndex,
        fieldName: fieldName,
        confidence: 1,
        evidence: const ['user'],
      ),
    ];
    setState(() {
      _current = _current.copyWith(candidates: next);
    });
    widget.onChanged?.call(_current);
  }

  void _swapPrimaryRoles() {
    final target = _current.role(OfficialAnkiFieldRole.targetText);
    final answer = _current.role(OfficialAnkiFieldRole.nativeText);
    if (target == null || answer == null) return;
    final next = [
      for (final candidate in _current.candidates)
        if (candidate.role != OfficialAnkiFieldRole.targetText &&
            candidate.role != OfficialAnkiFieldRole.nativeText)
          candidate,
      OfficialAnkiFieldCandidate(
        role: OfficialAnkiFieldRole.targetText,
        fieldIndex: answer.fieldIndex,
        fieldName: answer.fieldName,
        confidence: 1,
        evidence: const ['user:swap'],
      ),
      OfficialAnkiFieldCandidate(
        role: OfficialAnkiFieldRole.nativeText,
        fieldIndex: target.fieldIndex,
        fieldName: target.fieldName,
        confidence: 1,
        evidence: const ['user:swap'],
      ),
    ];
    setState(() => _current = _current.copyWith(candidates: next));
    widget.onChanged?.call(_current);
  }

  void _selectExercisePreset(OfficialExercisePreset preset) {
    setState(() {
      _current = withPreset(_current, preset);
    });
    widget.onChanged?.call(_current);
  }

  String _sampleValue(
    OfficialAnkiProjectionSample sample,
    OfficialAnkiFieldRole role,
  ) {
    final candidate = _current.role(role);
    if (candidate == null ||
        candidate.fieldIndex < 0 ||
        candidate.fieldIndex >= sample.fields.length) {
      return '未选择';
    }
    final plain = sample.fields[candidate.fieldIndex]
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
    return plain.isEmpty ? '（空白）' : plain;
  }

  @override
  Widget build(BuildContext context) {
    final flags = OfficialAnkiFeatureFlags.current;
    final conflict = OfficialAnkiProjectionMapper().mappingConflict(_current);
    final samples = widget.schema?.samples.take(1).toList() ?? const [];
    final fieldNames = widget.schema?.fieldNames ??
        [for (final c in _current.candidates) c.fieldName];
    final statusLabel = _statusLabels[_current.status] ?? _current.status.name;
    final missingTarget =
        _current.role(OfficialAnkiFieldRole.targetText) == null;
    final missingAnswer = !_current.singleFieldMode &&
        _current.role(OfficialAnkiFieldRole.nativeText) == null;
    final blocking = conflict != null || missingTarget || missingAnswer;
    final needsAttention = blocking ||
        (_current.status != OfficialAnkiMappingStatus.autoCandidate &&
            _current.status != OfficialAnkiMappingStatus.skipped);
    final statusColor = blocking
        ? TurnaTheme.error
        : needsAttention
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.ankiMappingEditTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  blocking
                      ? Icons.error_outline_rounded
                      : needsAttention
                          ? Icons.help_outline_rounded
                          : Icons.check_circle_outline,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${blocking ? '看一下样卡，选哪边是正面、哪边是背面' : statusLabel}'
                    '${widget.affectedCardCount > 0 ? '（共 ${widget.affectedCardCount} 张）' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (samples.isNotEmpty) ...[
            Text(
              AppStrings.ankiMappingSourceName(widget.notetypeName),
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '这样显示正确吗？',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final sample in samples)
              Container(
                key: Key('mapping-sample-${sample.noteId}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                  border: Border.all(
                    color: TurnaTheme.textHintColor(context)
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MappingPreviewSide(
                      label: '正面',
                      value: _sampleValue(
                        sample,
                        OfficialAnkiFieldRole.targetText,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Center(child: Icon(Icons.arrow_downward_rounded)),
                    ),
                    _MappingPreviewSide(
                      label: '背面',
                      value: _sampleValue(
                        sample,
                        OfficialAnkiFieldRole.nativeText,
                      ),
                    ),
                  ],
                ),
              ),
            Center(
              child: OutlinedButton.icon(
                key: const Key('mapping-swap'),
                onPressed: _current.role(OfficialAnkiFieldRole.targetText) !=
                            null &&
                        _current.role(OfficialAnkiFieldRole.nativeText) != null
                    ? _swapPrimaryRoles
                    : null,
                icon: const Icon(Icons.swap_vert_rounded, size: 18),
                label: Text(AppStrings.ankiMappingSwapSides),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            AppStrings.ankiOfficialExerciseTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.ankiOfficialExerciseHint,
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in OfficialExercisePreset.values)
                ChoiceChip(
                  key: Key('exercise-preset-${preset.name}'),
                  label: Text(_presetLabel(preset)),
                  selected: presetOf(_current.enabledKinds) == preset,
                  onSelected: (_) => _selectExercisePreset(preset),
                ),
            ],
          ),
          if (widget.schema?.kind == 'cloze')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                AppStrings.ankiOfficialExerciseClozeNote,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            '正面和背面',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '通常不用改；样卡反了就换一栏。',
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
          if (conflict != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '正面和背面不能用同一栏',
                key: const Key('mapping-conflict'),
                style: const TextStyle(
                  color: TurnaTheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          _roleSelector(
            role: OfficialAnkiFieldRole.targetText,
            label: '正面',
            fieldNames: fieldNames,
          ),
          _roleSelector(
            role: OfficialAnkiFieldRole.nativeText,
            label: '背面',
            fieldNames: fieldNames,
          ),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('mapping-more-fields'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                '更多内容',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('音频、图片、例句、分组等'),
              children: [
                for (final role in OfficialAnkiFieldRole.values)
                  if (role != OfficialAnkiFieldRole.ignored &&
                      role != OfficialAnkiFieldRole.targetText &&
                      role != OfficialAnkiFieldRole.nativeText)
                    _roleSelector(
                      role: role,
                      label: _roleLabels[role] ?? role.name,
                      fieldNames: fieldNames,
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('mapping-restore'),
                    onPressed: restoreSuggestion,
                    child: const Text('重新自动识别'),
                  ),
                ),
              ],
            ),
          ),
          if (!flags.allowsOfficialRenderer)
            const OfficialAnkiReviewerErrorView(
              messageKey: 'official_anki.renderer_flag_fail_closed',
            ),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              TextButton(
                key: const Key('mapping-skip'),
                onPressed: widget.onSkip,
                child: const Text('跳过这类卡片'),
              ),
              const Spacer(),
              if (widget.onGenerateCourse != null)
                TextButton(
                  key: const Key('mapping-generate'),
                  onPressed: widget.onGenerateCourse,
                  child: const Text('生成课程'),
                ),
              FilledButton(
                key: const Key('mapping-save'),
                onPressed:
                    blocking ? null : () => widget.onConfirm?.call(_current),
                child: Text(AppStrings.ankiMappingConfirmCorrect),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleSelector({
    required OfficialAnkiFieldRole role,
    required String label,
    required List<String> fieldNames,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _roleIcons[role],
        size: 22,
        color: TurnaTheme.brandTeal,
      ),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        _current.role(role)?.fieldName ?? '未选择（可留空）',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: fieldNames.isEmpty
          ? null
          : DropdownButton<int>(
              key: Key('mapping-role-${role.name}'),
              value: _current.role(role)?.fieldIndex,
              hint: const Text('选择字段'),
              items: [
                for (var i = 0; i < fieldNames.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(userFacingFieldName(fieldNames[i])),
                  ),
              ],
              onChanged: (index) {
                if (index != null) assignRole(role, index);
              },
            ),
    );
  }
}

class _MappingPreviewSide extends StatelessWidget {
  const _MappingPreviewSide({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: TurnaTheme.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
