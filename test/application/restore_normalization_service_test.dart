import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/restore_normalization_service.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/export_service.dart';

import '../helpers/in_memory_course_db.dart';

class _MemoryCredentialStore implements ICredentialStore {
  final values = <String, String>{};

  @override
  bool get isPersistent => true;
  @override
  Future<void> write(String id, String value) async => values[id] = value;
  @override
  Future<String?> read(String id) async => values[id];
  @override
  Future<void> delete(String id) async => values.remove(id);
  @override
  Future<void> deleteAll() async => values.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    for (final key in streaming.getKeys().getValue()) {
      await streaming.remove(key);
    }
    prefs = AppPrefs(streaming);
    db = emptyInMemoryCourseDatabase();
    await db.customSelect('SELECT 1').get();
    getIt.registerSingleton<AppPrefs>(prefs);
    getIt.registerSingleton<GemLedgerDao>(GemLedgerDao(db));
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  test('normalization is idempotent and converges all restored contracts',
      () async {
    await prefs.preferences.setInt(LocalStateKeys.gems, 120);
    await prefs.preferences.setStringList(
      LocalStateKeys.cosmeticsUnlocked,
      [kAvatarRingReed],
    );
    await prefs.preferences.setString(
      LocalStateKeys.cosmeticsEquippedRing,
      kAvatarRingReed,
    );
    await prefs.preferences.setBool(LocalStateKeys.funAutoAnswer, true);
    const secret = 'sk-restored-plaintext';
    await prefs.preferences.setString(
      LocalStateKeys.aiEngineConfig,
      jsonEncode(
        const AiEngineConfig(apiKey: secret, modelChat: 'restored-model')
            .toJson(includeApiKey: true),
      ),
    );

    final credentials = _MemoryCredentialStore();
    final gems = GemsProvider(prefs);
    final cosmetics = CosmeticProvider(prefs, gems);
    final service = RestoreNormalizationService(
      prefs: prefs,
      gems: gems,
      cosmetics: cosmetics,
      aiConfig: AiEngineConfigHolder(credentials),
    );

    await service.normalize();
    await service.normalize();

    final ledger = getIt<GemLedgerDao>();
    expect(await ledger.projectedBalance(), 120);
    final openings = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM gem_ledger "
          "WHERE reason = 'legacy prefs opening balance'",
        )
        .getSingle();
    expect(openings.read<int>('c'), 1);
    final entitlementRows = await db.customSelect(
      'SELECT COUNT(*) AS c FROM cosmetic_entitlements WHERE item_id = ?',
      variables: [Variable.withString(kAvatarRingReed)],
    ).getSingle();
    expect(entitlementRows.read<int>('c'), 1);
    expect(cosmetics.equippedRingId, kAvatarRingReed);
    expect(
      prefs.preferences
          .getBool(LocalStateKeys.funAutoAnswer, defaultValue: true)
          .getValue(),
      isFalse,
    );
    expect(credentials.values[AiEngineConfigHolder.apiKeyId], secret);
    final stored = prefs.preferences
        .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
        .getValue();
    expect(stored, isNot(contains(secret)));
    expect((jsonDecode(stored) as Map<String, dynamic>)['modelChat'],
        'restored-model');
  });

  test('local import invokes the shared normalization chain', () async {
    final credentials = _MemoryCredentialStore();
    final gems = GemsProvider(prefs);
    final cosmetics = CosmeticProvider(prefs, gems);
    final normalizer = RestoreNormalizationService(
      prefs: prefs,
      gems: gems,
      cosmetics: cosmetics,
      aiConfig: AiEngineConfigHolder(credentials),
    );
    getIt.registerSingleton<RestoreNormalizationService>(normalizer);

    final directory = await Directory.systemTemp.createTemp('turna_import');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    const secret = 'sk-local-import';
    final file = File('${directory.path}/restore.json');
    await file.writeAsString(jsonEncode({
      'meta': {'app': 'turna', 'schema': 1},
      'progress': {
        LocalStateKeys.gems: 75,
        LocalStateKeys.cosmeticsUnlocked: [kAvatarRingReed],
        LocalStateKeys.cosmeticsEquippedRing: kAvatarRingReed,
        LocalStateKeys.funAutoAnswer: true,
        LocalStateKeys.highContrast: true,
        LocalStateKeys.aiEngineConfig: jsonEncode(
          const AiEngineConfig(apiKey: secret, modelChat: 'import-model')
              .toJson(includeApiKey: true),
        ),
      },
    }));

    final result = await ExportService(prefs).importFromFile(file.path);
    expect(result.progressRestored, isTrue);
    expect(await getIt<GemLedgerDao>().projectedBalance(), 75);
    expect(cosmetics.equippedRingId, kAvatarRingReed);
    expect(credentials.values[AiEngineConfigHolder.apiKeyId], secret);
    expect(
      prefs.preferences
          .getBool(LocalStateKeys.funAutoAnswer, defaultValue: true)
          .getValue(),
      isFalse,
    );
    expect(
      prefs.preferences
          .getBool(LocalStateKeys.highContrast, defaultValue: false)
          .getValue(),
      isTrue,
    );
    expect(
      prefs.preferences
          .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
          .getValue(),
      isNot(contains(secret)),
    );
  });
}
