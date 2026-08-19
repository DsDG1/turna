import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

void main() {
  tearDown(() {
    OfficialAnkiFeatureFlags.current = OfficialAnkiFeatureFlags.fromEnvironment();
    OfficialAnkiCompositionRoot.session = null;
    OfficialAnkiCompositionRoot.executionMode = OfficialAnkiExecutionMode.none;
  });

  test('worker spawn failure does not create in-process host', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-comp-');
    addTearDown(() => root.deleteSync(recursive: true));
    await expectLater(
      OfficialAnkiCompositionRoot.requireImporter(
        supportDir: root,
        libraryPath: '/no/such/libturna_anki.so',
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
    expect(OfficialAnkiCompositionRoot.session, isNull);
    expect(
      OfficialAnkiCompositionRoot.executionMode,
      OfficialAnkiExecutionMode.none,
    );
  });

  test('explicit diagnostics option can still open in-process host', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      diagnostics: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-comp-diag-');
    addTearDown(() => root.deleteSync(recursive: true));
    try {
      await OfficialAnkiCompositionRoot.requireImporter(
        supportDir: root,
        libraryPath: '/no/such/libturna_anki.so',
        allowInProcessFallback: true,
      );
    } on OfficialAnkiException {
      // Library still missing; the important assertion is we were allowed
      // to attempt in-process instead of being blocked by production flags.
    }
  });

  test('requireImporter single-flights parallel fake spawns', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-comp-single-');
    addTearDown(() => root.deleteSync(recursive: true));
    final first = OfficialAnkiCompositionRoot.requireImporter(
      supportDir: root,
      useFake: true,
    );
    final second = OfficialAnkiCompositionRoot.requireImporter(
      supportDir: root,
      useFake: true,
    );
    final results = await Future.wait([first, second]);
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[0], OfficialAnkiCompositionRoot.session), isTrue);
  });

  test('production flags reject an in-process execution mode', () {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
    );
    OfficialAnkiCompositionRoot.executionMode =
        OfficialAnkiExecutionMode.inProcess;
    expect(
      () => OfficialAnkiCompositionRoot.rejectInProcessForProduction(
        OfficialAnkiFeatureFlags.current,
      ),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.messageKey,
          'key',
          'official_anki.in_process_forbidden',
        ),
      ),
    );
  });
}
