// Consolidated tests for Official Anki license notices, hooks, and feature flags.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_license_notices.dart';

void main() {
  setUp(debugResetOfficialAnkiLicenses);

  group('Official Anki license notices & registration', () {
    test('registers the pinned Anki AGPL notice once', () async {
      registerOfficialAnkiLicenses();
      registerOfficialAnkiLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final anki = entries.where(
        (entry) => entry.packages.contains(kOfficialAnkiLicenseName),
      );
      expect(anki, hasLength(1));
      final paragraphs = anki.single.paragraphs.map((p) => p.text).join('\n');
      expect(paragraphs, contains('Affero'));
      expect(paragraphs, contains('967aa0d578fc75181e292e95326f9b58698da25c'));
      expect(paragraphs, isNot(contains('FrontSide')));
      expect(kOfficialAnkiSourceOfferSummary, contains('SOURCE-OFFER.md'));
    });

    test('showTurnaLicensePage registers Anki AGPL first', () async {
      registerOfficialAnkiLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      expect(
        entries.any((entry) => entry.packages.contains(kOfficialAnkiLicenseName)),
        isTrue,
      );
    });
  });

  group('License hooks & feature gates', () {
    test('both production license entries call showTurnaLicensePage', () {
      final about =
          File('lib/views/settings/about_turna_page.dart').readAsStringSync();
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
        'lib/application/anki_import/anki_import_dependencies.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/application/anki_import/anki_import_controller.dart',
      ).readAsStringSync();
      final service = File(
        'lib/application/anki_official/import/official_anki_official_first_service.dart',
      ).readAsStringSync();
      expect(deps.contains('AnkiImporter'), isFalse,
          reason: 'doc 35 L1: the legacy Dart parser is not wired anywhere');
      expect(deps.contains('OfficialAnkiOfficialFirstService'), isTrue,
          reason: 'production deps wire the official-first service');
      expect(controller.contains('importThenPreview'), isTrue,
          reason: 'doc 40 P5.6: controller drives the official-first saga');
      expect(service.contains('startStaging'), isTrue);
    });
  });
}
