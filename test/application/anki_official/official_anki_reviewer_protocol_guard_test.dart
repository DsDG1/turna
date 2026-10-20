import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';

/// Protocol symmetry guard for the Dart↔ArkTS reviewer seam (R0 of the
/// 2026-10-17 review refactor plan).
///
/// The two halves of the wire contract live in
/// [OfficialAnkiReviewerProtocol] (Dart) and
/// `ohos/entry/src/main/ets/anki/AnkiReviewerProtocol.ets` (ArkTS). They are
/// separate implementations of one protocol — a rename on either side is a
/// silent `MissingPluginException` or a receipt nobody classifies, and it
/// only shows up when someone opens a card on a device. This test parses
/// BOTH sources as text and fails on any constant that does not pair up,
/// name (camelCase ↔ UPPER_SNAKE) and value alike, in both directions.
///
/// A constant may exist on one side only through the explicit
/// allowed-difference lists below ([_dartOnly], [_arktsOnly]), each entry
/// carrying its reason. Anything else one-sided is drift.
///
/// Deliberate asymmetries that are OUT of this guard's scope (do not "fix"
/// them into a regression; recorded in the Dart protocol module's doc too):
///
/// * The Android/iOS ack shape (`{ok, code, generation, side, height,
///   recoverable}`, decoded by `OfficialAnkiPresentResult.fromNative`) is a
///   separate contract from the OHOS ack shape and is not unified.
/// * Range/MIME has three implementations by design: Dart's
///   `OfficialAnkiHttpRange`/`OfficialAnkiMime` are the normative source,
///   `anki/AnkiHttp.ets` is the production ArkTS mirror, and the probe keeps a
///   deliberately looser copy. The probe's three accepted differences are
///   enumerated and pinned in [_rangeMimeAllowedDifferences] below, so neither
///   copy can be silently replaced by the other. `originAllowed` separately
///   normalises port -1 (Dart URL) vs 0 (ArkTS URL).
const _dartProtocolPath =
    'lib/application/anki_official/render/official_anki_reviewer_protocol.dart';
const _arktsProtocolPath =
    'ohos/entry/src/main/ets/anki/AnkiReviewerProtocol.ets';
const _arktsSessionPath =
    'ohos/entry/src/main/ets/anki/AnkiReviewerSession.ets';

/// The probe's own Range/MIME pair moved under `ets/probe/` in R1; its
/// production counterpart stayed in `ets/anki/`.
const _arktsProbeHttpPath = 'ohos/entry/src/main/ets/probe/AnkiProbeAssets.ets';
const _arktsProdHttpPath = 'ohos/entry/src/main/ets/anki/AnkiHttp.ets';

/// The declared differences between the probe's Range/MIME copy and the
/// production mirror — the machine-checkable half of the list written at the top
/// of [_arktsProbeHttpPath].
///
/// Each row asserts BOTH sides, because the failure this guards against runs in
/// both directions: someone copying the production implementation over the probe
/// (silently making the probe stricter, so a Range the probe cannot classify
/// answers 416 and the probe reports nothing at all), and someone copying the
/// probe over production (silently making the reviewer a server that answers 200
/// to every Range, which is one the kernel cannot seek in). Either way the
/// documented reason stops being true, so the row that described it has to go
/// with it — which is why these are needles on both sides rather than a note.
const _rangeMimeAllowedDifferences = <({
  String axis,
  String why,
  String probeNeedle,
  String prodNeedle,
})>[
  (
    axis: 'parseRange: unrecognized Range prefix',
    why: 'the probe still has to leave something to measure when it cannot '
        'classify the header; production must refuse, because a server that '
        'answers 200 to every Range is one the kernel cannot seek in',
    probeNeedle:
        r"if \(!raw\.toLowerCase\(\)\.startsWith\(prefix\)\)\s*\{\s*return whole;",
    prodNeedle:
        r"if \(!lower\.startsWith\('bytes='\)\)\s*\{\s*return unsatisfiable\(length\);",
  ),
  (
    axis: 'parseRange: unparseable Range spec',
    why: 'no dash, an empty spec, or a multi-range comma all fall back to the '
        'whole file on the probe side and to 416 on the production side, for '
        'the same reason as the prefix axis',
    probeNeedle: r"if \(dash <= 0\)\s*\{\s*return whole;",
    prodNeedle: r"if \(dash < 0\)\s*\{\s*return unsatisfiable\(length\);",
  ),
  (
    axis: 'mimeForName: .js',
    why: 'the kernel accepts both spellings; the probe serves four asset kinds '
        'and has no application/json, so the narrower production table would be '
        'dead code on that side',
    probeNeedle: r"'\.js': 'application/javascript'",
    prodNeedle: r"lower\.endsWith\('\.js'\)\)\s*\{\s*return 'text/javascript';",
  ),
  (
    axis: 'encodingForMime: utf-8 branch set',
    why: 'production gates on text/* or application/json after stripping the '
        '; parameters; the probe gates on text/* or anything ending in '
        'javascript, which is the only difference its own MIME table needs',
    probeNeedle:
        r"mime\.startsWith\('text/'\) \|\| mime\.endsWith\('javascript'\)",
    prodNeedle: r"base\.startsWith\('text/'\) \|\| base === 'application/json'",
  ),
];

