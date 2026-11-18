// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';

class CourseManagementCard extends StatelessWidget {
  final CourseCatalogEntry entry;
  final int index;
  final bool isActive;
  final bool isHighlighted;
  final bool ttsFeatureEnabled;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  final VoidCallback? onDelete;
  final VoidCallback? onAdaptation;

  const CourseManagementCard({
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    this.isHighlighted = false,
    required this.ttsFeatureEnabled,
    required this.onTap,
    required this.onSettings,
    required this.onDelete,
    this.onAdaptation,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isActive
        ? TurnaTheme.brandTeal
        : TurnaTheme.textSecondaryColor(context);
    final hasMenuActions =
        ttsFeatureEnabled || onDelete != null || onAdaptation != null;
    final radius = BorderRadius.circular(TurnaTheme.cardRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        // ADR 0062：课程卡是容器 → 中性淡彩实面。Material 只吃单色，
        // 所以用 glassSolid 接住 glassFill 渐变的最低点，与其它卡的
        // 观感一致又不会在 InkWell 下露出两段色差。
        color: TurnaTheme.glassSolid(
          context,
          TurnaTheme.glassNeutral,
          level: GlassLevel.l1Subtle,
        ),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: isActive || isHighlighted
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.brandTeal.withValues(alpha: 0.12),
                width: isActive || isHighlighted ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                _CourseCardIcon(
                  entry: entry,
                  isActive: isActive,
                  accent: accent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _CourseCardInfo(entry: entry, isActive: isActive),
                ),
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: TurnaTheme.brandTeal,
                      size: 22,
                    ),
                  ),
                // Card actions collapse into one overflow menu: TTS settings
                // (gated by the opt-in master switch) + remove. The built-in
                // course with read-aloud off renders no menu at all.
                if (hasMenuActions)
                  _CourseCardMenu(
                    ttsFeatureEnabled: ttsFeatureEnabled,
                    onSettings: onSettings,
                    onDelete: onDelete,
                    onAdaptation: onAdaptation,
                  ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 10,
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Leading course icon: teal gradient when active, muted tint otherwise.
class _CourseCardIcon extends StatelessWidget {
  final CourseCatalogEntry entry;
  final bool isActive;
  final Color accent;

  const _CourseCardIcon({
    required this.entry,
    required this.isActive,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: isActive ? TurnaTheme.brandHeroGradient : null,
        color: isActive ? null : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
      ),
      child: Icon(
        entry.isBuiltin ? Icons.language_rounded : Icons.style_rounded,
        color: isActive ? Colors.white : accent,
        size: 24,
      ),
    );
  }
}

/// Course name + badges + subtitle + optional license attribution.
class _CourseCardInfo extends StatelessWidget {
  final CourseCatalogEntry entry;
  final bool isActive;

  const _CourseCardInfo({required this.entry, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap 而非 Row：200% 字号下「名称 + 当前 + 默认」两枚徽章会溢出
        // 右缘（两门内置语言时每张卡都可能带徽章）；Wrap 让长名换行、
        // 徽章流到下一行，不再报 RenderFlex overflow。
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              entry.displayName,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (isActive)
              _Badge(
                label: AppStrings.courseManagementCurrentBadge,
                color: TurnaTheme.brandTeal,
              ),
            if (entry.isBuiltin)
              _Badge(
                label: AppStrings.courseManagementDefaultBadge,
                color: TurnaTheme.textSecondaryColor(context),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          entry.isBuiltin
              ? AppStrings.courseManagementBuiltinSubtitle
              : AppStrings.courseManagementCardCount(entry.cardCount),
          style: TextStyle(
            fontSize: 13,
            color: TurnaTheme.textSecondaryColor(context),
          ),
        ),
        if (entry.scope is BuiltinCourseScope) ...[
          Builder(
            builder: (context) {
              final code = (entry.scope as BuiltinCourseScope).languageCode;
              final attribution = ImportedLanguageRegistry.instance
                  .licenseAttributionOrNull(code);
              if (attribution == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  attribution,
                  style: TextStyle(
                    fontSize: 12,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Overflow menu: TTS settings (opt-in) + display mode + remove.
class _CourseCardMenu extends StatelessWidget {
  final bool ttsFeatureEnabled;
  final VoidCallback onSettings;
  final VoidCallback? onDelete;
  final VoidCallback? onAdaptation;

  const _CourseCardMenu({
    required this.ttsFeatureEnabled,
    required this.onSettings,
    required this.onDelete,
    this.onAdaptation,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: AppStrings.commonMoreActions,
      icon: Icon(
        Icons.more_vert_rounded,
        color: TurnaTheme.textSecondaryColor(context),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onSelected: (value) {
        if (value == 'tts') {
          onSettings();
        } else if (value == 'adaptation') {
          onAdaptation?.call();
        } else if (value == 'delete') {
          onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (ttsFeatureEnabled)
          PopupMenuItem(
            value: 'tts',
            child: Row(
              children: [
                const Icon(
                  Icons.record_voice_over_rounded,
                  size: 20,
                  color: TurnaTheme.brandTeal,
                ),
                const SizedBox(width: 10),
                Text(AppStrings.courseTtsSettingsTitle),
              ],
            ),
          ),
        if (onAdaptation != null)
          PopupMenuItem(
            value: 'adaptation',
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                const SizedBox(width: 10),
                Text(AppStrings.ankiAdaptationRestoreTitle),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: TurnaTheme.error,
                ),
                const SizedBox(width: 10),
                Text(AppStrings.courseManagementRemoveCourse),
              ],
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Hero entry card for adding a course — dashed teal outline so it reads as
/// "create/import here" instead of another course in the list.
class AddCourseCard extends StatelessWidget {
  final VoidCallback onTap;
  final String? title;
  final String? subtitle;

  const AddCourseCard({
    super.key,
    required this.onTap,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.cardRadius);
    const accent = TurnaTheme.brandTeal;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.45),
            radius: TurnaTheme.cardRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 28,
                  color: accent,
                ),
                const SizedBox(width: 10),
                // Flexible 而非裸 Column：字体放大后标题/副标题会超出卡片
                // 宽度（真机收据 `RIGHT OVERFLOWED BY 3 PIXELS`）。Flexible
                // 在宽度够时仍 shrink-wrap 保持整块居中，不够时文本换行。
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? AppStrings.courseManagementImportTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ?? AppStrings.homeFromAnkiSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row per uninstalled builtin language in the restore list.
class RestoreLanguageCard extends StatelessWidget {
  final String displayName;
  final VoidCallback onRestore;

  const RestoreLanguageCard({
    super.key,
    required this.displayName,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.cardRadius);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TurnaTheme.glassSolid(
          context,
          TurnaTheme.glassNeutral,
          level: GlassLevel.l1Subtle,
        ),
        borderRadius: radius,
        child: InkWell(
          onTap: onRestore,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    size: 20,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(
                    Icons.restore_rounded,
                    size: 18,
                    color: TurnaTheme.brandTeal,
                  ),
                  label: Text(AppStrings.courseManagementRestore(displayName)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rect border, drawn once per paint pass — no packages.
class _DashedBorderPainter extends CustomPainter {
  static const double _dashWidth = 6;
  static const double _dashGap = 5;
  static const double _strokeWidth = 1.6;

  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final metric = path.computeMetrics().first;
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + _dashWidth, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + _dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
