// Contract integrity cross-check (doc 39 P2): the Dart single table, the
// ENGINE_INFO golden fixture, and `contract/operations.md` must agree.
// This merges the assertions that used to live scattered in
// official_anki_scheduler_p4_test, official_anki_render_contract_test, and
// official_anki_contract_test.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';

void main() {
  final doc =
      File('native/turna_anki_core/contract/operations.md').readAsStringSync();
  final golden = jsonDecode(
    File('native/turna_anki_core/contract/fixtures/response_engine_info.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final caps = Set<String>.from((golden['payload'] as Map)['capabilities']);

  test('single id table stays aligned with operations.md (append-only)', () {
    expect(OfficialAnkiOperation.ids, isNotEmpty);
    for (final entry in OfficialAnkiOperation.ids.entries) {
      expect(
        doc.contains('| ${entry.value} | ${entry.key} |'),
        isTrue,
        reason: 'operations.md lost row | ${entry.value} | ${entry.key} |',
      );
    }
    // productionNames is the Dart-callable subset: every name resolves.
    for (final name in OfficialAnkiOperation.productionNames) {
      expect(OfficialAnkiOperation.ids.containsKey(name), isTrue,
          reason: '$name has no id');
      expect(OfficialAnkiOperation.idFor(name), isNotNull);
    }
    // DESCRIBE_NEXT_STATES (13) is retired from the Dart face (doc 39 P1-E)
    // but must keep its operations.md row on the Rust side.
    expect(doc.contains('| 13 | DESCRIBE_NEXT_STATES |'), isTrue);
    expect(
      OfficialAnkiOperation.ids.containsKey('DESCRIBE_NEXT_STATES'),
      isFalse,
    );
  });

  test('productionNames are a subset of the golden capabilities', () {
    // Subset, not equality: the Rust side may keep advertising ops the Dart
    // surface no longer calls (append-only policy).
    expect(
      caps.containsAll(OfficialAnkiOperation.productionNames),
      isTrue,
      reason: 'golden capabilities missing: '
          '${OfficialAnkiOperation.productionNames.difference(caps).toList()}',
    );
  });

  test('golden capabilities match the Rust contract list', () {
    // Doc 39 P2 repaired the fixture drift (RESTORE_BACKUP was missing when
    // minor was bumped to 1.10). Pin the count so the next manual bump
    // cannot silently drop an op again; regen via gen_fixtures on the
    // toolchain host must produce an identical list.
    expect(caps.length, 39, reason: caps.toList().join(','));
    expect(caps.contains('RESTORE_BACKUP'), isTrue);
    expect(caps.containsAll(<String>[
      'RENDER_CARD',
      'COMPARE_TYPED_ANSWER',
      'EXTRACT_CLOZE_FOR_TYPING',
      'GET_REVIEW_QUEUE',
      'REDO',
      'DELETE_NOTES',
      'SCHEDULE_CARDS_AS_NEW',
      'ANSWER_AHEAD_CARDS',
      'ENSURE_TODAY_NEW_QUOTA',
      'GET_PROJECTION_SCHEMAS',
    ]), isTrue);
  });

  test('fixture, VERSION file, and Dart constants agree on the version', () {
    expect((golden['payload'] as Map)['contractMajor'],
        kOfficialAnkiContractMajor);
    expect((golden['payload'] as Map)['contractMinor'],
        kOfficialAnkiContractMinor);
    expect(
      File('native/turna_anki_core/contract/VERSION')
          .readAsStringSync()
          .trim(),
      '$kOfficialAnkiContractMajor.$kOfficialAnkiContractMinor',
    );
  });

  test('scheduler operation ids stay pinned', () {
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.setCurrentDeck), 11);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.getReviewQueue), 12);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.answerCard), 14);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.getUndoStatus), 15);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.undo), 16);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.redo), 27);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.buryOrSuspendCards), 28);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.countsForDeckToday), 29);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.congratsInfo), 30);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.deleteNotes), 31);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.deleteCards), 32);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.statsForCardsBatch), 33);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.scheduleCardsAsNew), 34);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.answerAheadCards), 35);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.ensureTodayNewQuota), 36);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.gcUnusedMedia), 37);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.pruneEmptyMetadata), 38);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.compactCollection), 39);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.diffCollectionCheckpoint), 40);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.renderCard), 10);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.compareTypedAnswer), 22);
    expect(
      OfficialAnkiOperation.idFor(OfficialAnkiOperation.extractClozeForTyping),
      23,
    );
  });
}
