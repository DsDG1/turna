import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/content_ota/course_ota_service.dart';
import 'package:turna/views/settings/widgets/primitives/settings_section.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

typedef CourseUrlUpdate = Future<CourseOtaResult> Function(
  String rawUrl, {
  required String languageCode,
  CourseOtaPhaseCallback? onPhase,
  CourseOtaProgress? onProgress,
});

/// Phase-one manual entry for builtin-course content updates.
///
/// The callbacks are test seams; production resolves the current language and
/// [CourseProvider] from context. A successfully downloaded package is kept
/// in the dialog if reseeding is blocked, so retrying only applies that
/// package instead of downloading it again and tripping the version guard.
class SettingsCourseUpdateTile extends StatefulWidget {
  const SettingsCourseUpdateTile({
    super.key,
    this.updateFromUrl,
    this.refreshContent,
    this.languageCode,
  });

  final CourseUrlUpdate? updateFromUrl;
  final Future<bool> Function(String languageCode)? refreshContent;
  final String? languageCode;

  @override
  State<SettingsCourseUpdateTile> createState() =>
      _SettingsCourseUpdateTileState();
}

class _SettingsCourseUpdateTileState extends State<SettingsCourseUpdateTile> {
  final _urlController = TextEditingController();
  late final CourseOtaService? _service = widget.updateFromUrl == null
      ? CourseOtaService(allowInsecureHttp: kDebugMode)
      : null;
  late final CourseUrlUpdate _update =
      widget.updateFromUrl ?? _service!.updateFromUrl;

  @override
  void dispose() {
    _urlController.dispose();
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsActionTile(
        icon: Icons.cloud_download_outlined,
        title: AppStrings.settingsCourseUpdateTitle,
        subtitle: AppStrings.settingsCourseUpdateSubtitle,
        onTap: (_) => _showUpdateDialog(),
      );

  Future<void> _showUpdateDialog() async {
    var busy = false;
    var applying = false;
    var received = 0;
    var total = 0;
    var phase = CourseOtaPhase.checking;
    String? errorMessage;
    CourseOtaResult? pendingResult;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(VoidCallback change) {
            if (dialogContext.mounted) setDialogState(change);
          }

          Future<void> submit() async {
            var installed = pendingResult;
            final rawUrl = _urlController.text.trim();
            if (installed == null && rawUrl.isEmpty) {
              update(() =>
                  errorMessage = AppStrings.settingsCourseUpdateUrlRequired);
              return;
            }
            update(() {
              busy = true;
              applying = installed != null;
              errorMessage = null;
              received = 0;
              total = 0;
              phase = CourseOtaPhase.checking;
            });
            final refresh = widget.refreshContent ??
                this.context.read<CourseProvider>().refreshBuiltinContent;
            try {
              if (installed == null) {
                final code = widget.languageCode ??
                    this.context.read<LanguageProvider>().selectedLanguageCode;
                installed = await _update(
                  rawUrl,
                  languageCode: code,
                  onPhase: (next) => update(() => phase = next),
                  onProgress: (bytes, expected) => update(() {
                    received = bytes;
                    total = expected;
                  }),
                );
                pendingResult = installed;
              }
              update(() => applying = true);
              final changed = await refresh(installed.languageCode);
              if (!mounted) return;
              _urlController.clear();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              TurnaSnackBar.show(
                this.context,
                changed
                    ? AppStrings.settingsCourseUpdateSuccess(
                        installed.version.index,
                      )
                    : AppStrings.settingsCourseUpdateAlreadyCurrent,
              );
            } catch (error) {
              final message = pendingResult == null
                  ? AppStrings.settingsCourseUpdateDownloadFailed(
                      _errorText(error),
                    )
                  : AppStrings.settingsCourseUpdateApplyFailed(
                      _errorText(error),
                    );
              update(() => errorMessage = message);
            } finally {
              update(() {
                busy = false;
                applying = false;
              });
            }
          }

          return AlertDialog(
            title: Text(AppStrings.settingsCourseUpdateDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: AppStrings.settingsCourseUpdateUrlLabel,
                    hintText: AppStrings.settingsCourseUpdateUrlHint,
                  ),
                  onChanged: (_) {
                    if (pendingResult == null && errorMessage == null) return;
                    update(() {
                      pendingResult = null;
                      errorMessage = null;
                    });
                  },
                ),
                if (busy) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: !applying &&
                            phase == CourseOtaPhase.downloadingPackage &&
                            total > 0
                        ? (received / total).clamp(0.0, 1.0)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    applying
                        ? AppStrings.settingsCourseUpdateApplying
                        : _phaseLabel(phase),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (!applying &&
                      phase == CourseOtaPhase.downloadingPackage &&
                      total > 0)
                    Text(
                      '$received / $total 字节',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: Text(AppStrings.commonCancel),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  pendingResult != null
                      ? AppStrings.settingsCourseUpdateRetryApply
                      : busy
                          ? AppStrings.settingsCourseUpdateWorking
                          : AppStrings.settingsCourseUpdateAction,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _phaseLabel(CourseOtaPhase phase) => switch (phase) {
        CourseOtaPhase.checking => AppStrings.settingsCourseUpdateChecking,
        CourseOtaPhase.downloadingFeed => AppStrings.settingsCourseUpdateFeed,
        CourseOtaPhase.downloadingPackage =>
          AppStrings.settingsCourseUpdateDownloading,
        CourseOtaPhase.validating => AppStrings.settingsCourseUpdateValidating,
        CourseOtaPhase.installing => AppStrings.settingsCourseUpdateInstalling,
      };

  static String _errorText(Object error) =>
      error is CourseOtaException ? error.message : error.toString();
}
