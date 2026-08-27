import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
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
  const planner = AnkiImportExecutionPlanner();

  AnkiImportExecutionPlan plan({
    OfficialAnkiFeatureFlags flags = capableFlags,
    String filePath = '/tmp/deck.apkg',
    bool libraryAvailable = true,
  }) {
    return planner.resolve(
      flags: flags,
      platform: 'android',
      libraryAvailable: libraryAvailable,
      filePath: filePath,
    );
  }

  test('official-first apkg is the Android production plan', () {
    expect(plan().isOfficialFirst, isTrue);
    expect(plan(filePath: '/tmp/DECK.APKG').isOfficialFirst, isTrue);
  });

  test('colpkg / flag-off never choose Official-first', () {
    expect(plan(filePath: '/tmp/deck.colpkg').isOfficialFirst, isFalse);
    expect(
      plan(flags: capableFlags.copyWith(officialFirstImport: false))
          .isOfficialFirst,
      isFalse,
    );
    expect(
      plan(flags: capableFlags.copyWith(projection: false)).isOfficialFirst,
      isFalse,
    );
    expect(plan(filePath: '/tmp/deck.apkg.bak').isOfficialFirst, isFalse);
  });
}
