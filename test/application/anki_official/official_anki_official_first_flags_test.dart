import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

void main() {
  test('p5f_official_first_import_defaults_off', () {
    final env = OfficialAnkiFeatureFlags.fromEnvironment();
    expect(env.officialFirstImport, isFalse,
        reason: 'P5F is opt-in: no defaultValue on the dart-define');
    expect(env.allowsOfficialFirstImport, isFalse);
    expect(const OfficialAnkiFeatureFlags().officialFirstImport, isFalse);
  });

  test('p5f_official_first_requires_full_projection_capability', () {
    const base = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
    );
    expect(base.allowsOfficialFirstImport, isFalse,
        reason: 'flag itself must be opted in');
    expect(
      base.copyWith(officialFirstImport: true).allowsOfficialFirstImport,
      isTrue,
    );
    expect(
      base
          .copyWith(officialFirstImport: true, projection: false)
          .allowsOfficialFirstImport,
      isFalse,
      reason: 'course tree comes from the projection service',
    );
    expect(
      base
          .copyWith(officialFirstImport: true, courseEntry: false)
          .allowsOfficialFirstImport,
      isFalse,
    );
    expect(
      base
          .copyWith(officialFirstImport: true, import: false)
          .allowsOfficialFirstImport,
      isFalse,
    );
  });

  test('p5f_copyWith_round_trips_official_first_import', () {
    const off = OfficialAnkiFeatureFlags();
    final on = off.copyWith(officialFirstImport: true);
    expect(on.officialFirstImport, isTrue);
    expect(on.copyWith().officialFirstImport, isTrue);
    expect(on.copyWith(officialFirstImport: false).officialFirstImport, isFalse);
  });
}
