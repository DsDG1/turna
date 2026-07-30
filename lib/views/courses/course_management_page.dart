// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_deck_manager.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

/// Course management page — opened from the globe icon in the Learn tab.
/// Lists the built-in course plus every imported Anki deck, lets the user
/// switch the active course (tap), reorder courses (drag), delete imported
/// decks (the built-in course can never be deleted), and reach the
/// add-course entry points (Anki import / sample deck / new course).
@RoutePage()
class CourseManagementPage extends StatelessWidget {
  const CourseManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: VarnamalaTheme.surfaceColor(context),
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
            color: VarnamalaTheme.textPrimaryColor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: const _CourseManagementBody(),
    );
  }
}

class _CourseManagementBody extends StatelessWidget {
  const _CourseManagementBody();

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();
    final entries = courseProvider.courseEntries;
    final activeScope = courseProvider.courseScope;

    return Column(
      children: [
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.all(20),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) =>
                _onReorder(context, entries, oldIndex, newIndex),
            children: [
              for (var i = 0; i < entries.length; i++)
                _CourseCard(
                  key: ValueKey(entries[i].scope),
                  entry: entries[i],
                  index: i,
                  isActive: entries[i].scope == activeScope,
                  onTap: () => _selectCourse(context, entries[i]),
                  onDelete: entries[i].isBuiltin
                      ? null
                      : () => _confirmDelete(context, entries[i]),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.courseManagementAddTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                _AddCourseTile(
                  icon: Icons.upload_file_rounded,
                  title: AppStrings.homeFromAnki,
                  subtitle: AppStrings.homeFromAnkiSubtitle,
                  onTap: () => context.router
                      .push(AnkiImportRoute(startWithSample: false)),
                ),
                _AddCourseTile(
                  icon: Icons.auto_awesome_rounded,
                  title: AppStrings.homeSampleAnki,
                  subtitle: AppStrings.homeSampleAnkiSubtitle,
                  onTap: () => context.router
                      .push(AnkiImportRoute(startWithSample: true)),
                ),
                _AddCourseTile(
                  icon: Icons.add_circle_outline_rounded,
                  title: AppStrings.homeNewCourse,
                  subtitle: AppStrings.homeNewCourseComingSoon,
                  onTap: () => _showNewCourseDialog(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    List<({String scope, String name, bool isBuiltin})> entries,
    int oldIndex,
    int newIndex,
  ) async {
    final scopes = [for (final e in entries) e.scope];
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final scope = scopes.removeAt(oldIndex);
    scopes.insert(target, scope);
    await context.read<CourseProvider>().persistCourseOrder(scopes);
  }

  /// Tap a course = make it the active course, then return to the Learn tab.
  Future<void> _selectCourse(
    BuildContext context,
    ({String scope, String name, bool isBuiltin}) entry,
  ) async {
    final courseProvider = context.read<CourseProvider>();
    if (entry.isBuiltin) {
      final languageProvider = context.read<LanguageProvider>();
      languageProvider.setLanguage(TargetLanguage.turkish);
      unawaited(languageProvider.cacheLanguage());
    }
    await courseProvider.setCourseScope(entry.scope);
    if (context.mounted) {
      await context.router.maybePop();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ({String scope, String name, bool isBuiltin}) entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.ankiUninstallConfirmTitle),
        content: Text('${entry.name}\n\n${AppStrings.ankiUninstallConfirmBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VarnamalaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.ankiUninstallDeck),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final importId = entry.scope.substring('anki:'.length);
    await getIt<AnkiDeckManager>().uninstallDeck(importId);
    if (!context.mounted) return;
    final courseProvider = context.read<CourseProvider>();
    if (courseProvider.courseScope == entry.scope) {
      // The active scope pointed at the removed deck — fall back to the
      // built-in course (setCourseScope reloads the tree itself).
      await courseProvider.setCourseScope('');
    } else {
      await courseProvider.reloadCourse();
    }
    // Drop the removed deck from the persisted course order.
    await courseProvider.persistCourseOrder(
      [for (final e in courseProvider.courseEntries) e.scope],
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.ankiDeckRemoved)),
    );
  }

  void _showNewCourseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.homeNewCourse),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.homeNewCourseComingSoon),
            const SizedBox(height: 12),
            Text(
              AppStrings.homeNewCourseUseAi,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.dialogClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.router.push(const AiWishChatRoute());
            },
            child: Text(AppStrings.homeDesignWithAi),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final ({String scope, String name, bool isBuiltin}) entry;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _CourseCard({
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isActive
        ? VarnamalaTheme.peacockTeal
        : VarnamalaTheme.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
              border: Border.all(
                color: isActive
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    entry.isBuiltin
                        ? Icons.language_rounded
                        : Icons.style_rounded,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
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
                                  : entry.name,
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
                              color: VarnamalaTheme.peacockTeal,
                            ),
                          ],
                          if (entry.isBuiltin) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: AppStrings.courseManagementDefaultBadge,
                              color:
                                  VarnamalaTheme.textSecondaryColor(context),
                            ),
                          ],
                        ],
                      ),
                      if (entry.isBuiltin) ...[
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.courseManagementBuiltinSubtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: VarnamalaTheme.error,
                    ),
                    tooltip: AppStrings.ankiUninstallDeck,
                    onPressed: onDelete,
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

class _AddCourseTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddCourseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: VarnamalaTheme.peacockTeal),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: VarnamalaTheme.textSecondaryColor(context),
        ),
      ),
      onTap: onTap,
    );
  }
}
