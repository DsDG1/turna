// Dart imports:
import 'dart:async';
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/enums.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/theme.dart';

/// Course management page — opened from the course switcher in the Learn
/// tab. Lists the built-in course plus every Anki course (one entry per
/// source), lets the user switch the active course (tap), reorder courses
/// (drag), delete imported courses with an exact-source confirmation (the
/// built-in course can never be deleted), and reach the add-course entry
/// points.
///
/// [highlightWire] briefly highlights one catalog entry (v1 scope wire key)
/// — used by the import wizard's "view decks" action (plan 34 R1-4).
@RoutePage()
class CourseManagementPage extends StatelessWidget {
  const CourseManagementPage({super.key, this.highlightWire});

  final String? highlightWire;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
        title: Text(
          AppStrings.courseManagementTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('course-open-repair-center'),
            tooltip: AppStrings.ankiRepairCenterTitle,
            icon: const Icon(Icons.healing_outlined),
            onPressed: () =>
                context.router.push(OfficialAnkiRepairCenterRoute()),
          ),
        ],
      ),
      body: _CourseManagementBody(highlightWire: highlightWire),
    );
  }
}

class _CourseManagementBody extends StatefulWidget {
  const _CourseManagementBody({this.highlightWire});

  final String? highlightWire;

  @override
  State<_CourseManagementBody> createState() => _CourseManagementBodyState();
}

class _CourseManagementBodyState extends State<_CourseManagementBody> {
  String? _highlightWire;

