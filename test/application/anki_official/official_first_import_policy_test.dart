import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/import/official_first_import_policy.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

void main() {
  const capableFlags = OfficialAnkiFeatureFlags(
    engine: true,
    import: true,
    catalogReady: true,
    runtimeCapable: true,
    platformReady: true,
    projection: true,
    courseEntry: true,
    officialFirstImport: true,
  );

  bool eligible({
    bool isSample = false,
    bool officialCapable = true,
    OfficialAnkiFeatureFlags flags = capableFlags,
    String filePath = '/tmp/deck.apkg',
  }) =>
      officialFirstImportEligible(
        isSample: isSample,
        officialCapable: officialCapable,
        flags: flags,
        filePath: filePath,
      );

  test('p5f_official_first_eligible_on_optin_apkg', () {
    expect(eligible(), isTrue);
    expect(eligible(filePath: '/tmp/DECK.APKG'), isTrue,
        reason: 'extension check is case-insensitive');
  });

  test('p5f_official_first_ineligible_for_sample_colpkg_or_flag_off', () {
    expect(eligible(isSample: true), isFalse,
        reason: 'sample deck is synthetic and has no package file');
    expect(eligible(filePath: '/tmp/deck.colpkg'), isFalse,
        reason: 'official saga only accepts .apkg');
    expect(eligible(officialCapable: false), isFalse,
        reason: 'facade decision must be official (platform/gray/flags)');
    expect(
      eligible(flags: capableFlags.copyWith(officialFirstImport: false)),
      isFalse,
      reason: 'P5F stays opt-in',
    );
    expect(
      eligible(flags: capableFlags.copyWith(projection: false)),
      isFalse,
      reason: 'course tree comes from the projection service',
    );
    expect(eligible(filePath: '/tmp/deck.apkg.bak'), isFalse);
  });
}
