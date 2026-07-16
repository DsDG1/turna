// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/export_service.dart';
import 'package:varnamala/views/settings/widgets/settings_about_section.dart';
import 'package:varnamala/views/settings/widgets/settings_account_section.dart';
import 'package:varnamala/views/settings/widgets/settings_appearance_section.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/settings/widgets/settings_learning_section.dart';
import 'package:varnamala/views/settings/widgets/settings_reminder_section.dart';
import 'package:varnamala/views/settings/widgets/settings_sound_section.dart';
import 'package:varnamala/views/theme.dart';

/// Settings is organized as a category list that pushes a sub-page per
/// category (iOS Settings style). Because [SettingsPage] lives inside the
/// Home `IndexedStack` (not a routed page) and is switched to via `TabRouter`,
/// navigation is kept in-page with [_category] state rather than AutoRoute —
/// this preserves the "Go to settings" tab-switch and avoids touching routing.
class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// null = landing category list; 0..4 = the selected category sub-page.
  int? _category;

  static const _categories = <_SettingsCategory>[
    _SettingsCategory(
      index: 0,
      title: 'Account',
      icon: Icons.person_rounded,
    ),
    _SettingsCategory(
      index: 1,
      title: 'Learning',
      icon: Icons.menu_book_rounded,
    ),
    _SettingsCategory(
      index: 2,
      title: 'Audio & Display',
      icon: Icons.tune_rounded,
    ),
    _SettingsCategory(
      index: 3,
      title: 'Data',
      icon: Icons.storage_rounded,
    ),
    _SettingsCategory(
      index: 4,
      title: 'About',
      icon: Icons.info_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isList = _category == null;
    return PopScope(
      // When a sub-page is open, the system back button returns to the
      // category list instead of leaving the Settings tab.
      canPop: isList,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _category != null) {
          setState(() => _category = null);
        }
      },
      child: Scaffold(
        backgroundColor: VarnamalaTheme.surfaceColor(context),
        appBar: AppBar(
          backgroundColor: VarnamalaTheme.surfaceColor(context),
          elevation: 0,
          centerTitle: true,
          leading: isList
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  onPressed: () => setState(() => _category = null),
                ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.settings_rounded,
                color: VarnamalaTheme.peacockTeal,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isList ? 'Settings' : _categoryName(_category!),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isList ? _buildCategoryList() : _buildSubPage(_category!),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SingleChildScrollView(
      key: const ValueKey('settings-list'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsCard(
            children: [
              for (int i = 0; i < _categories.length; i++) ...[
                if (i > 0) settingsTileDivider(context),
                SettingsNavigationTile(
                  key: ValueKey(_categories[i].title),
                  icon: _categories[i].icon,
                  title: _categories[i].title,
                  onTap: (_) => setState(() => _category = _categories[i].index),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSubPage(int category) {
    return SingleChildScrollView(
      key: ValueKey('settings-$category'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _sectionChildren(category),
      ),
    );
  }

  List<Widget> _sectionChildren(int category) {
    switch (category) {
      case 0:
        return const [SettingsAccountTile(), SizedBox(height: 24)];
      case 1:
        return [
          SettingsCard(
            children: [
              const SettingsLanguageSelectorTile(),
              settingsTileDivider(context),
              const SettingsTtsSpeedTile(),
              settingsTileDivider(context),
              const SettingsDailyReminderTile(),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.vpn_key,
                title: 'AI API Configuration',
                subtitle: 'Base URL, API key & model (not saved on exit)',
                onTap: (context) => _openAiApiConfigSheet(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.auto_awesome,
                title: 'Design a course with AI',
                subtitle: 'Open the AI design chat',
                onTap: (context) =>
                    context.router.push(const AiWishChatRoute()),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 2:
        return [
          SettingsCard(
            children: [
              SettingsToggleTile(
                icon: Icons.music_note_rounded,
                title: 'Sound effects',
                subtitle: 'Play sounds for errors and level-ups',
                valueSelector: (p) => p.soundEffectsEnabled,
                onChanged: (p, value) => p.setSoundEffects(value),
              ),
              settingsTileDivider(context),
              SettingsToggleTile(
                icon: Icons.vibration_rounded,
                title: 'Haptic feedback',
                subtitle: 'Vibrate on key interactions',
                valueSelector: (p) => p.hapticFeedbackEnabled,
                onChanged: (p, value) => p.setHapticFeedback(value),
              ),
              settingsTileDivider(context),
              const SettingsTtsEngineTile(),
            ],
          ),
          const SizedBox(height: 8),
          const SettingsThemeSelector(),
          const SizedBox(height: 24),
        ];
      case 3:
        return [
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.ios_share_rounded,
                title: 'Export data',
                subtitle: 'Save progress and/or course content to a file',
                onTap: (context) => _openExportSheet(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.file_upload_outlined,
                title: 'Import data',
                subtitle: 'Restore progress from an exported file',
                onTap: (context) => _importData(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.delete_sweep_rounded,
                title: 'Clear mistake log',
                subtitle: 'Remove all saved mistakes',
                onTap: (context) => _confirmClearMistakes(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.restart_alt_rounded,
                title: 'Reset lesson progress',
                subtitle: 'Mark all lessons as not completed',
                onTap: (context) => _confirmResetProgress(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 4:
        return const [SettingsAboutSection(), SizedBox(height: 24)];
      default:
        return const [];
    }
  }

  String _categoryName(int category) =>
      _categories.firstWhere((c) => c.index == category).title;

  Future<void> _confirmClearMistakes(BuildContext context) async {
    final mistakeProvider = context.read<MistakeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const SettingsConfirmDialog(
        title: 'Clear mistake log?',
        message: 'This will permanently delete all saved mistakes.',
        confirmText: 'Clear',
      ),
    );
    if (confirmed == true) {
      await mistakeProvider.clear();
      if (context.mounted) {
        _showSnack(context, 'Mistake log cleared');
      }
    }
  }

  Future<void> _confirmResetProgress(BuildContext context) async {
    final gameProvider = context.read<GameProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const SettingsConfirmDialog(
        title: 'Reset lesson progress?',
        message: 'All lesson completion and perfect-lesson records will be '
            'cleared. This cannot be undone.',
        confirmText: 'Reset',
      ),
    );
    if (confirmed == true) {
      await gameProvider.resetLessonProgress();
      if (context.mounted) {
        _showSnack(context, 'Lesson progress reset');
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openAiApiConfigSheet(BuildContext context) async {
    final provider = context.read<AiCourseProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _AiApiConfigSheet(provider: provider),
    );
  }

  Future<void> _openExportSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ExportSheet(),
    );
  }

  Future<void> _importData(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return; // user cancelled
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const SettingsConfirmDialog(
        title: 'Import data?',
        message: 'This will overwrite your current progress with the file\'s '
            'contents. This cannot be undone. Consider exporting first.',
        confirmText: 'Import',
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final import = await getIt<ExportService>().importFromFile(pickedPath);
      if (!context.mounted) return;
      if (import.hasCoursePayload && !import.progressRestored) {
        _showSnack(context, 'Course content saved; restart to apply');
      } else if (import.progressRestored) {
        _showSnack(context, 'Progress restored — restart the app to apply');
      } else {
        _showSnack(context, 'Nothing to import');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Import failed: $e');
      }
    }
  }
}

class _SettingsCategory {
  const _SettingsCategory({
    required this.index,
    required this.title,
    required this.icon,
  });

  final int index;
  final String title;
  final IconData icon;
}

class _AiApiConfigSheet extends StatefulWidget {
  final AiCourseProvider provider;

  const _AiApiConfigSheet({required this.provider});

  @override
  State<_AiApiConfigSheet> createState() => _AiApiConfigSheetState();
}

class _AiApiConfigSheetState extends State<_AiApiConfigSheet> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: widget.provider.config.baseUrl);
    _apiKeyCtrl = TextEditingController(text: widget.provider.config.apiKey);
    _modelCtrl = TextEditingController(text: widget.provider.config.model);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'AI API Configuration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Not saved on exit — kept in memory only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textHintColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.deepseek.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'deepseek-v4-pro',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  widget.provider.updateConfig(
                    baseUrl: _baseUrlCtrl.text.trim(),
                    apiKey: _apiKeyCtrl.text.trim(),
                    model: _modelCtrl.text.trim(),
                  );
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.check),
                label: const Text('Save configuration'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _includeProgress = true;
  bool _includeCourse = false;
  bool _exporting = false;

  bool get _canExport => _includeProgress || _includeCourse;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final service = getIt<ExportService>();
      final file = await service.export(
        includeProgress: _includeProgress,
        includeCourse: _includeCourse,
      );
      await service.share(file);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Export data',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose what to include in the export file.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VarnamalaTheme.textHintColor(context),
                ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _includeProgress,
            onChanged: _exporting
                ? null
                : (v) => setState(() => _includeProgress = v ?? false),
            title: const Text('Progress data'),
            subtitle: const Text('SRS, score, streak, mistakes, achievements'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _includeCourse,
            onChanged: _exporting
                ? null
                : (v) => setState(() => _includeCourse = v ?? false),
            title: const Text('Course content'),
            subtitle: const Text('The bundled Turkish course JSON files'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_canExport && !_exporting) ? _export : null,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VarnamalaTheme.textOnPrimary,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(_exporting ? 'Exporting...' : 'Export'),
            ),
          ),
        ],
      ),
    );
  }
}