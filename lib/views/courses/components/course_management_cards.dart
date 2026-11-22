// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_cards.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// Top frosted-glass summary card for the currently active course (R03).
class ActiveCourseSummaryCard extends StatelessWidget {
  const ActiveCourseSummaryCard({super.key, required this.entry});

  final CourseCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final attribution = _licenseAttributionFor(entry);
    final subtitle = entry.isBuiltin
        ? AppStrings.courseManagementBuiltinSubtitle
        : AppStrings.courseManagementCardCount(entry.cardCount);

    return SoftCard(
      accentColor: TurnaTheme.brandTeal,
      frost: true,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: TurnaTheme.primaryCtaDecoration(
                borderRadius: TurnaTheme.borderRadius,
                elevated: false,
              ),
              child: TurnaIcon(
                entry.isBuiltin ? TurnaIconId.translate : TurnaIconId.cards,
                color: TurnaTheme.textOnPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: TurnaTheme.brandReed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text(
                            AppStrings.courseManagementCurrentBadge,
                            style: AppTextStyles.caption(context)
                                .copyWith(color: TurnaTheme.brandTeal),
                          ),
                        ],
                      ),
                      if (entry.isBuiltin)
                        _Badge(
                          label: AppStrings.courseManagementDefaultBadge,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    entry.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sectionTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: AppTextStyles.captionSm(context)),
                  if (attribution != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      attribution,
                      style: AppTextStyles.caption(context)
                          .copyWith(letterSpacing: 0),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: TurnaIcon(
                TurnaIconId.checkCircle,
                color: TurnaTheme.brandTeal,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bookshelf-style directory index row for one course or memory-card deck.
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
    final spineColor = isActive
        ? TurnaTheme.brandTeal
        : entry.isBuiltin
        ? TurnaTheme.brandSky
        : TurnaTheme.achievementAmethyst;
    final accent = isActive
        ? TurnaTheme.brandTeal
        : TurnaTheme.textSecondaryColor(context);
    final hasMenuActions =
        ttsFeatureEnabled || onDelete != null || onAdaptation != null;
    final emphasized = isActive || isHighlighted;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Material(
        color: emphasized
            ? TurnaTheme.glassSolid(
                context,
                TurnaTheme.brandTeal,
                level: GlassLevel.l1Subtle,
              )
            : TurnaTheme.cardBg(context),
        borderRadius: TurnaTheme.borderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: TurnaTheme.borderRadius,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: TurnaTheme.borderRadius,
              border: Border.all(
                color: emphasized
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.dividerBg(context),
                width: emphasized ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Bookshelf left spine marker.
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: spineColor,
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _CourseCardIcon(
                  entry: entry,
                  isActive: isActive,
                  accent: accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _CourseCardInfo(entry: entry, isActive: isActive),
                ),
                if (isActive)
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.xs),
                    child: TurnaIcon(
                      TurnaIconId.checkCircle,
                      color: TurnaTheme.brandTeal,
                      size: 20,
                    ),
                  ),
                // Card actions collapse into one overflow menu: TTS settings
                // (gated by the opt-in master switch), adaptation restore, and
                // remove.
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
                      vertical: AppSpacing.md,
                      horizontal: AppSpacing.sm + 2,
                    ),
                    child: TurnaIcon(
                      TurnaIconId.dragHandle,
                      size: 18,
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

/// Leading course icon tile: teal gradient when active, muted tint otherwise.
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
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: isActive ? TurnaTheme.brandHeroGradient : null,
        color: isActive ? null : accent.withValues(alpha: 0.10),
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: TurnaIcon(
        entry.isBuiltin ? TurnaIconId.translate : TurnaIconId.cards,
        color: isActive ? TurnaTheme.textOnPrimary : accent,
        size: 18,
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
    final attribution = _licenseAttributionFor(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap 而非 Row：200% 字号下「名称 + 当前 + 默认」两枚徽章会溢出
        // 右缘（两门内置语言时每张卡都可能带徽章）；Wrap 让长名换行、
        // 徽章流到下一行，不再报 RenderFlex overflow。
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(entry.displayName, style: AppTextStyles.cardTitle(context)),
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          entry.isBuiltin
              ? AppStrings.courseManagementBuiltinSubtitle
              : AppStrings.courseManagementCardCount(entry.cardCount),
          style: AppTextStyles.captionSm(context),
        ),
        if (attribution != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              attribution,
              style: AppTextStyles.caption(context).copyWith(letterSpacing: 0),
            ),
          ),
      ],
    );
  }
}

