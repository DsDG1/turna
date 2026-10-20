// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/play_tiles.dart';

/// One row in the AI practice library ("我的练习").
///
/// Shared by the AI Hub preview and the full library page so status wording,
/// colors, and menu actions cannot drift between the two surfaces.
class AiPracticeCard extends StatelessWidget {
  const AiPracticeCard({
    super.key,
    required this.item,
    this.selectionMode = false,
    this.selected = false,
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
    final accent = _accent(context);
    final subtitle = _subtitle(context);
    return SoftCard(
      accentColor: accent,
      onTap: selectionMode ? onTap : (onTap ?? (_playable ? onStart : null)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selectionMode) ...[
              Checkbox(
                value: selected,
                onChanged: onTap == null ? null : (_) => onTap!(),
                activeColor: TurnaTheme.brandTeal,
              ),
              const SizedBox(width: 2),
            ],
            AccentIconChip(
              icon: _icon,
              color: accent,
              size: 20,
              padding: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: TurnaTheme.textPrimaryColor(context),
                                  ),
                        ),
                      ),
                      if (item.pinned) ...[
                        const SizedBox(width: 6),
                        _Tag(
                            label: AppStrings.aiPracticePermanentTag,
                            color: accent),
                      ] else if (item.isPlayable &&
                          item.isExpiringSoon(DateTime.now())) ...[
                        const SizedBox(width: 6),
                        _Tag(
                          label: AppStrings.aiPracticeExpiringBadge,
                          color: TurnaTheme.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: item.status == AiPracticeStatus.failed ||
                                  item.status == AiPracticeStatus.interrupted
                              ? TurnaTheme.error
                              : TurnaTheme.textSecondaryColor(context),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
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
  }

  IconData get _icon => switch (item.status) {
        AiPracticeStatus.queued => Icons.schedule_rounded,
        AiPracticeStatus.running => Icons.auto_awesome_rounded,
        AiPracticeStatus.ready => Icons.play_circle_outline_rounded,
        AiPracticeStatus.failed => Icons.error_outline_rounded,
        AiPracticeStatus.interrupted => Icons.pause_circle_outline_rounded,
      };

  Color _accent(BuildContext context) {
    if (item.pinned) return TurnaTheme.anatolianClay;
    return switch (item.status) {
      AiPracticeStatus.queued => TurnaTheme.textSecondaryColor(context),
      AiPracticeStatus.running => TurnaTheme.brandTeal,
      AiPracticeStatus.ready => TurnaTheme.brandTeal,
      AiPracticeStatus.failed => TurnaTheme.error,
      AiPracticeStatus.interrupted => TurnaTheme.warning,
    };
  }

  String _subtitle(BuildContext context) {
    final source = _sourceLabel;
    final status = switch (item.status) {
      AiPracticeStatus.queued => AppStrings.aiPracticeQueued,
      AiPracticeStatus.running => AppStrings.aiPracticeProgress(
          item.progressDone,
          item.progressTotal,
        ),
      AiPracticeStatus.ready => AppStrings.aiPracticeReady,
      AiPracticeStatus.failed =>
        item.errorMessage ?? AppStrings.aiPracticeFailed,
      AiPracticeStatus.interrupted =>
        item.errorMessage ?? AppStrings.aiPracticeInterrupted,
    };
    final expiry = _expiryLabel();
    return expiry == null ? '$source · $status' : '$source · $status · $expiry';
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

  String get _sourceLabel => switch (item.source) {
        AiPracticeSource.mistakes => AppStrings.aiPracticeSourceMistakes,
        AiPracticeSource.weakWords => AppStrings.aiPracticeSourceWeakWords,
        AiPracticeSource.difficult => AppStrings.aiPracticeSourceDifficult,
        AiPracticeSource.custom => AppStrings.aiPracticeSourceCustom,
      };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
