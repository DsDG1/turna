import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';

void main() {
  late UnifiedAnkiImportOrchestrator orchestrator;

  setUp(() {
    orchestrator = UnifiedAnkiImportOrchestrator.instance;
    orchestrator.reset();
  });

  tearDown(() => orchestrator.reset());

  group('UnifiedAnkiImportOrchestrator', () {
    test('Official-capable path writes no Turna SRS and reconciles 1:1',
        () async {
      final persisted = <UnifiedAnkiImportRequest>[];
      orchestrator.persistIdentity = (request) async {
        persisted.add(request);
      };
      final result = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-official',
          sourceHash: 'hash-a',
          canonicalCardIds: [10, 11, 12],
          officialCapable: true,
        ),
      );
      expect(result.wroteTurnaSrs, isFalse);
      expect(result.noOp, isFalse);
      expect(result.canonicalCardCount, 3);
      expect(result.placementCount, 3);
      expect(result.presentationCount, 3);
      expect(result.cardinalityOk, isTrue);
      expect(result.turnaSrsWordIds, isEmpty);
      expect(orchestrator.turnaSrsWordIds, isEmpty);
      expect(persisted, hasLength(1));
      expect(persisted.single.canonicalCardIds, [10, 11, 12]);
    });

    test('legacy path still registers Turna SRS ids 1:1', () async {
      final result = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-legacy',
          sourceHash: 'hash-legacy',
          canonicalCardIds: [1, 2],
          officialCapable: false,
        ),
      );
      expect(result.wroteTurnaSrs, isTrue);
      expect(result.turnaSrsWordIds, {
        'anki-imp-legacy-c1',
        'anki-imp-legacy-c2',
      });
      expect(result.cardinalityOk, isTrue);
    });

    test('same source hash second import is a no-op', () async {
      const request = UnifiedAnkiImportRequest(
        importId: 'imp-same',
        sourceHash: 'hash-same',
        canonicalCardIds: [21, 22, 23, 24],
        officialCapable: true,
      );
      final first = await orchestrator.importPackage(request);
      expect(first.noOp, isFalse);
      expect(first.canonicalCardCount, 4);

      final second = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-same',
          sourceHash: 'hash-same',
          canonicalCardIds: [21, 22, 23, 24, 99],
          officialCapable: true,
        ),
      );
      expect(second.noOp, isTrue);
      expect(second.wroteTurnaSrs, isFalse);
      expect(second.canonicalCardCount, 4);
      expect(second.placementCount, 4);
      expect(second.presentationCount, 4);
      expect(orchestrator.placementCount('imp-same'), 4);
    });

    test('lookupByHash same-hash begin skips persist', () async {
      orchestrator.lookupByHash = (hash) async => hash == 'disk-hash';
      var persisted = 0;
      orchestrator.persistIdentity = (_) async {
        persisted++;
      };
      final result = await orchestrator.begin(
        const UnifiedAnkiImportRequest(
          importId: 'imp-disk',
          sourceHash: 'disk-hash',
          canonicalCardIds: [1, 2, 3],
          officialCapable: true,
        ),
      );
      expect(result.noOp, isTrue);
      expect(result.wroteTurnaSrs, isFalse);
      expect(persisted, 0);
    });

    test('import UI probes identity before assemble', () {
      final screen =
          File('lib/views/anki/anki_import_screen.dart').readAsStringSync();
      final beginAt = screen.indexOf('UnifiedAnkiImportOrchestrator.instance.begin');
      final assembleAt = screen.indexOf('assembler.assemble(');
      expect(beginAt, greaterThan(0));
      expect(assembleAt, greaterThan(beginAt));
      expect(screen.contains('if (unifiedBegin.noOp)'), isTrue);
      expect(screen.contains('facade.importOfficialOrNull'), isTrue);
      expect(
        screen.contains('!unifiedBegin.noOp') ||
            screen.contains('&& !unifiedBegin.noOp'),
        isTrue,
      );
    });
  });
}
