import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/import/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

OfficialAnkiFeatureFlags _fullOfficial({bool officialFirst = true}) {
  return OfficialAnkiFeatureFlags.productionAndroid.copyWith(
    officialFirstImport: officialFirst,
  );
}

void main() {
  const planner = AnkiImportExecutionPlanner();

  group('AnkiImportExecutionPlanner atomic outcomes', () {
    test('android production apkg is officialFirst with coherent writers', () {
      final plan = planner.resolve(
        flags: _fullOfficial(),
        platform: 'android',
        cutoverEnabled: true,
        libraryAvailable: true,
        filePath: '/tmp/deck.apkg',
      );
      expect(plan.productMode, AnkiProductMode.officialAndroid);
      expect(plan.kind, AnkiImportExecutionKind.officialFirst);
      expect(plan.owner, AnkiImportOwner.official);
      expect(plan.writesOfficialCollection, isTrue);
      expect(plan.writesLegacyNoteStore, isFalse);
      expect(plan.writesTurnaAnkiSrs, isFalse);
      expect(plan.facadeDecision, AnkiImportDecision.official);
      expect(plan.persistedOwnerIsOfficial, isTrue);
    });

    test('missing native library fails closed with zero writers', () {
      final plan = planner.resolve(
        flags: _fullOfficial(),
        platform: 'android',
        cutoverEnabled: true,
        libraryAvailable: false,
        filePath: '/tmp/deck.apkg',
      );
      expect(plan.kind, AnkiImportExecutionKind.failClosed);
      expect(plan.owner, isNull);
      expect(plan.writesLegacyNoteStore, isFalse);
      expect(plan.writesTurnaAnkiSrs, isFalse);
      expect(plan.writesOfficialCollection, isFalse);
      expect(plan.facadeDecision, AnkiImportDecision.failClosed);
      expect(plan.reason, contains('native_library'));
    });

    test('unsupported platforms never choose a Legacy writer', () {
      for (final plat in ['ohos', 'ios', 'windows', 'linux', 'macos', 'web']) {
        final plan = planner.resolve(
          flags: _fullOfficial(),
          platform: plat,
          cutoverEnabled: true,
          libraryAvailable: true,
            filePath: '/tmp/deck.apkg',
        );
        expect(plan.productMode, AnkiProductMode.ankiUnavailable, reason: plat);
        expect(plan.kind, AnkiImportExecutionKind.unsupported, reason: plat);
        expect(plan.owner, isNull, reason: plat);
        expect(plan.writesLegacyNoteStore, isFalse, reason: plat);
        expect(plan.writesTurnaAnkiSrs, isFalse, reason: plat);
        expect(plan.facadeDecision, AnkiImportDecision.failClosed, reason: plat);
      }
    });

    test('colpkg and bad extensions are unsupported without Legacy writes', () {
      final colpkg = planner.resolve(
        flags: _fullOfficial(),
        platform: 'android',
        cutoverEnabled: true,
        libraryAvailable: true,
        filePath: '/tmp/backup.colpkg',
      );
      expect(colpkg.kind, AnkiImportExecutionKind.unsupported);
      expect(colpkg.writesLegacyNoteStore, isFalse);

      final bad = planner.resolve(
        flags: _fullOfficial(),
        platform: 'android',
        cutoverEnabled: true,
        libraryAvailable: true,
        filePath: '/tmp/notes.txt',
      );
      expect(bad.kind, AnkiImportExecutionKind.unsupported);
      expect(bad.writesLegacyNoteStore, isFalse);
    });

    test('officialFirst flag off fails closed instead of mixed half-state', () {
      final plan = planner.resolve(
        flags: _fullOfficial(officialFirst: false),
        platform: 'android',
        cutoverEnabled: true,
        libraryAvailable: true,
        filePath: '/tmp/deck.apkg',
      );
      expect(plan.kind, AnkiImportExecutionKind.failClosed);
      expect(plan.writesLegacyNoteStore, isFalse);
      expect(plan.persistedOwnerIsOfficial, isFalse);
      expect(plan.reason, contains('official_first_required'));
    });

  });

  group('pre-fix mixed half-state cannot recur', () {
    test('production defaults no longer claim Official while writing Legacy',
        () {
      // Pre-fix combo: cutover+official flags on, officialFirst off, library
      // ok → old code wrote Legacy NoteStore while claiming Official owner.
      final flags = _fullOfficial(officialFirst: false);
      final decision = AnkiImportFacade.decisionFor(
        flags,
        platform: 'android',
        libraryAvailable: true,
      );
      final plan = AnkiImportFacade.planFor(
        flags,
        platform: 'android',
        libraryAvailable: true,
        filePath: '/tmp/deck.apkg',
      );

      // After the fix: fail closed — no Legacy writer under an Official claim.
      expect(decision, AnkiImportDecision.failClosed);
      expect(plan.kind, AnkiImportExecutionKind.failClosed);
      expect(plan.writesLegacyNoteStore, isFalse);
      expect(plan.persistedOwnerIsOfficial, isFalse);
    });

    test('unified request owner matches plan writers for officialFirst',
        () async {
      final plan = AnkiImportFacade.planFor(
        _fullOfficial(),
        platform: 'android',
        libraryAvailable: true,
        filePath: '/tmp/deck.apkg',
      );
      expect(plan.isOfficialFirst, isTrue);

      final orch = UnifiedAnkiImportOrchestrator(
        lookupByHash: (_) async => false,
        persistIdentity: (_) async {},
      );
      final result = await orch.importPackage(
        UnifiedAnkiImportRequest(
          importId: 'src-official',
          sourceHash: 'hash-official',
          canonicalCardIds: const [1, 2],
          persistedOwnerIsOfficial: plan.persistedOwnerIsOfficial,
        ),
      );
      expect(result.wroteTurnaSrs, isFalse);
      expect(plan.writesTurnaAnkiSrs, isFalse);
      expect(plan.writesLegacyNoteStore, isFalse);
      expect(plan.owner, AnkiImportOwner.official);
    });

    test('fromEnvironment defaults enable official-first on Android', () {
      final flags = OfficialAnkiFeatureFlags.fromEnvironment();
      expect(flags.officialFirstImport, isTrue);
      expect(flags.allowsOfficialFirstImport, isTrue);
      expect(LegacyAnkiMigrationFlags.cutoverEnabled, isTrue);

      final plan = AnkiImportFacade.planFor(
        flags,
        platform: 'android',
        libraryAvailable: true,
        filePath: 'deck.apkg',
      );
      expect(plan.kind, AnkiImportExecutionKind.officialFirst);
    });

    test('capability matrix never requires Legacy fallback writers', () {
      for (final plat in [
        'android',
        'ohos',
        'ios',
        'windows',
        'linux',
        'macos',
      ]) {
        final cap = OfficialAnkiCapabilityMatrix.forPlatform(
          plat,
          _fullOfficial(),
        );
        expect(cap.legacyFallbackRequired, isFalse, reason: plat);
      }
    });
  });

  group('combination matrix: writer == owner == facade decision', () {
    final platforms = ['android', 'ohos', 'ios', 'linux'];
    final libraryStates = [true, false];
    final firstStates = [true, false];

    for (final plat in platforms) {
      for (final libraryOk in libraryStates) {
        for (final first in firstStates) {
          test(
            'plat=$plat library=$libraryOk officialFirst=$first',
            () {
              final plan = planner.resolve(
                flags: _fullOfficial(officialFirst: first),
                platform: plat,
                cutoverEnabled: true,
                libraryAvailable: libraryOk,
                filePath: '/data/deck.apkg',
              );
              if (plan.createsSource) {
                // Doc 35 L1: the Legacy-only kind died with the parser — every
                // source-creating plan is Official-owned.
                expect(plan.owner, AnkiImportOwner.official);
                expect(plan.writesOfficialCollection, isTrue);
                expect(plan.writesLegacyNoteStore, isFalse);
                expect(plan.writesTurnaAnkiSrs, isFalse);
                expect(plan.facadeDecision, AnkiImportDecision.official);
              } else {
                expect(plan.writesLegacyNoteStore, isFalse);
                expect(plan.writesTurnaAnkiSrs, isFalse);
                expect(plan.writesOfficialCollection, isFalse);
                expect(plan.facadeDecision, AnkiImportDecision.failClosed);
              }
            },
          );
        }
      }
    }
  });

  test('Official-first service does not import a fail-closed plan', () async {
    final plan = planner.resolve(
      flags: _fullOfficial(officialFirst: false),
      platform: 'android',
      libraryAvailable: true,
      filePath: '/tmp/deck.apkg',
    );
    expect(plan.isOfficialFirst, isFalse);
    expect(
      await const OfficialAnkiOfficialFirstService().importPackage(
        filePath: '/tmp/deck.apkg',
        plan: plan,
      ),
      isNull,
    );
    expect(
      await const OfficialAnkiOfficialFirstService().importAndRecord(
        filePath: '/tmp/deck.apkg',
        plan: plan,
        importId: 'imp-1',
        hash: 'abc',
        cardCount: 0,
      ),
      isNull,
    );
  });
}