/// Constants that exist only on the Dart side, each with why.
const _dartOnly = <String, String>{
  'ackFieldType': 'ArkTS declares ack keys as RenderAck interface members in '
      'AnkiReviewerSession.ets; constants cannot name interface fields, so '
      'the interface is needle-checked by this test instead.',
  'ackFieldSide': 'Same reason as ackFieldType.',
  'ackFieldGeneration': 'Same reason as ackFieldType.',
  'ackFieldStableCode': 'Same reason as ackFieldType.',
  'payloadSourceProgress':
      'ArkTS reads payload keys as ReviewerPresentPayload interface members in '
          'AnkiReviewerSession.ets, because a typed interface cannot be indexed by '
          'a constant. The field names are therefore needle-checked there instead '
          'of being mirrored as constants.',
  'payloadCanRedo': 'Same reason as payloadSourceProgress.',
  'payloadCanMutate': 'Same reason as payloadSourceProgress.',
  'payloadChromeTheme': 'Same reason as payloadSourceProgress.',
  'payloadAutoComplete': 'Same reason as payloadSourceProgress.',
};

/// Constants that exist only on the ArkTS side, each with why.
const _arktsOnly = <String, String>{
  'RENDER_ERROR':
      'ArkTS fallback failure code when a report carries no code at all '
          '(session present catch-up, plugin notifyReviewerFailure default). '
          'Dart never compares this value — it falls through to the fatal '
          'default — so it has no Dart twin.',
};

/// The failure-classification sets that must mirror element-for-element.
const _mirroredSets = <String>{
  'recoverableCodes',
  'fatalCodes',
};

