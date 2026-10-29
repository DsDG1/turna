import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/study_preset_selector.dart';

/// 预览页的「笔记类型 → 学习模式」行（A1：从预览页抽出，页面只做摆放）。
///
/// [countsLabel] 是逐卡解析计数（可空：全部保持练习或尚无样本时不显示），
/// 由页面用同一个解析器聚合后传入。
class NotetypeModeRow extends StatelessWidget {
  const NotetypeModeRow({
    super.key,
    required this.schema,
    required this.mode,
    required this.onChanged,
    this.countsLabel,
  });

  final OfficialAnkiProjectionSchema schema;
  final StudyPresetMode mode;
  final ValueChanged<StudyPresetMode> onChanged;
  final String? countsLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schema.name.isEmpty
                      ? AppStrings.ankiPreviewStudyMode
                      : schema.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (countsLabel != null)
                  Text(
                    countsLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
              ],
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
