// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_cards.dart';

// ────────────────────────────────────────────────────────────────────
// Soft-tinted card surfaces — shared building blocks
// ────────────────────────────────────────────────────────────────────
// 设计目标（ADR 0062）：白纸上的彩色玻璃。SoftCard 走 L1 淡彩玻璃
// （[TurnaTheme.glassFill] + 同色相双层投影），Hero 例外保留 accent 渐变
// + 白字 —— 它是全页唯一的主 CTA，需要实色的分量。
// 暗色下淡彩由 glassFill 自动罩染到不透明基面，accent 文字经
// [TurnaTheme.accentOnCard] 提亮，避免发灰发浑。
//
// 抽取自 `play_hub_screen.dart`，供练习 Hub 与 AI 页共用，保证两页风格
// 完全一致。组件签名与原私有版本保持一致，仅去 `_` 改为 public。
// 2026-08 重构（Play Hub 焕新）：新增 TodayHeroCard / CompactToolTile；
// SoftCard 及各 tile 支持 onLongPress（长按浮窗交互，见 info_popup.dart），
// FocusTile 退役。2026-10-20：「AI 助手」横幅（原 AiAssistantTile）撤除，
// 改为复习队列里的「智能练习」一格，该组件随之删除。

/// 今日复习主 CTA Hero：teal→sky 渐变卡。左侧「开始今日复习」+ 下一个队列
/// 副标题，右侧今日待复习总数；下方一行队列 chips（四队列计数速览）。
/// 短按进入智能选中的队列，长按弹出全队列数据浮窗。
class TodayHeroCard extends StatelessWidget {
  final String subtitle;

  /// 右侧大数字：今日待复习总数。
  final int totalDue;

  /// 队列速览 chips（错题/单词/语法/Anki）。`count == null` 表示数据不可用。
  final List<QueueChipData> chips;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  const TodayHeroCard({
    required this.subtitle,
    required this.totalDue,
    required this.chips,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.cardRadius));

    return Semantics(
      button: true,
      onLongPress: onLongPress,
      hint: onLongPress == null ? null : AppStrings.playLongPressHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: Ink(
            decoration: TurnaTheme.brandHeroDecoration(
              context,
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.playTodayHeroTitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$totalDue',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                          ),
                          Text(
                            AppStrings.playTodayHeroTotalLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final chip in chips) _QueueChip(data: chip),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个队列速览 chip 的数据。
class QueueChipData {
  const QueueChipData({
    required this.label,
    required this.color,
    this.count,
  });

  final String label;
  final Color color;

  /// null = 数据不可用（显示 —）；0 = 弱化展示。
  final int? count;
}

class _QueueChip extends StatelessWidget {
  final QueueChipData data;

  const _QueueChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final dimmed = data.count == 0;
    final text = data.count == null ? '—' : '${data.count}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dimmed ? 0.08 : 0.14),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Colors.white.withValues(alpha: dimmed ? 0.14 : 0.26),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: data.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${data.label} $text',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: dimmed ? 0.6 : 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「复习队列」单格：accent icon chip + accent 标题 + 右侧箭头。
/// 长按弹出该队列的数据浮窗（onLongPress 为 null 时无长按交互）。
class ReviewTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? badge;

  /// Badge 底色，默认跟随 [accentColor]。用于「未配置」这类需要警示色的
  /// 非计数徽标（智能练习入口）。
  final Color? badgeColor;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  /// Soft-tint strength for [SoftCard] fill (default 0.10).
  final double tintAlpha;

  const ReviewTile({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.badgeColor,
    this.tintAlpha = 0.10,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return SoftCard(
      accentColor: accentColor,
      tintAlpha: tintAlpha,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsHint: onLongPress == null ? null : AppStrings.playLongPressHint,
      // 高度基线由外层 AdaptiveCardGrid 的 minChildAspectRatio 给出，
      // 常驻字体放大时随内容长高（不再靠 GridView 的固定格子高度）。
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AccentIconChip(
                  icon: icon,
                  color: accent,
                  size: 22,
                  padding: 8,
                ),
                const SizedBox(width: 8),
                // 「未配置」这类文字徽标在字体放大后会比格子还宽（真机
                // `RenderFlex overflowed ... on the right`）。右对齐区改用
                // Expanded + FittedBox(scaleDown)：放得下就保持原字号，
                // 放不下就缩字，不裁字也不溢出。
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: badge == null
                        ? const SizedBox.shrink()
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: CountBadge(
                              label: badge!,
                              color: badgeColor ?? accentColor,
                              circular: true,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: accent.withValues(alpha: 0.7),
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「工具」行：icon chip + 标题 + 副标题 + 右侧箭头，单卡一行。
///
/// [onTap] 可空 + [enabled] 控制可用态：禁用时降透明度且不响应点击，
/// 用于条件性入口（如「深度讲解当前题」需先有题目）。
class ToolsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final bool enabled;

  const ToolsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: SoftCard(
        accentColor: accentColor,
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        semanticsHint: (enabled && onLongPress != null)
            ? AppStrings.playLongPressHint
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              AccentIconChip(icon: icon, color: accent, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: TurnaTheme.textPrimaryColor(context),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: accent.withValues(alpha: 0.7),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「练习工具」紧凑格：icon chip + 标题 + 可选副标题，用于三列一行布局。
class CompactToolTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  const CompactToolTile({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return SoftCard(
      accentColor: accentColor,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsHint: onLongPress == null ? null : AppStrings.playLongPressHint,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AccentIconChip(icon: icon, color: accent, size: 20, padding: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: badge == null
                        ? const SizedBox.shrink()
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: CountBadge(
                              label: badge!,
                              color: accentColor,
                              circular: true,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
