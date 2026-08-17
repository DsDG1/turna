import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';

void main() {
  test('rapid question/answer/question supersedes and keeps newest height', () async {
    final gate = OfficialAnkiPresentGate();
    final started = <int>[];
    final completers = <int, Completer<OfficialAnkiPresentResult>>{};

    Future<OfficialAnkiPresentResult> enqueue(int generation) {
      return gate.run(generation, () {
        started.add(generation);
        final completer = Completer<OfficialAnkiPresentResult>();
        completers[generation] = completer;
        return completer.future;
      });
    }

    final q1 = enqueue(1);
    final a2 = enqueue(2);
    final q3 = enqueue(3);
    expect(started, [1, 2, 3]);

    completers[1]!.complete(
      const OfficialAnkiPresentResult(
        ok: true,
        generation: 1,
        side: 'question',
        height: 11,
      ),
    );
    completers[2]!.complete(
      const OfficialAnkiPresentResult(
        ok: false,
        code: OfficialAnkiPresentResult.supersededCode,
        generation: 2,
        side: 'answer',
        recoverable: true,
      ),
    );
    completers[3]!.complete(
      const OfficialAnkiPresentResult(
        ok: true,
        generation: 3,
        side: 'question',
        height: 33,
      ),
    );

    final results = await Future.wait([q1, a2, q3]);
    expect(results[1].isSuperseded, isTrue);
    expect(results[1].ok, isFalse);
    expect(results[2].ok, isTrue);
    expect(results[2].height, 33);
    expect(results[2].generation, 3);
    expect(results[2].side, 'question');
    expect(gate.lastHeight, 33);
    expect(gate.shouldApplyHeight(1, 99), isFalse);
    expect(gate.lastHeight, 33);
    expect(gate.inFlight, 0);
  });

  test('fromNative reads ok/code/generation/side', () {
    final parsed = OfficialAnkiPresentResult.fromNative(<String, Object?>{
      'ok': false,
      'code': 'RENDER_SUPERSEDED',
      'generation': 4,
      'side': 'answer',
      'height': 20,
      'recoverable': true,
    });
    expect(parsed.ok, isFalse);
    expect(parsed.code, 'RENDER_SUPERSEDED');
    expect(parsed.generation, 4);
    expect(parsed.side, 'answer');
    expect(parsed.isSuperseded, isTrue);
    expect(parsed.recoverable, isTrue);
  });
}
