import 'dart:convert';

import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/service/locator.dart';

/// Idempotent migrations that must run after every kind of user-state restore.
///
/// Restore writers only put bytes/prefs back. This service owns the semantic
/// convergence that follows: no debug auto-answer, no plaintext AI key,
/// ledger/prefs agreement, and slot-based cosmetic equipment/entitlements.
class RestoreNormalizationService {
  RestoreNormalizationService({
    required AppPrefs prefs,
    required GemsProvider gems,
    required CosmeticProvider cosmetics,
    required AiEngineConfigHolder aiConfig,
  })  : _prefs = prefs,
        _gems = gems,
        _cosmetics = cosmetics,
        _aiConfig = aiConfig;

  final AppPrefs _prefs;
  final GemsProvider _gems;
  final CosmeticProvider _cosmetics;
  final AiEngineConfigHolder _aiConfig;

  Future<void> normalize() async {
    // Debug convenience state is intentionally never restored as enabled.
    await _prefs.preferences.setBool(LocalStateKeys.funAutoAnswer, false);

    // Load first: legacy plaintext is copied to secure storage and then
    // removed from the prefs document by AiEngineConfigHolder.
    await _aiConfig.loadPersisted();
    if (_aiConfig.migrationStatus != AiCredentialMigrationStatus.failed) {
      await _stripAnyResidualPlaintextAiKey();
    }

    // migrateFromPrefs + reconciliation and cosmetic slot migration are both
    // idempotent, so a crash/retry cannot add a second opening balance or
    // duplicate an entitlement.
    await _gems.reconcileAfterRestore();
    await _cosmetics.ensureInitialized();
  }

  Future<void> _stripAnyResidualPlaintextAiKey() async {
    final store = _prefs.preferences;
    final raw = store
        .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          (decoded['apiKey']?.toString().isEmpty ?? true)) {
        return;
      }
      decoded['apiKey'] = '';
      await store.setString(LocalStateKeys.aiEngineConfig, jsonEncode(decoded));
    } catch (_) {
      // Corrupt config is ignored by the holder; never rewrite unknown bytes.
    }
  }
}
