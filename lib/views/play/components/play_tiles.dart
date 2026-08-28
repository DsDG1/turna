// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

// ────────────────────────────────────────────────────────────────────
// Soft-tinted card surfaces — shared building blocks
// ────────────────────────────────────────────────────────────────────
// 设计目标：轻盈 pastel 着色卡，accent @ 0.10 底色 + 白色高光描边 +
// 白色晕染发光 + 内侧顶部霜面高光 + 圆角 20。Hero 例外用 accent 渐变 + 白字。
// 暗色模式由 [TurnaTheme.softTint] 改为不透明罩染，accent 文字经
// [TurnaTheme.accentOnCard] 提亮，避免发灰发浑。
//
// 抽取自 `play_hub_screen.dart`，供练习 Hub 与 AI 页共用，保证两页风格
// 完全一致。组件签名与原私有版本保持一致，仅去 `_` 改为 public。
// 2026-08 重构（Play Hub 焕新）：新增 TodayHeroCard / AiAssistantTile /
// CompactToolTile；SoftCard 及各 tile 支持 onLongPress（长按浮窗交互，
// 见 info_popup.dart），FocusTile 退役。

/// 顶部渐变 Hero 卡：teal->cyan 渐变 + 白字。Playground（语言课程入口）使用；
/// 保持通用签名（标题/副标题/图标）。支持长按浮窗。
class PlaygroundHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  const PlaygroundHero({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.sports_esports_rounded,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                TurnaTheme.brandTeal,
                TurnaTheme.brandSky,
              ],
            ),
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TurnaTheme.brandTeal, TurnaTheme.brandSky],
              ),
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
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
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
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
                      for (final chip in chips)
                        _QueueChip(data: chip),
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
        color: Colors.white.withValues(alpha: dimmed ? 0.10 : 0.18),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Colors.white.withValues(alpha: dimmed ? 0.18 : 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: data.color, shape: BoxShape.circle),
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
                const Spacer(),
                if (badge != null)
                  CountBadge(
                    label: badge!,
                    color: accentColor,
                    circular: true,
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
                    maxLines: 1,
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

// ────────────────────────────────────────────────────────────────────
// Building blocks
// ────────────────────────────────────────────────────────────────────

/// 软着色卡底座：accent 着色底 + 白色高光描边（无彩色线条）+ 圆角 20 +
/// accent 轻阴影 + 白色晕染发光 + 内侧顶部霜面高光。
/// 暗色模式由 [TurnaTheme.softTint] 自动转为不透明罩染。
/// `onLongPress` 非空时附加长按语义（无障碍「长按查看数据详情」）。
class SoftCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  /// Blend alpha for [TurnaTheme.softTint] (default 0.10).
  final double tintAlpha;

  const SoftCard({
    required this.accentColor,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tintAlpha = 0.10,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

    Widget card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: TurnaTheme.softTint(context, accentColor, alpha: tintAlpha),
            borderRadius: radius,
            border: Border.all(
              color: TurnaTheme.glassBorder(context),
              width: 1,
            ),
            boxShadow: [
              ...TurnaTheme.softCardShadow(context, accentColor),
              ...TurnaTheme.featheredButtonGlow(context),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: TurnaTheme.softCardSheen(context),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onLongPress != null) {
      card = Semantics(
        button: true,
        onLongPress: onLongPress,
        hint: AppStrings.playLongPressHint,
        child: card,
      );
    }
    return card;
  }
}

/// AI 助手行卡：icon chip + 标题 + 引擎状态点 + chevron。合并旧版
/// 「AI 助手大格 + 引擎状态条」为单行，长按查看引擎配置浮窗。
class AiAssistantTile extends StatelessWidget {
  final bool engineReady;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  const AiAssistantTile({
    required this.engineReady,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.amethystLeague);
    final statusColor = engineReady ? TurnaTheme.success : TurnaTheme.warning;

    return SoftCard(
      accentColor: TurnaTheme.amethystLeague,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AccentIconChip(
              icon: Icons.auto_awesome_rounded,
              color: accent,
              size: 22,
              padding: 9,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.playAiAssistantTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.textPrimaryColor(context),
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    engineReady
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: statusColor,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    engineReady
                        ? AppStrings.playAiEngineReady
                        : AppStrings.playAiEngineNotConfigured,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: accent.withValues(alpha: 0.7),
              size: 14,
            ),
          ],
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AccentIconChip(icon: icon, color: accent, size: 20, padding: 8),
                const Spacer(),
                if (badge != null)
                  CountBadge(
                    label: badge!,
                    color: accentColor,
                    circular: true,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
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

/// accent icon chip：accent @ 0.22 底 + accent 图标，浅色下加 1px 白色描边
/// 提亮。`size` / `padding` / `radius` 可调，复用于 FocusTile / ReviewTile /
/// ToolsTile。
class AccentIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double padding;
  final double radius;

  const AccentIconChip({
    required this.icon,
    required this.color,
    this.size = 26,
    this.padding = 10,
    this.radius = 12,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// 小号玻璃 chip：accent 实色 + 白边高光 + 轻阴影。
/// 默认 pill 形态；[circular] 时切换为小圆角（用于复习宫格小格子）。
class CountBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool circular;

  const CountBadge({
    required this.label,
    required this.color,
    this.circular = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final radius = circular
        ? const BorderRadius.all(Radius.circular(TurnaTheme.radiusMedium))
        : const BorderRadius.all(Radius.circular(TurnaTheme.radiusMedium));

    return Container(
      padding: circular
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.glassBadgeFill(color),
        borderRadius: radius,
        border: Border.all(
          color: TurnaTheme.glassHighlight(context),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: TurnaTheme.textOnPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: TurnaTheme.textPrimaryColor(context),
            ),
      ),
    );
  }
}