void main() {
  group('reviewer protocol symmetry (Dart ↔ ArkTS)', () {
    late final String dartSource;
    late final String arktsSource;

    setUpAll(() {
      dartSource = File(_dartProtocolPath).readAsStringSync();
      arktsSource = File(_arktsProtocolPath).readAsStringSync();
    });

    test('scalar vocabulary pairs one-to-one, name and value', () {
      final dart = _dartScalars(dartSource);
      final arkts = _arktsScalars(arktsSource);
      expect(dart, isNotEmpty, reason: 'Dart protocol source unreadable');
      expect(arkts, isNotEmpty, reason: 'ArkTS protocol source unreadable');

      final dartExpectedOnArkts = dart.keys
          .where((camel) => !_dartOnly.containsKey(camel))
          .map(_upperSnake)
          .toSet();
      final arktsExpectedOnDart =
          arkts.keys.where((name) => !_arktsOnly.containsKey(name)).toSet();

      final missingOnArkTS = dartExpectedOnArkts.difference(arkts.keys.toSet());
      expect(
        missingOnArkTS,
        isEmpty,
        reason: 'constants declared in $_dartProtocolPath but missing from '
            '$_arktsProtocolPath (or renamed there): $missingOnArkTS',
      );

      final missingOnDart =
          arktsExpectedOnDart.difference(dart.keys.map(_upperSnake).toSet());
      expect(
        missingOnDart,
        isEmpty,
        reason: 'constants exported by $_arktsProtocolPath but absent from '
            '$_dartProtocolPath — add them there or list them in _arktsOnly '
            'with a reason: $missingOnDart',
      );

      for (final entry in dart.entries) {
        final arktsName = _upperSnake(entry.key);
        if (_dartOnly.containsKey(entry.key)) continue;
        expect(
          arkts[arktsName],
          entry.value,
          reason: '$arktsName drifted between the two protocol sources: Dart '
              '${entry.key}=${entry.value} vs ArkTS '
              '${arkts[arktsName]}',
        );
      }
    });

    test('failure classification sets mirror element-for-element', () {
      final dartSets = _dartSets(dartSource);
      final arktsSets = _arktsArrays(arktsSource);
      for (final name in _mirroredSets) {
        final arktsName = _upperSnake(name);
        expect(
          dartSets[name],
          isNotNull,
          reason: '$_dartProtocolPath no longer declares set $name — update '
              'this test if the set was deliberately removed on both sides',
        );
        expect(
          arktsSets[arktsName],
          isNotNull,
          reason: '$_arktsProtocolPath no longer declares $arktsName',
        );
        expect(
          dartSets[name]!.difference(arktsSets[arktsName]!),
          isEmpty,
          reason: '$name has members Dart classifies but ArkTS does not: '
              '${dartSets[name]!.difference(arktsSets[arktsName]!)} — the '
              'page would offer retry for failures Dart calls fatal',
        );
        expect(
          arktsSets[arktsName]!.difference(dartSets[name]!),
          isEmpty,
          reason: '$arktsName has members ArkTS knows but Dart does not: '
              '${arktsSets[arktsName]!.difference(dartSets[name]!)}',
        );
      }
    });

    test('rating receipt codes are ten distinct values', () {
      // A duplicated value would silently alias two branches on the page and
      // one of the aliasing constants would read as dead vocabulary.
      final receipts = <String>{
        OfficialAnkiReviewerProtocol.receiptOk,
        OfficialAnkiReviewerProtocol.receiptOkComplete,
        OfficialAnkiReviewerProtocol.receiptAnswerNotReady,
        OfficialAnkiReviewerProtocol.receiptSchedulerBusy,
        OfficialAnkiReviewerProtocol.receiptCardMismatch,
        OfficialAnkiReviewerProtocol.receiptSessionClosed,
        OfficialAnkiReviewerProtocol.receiptEngineError,
        OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable,
        OfficialAnkiReviewerProtocol.receiptNoCard,
        OfficialAnkiReviewerProtocol.receiptAdvanceFailed,
      };
      expect(receipts, hasLength(10));
    });

    test('classification sets are disjoint; renderTimeout is recoverable', () {
      final overlap = OfficialAnkiReviewerProtocol.recoverableCodes
          .intersection(OfficialAnkiReviewerProtocol.fatalCodes);
      expect(overlap, isEmpty,
          reason: 'a code cannot be both retryable and '
              'fatal — the page and the controller would disagree about whether '
              'to offer retry');
      expect(
        OfficialAnkiReviewerProtocol.recoverableCodes,
        contains(OfficialAnkiReviewerProtocol.renderTimeout),
        reason: 'both sides synthesise renderTimeout as a recoverable '
            'give-up; if it moves sets, update the ArkTS mirror too',
      );
    });

    test('OHOS ack field names are declared by the ArkTS RenderAck interface',
        () {
      final sessionSource = File(_arktsSessionPath).readAsStringSync();
      final interfaceBody = RegExp(
        r'export interface RenderAck \{([^}]*)\}',
        dotAll: true,
      ).firstMatch(sessionSource);
      expect(
        interfaceBody,
        isNotNull,
        reason: 'RenderAck interface not found in $_arktsSessionPath — if it '
            'moved, update this test and the protocol module doc together',
      );
      final body = interfaceBody!.group(1)!;
      // These four are the fields the Dart binding actually branches on
      // (_applyAck); the interface may declare more (frame-authored ack).
      for (final field in const [
        OfficialAnkiReviewerProtocol.ackFieldType,
        OfficialAnkiReviewerProtocol.ackFieldSide,
        OfficialAnkiReviewerProtocol.ackFieldGeneration,
        OfficialAnkiReviewerProtocol.ackFieldStableCode,
      ]) {
        expect(
          body.contains('$field?:'),
          isTrue,
          reason: 'RenderAck no longer declares a "$field" member — the Dart '
              'binding reads ack["$field"], which would silently fall back to '
              'defaults and turn every ack into a timeout-shaped failure',
        );
      }
    });

    test('a present with no generation is refused before the frame runs', () {
      final sessionSource = File(_arktsSessionPath).readAsStringSync();
      expect(sessionSource, contains('parsePresentPayload('));
      expect(sessionSource, contains('PRESENT_PAYLOAD_INVALID'));
      expect(
        sessionSource,
        contains('ackGeneration !== undefined && ackGeneration === generation'),
        reason: 'an ack with no generation must not settle the current present',
      );
      expect(
        sessionSource,
        isNot(contains("parts[1] ?? '0'")),
        reason: 'an empty generation field must not become generation 0',
      );
    });

    test('ArkTS payload parser only reads fields the Dart payloads emit', () {
      final sessionSource = File(_arktsSessionPath).readAsStringSync();
      final interfaceBody = RegExp(
        r'interface ReviewerPresentPayload \{([^}]*)\}',
        dotAll: true,
      ).firstMatch(sessionSource);
      expect(
        interfaceBody,
        isNotNull,
        reason: 'ReviewerPresentPayload not found in $_arktsSessionPath — if '
            'it moved, update this test',
      );
      final interfaceFields = RegExp(r'(\w+)\?')
          .allMatches(interfaceBody!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      const card = OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: 'q',
        answerHtml: 'a',
        questionDisplayHtml: 'q',
        answerDisplayHtml: 'a',
        css: '',
      );
      final emittedKeys = <String>{
        ...officialAnkiReviewerPayload(
          card: card,
          generation: 1,
          showingAnswer: false,
          dark: false,
        ).keys,
        ...ohosReviewerPayload(
          card: card,
          generation: 1,
          showingAnswer: false,
          dark: false,
        ).keys,
      };

      final unknown = interfaceFields.difference(emittedKeys);
      expect(
        unknown,
        isEmpty,
        reason: 'AnkiReviewerSession parses payload fields Dart never sends: '
            '$unknown — either dead parsing or a renamed field on one side',
      );
    });

    test('allowed-difference lists still match real declarations', () {
      // The lists above are the only one-sided escape hatch; an entry whose
      // constant has since been deleted would silently stop guarding.
      final dart = _dartScalars(dartSource).keys.toSet();
      for (final name in _dartOnly.keys) {
        expect(dart, contains(name),
            reason: '_dartOnly lists $name, which no longer exists — remove '
                'the entry');
      }
      final arkts = _arktsScalars(arktsSource).keys.toSet();
      for (final name in _arktsOnly.keys) {
        expect(arkts, contains(name),
            reason: '_arktsOnly lists $name, which no longer exists — remove '
                'the entry');
      }
    });

    test('probe Range/MIME keeps both sides of its declared differences', () {
      final probeSource = _readArkts(_arktsProbeHttpPath);
      final prodSource = _readArkts(_arktsProdHttpPath);
      for (final diff in _rangeMimeAllowedDifferences) {
        expect(
          RegExp(diff.probeNeedle).hasMatch(probeSource),
          isTrue,
          reason: '${diff.axis}: $_arktsProbeHttpPath no longer shows the '
              'declared probe behaviour — ${diff.why} Restore it, or close the '
              'difference on purpose and update this table together with the '
              'header of that file.',
        );
        expect(
          RegExp(diff.prodNeedle).hasMatch(prodSource),
          isTrue,
          reason: '${diff.axis}: $_arktsProdHttpPath no longer shows the '
              'declared production behaviour — ${diff.why} If the two copies '
              'have silently converged, update this table together with the '
              'probe header in the same commit.',
        );
      }
    });
  });
}

