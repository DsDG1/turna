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

/// 顶部「快速练习」Hero：teal->cyan 渐变 + 白字 + 白色闪电 chip。
class QuickPlayHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const QuickPlayHero({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.bolt_rounded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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

/// 「今日重点」单格：accent 着色底 + accent icon chip + accent 标题 +
/// 主文字色 count + accent「开始 ›」。
class FocusTile extends StatelessWidget {
  final String title;
  final String countText;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final VoidCallback onTap;

  const FocusTile({
    required this.title,
    required this.countText,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return SoftCard(
      accentColor: accentColor,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AccentIconChip(icon: icon, color: accent, size: 26),
                const Spacer(),
                if (badge != null)
                  CountBadge(label: badge!, color: accentColor),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                countText,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: TurnaTheme.textPrimaryColor(context),
                    ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  AppStrings.playStartAction,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: accent.withValues(alpha: 0.7),
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「复习中心」单格：accent icon chip + accent 标题 + 右侧箭头。
class ReviewTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? badge;
  final VoidCallback onTap;

  const ReviewTile({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return SoftCard(
      accentColor: accentColor,
      onTap: onTap,
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
  final bool enabled;

  const ToolsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.onTap,
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
class SoftCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final VoidCallback? onTap;

  const SoftCard({
    required this.accentColor,
    required this.child,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: TurnaTheme.softTint(context, accentColor),
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
