// crash-hunt 2026-09-02: the import wizard's PopScope(canPop: false)
// handler retried blocked pops with `context.router.maybePop()`. With canPop
// permanently false that is an infinite microtask loop — each round trips
// the pop callback, re-resolves `context.router` through the whole element
// tree and re-enters maybePop: on-device it presented as ~100 scavenges/s
// (1.6GB/s short-lived allocations), 100% main-isolate CPU, a frozen
// import-done screen and an ANR kill on the next touch (导入后点「开始学习/
// 完成/返回/取消并清理」卡死闪退). The fix pops unconditionally after the
// confirm (router.pop bypasses the canPop gate — same shape as the
// ai_api_config_page fix). This guard keeps maybePop out of every leave
// path so the landmine cannot be reintroduced.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/views/anki/anki_import_screen.dart',
  ).readAsStringSync();

  group('import wizard pop-loop guard (crash-hunt)', () {
    test('no leave path retries with maybePop behind the canPop gate', () {
      expect(
        RegExp(r'\.maybePop\(').hasMatch(source),
        isFalse,
        reason:
            'AnkiImportPage sits behind PopScope(canPop: false); any '
            'maybePop in it re-enters the blocked-pop callback forever. '
            'Leave via context.router.pop() (bypasses the gate) instead.',
      );
    });

    test('pop handler and back arrow pop unconditionally after confirm', () {
      expect(
        source.contains(RegExp(r'leave && context\.mounted\) context\.router\.pop\(\)')),
        isTrue,
        reason: 'both confirm-gated leave paths must bypass the canPop gate',
      );
    });
  });
}