  @override
  void initState() {
    super.initState();
    _highlightWire = widget.highlightWire;
    if (_highlightWire != null) {
      // The highlight is a brief affordance, not a permanent state.
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightWire = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();
    final entries = courseProvider.catalogEntries;
    final activeScope = courseProvider.courseScope;
    // The read-aloud per-course entry is opt-in: it only appears once the
    // master switch in Settings > Learning is on.
    final ttsFeatureEnabled = context.select<SettingsProvider, bool>(
      (p) => p.ttsFeatureEnabled,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppStrings.courseManagementMyCourses,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) =>
                _onReorder(context, entries, oldIndex, newIndex),
            children: [
              for (var i = 0; i < entries.length; i++)
                _CourseCard(
                  key: ValueKey(entries[i].wireKey),
                  entry: entries[i],
                  index: i,
                  isActive: entries[i].wireKey == activeScope,
                  isHighlighted: entries[i].wireKey == _highlightWire,
                  ttsFeatureEnabled: ttsFeatureEnabled,
                  onTap: () => _selectCourse(context, entries[i]),
                  onSettings: () => _showTtsSettings(
                    context,
                    entries[i].wireKey,
                    entries[i].isBuiltin
                        ? TargetLanguage.turkish.displayName
                        : entries[i].displayName,
                  ),
                  onDelete: entries[i].isBuiltin
                      ? null
                      : () => _confirmDelete(context, entries[i]),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 底部「添加课程」区:内层 Column 必须用 MainAxisSize.min,
        // 否则它会吃掉外层 Column 的全部剩余高度,把 Expanded(ReorderableListView)
        // 挤成 0 高度,渲染出大面积红色溢出条。SingleChildScrollView 兜底,
        // 小屏 / 大字体下也能滚出来。
        SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.courseManagementAddTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OfficialPendingImportBanner(
                    onChanged: () => setState(() {}),
                  ),
                  _AddCourseCard(
                    onTap: () => context.router.push(const AnkiImportRoute()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    List<CourseCatalogEntry> entries,
    int oldIndex,
    int newIndex,
  ) async {
    final wires = [for (final e in entries) e.wireKey];
    final wire = wires.removeAt(oldIndex);
    wires.insert(newIndex, wire);
    await context.read<CourseProvider>().persistCourseOrder(wires);
  }

  /// Tap a course = make it the active course, then return to the Learn tab.
  Future<void> _selectCourse(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    final courseProvider = context.read<CourseProvider>();
    if (entry.isBuiltin) {
      final languageProvider = context.read<LanguageProvider>();
      languageProvider.setLanguage(TargetLanguage.turkish);
      unawaited(languageProvider.cacheLanguage());
    }
    await courseProvider.setScope(entry.scope);
    if (context.mounted) {
      await context.router.maybePop();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    // Exact-source confirmation (plan 34 R1-7): display name, short source
    // id and card count, so deleting one source can never be confused with
    // a sibling sharing the `src-` prefix.
    final idDetail = entry.shortId.isEmpty
        ? ''
        : '\n${entry.shortId} · ${entry.cardCount} cards';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.ankiUninstallConfirmTitle),
        content: Text(
          '${entry.displayName}$idDetail\n\n${AppStrings.ankiUninstallConfirmBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.ankiUninstallDeck),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Uninstall with the COMPLETE source identity — never a truncated id.
    final deletionId = entry.officialSourceId ?? entry.legacyImportId!;
    var uninstallCompleted = false;
    var uninstallFailed = false;
    try {
      uninstallCompleted = await getIt<AnkiDeckManager>().uninstall(deletionId);
    } catch (e) {
      uninstallFailed = true;
      debugPrint('[CourseManagement] uninstall failed for $deletionId: $e');
    }
    if (!context.mounted) return;
    final courseProvider = context.read<CourseProvider>();
    if (courseProvider.scope == entry.scope) {
      // The active scope pointed at the removed course — fall back to the
      // built-in course (setScope reloads the tree itself).
      await courseProvider.setScope(const BuiltinCourseScope('turkish'));
    } else {
      await courseProvider.reloadCourse();
    }
    // Drop the removed course from the persisted order.
    await courseProvider.persistCourseOrder(
      [for (final e in courseProvider.catalogEntries) e.wireKey],
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          uninstallFailed
              ? AppStrings.ankiDeckRemovalFailed
              : uninstallCompleted
                  ? AppStrings.ankiDeckRemoved
                  : AppStrings.ankiDeckRemovalPending,
        ),
      ),
    );
  }

  /// Per-course TTS settings (auto-read toggle + translation/native language).
  void _showTtsSettings(BuildContext context, String scope, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusLarge),
        ),
      ),
      builder: (_) => _CourseTtsSettingsSheet(
        scope: scope,
        name: name,
        settings: context.read<SettingsProvider>(),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseCatalogEntry entry;
  final int index;
  final bool isActive;
  final bool isHighlighted;
  final bool ttsFeatureEnabled;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  final VoidCallback? onDelete;

  const _CourseCard({
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    this.isHighlighted = false,
    required this.ttsFeatureEnabled,
    required this.onTap,
    required this.onSettings,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isActive
        ? TurnaTheme.brandTeal
        : TurnaTheme.textSecondaryColor(context);
    final hasMenuActions = ttsFeatureEnabled || onDelete != null;
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TurnaTheme.cardBg(context),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [TurnaTheme.brandTeal, TurnaTheme.brandSky],
                          )
                        : null,
                    color: isActive
                        ? null
                        : accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    entry.isBuiltin
                        ? Icons.language_rounded
                        : Icons.style_rounded,
                    color: isActive ? Colors.white : accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.isBuiltin
                                  ? TargetLanguage.turkish.displayName
                                  : entry.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: AppStrings.courseManagementCurrentBadge,
                              color: TurnaTheme.brandTeal,
                            ),
                          ],
                          if (entry.isBuiltin) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: AppStrings.courseManagementDefaultBadge,
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.isBuiltin
                            ? AppStrings.courseManagementBuiltinSubtitle
                            : AppStrings.courseManagementCardCount(
                                entry.cardCount,
                              ),
                        style: TextStyle(
                          fontSize: 13,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
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
                  PopupMenuButton<String>(
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
class _AddCourseCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCourseCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.45),
            radius: TurnaTheme.radiusLarge,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 28,
                  color: TurnaTheme.brandTeal,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.courseManagementImportTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.brandTeal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.homeFromAnkiSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
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

/// Bottom sheet for a single course's smart-TTS settings: the auto-read
/// toggle and the translation/native language used as the Latin-text fallback.
class _CourseTtsSettingsSheet extends StatefulWidget {
  final String scope;
  final String name;
  final SettingsProvider settings;

  const _CourseTtsSettingsSheet({
    required this.scope,
    required this.name,
    required this.settings,
  });

  @override
  State<_CourseTtsSettingsSheet> createState() =>
      _CourseTtsSettingsSheetState();
}

class _CourseTtsSettingsSheetState extends State<_CourseTtsSettingsSheet> {
  static const _nativeLangOptions = <({String code, String label})>[
    (code: 'en', label: '英语'),
    (code: 'zh', label: '中文'),
    (code: 'tr', label: '土耳其语'),
    (code: 'ru', label: '俄语'),
    (code: 'ar', label: '阿拉伯语'),
    (code: 'es', label: '西班牙语'),
    (code: 'fr', label: '法语'),
    (code: 'de', label: '德语'),
    (code: 'ja', label: '日语'),
    (code: 'ko', label: '韩语'),
    (code: 'pt', label: '葡萄牙语'),
    (code: 'it', label: '意大利语'),
    (code: 'vi', label: '越南语'),
    (code: 'id', label: '印尼语'),
  ];

  late bool _autoRead;
  late String _nativeLang;

  @override
  void initState() {
    super.initState();
    _autoRead = widget.settings.autoReadOnTapFor(widget.scope);
    _nativeLang = widget.settings.nativeLanguageCodeFor(widget.scope);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.courseTtsSettingsTitle} · ${widget.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.courseTtsAutoReadTitle),
              subtitle: Text(
                AppStrings.courseTtsAutoReadSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
              value: _autoRead,
              onChanged: (value) async {
                setState(() => _autoRead = value);
                await widget.settings.setAutoReadOnTapFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.courseTtsNativeLangTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              AppStrings.courseTtsNativeLangSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _nativeLang,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final opt in _nativeLangOptions)
                  DropdownMenuItem(
                    value: opt.code,
                    child: Text(opt.label),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _nativeLang = value);
                await widget.settings
                    .setNativeLanguageCodeFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.dialogClose),
            ),
          ],
        ),
      ),
    );
  }
}
