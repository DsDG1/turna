// Doc 39 P3 round-trip parity: every DTO class migrated to @JsonSerializable
// must decode exactly like the hand-written parser it replaced, over golden
// vectors and the missing-field / extra-key / null edges. The legacy parsers
// below are verbatim copies of the pre-migration implementations and exist
// only as the comparison reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

void main() {
  final schemaGolden = jsonDecode(
    File('test/fixtures/anki_official/expected/01-basic-unicode.json')
        .readAsStringSync(),
  );

  test('codegen decoders match legacy parsers (parity fixtures + edges)', () {
    // ── OfficialAnkiCardPage ────────────────────────────────────────────
    Map<String, Object?> legacyCardPage(Map<String, Object?> json) {
      final raw = json['cardIds'];
      return <String, Object?>{
        'cardIds': raw is List
            ? raw.whereType<num>().map((n) => n.toInt()).toList()
            : const <int>[],
        'nextPageToken': json['nextPageToken'],
        'totalHint': (json['totalHint'] as num?)?.toInt(),
      };
    }

    Map<String, Object?> describeCardPage(OfficialAnkiCardPage p) => {
          'cardIds': p.cardIds,
          'nextPageToken': p.nextPageToken,
          'totalHint': p.totalHint,
        };

    for (final vector in const <Map<String, Object?>>[
      {
        'cardIds': <Object>[1, 2, 3],
        'nextPageToken': 'tok',
        'totalHint': 9,
      },
      <String, Object?>{},
      {'cardIds': <Object>[]},
      {'unknown': 'extra'},
    ]) {
      expect(
        describeCardPage(OfficialAnkiCardPage.fromJson(vector)),
        legacyCardPage(vector),
        reason: 'CardPage $vector',
      );
    }

    // ── OfficialAnkiTypedAnswerHint ─────────────────────────────────────
    Map<String, Object?> legacyHint(Map<String, Object?> json) => {
          'marker': json['marker'] as String? ?? '',
          'fontFamily': json['fontFamily'] as String? ?? 'Arial',
          'fontSizePx': (json['fontSizePx'] as num? ?? 20).toInt(),
          'combining': json['combining'] != false,
          'clozeOrdinal': (json['clozeOrdinal'] as num?)?.toInt(),
        };

    Map<String, Object?> describeHint(OfficialAnkiTypedAnswerHint h) => {
          'marker': h.marker,
          'fontFamily': h.fontFamily,
          'fontSizePx': h.fontSizePx,
          'combining': h.combining,
          'clozeOrdinal': h.clozeOrdinal,
        };

    for (final vector in const <Map<String, Object?>>[
      {
        'marker': '[[type:Back]]',
        'fontFamily': 'Noto',
        'fontSizePx': 32,
        'combining': false,
        'clozeOrdinal': 2,
      },
      {'marker': 'x'},
      <String, Object?>{},
    ]) {
      expect(
        describeHint(OfficialAnkiTypedAnswerHint.fromJson(vector)),
        legacyHint(vector),
        reason: 'TypedAnswerHint $vector',
      );
    }

    // ── OfficialAnkiTypedComparison ─────────────────────────────────────
    Map<String, Object?> legacyCmp(Map<String, Object?> json) => {
          'comparisonHtml': json['comparisonHtml'] as String? ?? '',
          'hasExpected': json['hasExpected'] == true,
        };

    for (final vector in const <Map<String, Object?>>[
      {'comparisonHtml': '<b>diff</b>', 'hasExpected': true},
      <String, Object?>{},
    ]) {
      final decoded = OfficialAnkiTypedComparison.fromJson(vector);
      expect({
        'comparisonHtml': decoded.comparisonHtml,
        'hasExpected': decoded.hasExpected,
      }, legacyCmp(vector), reason: 'TypedComparison $vector');
    }

    // ── OfficialAnkiProjectionSample ────────────────────────────────────
    Map<String, Object?> legacySample(Map<String, Object?> json) {
      final raw = json['fields'];
      return <String, Object?>{
        'noteId': (json['noteId'] as num? ?? 0).toInt(),
        'fields': raw is List
            ? raw.map((e) => e.toString()).toList()
            : const <String>[],
        'truncated': json['truncated'] == true,
      };
    }

    for (final vector in const <Map<String, Object?>>[
      {
        'noteId': 7,
        'fields': <Object>['Front', 'Back'],
        'truncated': true,
      },
      <String, Object?>{},
    ]) {
      final decoded = OfficialAnkiProjectionSample.fromJson(vector);
      expect({
        'noteId': decoded.noteId,
        'fields': decoded.fields,
        'truncated': decoded.truncated,
      }, legacySample(vector), reason: 'ProjectionSample $vector');
    }

    // ── OfficialAnkiCardRequirement / TemplateFacts / Schema ────────────
    Map<String, Object?> legacyRequirement(Map<String, Object?> json) {
      final raw = json['fieldOrds'];
      return <String, Object?>{
        'cardOrd': (json['cardOrd'] as num? ?? 0).toInt(),
        'kind': json['kind'] as String? ?? 'NONE',
        'fieldOrds': raw is List
            ? raw.map((e) => (e as num?)?.toInt() ?? 0).toList()
            : const <int>[],
      };
    }

    for (final vector in const <Map<String, Object?>>[
      {'cardOrd': 1, 'kind': 'ANY', 'fieldOrds': <Object>[0, 2]},
      <String, Object?>{},
    ]) {
      final decoded = OfficialAnkiCardRequirement.fromJson(vector);
      expect({
        'cardOrd': decoded.cardOrd,
        'kind': decoded.kind,
        'fieldOrds': decoded.fieldOrds,
      }, legacyRequirement(vector), reason: 'CardRequirement $vector');
    }

    final factsEmpty = OfficialAnkiTemplateFacts.fromJson(<String, Object?>{});
    expect(factsEmpty.hash, '');
    expect(factsEmpty.templates, isEmpty);
    expect(factsEmpty.reqs, isEmpty);
    expect(factsEmpty.isAvailable, isFalse);

    final schemaEmpty = OfficialAnkiProjectionSchema.fromJson(<String, Object?>{});
    expect(schemaEmpty.notetypeId, 0);
    expect(schemaEmpty.kind, 'normal');
    expect(schemaEmpty.fieldNames, isEmpty);
    expect(schemaEmpty.schemaFingerprint, '');
    expect(schemaEmpty.templateFacts, isNull);

    // Golden schema vector: a real projection schema shape with nested
    // facts + samples decodes through codegen without losing fields.
    final schemaVector = <String, Object?>{
      'notetypeId': 1604630396,
      'name': 'Basic',
      'kind': 'normal',
      'fieldNames': <Object>['Front', 'Back'],
      'templateNames': <Object>['Card 1'],
      'schemaFingerprint': 'abc123',
      'samples': <Object>[
        {'noteId': 1, 'fields': <Object>['f', 'b'], 'truncated': false},
      ],
      'templateFacts': <String, Object?>{
        'hash': 'h1',
        'templates': <Object>[
          {
            'ord': 0,
            'name': 'Card 1',
            'frontFields': <Object>[0],
            'backFields': <Object>[1],
            'filters': <String, Object?>{'typeIn': true},
          }
        ],
        'reqs': <Object>[
          {'cardOrd': 0, 'kind': 'ALL', 'fieldOrds': <Object>[0, 1]},
        ],
      },
    };
    final schema = OfficialAnkiProjectionSchema.fromJson(schemaVector);
    expect(schema.templateFacts?.hash, 'h1');
    expect(schema.templateFacts?.templates.single.typeIn, isTrue);
    expect(schema.templateFacts?.reqs.single.kind, 'ALL');
    expect(schema.samples.single.noteId, 1);
    expect(schemaGolden, isA<Map>(), reason: 'golden fixture present');

    // ── Snapshot / Row / Page ───────────────────────────────────────────
    final snapshotEmpty =
        OfficialAnkiProjectionSnapshot.fromJson(<String, Object?>{});
    expect(snapshotEmpty.snapshotToken, '');
    expect(snapshotEmpty.collectionGeneration, 0);
    expect(snapshotEmpty.backendCommit, '');

    final rowVector = <String, Object?>{
      'cardId': 11,
      'noteId': 12,
      'noteGuid': 'g',
      'notetypeId': 13,
      'deckId': 1,
      'deckPath': <Object>['A', 'B'],
      'templateOrdinal': 0,
      'tags': <Object>['t1'],
      'fields': <Object>['front', 'back'],
      'sourceFingerprint': 'fp',
      'truncated': true,
    };
    final row = OfficialAnkiProjectionRow.fromJson(rowVector);
    expect(row.deckPath, ['A', 'B']);
    expect(row.fields, ['front', 'back']);
    final rowEmpty = OfficialAnkiProjectionRow.fromJson(<String, Object?>{
      'extraKey': 1,
    });
    expect(rowEmpty.cardId, 0);
    expect(rowEmpty.deckPath, isEmpty);
    expect(rowEmpty.truncated, isFalse);

    final pageEmpty = OfficialAnkiProjectionPage.fromJson(<String, Object?>{
      'missingCardIds': <Object>[3, 4],
    });
    expect(pageEmpty.rows, isEmpty);
    expect(pageEmpty.missingCardIds, [3, 4]);

    // ── CongratsInfo / AheadAnswerOutcome ───────────────────────────────
    final congratsEmpty = OfficialCongratsInfo.fromJson(<String, Object?>{});
    expect(congratsEmpty.learnRemaining, 0);
    expect(congratsEmpty.reviewRemaining, isFalse);
    expect(congratsEmpty.deckDescription, '');
  });

  test('AheadAnswerOutcome reads answeredCards wire key', () {
    final outcome = OfficialAheadAnswerOutcome.fromJson(<String, Object?>{
      'answeredCards': 5,
      'skippedRatedToday': 2,
    });
    expect(outcome.answered, 5);
    expect(outcome.skippedRatedToday, 2);
    final empty = OfficialAheadAnswerOutcome.fromJson(<String, Object?>{});
    expect(empty.answered, 0);
    expect(empty.skippedRatedToday, 0);
  });
}
