/// 会话骨架 ——「湿地雾光」沉浸作答模式（P2 组件，P3 / P4 逐域接线）。
///
/// 课时壳、统一复习、正式记忆卡与语法三相位共用同一副骨架，只换上下文行：
///
/// ```text
/// SessionProgressBand   退出 + 分段进度 + 计数（+ 上下文动作键）
/// ── 来源行 / 题型标记（调用方按域自选）──
/// Expanded + SessionRecallCanvas   回忆画布 / 大题面（纸面容器）
/// SessionActionBand     阶段动作带（SessionPrimaryAction / SessionRatingBand）
/// ```
///
/// 它吸收的是 `review/components` 里三套平行实现的共性：进度头
/// （ReviewProgressHeader + 语法页手写 AppBar actions）、评分条
/// （BinaryRecallBar 与 ReviewRatingBar）与「显示答案」按钮。**本文件不做
/// 接线**——旧实现原样保留，迁移发生在 P3 / P4 各域重构时。
///
/// 高对比：进度点与评分按钮全部依赖轮廓 / 形状表达（环 vs 实心），不依赖
/// 玻璃材质；动作带是纸面（实色 + 发丝线），不经 GlassSurface。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// 顶部会话进度带的进度表达方式。
enum SessionProgressStyle {
  /// 分段圆点（默认）：已完成实心、当前空心环、未达浅灰。题目数少（≤16）
  /// 时逐题可见，是课时与短队列的首选。
  dots,

  /// 细进度条：长队列（统一复习、每日挑战）用，不逐题占位。
  bar,
}

/// 会话顶带：退出 + 进度 + 计数 + 上下文动作键。
///
/// [currentIndex] 从 1 计。`dots` 风格在题目数超过 16 时自动落回 `bar`，
/// 避免圆点互相挤压成一条灰带。
class SessionProgressBand extends StatelessWidget
    implements PreferredSizeWidget {
  const SessionProgressBand({
    required this.currentIndex,
    required this.totalCount,
    this.style = SessionProgressStyle.dots,
    this.onExit,
    this.exitTooltip,
    this.actions = const <Widget>[],
    this.includeSafeArea = true,
    super.key,
  });

  final int currentIndex;
  final int totalCount;
  final SessionProgressStyle style;
  final VoidCallback? onExit;

  /// 退出键的语义名；不传用「关闭」。
  final String? exitTooltip;

  /// 上下文动作键（AI 讲解 / 撤销 / 更多），排在计数之后。
  final List<Widget> actions;
  final bool includeSafeArea;

  static const double bandHeight = 56;

  @override
  Size get preferredSize => const Size.fromHeight(bandHeight);

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style == SessionProgressStyle.dots &&
            totalCount > _maxDots
        ? SessionProgressStyle.bar
        : style;

    final content = SizedBox(
      height: bandHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMarginCompact,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: exitTooltip ?? AppStrings.commonClose,
              onPressed: onExit ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Center(
                child: switch (effectiveStyle) {
                  SessionProgressStyle.dots => SessionSegmentedDots(
                      done: currentIndex - 1,
                      isCurrentReached: currentIndex <= totalCount,
                      total: totalCount,
                    ),
                  SessionProgressStyle.bar => SessionThinProgressBar(
                      value: totalCount <= 0
                          ? 0
                          : (currentIndex / totalCount).clamp(0.0, 1.0),
                    ),
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _CountLabel(currentIndex: currentIndex, totalCount: totalCount),
            ...actions,
          ],
        ),
      ),
    );
    return includeSafeArea
        ? SafeArea(bottom: false, child: content)
        : content;
  }

  static const int _maxDots = 16;
}

/// 「n / m」计数。等宽数字防跳变（3→10 时宽度不抖）。
class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.currentIndex, required this.totalCount});

  final int currentIndex;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$currentIndex / $totalCount',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textSecondaryColor(context),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 分段进度点：已完成实心 teal、当前空心环、未达浅灰。
///
/// [done] 是已完成数；当前项画环（[isCurrentReached] 为 false 时全部画点，
/// 用于「进入即完成」之外的装配态）。
class SessionSegmentedDots extends StatelessWidget {
  const SessionSegmentedDots({
    required this.done,
    required this.isCurrentReached,
    required this.total,
    super.key,
  });

  final int done;
  final bool isCurrentReached;
  final int total;

  @override
  Widget build(BuildContext context) {
    final track = TurnaTheme.dividerBg(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < done
                  ? TurnaTheme.brandTeal
                  : (i == done && isCurrentReached)
                      ? Colors.transparent
                      : track,
              border: (i == done && isCurrentReached)
                  ? Border.all(color: TurnaTheme.brandTeal, width: 2.5)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// 细进度条（3px）：长队列的进度表达。
class SessionThinProgressBar extends StatelessWidget {
  const SessionThinProgressBar({required this.value, super.key});

  /// 0–1，越界自动收敛。
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 3,
        backgroundColor: TurnaTheme.dividerBg(context),
        valueColor:
            const AlwaysStoppedAnimation<Color>(TurnaTheme.brandTeal),
      ),
    );
  }
}

