import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

void main() {
  test('p5f_official_first_import_defaults_on_for_production', () {
    final env = OfficialAnkiFeatureFlags.fromEnvironment();
    expect(env.officialFirstImport, isTrue,
        reason: 'doc 34: Official-first is the Android production default');
    expect(env.allowsOfficialFirstImport, isTrue);
    expect(env.allowsOfficialScheduler, isTrue);
    expect(env.diagnostics, isFalse);
    expect(env.legacyMirror, isFalse);
    expect(env.courseGradesScheduler, isFalse);
    expect(env.migrationPilot, isFalse);
    // Zero-arg constructor stays all-false for focused unit tests.
    expect(const OfficialAnkiFeatureFlags().officialFirstImport, isFalse);
    expect(const OfficialAnkiFeatureFlags().allowsOfficialImport, isFalse);
    expect(
      OfficialAnkiFeatureFlags.productionAndroid.allowsOfficialFirstImport,
      isTrue,
    );
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
