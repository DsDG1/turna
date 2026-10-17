import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guard for the OHOS header's redo / bury / suspend entries (D8).
///
/// The ArkUI page cannot be unit-tested from Dart: `isHarmonyOsTarget` is
/// compile-time on this side, and ArkTS has no test host here. What *can* be
/// checked is that the four files still form the chain they are supposed to —
/// chrome button → page handler → bridge method → protocol constant — and that
/// the page names its actions through the protocol constants rather than
/// spelling them out. A typo in a string literal is exactly the failure that
/// survives every local gate and only shows up as three dead buttons on a
/// device.
const _chromePath = 'ohos/entry/src/main/ets/anki/AnkiReviewerChrome.ets';
const _pagePath = 'ohos/entry/src/main/ets/pages/AnkiReviewerPage.ets';
const _bridgePath = 'ohos/entry/src/main/ets/anki/AnkiReviewerBridge.ets';

/// Drops `//` and `///` lines before needle-matching.
///
/// Learned the hard way on a sibling guard: a needle can match the comment that
/// explains why the needle exists, which turns the test into an assertion about
/// its own documentation. Comments are stripped here so every needle below can
/// only match code.
String _code(String path) {
  return File(path)
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  group('OHOS card action chrome (D8)', () {
    late final String chrome;
    late final String page;
    late final String bridge;

    setUpAll(() {
      chrome = _code(_chromePath);
      page = _code(_pagePath);
      bridge = _code(_bridgePath);
    });

    test('the chrome renders three entries and calls the page back', () {
      for (final entry in <(String, String)>[
        ('重做', 'onRedo'),
        ('搁置', 'onBury'),
        ('暂停', 'onSuspend'),
      ]) {
        expect(
          chrome.contains('Button(\'${entry.$1}\')'),
          isTrue,
          reason: '${entry.$1} button is gone from $_chromePath',
        );
        expect(
          RegExp(r'this\.' + entry.$2 + r'\(\)').hasMatch(chrome),
          isTrue,
          reason: '${entry.$1} no longer calls this.${entry.$2}()',
        );
      }
    });

    test('the entries are hidden in preview and disabled while mutating', () {
      // A preview has no session to mutate; every receipt would come back
      // "not available" and read as a broken button. Matched as a contiguous
      // run, because there is a second `!previewOnly` guard further up (undo)
      // that a looser window would be satisfied by.
      expect(
        RegExp(r"if \(!this\.previewOnly\) \{\s*Row\(\) \{\s*Blank\(\)\s*"
                r"Button\('重做'\)")
            .hasMatch(chrome),
        isTrue,
        reason: 'the card-action row must sit directly inside the previewOnly '
            'guard',
      );
      final mutations =
          RegExp(r'\.enabled\(this\.booted && !this\.isComplete && '
                  r'!this\.mutating && !this\.presentPending\)')
              .allMatches(chrome)
              .length;
      expect(
        mutations,
        3,
        reason: 'all three entries must share one enable rule — a button that '
            'stays armed during a mutation would race two advances',
      );
    });

    test('the page names its actions through protocol constants', () {
      for (final action in <String>[
        'CARD_ACTION_REDO',
        'CARD_ACTION_BURY',
        'CARD_ACTION_SUSPEND',
      ]) {
        expect(
          page.contains(action),
          isTrue,
          reason: '$action is not referenced from $_pagePath',
        );
      }
      // A literal here is the bug this whole guard exists for: it compiles,
      // crosses the channel, and matches nothing on the Dart side.
      for (final literal in <String>["'redo'", "'bury'", "'suspend'"]) {
        expect(
          page.contains(literal),
          isFalse,
          reason: 'action word $literal is spelled out in the page; use the '
              'protocol constant so a rename cannot silently stop matching',
        );
      }
    });

    test('one receipt path serves all three actions', () {
      expect(
        RegExp(r'private requestCardAction\(action: string, pendingText: string\)')
            .hasMatch(page),
        isTrue,
        reason:
            'the three entries must share one handler; three handlers would '
            'be three copies of the same interlock',
      );
      final receiptBody = RegExp(
        r'private onMutationReceipt\(code: string\): void \{([\s\S]{0,700}?)\n  \}',
      ).firstMatch(page)?.group(1);
      expect(receiptBody, isNotNull, reason: 'onMutationReceipt is gone');
      for (final needle in <String>[
        'RECEIPT_OK_COMPLETE',
        'this.complete = true',
        'this.fetchSettlement()',
      ]) {
        expect(
          receiptBody!.contains(needle),
          isTrue,
          reason: 'the mutation receipt path lost $needle, so a bury that '
              'empties the queue would never end the session on screen',
        );
      }
    });

    test('the bridge forwards the action word unchanged', () {
      expect(
        RegExp(r'invokeMethod\(METHOD_REQUEST_CARD_ACTION, action, receiver\)')
            .hasMatch(bridge),
        isTrue,
        reason: 'the bridge must pass the word through: deciding what each '
            'action means belongs to the Dart switch, not to two layers',
      );
      // `requestUndo` is deliberately fire-and-forget; the three D8 entries are
      // not, and collapsing them into `callDart` would drop every receipt.
      expect(
        RegExp(r'public requestCardAction\(action: string, '
                r'onResult: \(code: string\) => void\)')
            .hasMatch(bridge),
        isTrue,
        reason: 'requestCardAction lost its receipt callback',
      );
    });

    test('the free-text labels are not localised twice', () {
      // Both platforms' copy for these three lives here for now; if a second
      // set is added (an l10n table, a Flutter mirror), this test is the place
      // that notices the drift began.
      expect(chrome.contains('Button(\'搁置\')'), isTrue);
      expect(
        chrome.contains('Button(\'暂停\')'),
        isTrue,
        reason: 'suspend is worded 暂停 on the device today; changing it here '
            'without the Flutter side would make the two platforms disagree',
      );
    });
  });

  group('exit confirmation count (D9)', () {
    late final String chrome;
    late final String page;

    setUpAll(() {
      chrome = _code(_chromePath);
      page = _code(_pagePath);
    });

    test('the confirmation says how many cards are left', () {
      // Android's `reviewExitConfirmBody(remaining)` tells the learner what the
      // decision costs; a bare "are you sure" on one platform and a count on
      // the other is the same product behaving differently.
      expect(
        chrome.contains("'还剩 ' + String(this.remainingCount) +"),
        isTrue,
        reason: 'the exit confirmation lost its remaining-card count',
      );
      expect(
        chrome.contains(": '再按一次返回或 ✕ 结束复习（已评分的卡片会保留）'"),
        isTrue,
        reason: 'the count-free fallback is gone — it is what shows when the '
            'count is not yet known (boot, or a session that owes nothing)',
      );
    });

    test('the count uses Android\'s formula, current card included', () {
      // Android: `items.length - currentIndex`. On this side that is
      // `progressTotal - (progressIndex - 1)`, because `progressIndex` is
      // `answered + 1` and `progressTotal` is `answered + owed`.
      expect(
        RegExp(r'this\.progressTotal - this\.progressIndex \+ 1')
            .hasMatch(page),
        isTrue,
        reason: 'the remaining count drifted from Android\'s definition; '
            'off-by-one here is a lie in a confirmation dialog',
      );
      expect(
        page.contains('remainingCount: this.remainingCards()'),
        isTrue,
        reason: 'the status area is no longer fed the computed count',
      );
    });

    test('a negative count can never be rendered', () {
      expect(
        RegExp(r'return owed > 0 \? owed : 0;').hasMatch(page),
        isTrue,
        reason: 'during boot both progress fields are 0; without the clamp the '
            'line reads 还剩 -1 张',
      );
    });
  });
}