/// 会话来源行：图标 + 来源说明 + 尾部动作（更多 / AI）。
///
/// 放在进度带之下、画布之上，是三相位会话唯一的「上下文行」差异位。
class SessionSourceLine extends StatelessWidget {
  const SessionSourceLine({
    required this.icon,
    required this.label,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: TurnaTheme.textSecondaryColor(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.captionSm(context).copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 回忆画布：会话中段的大内容容器（纸面）。
///
/// 实色 + 发丝边（[TurnaTheme.flatPaperDecoration]）——评审决定题面不再放
/// 装饰图形，第三方卡片宿主也不加材质包装，所以这里刻意是纸面而不是玻璃。
/// 调用方负责 `Expanded` 与水平边距。
class SessionRecallCanvas extends StatelessWidget {
  const SessionRecallCanvas({
    required this.child,
    this.alignment = Alignment.center,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    super.key,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: padding,
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      ),
      child: child,
    );
  }
}

/// 底部阶段动作带：顶部发丝线 + 纸面底 + 安全区。
///
/// 位置跨题型 / 跨阶段稳定（P1 决定），内容随作答阶段换（提交 → 评分）。
class SessionActionBand extends StatelessWidget {
  const SessionActionBand({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.pageMargin,
      AppSpacing.lg,
      AppSpacing.pageMargin,
      AppSpacing.xl,
    ),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        border: Border(
          top: BorderSide(color: TurnaTheme.dividerBg(context)),
        ),
      ),
      child: SafeArea(top: false, child: Padding(padding: padding, child: child)),
    );
  }
}

/// 阶段主操作：全宽 52 高 teal 实体键（核对 / 显示答案 / 继续 / 开始）。
///
/// 规格与既有「显示答案」按钮一致（同一字符串族、52 高、radius 16、
/// elevation 钉 0），渐变走主题 [TurnaTheme.primaryCtaDecoration] 竖向档；
/// 禁用时退为平涂弱化底 + 禁用文字色。
class SessionPrimaryAction extends StatelessWidget {
  const SessionPrimaryAction({
    required this.label,
    this.onPressed,
    this.trailingIcon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    final decoration = enabled
        ? TurnaTheme.primaryCtaDecoration(
            borderRadius: radius,
            vertical: true,
          )
        : BoxDecoration(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.30),
            borderRadius: radius,
          );

    return Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: decoration,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: TurnaTheme.textOnPrimary,
            disabledForegroundColor:
                TurnaTheme.textOnPrimary.withValues(alpha: 0.55),
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: radius),
          ).copyWith(
            elevation: const WidgetStatePropertyAll<double>(0),
            shadowColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTextStyles.buttonLabel),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(trailingIcon, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 评分档的视觉调性。
enum SessionRatingTone {
  /// 描边档（弱反馈：不记得 / 再来一次）。天光蓝描边 + 同色文字，
  /// 评审确认的「不给错误红」的安静二元。
  outline,

  /// 实心档（正反馈：记得 / 掌握了）。teal 实底白字。
  primary,
}

/// 一档评分动作。
class SessionRatingAction {
  const SessionRatingAction({
    required this.label,
    required this.tone,
    this.interval,
    this.onPressed,
  });

  final String label;
  final SessionRatingTone tone;

  /// 权威间隔预览（FSRS「9 天」）；空串不渲染。
  final String? interval;
  final VoidCallback? onPressed;
}

/// 评分带：揭示之后的阶段动作带内容。
///
/// [above] 放揭示行（答案 / 对照），[actions] 是二档或三档评分键；间隔
/// 预览作小字注在主标签下。替代 BinaryRecallBar / ReviewRatingBar 两套
/// 平行实现。
class SessionRatingBand extends StatelessWidget {
  const SessionRatingBand({
    required this.actions,
    this.above,
    this.enabled = true,
    super.key,
  });

  /// 揭示行或阶段说明（可选）。
  final Widget? above;
  final List<SessionRatingAction> actions;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (above != null) ...[
          above!,
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _RatingButton(
                  action: actions[i],
                  enabled: enabled,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({required this.action, required this.enabled});

  final SessionRatingAction action;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tone = action.tone;
    final color = tone == SessionRatingTone.primary
        ? TurnaTheme.brandTeal
        : TurnaTheme.brandSky;
    final showInterval =
        action.interval != null && action.interval!.isNotEmpty;

    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? action.onPressed : null,
        // styleFrom treats elevation as a base level (pressed: +6); pin flat.
        style: ElevatedButton.styleFrom(
          backgroundColor: tone == SessionRatingTone.primary
              ? color
              : Colors.transparent,
          foregroundColor: color,
          disabledBackgroundColor: tone == SessionRatingTone.primary
              ? color.withValues(alpha: 0.30)
              : Colors.transparent,
          disabledForegroundColor: color.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: tone == SessionRatingTone.outline
                ? BorderSide(color: color.withValues(alpha: 0.55), width: 1.5)
                : BorderSide.none,
          ),
        ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              action.label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.15,
              ),
            ),
            if (showInterval) ...[
              const SizedBox(height: 3),
              Text(
                action.interval!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.75),
                  height: 1.15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'Session shell · light', group: 'Wetland mist')
@Preview(
    name: 'Session shell · dark', group: 'Wetland mist', brightness: Brightness.dark)
Widget sessionShellPreview() {
  return const _SessionShellPreview();
}

class _SessionShellPreview extends StatelessWidget {
  const _SessionShellPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.lessonCanvasBg(context),
      appBar: const SessionProgressBand(
        currentIndex: 8,
        totalCount: 13,
        actions: [
          IconButton(
            tooltip: 'AI',
            icon: Icon(Icons.auto_awesome_rounded),
            onPressed: null,
          ),
        ],
      ),
      body: const Padding(
        padding: EdgeInsets.all(AppSpacing.pageMargin),
        child: SessionRecallCanvas(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('döner', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.md),
              Text('转 · 名词'),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SessionActionBand(
        child: SessionRatingBand(
          above: Text('答案 · 你好'),
          actions: [
            SessionRatingAction(
              label: '不记得',
              tone: SessionRatingTone.outline,
              interval: '4 天',
            ),
            SessionRatingAction(
              label: '记得',
              tone: SessionRatingTone.primary,
              interval: '9 天',
            ),
          ],
        ),
      ),
    );
  }
}
