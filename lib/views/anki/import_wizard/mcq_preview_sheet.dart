import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/views/theme.dart';

/// In-place modal bottom sheet for inspecting and fine-tuning recognized choice
/// questions (or other archetypes) for a specific Anki notetype/chapter.
void showMcqPreviewSheet({
  required BuildContext context,
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion currentSuggestion,
  required void Function(OfficialAnkiMappingSuggestion updated) onConfirmed,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusLarge),
      ),
    ),
    builder: (sheetContext) {
      return _McqPreviewContent(
        schema: schema,
        currentSuggestion: currentSuggestion,
        onConfirmed: onConfirmed,
      );
    },
  );
}

class _McqPreviewContent extends StatefulWidget {
  const _McqPreviewContent({
    required this.schema,
    required this.currentSuggestion,
    required this.onConfirmed,
  });

  final OfficialAnkiProjectionSchema schema;
  final OfficialAnkiMappingSuggestion currentSuggestion;
  final void Function(OfficialAnkiMappingSuggestion updated) onConfirmed;

  @override
  State<_McqPreviewContent> createState() => _McqPreviewContentState();
}

class _McqPreviewContentState extends State<_McqPreviewContent> {
  late List<String> _enabledKinds;

  @override
  void initState() {
    super.initState();
    _enabledKinds = List<String>.from(widget.currentSuggestion.enabledKinds);
  }

  void _applyMode(int index) {
    setState(() {
      if (index == 0) {
        // 智能练习 (含选择题)
        _enabledKinds = const [
          'multipleChoice',
          'multiSelect',
          'fillBlank',
          'listenPick',
          'typeAnswer',
          'flip',
          'canonicalLink',
        ];
      } else if (index == 1) {
        // 经典翻卡
        _enabledKinds = const ['flip', 'canonicalLink'];
      } else {
        // 官方保真
        _enabledKinds = const ['canonicalLink'];
      }
    });

    final updated = widget.currentSuggestion.copyWith(
      enabledKinds: _enabledKinds,
      status: OfficialAnkiMappingStatus.manual,
      userConfirmed: true,
    );
    widget.onConfirmed(updated);
  }

  @override
  Widget build(BuildContext context) {
    final sample = widget.schema.samples.firstOrNull;
    final isChoice = widget.currentSuggestion.cardArchetype.name == 'choice' ||
        _enabledKinds.contains('multipleChoice') ||
        _enabledKinds.contains('multiSelect');

    // Parse sample choice
    String promptText = '';
    List<String> options = [];
    List<int> correctIndices = [];

    if (sample != null) {
      final fieldNames = widget.schema.fieldNames;
      final fieldValues = sample.fields;

      // Try multi-field first
      final multiOptions = EmbeddedOptionsParser.extractMultiFieldOptions(
        fieldNames,
        fieldValues,
      );

      final frontVal = fieldValues.isNotEmpty ? fieldValues.first : '';
      final backVal = fieldValues.length > 1 ? fieldValues[1] : '';

      if (multiOptions != null && multiOptions.length >= 2) {
        options = multiOptions;
        promptText = frontVal.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        correctIndices =
            EmbeddedOptionsParser.parseCorrectIndices(backVal, options);
      } else {
        // Try embedded options
        final embedded =
            EmbeddedOptionsParser.extractEmbeddedOptions(frontVal);
        if (embedded != null) {
          promptText =
              embedded.prompt.replaceAll(RegExp(r'<[^>]*>'), '').trim();
          options = embedded.options;
          correctIndices =
              EmbeddedOptionsParser.parseCorrectIndices(backVal, options);
        } else {
          promptText = frontVal.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        }
      }
    }

    final isMultiSelect = correctIndices.length >= 2;

    int selectedModeIndex = 0;
    if (_enabledKinds.contains('canonicalLink') && _enabledKinds.length == 1) {
      selectedModeIndex = 2;
    } else if (!_enabledKinds.contains('multipleChoice') &&
        !_enabledKinds.contains('fillBlank')) {
      selectedModeIndex = 1;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: TurnaTheme.textHintColor(context)
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '题型效果预览（${widget.schema.name}）',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                  ),
                  child: Text(
                    isMultiSelect ? '多选题' : (isChoice ? '单选题' : '翻转卡'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 模式微调选项卡
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: TurnaTheme.scaffoldBg(context),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Row(
                children: [
                  _modeTab(0, '智能互动练习', selectedModeIndex == 0),
                  _modeTab(1, '经典闪卡翻面', selectedModeIndex == 1),
                  _modeTab(2, '原卡官方保真', selectedModeIndex == 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 题目渲染卡片
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: TurnaTheme.scaffoldBg(context),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                  border: Border.all(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.15),
                  ),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      promptText.isNotEmpty ? promptText : '无可用题目文本',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    if (options.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (var i = 0; i < options.length; i++)
                        _optionTile(
                          context,
                          index: i,
                          text: options[i],
                          isCorrect: correctIndices.contains(i),
                          isMulti: isMultiSelect,
                        ),
                    ],
                    if (sample != null &&
                        sample.fields.length > 1 &&
                        options.isEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Text(
                        '背面答案：${sample.fields[1].replaceAll(RegExp(r'<[^>]*>'), '').trim()}',
                        style: TextStyle(
                          fontSize: 13,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TurnaTheme.brandTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusMedium),
                  ),
                ),
                child: const Text('完成', style: TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(int index, String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyMode(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? TurnaTheme.cardBg(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required int index,
    required String text,
    required bool isCorrect,
    required bool isMulti,
  }) {
    final letter = String.fromCharCode(65 + index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCorrect
              ? TurnaTheme.brandTeal.withValues(alpha: 0.06)
              : TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
          border: Border.all(
            color: isCorrect
                ? TurnaTheme.brandTeal
                : TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
            width: isCorrect ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isMulti
                  ? (isCorrect
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded)
                  : (isCorrect
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded),
              size: 18,
              color: isCorrect
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.textHintColor(context),
            ),
            const SizedBox(width: 8),
            Text(
              '$letter. ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCorrect
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textPrimaryColor(context),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
            ),
            if (isCorrect)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '正确答案',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
