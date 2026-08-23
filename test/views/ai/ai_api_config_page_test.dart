// Widget tests: AI connection page draft-commit semantics (Plan 2 §4.10 /
// §6.2) — text edits are debounced (≥500 ms) instead of persisted per
// keystroke, and the stored API key is never prefilled into the field.

// Flutter imports:
import 'dart:convert';

import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/ai/ai_api_config_page.dart';

class _EphemeralStore implements ICredentialStore {
  final Map<String, String> _map = {};

  @override
  bool get isPersistent => true;

  @override
  Future<void> write(String id, String value) async => _map[id] = value;

  @override
  Future<String?> read(String id) async => _map[id];

  @override
  Future<void> delete(String id) async => _map.remove(id);

  @override
  Future<void> deleteAll() async => _map.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late AiEngineConfigHolder holder;
  int holderNotifications = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    holder = AiEngineConfigHolder(_EphemeralStore());
    holderNotifications = 0;
    holder.addListener(() => holderNotifications++);
    getIt.registerLazySingleton<AiEngineConfigHolder>(() => holder);
  });

  tearDown(() => getIt.reset());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AiEngineConfigHolder>.value(
        value: holder,
        child: const MaterialApp(home: AiApiConfigPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder modelChatField() {
    final hint = find.text(AppStrings.settingsModelHint);
    return find
        .ancestor(of: hint, matching: find.byType(TextField))
        .first;
  }

  testWidgets('typing does not persist per keystroke; one debounced commit',
      (tester) async {
    await pumpPage(tester);
    holderNotifications = 0;

    // Simulate a burst of keystrokes, each well under the 500 ms debounce.
    for (var i = 1; i <= 10; i++) {
      await tester.enterText(modelChatField(), 'model-$i');
      await tester.pump(const Duration(milliseconds: 100));
      expect(holder.config.modelChat, isNot('model-$i'),
          reason: 'commit must not happen before the debounce fires');
    }
    expect(holderNotifications, 0,
        reason: 'no persistence writes during active typing');

    // Idle past the debounce: exactly one commit for the whole burst.
    await tester.pump(const Duration(milliseconds: 600));
    expect(holder.config.modelChat, 'model-10');
    expect(holderNotifications, 1);

    // The prefs blob still contains no API key.
    final raw = prefs.preferences
        .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
        .getValue();
    expect(jsonDecode(raw), isA<Map<String, dynamic>>());
    expect((jsonDecode(raw) as Map).containsKey('apiKey'), isFalse);
  });

  testWidgets('stored API key is masked in the hint, never prefilled',
      (tester) async {
    await holder.updateConfig(
      const AiEngineConfig(apiKey: 'sk-very-secret-key-12345'),
    );
    await pumpPage(tester);

    // The key field is the only obscured TextField on the page; its text
    // must be empty (the stored key only appears as a masked hint).
    final keyTexts = find
        .byType(TextField)
        .evaluate()
        .map((e) => e.widget as TextField)
        .where((t) => t.obscureText)
        .map((t) => t.controller?.text ?? '')
        .toList();
    expect(keyTexts, isNotEmpty);
    expect(keyTexts.first, isEmpty,
        reason: 'the full key must never be echoed into an editable field');

    // The hint shows only the masked form.
    expect(find.textContaining('sk-very-secret-key-12345'), findsNothing);
    expect(find.textContaining('已配置'), findsWidgets);
  });

  testWidgets('dispose flushes a pending draft instead of dropping it',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(modelChatField(), 'last-second-edit');
    // Navigate away before the debounce fires.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(holder.config.modelChat, 'last-second-edit',
        reason: 'leaving the page must not silently lose the draft');
  });
}