String? _licenseAttributionFor(CourseCatalogEntry entry) {
  final scope = entry.scope;
  if (scope is! BuiltinCourseScope) return null;
  return ImportedLanguageRegistry.instance.licenseAttributionOrNull(
    scope.languageCode,
  );
}

/// Overflow menu: TTS settings (opt-in) + adaptation restore + remove.
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
      icon: TurnaIcon(
        TurnaIconId.moreVert,
        size: 20,
        color: TurnaTheme.textSecondaryColor(context),
      ),
      shape: TurnaTheme.shape,
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
                const TurnaIcon(
                  TurnaIconId.speakVoice,
                  size: 18,
                  color: TurnaTheme.brandTeal,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Text(
                  AppStrings.courseTtsSettingsTitle,
                  style: AppTextStyles.bodyText(context),
                ),
              ],
            ),
          ),
        if (onAdaptation != null)
          PopupMenuItem(
            value: 'adaptation',
            child: Row(
              children: [
                TurnaIcon(
                  TurnaIconId.wrench,
                  size: 18,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Text(
                  AppStrings.ankiAdaptationRestoreTitle,
                  style: AppTextStyles.bodyText(context),
                ),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const TurnaIcon(
                  TurnaIconId.delete,
                  size: 18,
                  color: TurnaTheme.error,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Text(
                  AppStrings.courseManagementRemoveCourse,
                  style: AppTextStyles.bodyText(context)
                      .copyWith(color: TurnaTheme.error),
                ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(
          context,
        ).copyWith(letterSpacing: 0, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Entry card for adding or importing a course — dashed 4px teal outline so
/// it reads as "import here" rather than an installed course on the shelf.
class AddCourseCard extends StatelessWidget {
  final VoidCallback onTap;
  final String? title;
  final String? subtitle;
  final TurnaIconId icon;

  const AddCourseCard({
    super.key,
    required this.onTap,
    this.title,
    this.subtitle,
    this.icon = TurnaIconId.add,
  });

  @override
  Widget build(BuildContext context) {
    const accent = TurnaTheme.brandTeal;
    return Material(
      color: Colors.transparent,
      borderRadius: TurnaTheme.borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: TurnaTheme.borderRadius,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.45),
            cornerRadius: TurnaTheme.borderRadius.topLeft,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TurnaTheme.tintSoft,
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: TurnaIcon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? AppStrings.courseManagementImportTitle,
                        style: AppTextStyles.cardTitle(context)
                            .copyWith(color: accent),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle ?? AppStrings.homeFromAnkiSubtitle,
                        style: AppTextStyles.captionSm(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TurnaIcon(
                  TurnaIconId.chevronRight,
                  size: 16,
                  color: TurnaTheme.textSecondaryColor(context),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Material(
        color: TurnaTheme.cardBg(context),
        borderRadius: TurnaTheme.borderRadius,
        child: InkWell(
          onTap: onRestore,
          borderRadius: TurnaTheme.borderRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: TurnaTheme.borderRadius,
              border: Border.all(color: TurnaTheme.dividerBg(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TurnaTheme.tintSoft,
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: const TurnaIcon(
                    TurnaIconId.translate,
                    size: 18,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const TurnaIcon(
                    TurnaIconId.restore,
                    size: 16,
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

/// Dashed 4px rounded-rect border, drawn once per paint pass — no packages.
class _DashedBorderPainter extends CustomPainter {
  static const double _dashWidth = 6;
  static const double _dashGap = 5;
  static const double _strokeWidth = 1.4;

  final Color color;
  final Radius cornerRadius;

  const _DashedBorderPainter({required this.color, required this.cornerRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, cornerRadius));
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
      color != oldDelegate.color || cornerRadius != oldDelegate.cornerRadius;
}
