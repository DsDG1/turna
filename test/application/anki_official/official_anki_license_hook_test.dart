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

  test('official import stays opt-in', () {
    expect(const OfficialAnkiFeatureFlags().import, isFalse);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialImport, isFalse);
    final screen = File('lib/views/anki/anki_import_screen.dart').readAsStringSync();
    expect(screen.contains('AnkiImporter'), isTrue);
    expect(screen.contains('AnkiImportFacade.resolve'), isTrue);
  });
}
