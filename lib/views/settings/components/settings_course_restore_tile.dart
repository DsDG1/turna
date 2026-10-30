import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/content_ota/course_ota_service.dart';
import 'package:turna/views/settings/widgets/feedback/settings_feedback.dart';
import 'package:turna/views/settings/widgets/primitives/settings_section.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

typedef CourseContentClear = Future<bool> Function(String languageCode);
typedef CourseContentRefresh = Future<bool> Function(String languageCode);

/// Rolls a builtin language back to its bundled course content.
///
/// Clears `<documents>/content_updates/<language>/` and reseeds, so a bad or
/// unwanted download has a user-reachable exit without reinstalling the app.
/// The callbacks are test seams; production resolves the language and
/// [CourseProvider] from context.
class SettingsCourseRestoreTile extends StatefulWidget {
  const SettingsCourseRestoreTile({
    super.key,
    this.clearInstalled,
    this.refreshContent,
    this.acknowledgeContentVersion,
    this.languageCode,
  });

  final CourseContentClear? clearInstalled;
  final CourseContentRefresh? refreshContent;
  final Future<void> Function()? acknowledgeContentVersion;
  final String? languageCode;

  @override
  State<SettingsCourseRestoreTile> createState() =>
      _SettingsCourseRestoreTileState();
}

class _SettingsCourseRestoreTileState extends State<SettingsCourseRestoreTile> {
  late final CourseOtaService? _service = widget.clearInstalled == null
      ? CourseOtaService(allowInsecureHttp: kDebugMode)
      : null;
  late final CourseContentClear _clear =
      widget.clearInstalled ?? (code) => _service!.clearInstalledContent(code);
  bool _busy = false;

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsActionTile(
        icon: Icons.settings_backup_restore_rounded,
        title: AppStrings.settingsCourseRestoreTitle,
        subtitle: AppStrings.settingsCourseRestoreSubtitle,
        enabled: !_busy,
        onTap: (_) => _confirmRestore(),
      );

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsCourseRestoreDialogTitle,
        message: AppStrings.settingsCourseRestoreDialogMessage,
        confirmText: AppStrings.settingsCourseRestoreConfirm,
      ),
    );
    if (confirmed != true || !mounted) return;

    final refresh = widget.refreshContent ??
        context.read<CourseProvider>().refreshBuiltinContent;
    final acknowledge = widget.acknowledgeContentVersion ??
        context.read<CourseProvider>().acknowledgeContentVersion;
    final code = widget.languageCode ??
        context.read<LanguageProvider>().selectedLanguageCode;

    setState(() => _busy = true);
    String message;
    try {
      final removed = await _clear(code);
      if (!removed) {
        message = AppStrings.settingsCourseRestoreNothingInstalled;
      } else {
        try {
          await refresh(code);
          // The version moves down: acknowledge it so the next launch does not
          // re-arm the keep/reset prompt for a rollback the user just chose.
          await acknowledge();
          message = AppStrings.settingsCourseRestoreDone;
        } catch (error) {
          message = AppStrings.settingsCourseRestoreReseedFailed(
            _errorText(error),
          );
        }
      }
    } catch (error) {
      message = AppStrings.settingsCourseRestoreFailed(_errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) TurnaSnackBar.show(context, message);
  }

  static String _errorText(Object error) =>
      error is CourseOtaException ? error.message : error.toString();
}
