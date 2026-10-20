import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

void main() {
  test('empty constructor stays fail-closed; production current is open', () {
    const closed = OfficialAnkiFeatureFlags();
    expect(closed.import, isFalse);
    expect(closed.allowsOfficialImport, isFalse);
    expect(closed.renderer, isFalse);
    expect(closed.allowsOfficialRenderer, isFalse);
    expect(OfficialAnkiFeatureFlags.current.import, isTrue);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialImport, isTrue);
    expect(OfficialAnkiFeatureFlags.current.renderer, isTrue);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialRenderer, isTrue);
  });

  test('p5f_official_first_import_defaults_on_for_production', () {
    final env = OfficialAnkiFeatureFlags.fromEnvironment();
    expect(env.officialFirstImport, isTrue,
        reason: 'Official-first is the Android production default (ADR 0043)');
    expect(env.allowsOfficialFirstImport, isTrue);
    expect(env.allowsOfficialScheduler, isTrue);
    expect(env.courseGradesScheduler, isFalse);
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
}
