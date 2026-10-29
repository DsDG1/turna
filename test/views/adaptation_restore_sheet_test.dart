import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/components/adaptation_restore_sheet.dart';

/// P6 rollback gate: an active plan can be withdrawn one scope at a time or all
/// at once, and a failed withdraw never pretends the row is gone (ADR 0057 §6).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AdaptationManifest manifest(Map<String, int> scopes) =>
      AdaptationManifest(
        entries: {
          for (final entry in scopes.entries)
            entry.key: AdaptationManifestEntry(
              planId: 'plan-${entry.value}',
              revision: 1,
            ),
        },
      );

  Future<void> pump(
    WidgetTester tester, {
    required Future<AdaptationManifest> Function() load,
    Future<bool> Function(String scopeKey)? restoreScope,
    Future<bool> Function()? restoreAll,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptationRestoreSheet(
            loadManifest: load,
            restoreScope: restoreScope ??
                (_) async {
                  return true;
                },
            restoreAll: restoreAll ??
                () async {
                  return true;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists active scopes with human labels', (tester) async {
    await pump(
      tester,
      load: () async => manifest(const {'7:0': 1, '9:2': 2}),
    );

    expect(
      find.text(AppStrings.ankiAdaptationScopeLabel(7, 0)),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.ankiAdaptationScopeLabel(9, 2)),
      findsOneWidget,
    );
  });

  testWidgets('restoring one scope calls the store and drops the row',
      (tester) async {
    final restored = <String>[];
    await pump(
      tester,
      load: () async => manifest(const {'7:0': 1, '9:2': 2}),
      restoreScope: (scopeKey) async {
        restored.add(scopeKey);
        return true;
      },
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('adaptation-scope-7:0')),
        matching: find.text(AppStrings.ankiAdaptationRestoreOne),
      ),
    );
    await tester.pumpAndSettle();

    expect(restored, ['7:0']);
    expect(find.byKey(const ValueKey('adaptation-scope-7:0')), findsNothing);
    expect(find.byKey(const ValueKey('adaptation-scope-9:2')), findsOneWidget);
  });

  testWidgets('a failed restore keeps the row visible', (tester) async {
    await pump(
      tester,
      load: () async => manifest(const {'7:0': 1}),
      restoreScope: (_) async => false,
    );

    await tester.tap(find.text(AppStrings.ankiAdaptationRestoreOne));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('adaptation-scope-7:0')),
      findsOneWidget,
      reason: '没删掉就不能显示成已恢复',
    );
  });

  testWidgets('restore-all clears the whole manifest', (tester) async {
    var allCalls = 0;
    await pump(
      tester,
      load: () async => manifest(const {'7:0': 1, '9:2': 2}),
      restoreAll: () async {
        allCalls++;
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('adaptation-restore-all')));
    await tester.pumpAndSettle();

    expect(allCalls, 1);
    expect(find.byKey(const ValueKey('adaptation-restore-empty')), findsOneWidget);
  });

  testWidgets('no active plan shows the empty state', (tester) async {
    await pump(tester, load: () async => AdaptationManifest.empty);

    expect(find.text(AppStrings.ankiAdaptationRestoreEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptation-restore-all')), findsNothing);
  });

  test('a malformed scope key is shown verbatim, never dropped', () {
    expect(
      adaptationScopeLabel(
        'garbage',
        (id, template) => AppStrings.ankiAdaptationScopeLabel(id, template),
      ),
      'garbage',
    );
  });
}
