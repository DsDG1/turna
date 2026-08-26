import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_license_notices.dart';

void main() {
  setUp(debugResetOfficialAnkiLicenses);

  test('showTurnaLicensePage registers Anki AGPL first', () async {
    registerOfficialAnkiLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    expect(
      entries.any((entry) => entry.packages.contains(kOfficialAnkiLicenseName)),
      isTrue,
    );
  });

  test('both production license entries call showTurnaLicensePage', () {
    final about = File('lib/views/settings/about_turna_page.dart').readAsStringSync();
    final settings = File(
      'lib/views/settings/widgets/settings_about_section.dart',
    ).readAsStringSync();
    expect(about.contains('showTurnaLicensePage'), isTrue);
    expect(settings.contains('showTurnaLicensePage'), isTrue);
    expect(RegExp(r'(?<!Turna)showLicensePage\(').hasMatch(about), isFalse);
    expect(RegExp(r'(?<!Turna)showLicensePage\(').hasMatch(settings), isFalse);
  });

  test('official import constructor stays off; production current is on', () {
    expect(const OfficialAnkiFeatureFlags().import, isFalse);
    expect(const OfficialAnkiFeatureFlags().renderer, isFalse);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialImport, isTrue);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialRenderer, isTrue);
    final deps = File(
      'lib/application/anki/import_wizard/anki_import_dependencies.dart',
    ).readAsStringSync();
    final officialFlow = File(
      'lib/application/anki/import_wizard/official_first_anki_import_flow.dart',
    ).readAsStringSync();
    final service = File(
      'lib/application/anki_official/import/official_anki_official_first_service.dart',
    ).readAsStringSync();
    expect(deps.contains('AnkiImporter'), isTrue,
        reason: 'production deps wire the real importer');
    expect(deps.contains('OfficialAnkiOfficialFirstService'), isTrue,
        reason: 'production deps wire the official-first service');
    expect(officialFlow.contains('importThenPreview'), isTrue,
        reason: 'the official flow drives the real saga');
    expect(service.contains('AnkiImportFacade.resolve'), isTrue);
  });
}