String _readArkts(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason:
          '$path is missing — if it was relocated, update the path constant '
          'next to the allowed-difference table it is read through');
  return file.readAsStringSync();
}

Map<String, String> _dartScalars(String source) {
  final result = <String, String>{};
  for (final match
      in RegExp(r"static const (\w+) = '([^']*)';").allMatches(source)) {
    result[match.group(1)!] = match.group(2)!;
  }
  return result;
}

Map<String, String> _arktsScalars(String source) {
  final result = <String, String>{};
  for (final match in RegExp(
    r"export const (\w+): string = '([^']*)';",
  ).allMatches(source)) {
    result[match.group(1)!] = match.group(2)!;
  }
  return result;
}

Map<String, Set<String>> _dartSets(String source) {
  final result = <String, Set<String>>{};
  for (final match in RegExp(r'static const (\w+) = <String>\{([^}]*)\};')
      .allMatches(source)) {
    result[match.group(1)!] = _splitElements(match.group(2)!);
  }
  return result;
}

Map<String, Set<String>> _arktsArrays(String source) {
  final result = <String, Set<String>>{};
  for (final match in RegExp(
    r'export const (\w+): Array<string> = \[([^\]]*)\];',
  ).allMatches(source)) {
    result[match.group(1)!] = _splitElements(match.group(2)!);
  }
  return result;
}

Set<String> _splitElements(String raw) {
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => e.replaceAll("'", '').replaceAll('"', ''))
      .toSet();
}

String _upperSnake(String camel) => camel
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    )
    .toUpperCase();
