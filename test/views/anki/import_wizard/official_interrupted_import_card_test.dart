import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';

void main() {
  testWidgets('interrupted import card offers discard only', (tester) async {
    var discarded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfficialInterruptedImportCard(
            displayName: 'Large Fixture',
            onDiscard: () => discarded = true,
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.ankiPendingImportTitle), findsOneWidget);
    expect(find.text('Large Fixture'), findsOneWidget);
    expect(find.text(AppStrings.ankiImportSystemError), findsOneWidget);
    expect(find.text(AppStrings.ankiPendingMustDiscardBeforeNew), findsOneWidget);
    expect(find.text(AppStrings.ankiPendingContinue), findsNothing);
    expect(find.text(AppStrings.ankiPendingImportBody('Large Fixture')),
        findsOneWidget);

    await tester.tap(find.text(AppStrings.ankiPendingDiscard));
    await tester.pump();
    expect(discarded, isTrue);
  });
}
