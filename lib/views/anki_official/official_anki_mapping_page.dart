import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

/// Editable mapping wizard. Saving does not generate a course.
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
  State<OfficialAnkiMappingPage> createState() => OfficialAnkiMappingPageState();
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

  @override
  Widget build(BuildContext context) {
    final flags = OfficialAnkiFeatureFlags.current;
    final conflict = OfficialAnkiProjectionMapper().mappingConflict(_current);
    final samples = widget.schema?.samples.take(3).toList() ?? const [];
    final payloads = OfficialAnkiProjectionPayloads();
    final previewKinds = widget.schema == null
        ? const <String>[]
        : [
            for (final sample in samples.take(1))
              ...payloads
                  .kindsFor(
                    values: payloads.values(
                      OfficialAnkiProjectionRow(
                        cardId: 0,
                        noteId: sample.noteId,
                        noteGuid: '',
                        notetypeId: widget.schema!.notetypeId,
                        deckId: 0,
                        deckPath: const <String>[],
                        templateOrdinal: 0,
                        tags: const <String>[],
                        fields: sample.fields,
                        sourceFingerprint: '',
                      ),
                      _current,
                    ),
                    mapping: _current,
                    typeAnswerEnabled: false,
                  )
                  .map((kind) => kind.name),
          ];
    return Scaffold(
      appBar: AppBar(title: Text('字段映射 · ${widget.notetypeName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('状态：${_current.status.name}'),
          Text('受影响卡片：${widget.affectedCardCount}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('mapping-restore'),
                onPressed: restoreSuggestion,
                child: const Text('恢复自动建议'),
              ),
              FilledButton(
                key: const Key('mapping-save'),
                onPressed: () => widget.onConfirm?.call(_current),
                child: const Text('保存映射'),
              ),
              OutlinedButton(
                key: const Key('mapping-skip'),
                onPressed: widget.onSkip,
                child: const Text('跳过此 Notetype'),
              ),
              if (widget.onGenerateCourse != null)
                FilledButton.tonal(
                  key: const Key('mapping-generate'),
                  onPressed: widget.onGenerateCourse,
                  child: const Text('生成课程'),
                ),
            ],
          ),
          if (conflict != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('冲突：$conflict', key: const Key('mapping-conflict')),
            ),
          if (widget.schema != null)
            Text('字段：${widget.schema!.fieldNames.join(', ')}'),
          for (final sample in samples)
            ListTile(
              title: Text(
                sample.fields.take(3).join(' / '),
                key: Key('mapping-sample-${sample.noteId}'),
              ),
              subtitle: Text(
                sample.fields.any((f) => f.length >= 8000)
                    ? 'truncated'
                    : 'sample',
              ),
            ),
          for (final role in OfficialAnkiFieldRole.values)
            if (role != OfficialAnkiFieldRole.ignored)
              ListTile(
                title: Text('${role.name} ← ${_current.role(role)?.fieldName ?? '未选'}'),
                subtitle: Text(
                  'confidence=${(_current.role(role)?.confidence ?? 0).toStringAsFixed(2)} '
                  '${_current.role(role)?.evidence.join(', ') ?? ''}',
                ),
                trailing: widget.schema == null
                    ? null
                    : DropdownButton<int>(
                        key: Key('mapping-role-${role.name}'),
                        value: _current.role(role)?.fieldIndex,
                        hint: const Text('选择字段'),
                        items: [
                          for (var i = 0; i < widget.schema!.fieldNames.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(widget.schema!.fieldNames[i]),
                            ),
                        ],
                        onChanged: (index) {
                          if (index != null) assignRole(role, index);
                        },
                      ),
              ),
          Text('将生成：${previewKinds.toSet().join(', ')}'),
          if (!flags.allowsOfficialRenderer)
            const OfficialAnkiReviewerErrorView(
              messageKey: 'official_anki.renderer_flag_fail_closed',
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
