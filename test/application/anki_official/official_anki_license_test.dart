import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_license_notices.dart';

void main() {
  setUp(debugResetOfficialAnkiLicenses);

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
}
