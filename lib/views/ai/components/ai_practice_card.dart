// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';

/// One row in the AI practice library ("我的练习") —— 目录行，不是卡。
///
/// 五态（排队 / 生成中 / 待练习 / 失败 / 中断）全部行内表达：左侧状态符
/// （环 = 排队、spinner = 生成中、实心 = 待练习、error 轮廓 = 失败、pause =
/// 中断），状态词进副行文字；收藏与菜单动作收进行尾。共享于 AI Hub 预览与
/// 练习库全页，两处状态口径不会漂移。
class AiPracticeCard extends StatelessWidget {
  const AiPracticeCard({
    super.key,
    required this.item,
    this.selectionMode = false,
    this.selected = false,
    this.showDivider = true,
    this.onTap,
    this.onStart,
    this.onPin,
    this.onUnpin,
    this.onAdjust,
    this.onDetail,
    this.onDelete,
    this.onRetry,
    this.onCancel,
  });

  final AiCourse item;
  final bool selectionMode;
  final bool selected;
  final bool showDivider;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final VoidCallback? onAdjust;
  final VoidCallback? onDetail;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  bool get _playable => item.isPlayable;

  @override
  Widget build(BuildContext context) {
    final failed = item.status == AiPracticeStatus.failed ||
        item.status == AiPracticeStatus.interrupted;
    final row = InkWell(
      onTap: selectionMode
          ? onTap
          : (onTap ?? (_playable ? onStart : null)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 1),
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: onTap == null ? null : (_) => onTap!(),
                activeColor: TurnaTheme.brandTeal,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            _StatusGlyph(status: item.status),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xs - 2),
                  Text(
                    _statusLine(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.captionSm(context).copyWith(
                          fontSize: 12.5,
                          color: failed
                              ? TurnaTheme.error
                              : TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (item.status.isBusy)
              IconButton(
                tooltip: AppStrings.aiPracticeCancel,
                onPressed: onCancel,
                icon: Icon(
                  Icons.stop_circle_outlined,
                  size: 20,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              )
            else if (!selectionMode) ...[
              // One tap from "about to expire" to "permanent": the countdown is
              // useless if saving it hides in a menu.
              if (_playable)
                IconButton(
                  tooltip: item.pinned
                      ? AppStrings.aiPracticeUnfavorite
                      : AppStrings.aiPracticeFavorite,
                  onPressed: item.pinned ? onUnpin : onPin,
                  icon: Icon(
                    item.pinned
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: item.pinned
                        ? TurnaTheme.anatolianClay
                        : TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: AppStrings.commonMoreActions,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'start':
                      onStart?.call();
                      break;
                    case 'pin':
                      onPin?.call();
                      break;
                    case 'unpin':
                      onUnpin?.call();
                      break;
                    case 'adjust':
                      onAdjust?.call();
                      break;
                    case 'detail':
                      onDetail?.call();
                      break;
                    case 'retry':
                      onRetry?.call();
                      break;
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (_playable)
                    PopupMenuItem(
                      value: 'start',
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded,
                              size: 20, color: TurnaTheme.brandTeal),
                          const SizedBox(width: 10),
                          Text(AppStrings.aiPracticeStart),
                        ],
                      ),
                    ),
                  if (item.status == AiPracticeStatus.failed ||
                      item.status == AiPracticeStatus.interrupted)
                    PopupMenuItem(
                      value: 'retry',
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded,
                              size: 20, color: TurnaTheme.brandTeal),
                          const SizedBox(width: 10),
                          Text(AppStrings.aiPracticeRetry),
                        ],
                      ),
                    ),
                  if (item.versions.isNotEmpty)
                    PopupMenuItem(
                      value: 'detail',
                      child: Row(
                        children: [
                          const Icon(Icons.account_tree_outlined,
                              size: 20, color: TurnaTheme.brandSky),
                          const SizedBox(width: 10),
                          Text(AppStrings.aiPracticeDetailTitle),
                        ],
                      ),
                    ),
                  if (item.status == AiPracticeStatus.ready)
                    PopupMenuItem(
                      value: 'adjust',
                      child: Row(
                        children: [
                          const Icon(Icons.auto_fix_high_rounded,
                              size: 20, color: TurnaTheme.brandTeal),
                          const SizedBox(width: 10),
                          Text(AppStrings.aiPracticeAdjust),
                        ],
                      ),
                    ),
                  if (item.status == AiPracticeStatus.ready)
                    PopupMenuItem(
                      value: item.pinned ? 'unpin' : 'pin',
                      child: Row(
                        children: [
                          Icon(
                            item.pinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin_rounded,
                            size: 20,
                            color: TurnaTheme.anatolianClay,
                          ),
                          const SizedBox(width: 10),
                          Text(item.pinned
                              ? AppStrings.aiPracticeUnpin
                              : AppStrings.aiPracticePin),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            size: 20, color: TurnaTheme.error),
                        const SizedBox(width: 10),
                        Text(AppStrings.aiPracticeDelete),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (!showDivider) return row;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
        ),
      ),
      child: row,
    );
  }

  /// 「来源 · 状态（· 过期）」一行：五态的文本表达。
  String _statusLine() {
    final status = switch (item.status) {
      AiPracticeStatus.queued => AppStrings.aiPracticeQueued,
      AiPracticeStatus.running => AppStrings.aiPracticeProgress(
          item.progressDone,
          item.progressTotal,
        ),
      AiPracticeStatus.ready => item.pinned
          ? '${AppStrings.aiPracticeReady} · ${AppStrings.aiPracticePermanentTag}'
          : AppStrings.aiPracticeReady,
      AiPracticeStatus.failed =>
        item.errorMessage ?? AppStrings.aiPracticeFailed,
      AiPracticeStatus.interrupted =>
        item.errorMessage ?? AppStrings.aiPracticeInterrupted,
    };
    final expiry = _expiryLabel();
    final source = switch (item.source) {
      AiPracticeSource.mistakes => AppStrings.aiPracticeSourceMistakes,
      AiPracticeSource.weakWords => AppStrings.aiPracticeSourceWeakWords,
      AiPracticeSource.difficult => AppStrings.aiPracticeSourceDifficult,
      AiPracticeSource.custom => AppStrings.aiPracticeSourceCustom,
    };
    return expiry == null
        ? '$source · $status'
        : '$source · $status · $expiry';
  }

  /// "还剩 3 天" / "今天过期" for plain drafts; null for favourites (permanent)
  /// and for jobs that never became playable.
  String? _expiryLabel() {
    if (item.pinned || !item.isPlayable) return null;
    final days = item.daysLeft(DateTime.now());
    if (days == null) return null;
    return days <= 0
        ? AppStrings.aiPracticeExpiringToday
        : AppStrings.aiPracticeExpiresInDays(days);
  }
}

/// 行首状态符：形状表达状态，不靠色相。
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status});

  final AiPracticeStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      // 排队：空心环（未达）。
      AiPracticeStatus.queued => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: TurnaTheme.dividerBg(context), width: 2),
          ),
        ),
      // 生成中：小 spinner。
      AiPracticeStatus.running => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: TurnaTheme.brandTeal,
          ),
        ),
      // 待练习：实心 teal（可开始）。
      AiPracticeStatus.ready => Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: TurnaTheme.brandTeal,
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            size: 12,
            color: TurnaTheme.textOnPrimary,
          ),
        ),
      AiPracticeStatus.failed => const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: TurnaTheme.error,
        ),
      AiPracticeStatus.interrupted => Icon(
          Icons.pause_circle_outline_rounded,
          size: 18,
          color: TurnaTheme.warning,
        ),
    };
  }
}
