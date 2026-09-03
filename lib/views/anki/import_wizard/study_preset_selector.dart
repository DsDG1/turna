import 'package:flutter/material.dart';
import 'package:turna/views/theme.dart';

/// Global learning style preset modes for imported Anki decks.
enum StudyPresetMode {
  /// Interactive practice: transforms recognized cards into multiple choice,
  /// fill-in-the-blank, and listening questions, with flip as fallback.
  interactive,

  /// Classic flashcards: uses traditional active-recall front/back flips.
  classicFlip,

  /// Raw official fidelity: preserves original HTML/CSS styling via WebView.
  fidelity,
}

/// Selector widget for global study preset modes.
class StudyPresetSelector extends StatelessWidget {
  const StudyPresetSelector({
    super.key,
    required this.selectedMode,
    required this.onSelectMode,
  });

  final StudyPresetMode selectedMode;
  final ValueChanged<StudyPresetMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.tune_rounded,
              size: 18,
              color: TurnaTheme.brandTeal,
            ),
            const SizedBox(width: 6),
            const Text(
              '学习模式设定',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '导入后可在课程设置中更改',
              style: TextStyle(
                fontSize: 11,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildModeCard(
          context,
          mode: StudyPresetMode.interactive,
          icon: Icons.psychology_rounded,
          title: '智能互动练习',
          badgeText: '推荐',
          description: '自动转换出选择、填空、听音等互动题型，告别单一翻面，提升做题趣味与记忆效果。',
        ),
        const SizedBox(height: 8),
        _buildModeCard(
          context,
          mode: StudyPresetMode.classicFlip,
          icon: Icons.flip_to_back_rounded,
          title: '经典闪卡翻面',
          description: '纯粹的正反翻面主动回忆，适合词汇快速刷记与传统 Anki 熟练背诵。',
        ),
        const SizedBox(height: 8),
        _buildModeCard(
          context,
          mode: StudyPresetMode.fidelity,
          icon: Icons.web_asset_rounded,
          title: '原卡官方保真',
          description: '100% 还原 Anki 桌面端 HTML/CSS/JS 样式与动态效果，适合复杂定制排版。',
        ),
      ],
    );
  }

  Widget _buildModeCard(
    BuildContext context, {
    required StudyPresetMode mode,
    required IconData icon,
    required String title,
    required String description,
    String? badgeText,
  }) {
    final isSelected = selectedMode == mode;
    const activeColor = TurnaTheme.brandTeal;

    return Material(
      color: TurnaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        onTap: () => onSelectMode(mode),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : TurnaTheme.textHintColor(context).withValues(alpha: 0.18),
              width: isSelected ? 1.5 : 1.0,
            ),
            color: isSelected
                ? activeColor.withValues(alpha: 0.04)
                : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected
                    ? activeColor
                    : TurnaTheme.textHintColor(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: activeColor),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isSelected
                                ? activeColor
                                : TurnaTheme.textPrimaryColor(context),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: TurnaTheme.anatolianClay,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: TurnaTheme.textSecondaryColor(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
