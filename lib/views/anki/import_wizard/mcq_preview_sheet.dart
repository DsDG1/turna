import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// In-place modal bottom sheet for inspecting and fine-tuning recognized choice
/// questions (or other archetypes) for a specific Anki notetype/chapter.
void showMcqPreviewSheet({
  required BuildContext context,
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion currentSuggestion,
  required void Function(OfficialAnkiMappingSuggestion updated) onConfirmed,
}) {
  showTurnaSheet<void>(
    context: context,
    title: AppStrings.mcqPreviewTitle(schema.name),
    body: _McqPreviewContent(
      schema: schema,
      currentSuggestion: currentSuggestion,
      onConfirmed: onConfirmed,
    ),
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
    final isChoice =
        widget.currentSuggestion.cardArchetype.name == 'choice' ||
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
        correctIndices = EmbeddedOptionsParser.parseCorrectIndices(
          backVal,
          options,
        );
      } else {
        // Try embedded options
        final embedded = EmbeddedOptionsParser.extractEmbeddedOptions(frontVal);
        if (embedded != null) {
          promptText = embedded.prompt
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          options = embedded.options;
          correctIndices = EmbeddedOptionsParser.parseCorrectIndices(
            backVal,
            options,
          );
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.xs,
        AppSpacing.pageMargin,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: Text(
              isMultiSelect
                  ? AppStrings.mcqPreviewKindMultiSelect
                  : (isChoice
                        ? AppStrings.mcqPreviewKindSingleChoice
                        : AppStrings.mcqPreviewKindFlip),
              style: AppTextStyles.caption(context).copyWith(
                fontWeight: FontWeight.w600,
                color: TurnaTheme.brandTeal,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 模式微调选项卡
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: TurnaTheme.scaffoldBg(context),
              borderRadius: TurnaTheme.borderRadius,
              border: Border.all(color: TurnaTheme.dividerBg(context)),
            ),
            child: Row(
              children: [
                _modeTab(
                  0,
                  AppStrings.mcqPreviewModeInteractive,
                  selectedModeIndex == 0,
                ),
                _modeTab(
                  1,
                  AppStrings.mcqPreviewModeClassic,
                  selectedModeIndex == 1,
                ),
                _modeTab(
                  2,
                  AppStrings.mcqPreviewModeFidelity,
                  selectedModeIndex == 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 题目渲染卡片
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: TurnaTheme.scaffoldBg(context),
                borderRadius: TurnaTheme.borderRadius,
                border: Border.all(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.15),
                ),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    promptText.isNotEmpty
                        ? promptText
                        : AppStrings.mcqPreviewNoPrompt,
                    style: AppTextStyles.cardTitle(context)
                        .copyWith(height: 1.4),
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.mcqPreviewBackAnswer(
                        sample.fields[1]
                            .replaceAll(RegExp(r'<[^>]*>'), '')
                            .trim(),
                      ),
                      style: AppTextStyles.captionSm(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: TurnaTheme.shape,
              ),
              child: Text(AppStrings.commonDone),
            ),
          ),
        ],
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
            borderRadius: TurnaTheme.borderRadius,
            border: active
                ? Border.all(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.35),
                  )
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.caption(context).copyWith(
                letterSpacing: 0,
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isCorrect
              ? TurnaTheme.brandTeal.withValues(alpha: 0.06)
              : TurnaTheme.cardBg(context),
          borderRadius: TurnaTheme.borderRadius,
          border: Border.all(
            color: isCorrect
                ? TurnaTheme.brandTeal
                : TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
            width: isCorrect ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            TurnaIcon(
              isMulti
                  ? (isCorrect
                        ? TurnaIconId.checkboxChecked
                        : TurnaIconId.checkboxUnchecked)
                  : (isCorrect
                        ? TurnaIconId.radioChecked
                        : TurnaIconId.radioUnchecked),
              size: 18,
              color: isCorrect
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.textHintColor(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$letter. ',
              style: AppTextStyles.captionSm(context).copyWith(
                fontWeight: FontWeight.w700,
                color: isCorrect
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.textPrimaryColor(context),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.captionSm(context)
                    .copyWith(color: TurnaTheme.textPrimaryColor(context)),
              ),
            ),
            if (isCorrect)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: const BoxDecoration(
                  color: TurnaTheme.brandTeal,
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: Text(
                  AppStrings.mcqPreviewCorrectBadge,
                  style: AppTextStyles.caption(context).copyWith(
                    color: TurnaTheme.textOnPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
