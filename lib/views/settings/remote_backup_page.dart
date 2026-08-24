// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:intl/intl.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_service.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Manual WebDAV remote backup / restore. Everything is user-triggered:
/// "立即备份" snapshots + uploads, "从远程恢复" downloads + stages the
/// restore for the next boot (see RestoreApplier).
///
/// Credentials: the password lives only in the platform secure store. The
/// form shows a "已保存凭据" placeholder instead of echoing it back, and the
/// password field only replaces the stored credential when the user types
/// something. Edits are persisted via the explicit "保存并测试" action —
/// never per keystroke.
@RoutePage()
class RemoteBackupPage extends StatefulWidget {
  const RemoteBackupPage({super.key});

  @override
  State<RemoteBackupPage> createState() => _RemoteBackupPageState();
}

class _RemoteBackupPageState extends State<RemoteBackupPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passwordCtrl;
  bool _obscurePassword = true;

  RemoteBackupEndpointConfig _endpoint = const RemoteBackupEndpointConfig();
  bool _credentialStored = false;

  /// True when URL / username / password fields diverge from the persisted
  /// state. Editing anything also invalidates a previous connection-test
  /// result — a green checkmark must never survive an edit.
  bool _dirty = false;

  bool _saving = false;
  bool _testing = false;
  String? _testResult; // null = no result yet
  bool _testOk = false;

  bool _backingUp = false;
  String? _stage;
  bool _restoring = false;

  RemoteBackupResult? _lastLocal;
  String? _remoteStatusText;
  String? _blockedNotice;

  RemoteBackupService? get _service => getIt.isRegistered<RemoteBackupService>()
      ? getIt<RemoteBackupService>()
      : null;

  RemoteBackupConfigStore? get _configStore =>
      getIt.isRegistered<RemoteBackupConfigStore>()
          ? getIt<RemoteBackupConfigStore>()
          : null;

  bool get _supported => _service != null;

  bool get _busy => _saving || _testing || _backingUp || _restoring;

  bool get _canSave =>
      _dirty &&
      !_busy &&
      _urlCtrl.text.trim().isNotEmpty &&
      _userCtrl.text.trim().isNotEmpty;

  /// Actions require a saved, fully configured endpoint + credential.
  Future<bool> get _isConfigured async {
    if (_dirty) return false;
    final resolved = await _configStore?.loadResolved();
    return resolved?.isConfigured ?? false;
  }

  @override
  void initState() {
    super.initState();
    final store = _configStore;
    if (store != null) {
      _endpoint = store.loadEndpoint();
      _credentialStored = false;
      store.hasStoredPassword().then((stored) {
        if (mounted) setState(() => _credentialStored = stored);
      });
    }
    _urlCtrl = TextEditingController(text: _endpoint.serverUrl);
    _userCtrl = TextEditingController(text: _endpoint.username);
    // Never echo the stored password back into an editable field — the hint
    // communicates presence, a new entry replaces it.
    _passwordCtrl = TextEditingController();
    for (final controller in [_urlCtrl, _userCtrl, _passwordCtrl]) {
      controller.addListener(_onFieldEdited);
    }
    final service = _service;
    if (service != null) {
      _lastLocal = service.lastLocalBackup();
      _blockedNotice = _readBlockedNotice();
      _refreshRemoteStatus();
    }
  }

  @override
  void dispose() {
    // Detach listeners first so the scrub below cannot notify a defunct
    // element, then scrub the password draft so it does not outlive the
    // page.
    for (final controller in [_urlCtrl, _userCtrl, _passwordCtrl]) {
      controller.removeListener(_onFieldEdited);
    }
    _passwordCtrl.clear();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onFieldEdited() {
    // Always rebuild: the save button's enabled state is derived from the
    // controller texts at BUILD time, so skipping setState once _dirty is
    // already true would leave the button disabled after the second field
    // edit.
    setState(() {
      _dirty = true;
      _testResult = null;
      _testOk = false;
    });
  }

  String? _readBlockedNotice() {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    final raw = getIt<AppPrefs>()
        .preferences
        .getString(LocalStateKeys.remoteBackupRestoreBlockedReason,
            defaultValue: '')
        .getValue();
    return raw.isEmpty ? null : AppStrings.remoteBackupBlockedNotice(raw);
  }

  Future<void> _refreshRemoteStatus() async {
    final service = _service;
    if (service == null) return;
    final resolved = await _configStore?.loadResolved();
    if (resolved == null || !resolved.isConfigured) return;
    setState(
        () => _remoteStatusText = AppStrings.remoteBackupRemoteStatusLoading);
    try {
      final manifest = await service.fetchRemoteStatus();
      if (!mounted) return;
      if (manifest == null) {
        setState(() => _remoteStatusText = AppStrings.remoteBackupNoBackupYet);
      } else {
        final time =
            DateFormat('yyyy-MM-dd HH:mm').format(manifest.createdAtUtc);
        setState(() => _remoteStatusText =
            AppStrings.remoteBackupRemoteStatus(time, manifest.deviceLabel));
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _remoteStatusText =
          AppStrings.remoteBackupRemoteStatusError(_errText(e)));
    }
  }

  /// Explicit save of endpoint + credential. The stored password is only
  /// replaced when the (masked) password field contains a new entry; an
  /// empty field plus the "已保存凭据" placeholder keeps the existing one.
  Future<void> _saveAndTest() async {
    debugPrint('SAVEANDTEST: store=${_configStore != null} busy=$_busy '
        'canSave=$_canSave');
    final store = _configStore;
    if (store == null || _busy) return;
    setState(() {
      _saving = true;
      _testResult = null;
    });
    try {
      final endpoint = _endpoint
          .copyWith(
            serverUrl: _urlCtrl.text,
            username: _userCtrl.text,
          )
          .normalized();
      final newPassword = _passwordCtrl.text;
      if (newPassword.isNotEmpty) {
        await store.savePassword(newPassword);
        _credentialStored = true;
        _passwordCtrl.clear();
      }
      await store.saveEndpoint(endpoint);
      _endpoint = endpoint;
      if (mounted) setState(() => _dirty = false);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(_errText(e));
      return;
    }

    // Saved — immediately verify the connection so "保存" never reports
    // success for a configuration that cannot reach the server.
    setState(() => _saving = false);
    await _testConnection();
  }

  Future<void> _setIncludeMedia(bool value) async {
    final store = _configStore;
    if (store == null) return;
    setState(() => _endpoint = _endpoint.copyWith(includeMedia: value));
    await store.saveEndpoint(_endpoint);
  }

  Future<void> _testConnection() async {
    final service = _service;
    if (service == null || _testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await service.testConnection();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _testResult = AppStrings.remoteBackupTestOk;
      });
      _refreshRemoteStatus();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = AppStrings.remoteBackupTestFailed(_errText(e));
      });
    }
  }

  Future<void> _backupNow() async {
    final service = _service;
    if (service == null || _backingUp) return;
    if (!await _isConfigured) {
      _showSnack('请先保存服务器配置与凭据');
      return;
    }
    setState(() {
      _backingUp = true;
      _stage = null;
    });
    try {
      final result = await service.backupNow(
        onPhase: (phase) {
          if (!mounted) return;
          setState(() => _stage = _phaseText(phase));
        },
        onMediaProgress: (done, total) {
          if (!mounted) return;
          setState(() =>
              _stage = AppStrings.remoteBackupPhaseHashingMedia(done, total));
        },
        onMediaUploadProgress: (uploaded, skipped) {
          if (!mounted) return;
          setState(() => _stage =
              AppStrings.remoteBackupPhaseUploadingMedia(uploaded, skipped));
        },
      );
      _lastLocal = service.lastLocalBackup();
      if (!mounted) return;
      setState(() {
        _backingUp = false;
        _stage = null;
      });
      _showSnack(
          AppStrings.remoteBackupSuccess(_formatBytes(result.coreZipBytes)));
      _refreshRemoteStatus();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _backingUp = false;
        _stage = null;
      });
      _showSnack(AppStrings.remoteBackupFailed(_errText(e)));
    }
  }

  String _phaseText(BackupSnapshotPhase phase) {
    switch (phase) {
      case BackupSnapshotPhase.collectingPrefs:
        return AppStrings.remoteBackupPhaseCollectingPrefs;
      case BackupSnapshotPhase.snapshottingCourseDb:
        return AppStrings.remoteBackupPhaseSnapshottingCourseDb;
      case BackupSnapshotPhase.snapshottingOfficialDbs:
        return AppStrings.remoteBackupPhaseSnapshottingOfficialDbs;
      case BackupSnapshotPhase.hashingMedia:
        return AppStrings.remoteBackupPhaseHashingMedia(0, 0);
      case BackupSnapshotPhase.packingArchive:
        return AppStrings.remoteBackupPhasePackingArchive;
    }
  }

  Future<void> _restoreFromRemote() async {
    final service = _service;
    if (service == null || _restoring) return;
    if (!await _isConfigured) {
      _showSnack('请先保存服务器配置与凭据');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.remoteBackupRestoreDialogTitle,
        message: AppStrings.remoteBackupRestoreDialogMessage,
        confirmText: AppStrings.remoteBackupRestoreConfirm,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _restoring = true;
      _stage = AppStrings.remoteBackupRestoringCore;
    });
    try {
      final manifest = await service.fetchRemoteStatus();
      if (manifest == null) {
        throw const WebDavException('服务器上没有可恢复的备份');
      }
      await service.restoreToStaging(
        manifest,
        onMediaProgress: (done, total) {
          if (!mounted) return;
          setState(() =>
              _stage = AppStrings.remoteBackupRestoringMedia(done, total));
        },
      );
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _stage = null;
      });
      await showDialog<void>(
        context: context,
        builder: (_) => SettingsInfoDialog(
          title: AppStrings.remoteBackupRestoreStagedTitle,
          message: AppStrings.remoteBackupRestoreStagedMessage,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _stage = null;
      });
      _showSnack(AppStrings.remoteBackupRestoreFailed(_errText(e)));
    }
  }

  String _errText(Object error) {
    switch (error) {
      case WebDavAuthException _:
        return '用户名或密码被服务器拒绝';
      case RemoteBackupSecureStoreException _:
        return error.message.isEmpty ? error.toString() : error.message;
      case RemoteBackupBusyException _:
        return error.toString();
      case WebDavException _:
        return error.message;
      default:
        return error.toString();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: AppStrings.settingsRemoteBackupTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (!_supported) ...[
            const SettingsEmptyCard(
              icon: Icons.cloud_off_outlined,
              message: '当前平台暂不支持远程备份',
            ),
            const SizedBox(height: 20),
          ] else ...[
            if (_blockedNotice != null) ...[
              SettingsInfoCard(
                tone: SettingsInfoTone.warning,
                icon: Icons.warning_amber_rounded,
                text: _blockedNotice!,
              ),
              const SizedBox(height: 12),
            ],
            _serverSection(context),
            const SizedBox(height: 20),
            _backupSection(context),
            const SizedBox(height: 20),
            _restoreSection(context),
            const SizedBox(height: 20),
            SettingsInfoCard(
              tone: SettingsInfoTone.neutral,
              icon: Icons.info_outline,
              text: AppStrings.remoteBackupHint,
            ),
          ],
        ],
      ),
    );
  }

  Widget _serverSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          icon: Icons.dns_outlined,
          title: AppStrings.remoteBackupServerSection,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _labeledField(
                    context,
                    label: AppStrings.remoteBackupServerUrlLabel,
                    child: TextField(
                      controller: _urlCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: _inputDecoration(
                          context, AppStrings.remoteBackupServerUrlHint),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    context,
                    label: AppStrings.remoteBackupUsernameLabel,
                    child: TextField(
                      controller: _userCtrl,
                      enabled: !_busy,
                      autocorrect: false,
                      decoration: _inputDecoration(
                          context, AppStrings.remoteBackupUsernameHint),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    context,
                    label: AppStrings.remoteBackupPasswordLabel,
                    child: TextField(
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      decoration: _inputDecoration(
                        context,
                        _credentialStored && _passwordCtrl.text.isEmpty
                            ? '已保存凭据（输入新密码可替换）'
                            : AppStrings.remoteBackupPasswordHint,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: TurnaTheme.textHintColor(context),
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SettingsPrimaryButton(
                    label: _saving
                        ? AppStrings.remoteBackupSaving
                        : AppStrings.remoteBackupSaveAndTest,
                    icon: Icons.save_rounded,
                    onPressed: _canSave ? _saveAndTest : null,
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 10),
                    _resultRow(context),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultRow(BuildContext context) {
    final color = _testOk ? TurnaTheme.brandTeal : TurnaTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(_testOk ? Icons.check_circle : Icons.error_outline,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _testResult!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupSection(BuildContext context) {
    final busy = _backingUp || _restoring;
    final last = _lastLocal;
    final lastText = last == null
        ? AppStrings.remoteBackupNoBackupYet
        : AppStrings.remoteBackupLastBackup(
            DateFormat('yyyy-MM-dd HH:mm').format(last.createdAtUtc),
            _formatBytes(last.coreZipBytes),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          icon: Icons.cloud_upload_outlined,
          title: AppStrings.remoteBackupBackupSection,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.image_outlined,
              title: AppStrings.remoteBackupIncludeMediaTitle,
              subtitle: AppStrings.remoteBackupIncludeMediaSubtitle,
              value: _endpoint.includeMedia,
              onChanged: busy ? null : _setIncludeMedia,
            ),
            settingsTileDivider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                lastText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsPrimaryButton(
                    label: AppStrings.remoteBackupBackupNow,
                    icon: Icons.backup_outlined,
                    onPressed: busy ? null : _backupNow,
                  ),
                  if (_stage != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _stage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _restoreSection(BuildContext context) {
    final busy = _backingUp || _restoring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          icon: Icons.cloud_download_outlined,
          title: AppStrings.remoteBackupRestoreSection,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsActionTile(
              icon: Icons.settings_backup_restore_rounded,
              title: AppStrings.remoteBackupRestoreFromRemote,
              subtitle:
                  _remoteStatusText ?? AppStrings.remoteBackupRestoreSubtitle,
              enabled: !busy,
              onTap: (_) => _restoreFromRemote(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _labeledField(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String hint, {
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        hintText: hint,
        suffixIcon: suffixIcon,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        ),
      );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
