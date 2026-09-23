// Package imports:
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/restore_normalization_service.dart';
import 'package:turna/application/settings/commands/apply_fsrs_parameters_command.dart';
import 'package:turna/application/settings/commands/clear_regenerable_caches_command.dart';
import 'package:turna/application/settings/commands/reset_account_command.dart';
import 'package:turna/application/settings/commands/reset_learning_settings_command.dart';
import 'package:turna/application/settings/commands/update_daily_reminder_command.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/export_service.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/secure_credential_store.dart';
import 'package:turna/service/tab_router.dart';

/// Generated-track registrations for services that used to live in the
/// manual `setupLocator()` track (batch 7 DI merge).
///
/// Everything here is a plain synchronous factory; the manual track keeps
/// only what Injectable cannot express: async construction (`AppPrefs`,
/// `PackageInfo`), the `CourseDatabase` open → probe → restore → reopen
/// fault chain plus its dependent DAO registrations, platform-gated
/// `FlutterTts`, the `Directory`/`int` bridge for `TurnaMigrationImporter`,
/// and `RemoteBackupService` (needs an async-resolved `appSupport` directory
/// plus a WebDAV client factory closure).
///
/// Lazy singletons defer dependency resolution to first use, so factories
/// below may reference manual-track types (`AppPrefs`, `CourseDatabase`,
/// `PackageInfo`) even though those are registered later by `setupLocator`.
@module
abstract class ServiceModule {
  /// Bottom-nav tab switcher shared by HomePage and pushed routes.
  @lazySingleton
  TabRouter tabRouter() => TabRouter();

  /// Platform secure credential storage (AI API key, WebDAV password).
  @lazySingleton
  ICredentialStore credentialStore() => SecureCredentialStore();

  @lazySingleton
  SystemHealthMonitor systemHealthMonitor(AppPrefs prefs) =>
      SystemHealthMonitor(prefs);

  // ── Settings command coordinators ───────────────────────────────────────
  @lazySingleton
  UpdateDailyReminderCommand updateDailyReminderCommand() =>
      UpdateDailyReminderCommand();

  @lazySingleton
  ResetLearningSettingsCommand resetLearningSettingsCommand() =>
      ResetLearningSettingsCommand();

  @lazySingleton
  ResetAccountCommand resetAccountCommand() => ResetAccountCommand();

  @lazySingleton
  ApplyFsrsParametersCommand applyFsrsParametersCommand() =>
      ApplyFsrsParametersCommand();

  @lazySingleton
  ClearRegenerableCachesCommand clearRegenerableCachesCommand() =>
      ClearRegenerableCachesCommand();

  @lazySingleton
  ExportService exportService(AppPrefs prefs) => ExportService(prefs);

  // ── Companion stores (single instances for all AI surfaces) ─────────────
  @lazySingleton
  AiExplainPrefsStore aiExplainPrefsStore() => AiExplainPrefsStore();

  @lazySingleton
  AiSavedExplanationsStore aiSavedExplanationsStore() =>
      AiSavedExplanationsStore();

  /// Post-restore normalization: strips debug flags, migrates AI
  /// credentials, reconciles gem/cosmetic state.
  @lazySingleton
  RestoreNormalizationService restoreNormalizationService(
    AppPrefs prefs,
    GemsProvider gems,
    CosmeticProvider cosmetics,
    AiEngineConfigHolder aiConfig,
  ) =>
      RestoreNormalizationService(
        prefs: prefs,
        gems: gems,
        cosmetics: cosmetics,
        aiConfig: aiConfig,
      );

  // ── Remote backup ───────────────────────────────────────────────────────
  @lazySingleton
  RemoteBackupConfigStore remoteBackupConfigStore(AppPrefs prefs) =>
      RemoteBackupConfigStore(prefs);

  @lazySingleton
  BackupSnapshotService backupSnapshotService(
    CourseDatabase db,
    PackageInfo packageInfo,
  ) =>
      BackupSnapshotService(db: db, packageInfo: packageInfo);
}
