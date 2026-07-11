// Unit-level tests for Piper init Completer join semantics (Phase 21).
// Does not load the real ONNX model — exercises a test double of the
// "wait for in-flight init" pattern used by PiperSwahiliTts._init.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors PiperSwahiliTts Completer join (no busy-wait).
class _InitGate {
  Completer<void>? _initCompleter;
  bool initializing = false;
  int startCount = 0;
  int finishCount = 0;
  Duration workDelay = const Duration(milliseconds: 30);

  Future<void> init() async {
    final inFlight = _initCompleter;
    if (inFlight != null) {
      await inFlight.future;
      return;
    }

    final completer = Completer<void>();
    _initCompleter = completer;
    initializing = true;
    startCount++;
    try {
      await Future<void>.delayed(workDelay);
      finishCount++;
      if (!completer.isCompleted) completer.complete();
    } finally {
      initializing = false;
      _initCompleter = null;
    }
  }
}

void main() {
  test('concurrent init awaits one in-flight work unit (no polling)', () async {
    final gate = _InitGate();

    await Future.wait([gate.init(), gate.init(), gate.init()]);

    expect(gate.startCount, 1);
    expect(gate.finishCount, 1);
    expect(gate.initializing, isFalse);
  });

  test('sequential inits after first completes run again', () async {
    final gate = _InitGate()..workDelay = const Duration(milliseconds: 5);

    await gate.init();
    await gate.init();

    expect(gate.startCount, 2);
    expect(gate.finishCount, 2);
  });
}
