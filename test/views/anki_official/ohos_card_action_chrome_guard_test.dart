import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guard for the OHOS reviewer chrome.
///
/// The four queue-mutation entries (undo / redo / bury / suspend) were removed
/// on 2026-10-19 at the product owner's request. The assertions here pin that
/// removal — no such button may reappear — and keep the chrome invariants that
/// outlived them: the Review All badge, the four theme variants, and the system
/// bars that have to follow whichever of those is active.
///
/// The ArkUI page cannot be unit-tested from Dart: `isHarmonyOsTarget` is
/// compile-time on this side, and ArkTS has no test host here. What *can* be
/// checked is the source shape the page and its chrome are supposed to keep.
const _chromePath = 'ohos/entry/src/main/ets/anki/AnkiReviewerChrome.ets';
const _pagePath = 'ohos/entry/src/main/ets/pages/AnkiReviewerPage.ets';

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
  group('OHOS reviewer chrome', () {
    late final String chrome;
    late final String page;

    setUpAll(() {
      chrome = _code(_chromePath);
      page = _code(_pagePath);
    });

    test('the queue-mutation entries stay gone', () {
      // Removed 2026-10-19: undo / redo / bury / suspend. A re-introduced
      // button must fail here, not silently reappear on a device where the
      // ArkTS side has no test host of its own.
      for (final label in <String>['撤销', '重做', '搁置', '暂停']) {
        expect(
          RegExp("Button\\('$label'\\)").hasMatch(chrome),
          isFalse,
          reason: '$label was removed from $_chromePath and must not come back',
        );
      }
      for (final handler in <String>[
        'onUndo',
        'onRedo',
        'onBury',
        'onSuspend',
      ]) {
        expect(
          chrome.contains('this.$handler()'),
          isFalse,
          reason: '$handler still has a caller in the chrome',
        );
        expect(
          page.contains('this.$handler'),
          isFalse,
          reason: '$handler still has a handler on the page',
        );
      }
    });

    test('the Review All badge renders only when Dart sent one (UI-15)', () {
      expect(
        RegExp(r'if \(!this\.previewOnly && '
                r'this\.sourceProgress\.length > 0\) \{')
            .hasMatch(chrome),
        isTrue,
        reason: 'the source badge must be conditional — an empty string would '
            'otherwise paint an empty pill on every single-deck session',
      );
      expect(
        RegExp(r'\.maxLines\(1\)').hasMatch(chrome),
        isTrue,
        reason: 'a long deck name must ellipsize, not wrap the strip',
      );
    });

    test('the chrome paints all four Flutter theme variants (UI-15)', () {
      for (final token in <String>[
        'CHROME_HIGH_CONTRAST_LIGHT',
        'CHROME_HIGH_CONTRAST_DARK',
        'CHROME_DARK',
      ]) {
        expect(
          chrome.contains(token),
          isTrue,
          reason: '$token is not dispatched from paletteForTheme — the native '
              'bars would fall back to a plain palette',
        );
      }
      // The frame's own tokens must still resolve: the first present of a
      // session arrives before Dart has sent a chromeTheme.
      expect(
        RegExp(r'function paletteForTheme[\s\S]*?THEME_NIGHT').hasMatch(chrome),
        isTrue,
        reason: 'day/night must stay accepted for the pre-chromeTheme present',
      );
    });
    test('a finished single-source session hands the summary to Flutter', () {
      // UI-16: the native row used to be the only completion surface the
      // learner ever saw — tapping 「完成」 closed the ability, and Dart popped
      // the page, tearing down the `UnifiedReviewCompletion` already rendered
      // underneath (the exact component Android shows).
      expect(
        RegExp(r'if \(this\.autoComplete\) \{').hasMatch(chrome),
        isTrue,
        reason: 'the completion row must branch on autoComplete',
      );
      expect(
        chrome.contains('正在打开结算…'),
        isTrue,
        reason: 'the hand-off row needs its own copy; repeating the numbers '
            'here would be a second summary screen',
      );
      expect(
        RegExp(r'if \(!this\.autoComplete\) \{').hasMatch(chrome),
        isTrue,
        reason: 'the 完成 button must be hidden when the page closes itself — '
            'a button next to an auto-close reads as "you must tap this"',
      );
      // Armed at most once, and it re-checks both guards: a Review All
      // hand-off swaps the session and resets `complete`, and closing a page
      // the next source is already using is the failure this protects.
      expect(
        RegExp(r'if \(!this\.autoComplete \|\| this\.autoCloseScheduled\) \{')
            .hasMatch(page),
        isTrue,
      );
      expect(
        RegExp(r'if \(!this\.alive \|\| !this\.complete\) \{').hasMatch(page),
        isTrue,
        reason: 'the timer must not close a page that already moved on to the '
            'next source',
      );
      // `endReview` is reachable from both the timer and the learner's tap.
      expect(
        RegExp(r'if \(this\.terminating\) \{').hasMatch(page),
        isTrue,
        reason: 'two terminateSelfWithResult calls on a dying ability are '
            'noise, not a second exit',
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

  // UI-8 follow-up: the rating interlock's release rules.
  //
  // The page cannot be driven from Dart (see the file header) and the defect
  // these pin is a *deadlock*: `ratingSent` stays true, the bottom bar renders
  // a disabled "已提交，加载中…", and no receipt ever flips it back. The only
  // signal available here is the shape of the branch.
  group('rating receipt interlock (UI-8)', () {
    late final String page;

    setUpAll(() {
      page = _code(_pagePath);
    });

    /// The body of `onRateReceipt`, with the method's closing brace excluded.
    String receiptBody() {
      final body = RegExp(
        r'private onRateReceipt\(code: string\): void \{([\s\S]{0,2200}?)\n  \}',
      ).firstMatch(page)?.group(1);
      expect(body, isNotNull, reason: 'onRateReceipt is gone from $_pagePath');
      return body!;
    }

    /// One `if (code === …) { … }` arm of the receipt switch.
    String? branch(String needle) {
      return RegExp(
        'if \\(code === $needle\\) \\{([\\s\\S]{0,900}?)\\n    \\}',
      ).firstMatch(receiptBody())?.group(1);
    }

    test('a receipt that did not commit re-arms the rating row', () {
      // The catch-all used to call `showError` only. Every code that lands
      // there — bridge_detached, not_implemented, channel errors,
      // session_closed, no_card, engine_error, card_mismatch,
      // scheduler_unavailable — means no grade was written, so the two rating
      // buttons must come back.
      final body = receiptBody();
      final anchor = body.indexOf("'rating_failed'");
      expect(anchor, greaterThan(0),
          reason: 'the catch-all receipt branch lost its diagnostic code');
      final before = body.substring(anchor > 320 ? anchor - 320 : 0, anchor);
      expect(
        before.contains('this.ratingSent = false;'),
        isTrue,
        reason: 'the catch-all branch no longer clears ratingSent; a detached '
            'bridge or a closed session would leave the rating row disabled '
            'for the rest of the review — the reported 已提交，加载中… stall',
      );
    });

    test('a committed rating keeps the interlock until the next card', () {
      // `ok` and `advance_failed` both mean the grade is already in the
      // scheduler. Re-arming there submits the same card twice.
      final ok = branch('RECEIPT_OK \\|\\| code === RECEIPT_OK_COMPLETE');
      expect(ok, isNotNull, reason: 'the ok / ok_complete arm is gone');
      expect(
        ok!.contains('this.ratingSent = false'),
        isFalse,
        reason: 'the ok arm must not re-arm the row: the next card has not '
            'landed yet and the row returns as soon as answerLanded is true',
      );
      final failed = branch('RECEIPT_ADVANCE_FAILED');
      expect(failed, isNotNull, reason: 'the advance_failed arm is gone');
      expect(
        failed!.contains('this.ratingSent = false'),
        isFalse,
        reason: 'advance_failed means the grade is committed; re-arming would '
            'submit it again, so the retry entry is the only way forward',
      );
      expect(
        failed.contains('this.advanceStuck = true'),
        isTrue,
        reason: 'advance_failed must swap in the retry / exit row',
      );
    });

    test('an ok receipt clears a stale advance failure', () {
      // `onRetryAdvance` replays the advance and a success answers `ok`. If
      // the page does not clear `advanceStuck`, the bottom bar stays on
      // "重试进入下一张" for the rest of the session even though the card moved.
      final ok = branch('RECEIPT_OK \\|\\| code === RECEIPT_OK_COMPLETE');
      expect(
        ok!.contains('this.advanceStuck = false'),
        isTrue,
        reason: 'a successful retry must take the page out of the stuck row',
      );
    });

    test('a stalled rating becomes the retry row, not a dead button', () {
      expect(
        RegExp(r'private armRatingWatchdog\(\): void \{').hasMatch(page),
        isTrue,
        reason: 'without the watchdog a present that never lands leaves the '
            'page on a disabled button with no entry at all',
      );
      expect(
        RegExp(r'private static readonly RATING_STALL_MS: number = 20000;')
            .hasMatch(page),
        isTrue,
        reason: 'the stall window must stay above the present ack timeout '
            '(12 s) plus the media push, or a slow card reads as a failure',
      );
      expect(
        RegExp(r'this\.ratingTimer = setTimeout\(').hasMatch(page),
        isTrue,
      );
      expect(
        RegExp(r'private disarmRatingWatchdog\(\): void \{').hasMatch(page),
        isTrue,
        reason: 'the timer must be cancelled when the next card lands',
      );
    });

    test('the chrome listener releases only on a question face', () {
      // `presentPending` is true from the present call until its ack. Clearing
      // `ratingSent` there re-armed the row while the receipt was still in
      // flight — once the present finished, a second tap graded the same card.
      expect(
        RegExp(r'if \(!state\.presentPending && !state\.answerLanded\) \{')
            .hasMatch(page),
        isTrue,
        reason: 'the chrome listener must not clear ratingSent while a present '
            'is in flight or an answer face is showing',
      );
    });
  });

  // The reviewer used to sit between a white status bar and a white navigation
  // bar: the ability never configured them, so a night session was a dark page
  // inside a light screen. Nothing in `flutter test` can see that — it is a
  // window property, and the only symptom is two bright bands on a device. The
  // three parts that keep it fixed are asserted here instead: the call, the
  // palette it reads, and the branch that re-applies it when day/night flips
  // mid-session.
  group('edge-to-edge window and safe areas', () {
    late final String chrome;
    late final String page;

    setUpAll(() {
      chrome = _code(_chromePath);
      page = _code(_pagePath);
    });

    test('the window reaches under both bars', () {
      // `navigationBarColor` is not honoured on the device this shipped to:
      // the strip stayed white under a black page whatever was sent. The only
      // fix that survives that is to extend the window and paint it with the
      // page itself.
      expect(
        page.contains('setWindowLayoutFullScreen(true)'),
        isTrue,
        reason: 'without edge-to-edge the navigation strip keeps the platform '
            'background, and a night review ends in a white band',
      );
      expect(
        page.contains('statusBarColor: \'#00000000\''),
        isTrue,
        reason: 'the bars must be transparent — an opaque bar colour is the '
            'call that silently did nothing on the bottom one',
      );
      expect(page.contains('navigationBarColor: \'#00000000\''), isTrue);
    });

    test('the insets come back as padding', () {
      expect(
        page.contains('padding({ top: this.topAvoid, bottom: this.bottomAvoid })'),
        isTrue,
        reason: 'an edge-to-edge window puts the header under the status bar '
            'and the action row under the gesture indicator unless the page '
            'pads itself',
      );
      expect(
        page.contains('win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)'),
        isTrue,
        reason: 'the status bar height is only knowable from the avoid area',
      );
    });

    test('the glyph colour flips with the theme', () {
      expect(
        page.contains('isDarkTheme(this.theme)'),
        isTrue,
        reason: 'black glyphs on a dark bar are invisible',
      );
      expect(
        chrome.contains('export function isDarkTheme('),
        isTrue,
        reason: 'the theme -> bright/dark mapping belongs next to the palette '
            'it describes, not inlined in the page',
      );
    });

    test('a mid-session theme flip repaints them', () {
      // The first present of a session arrives before Dart has said whether
      // this is day or night, so `aboutToAppear` alone leaves a light bar over
      // a dark page until the ability is rebuilt.
      expect(
        RegExp(r'if \(state\.theme !== this\.theme\) \{[\s\S]{0,400}?'
                r'this\.refreshSystemBarGlyphs\(\);')
            .hasMatch(page),
        isTrue,
        reason: 'the chrome listener must re-derive the bar glyphs when the '
            'theme actually changed',
      );
    });

    test('night chrome uses the app\'s own darkScaffold', () {
      // The old night palette (`#10181B` / `#1A2327`) existed nowhere in
      // `lib/core/theme.dart`: the reviewer was the one screen whose night mode
      // was a different colour family from the pages around it. Reading the
      // token instead of hardcoding it means a theme change moves both.
      final theme = File('lib/core/theme.dart').readAsLinesSync().join('\n');
      final match =
          RegExp(r'darkScaffold = Color\(0xFF([0-9A-Fa-f]{6})\)').firstMatch(theme);
      expect(match, isNotNull, reason: 'TurnaTheme.darkScaffold moved or was renamed');
      final token = '#${match!.group(1)!.toUpperCase()}';
      final night =
          chrome.substring(chrome.indexOf('export function nightPalette()'));
      expect(
        night.contains("bg: '$token'"),
        isTrue,
        reason: 'the reviewer night background drifted from '
            'TurnaTheme.darkScaffold ($token)',
      );
    });
  });
}
