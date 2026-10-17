// P0-2 is a scaling change: the first batch renders a window of the queue
// instead of all of it. Its behaviour is invisible on the queues the existing
// tests use (2–4 cards, all inside the window), so a behavioural test there
// would pass with the code deleted.
//
// **The behavioural half now exists**:
// `official_formal_review_render_window_behavior_test.dart` builds the 20-card
// fixture (catalog ledger + course-tree view + introduction store) and asserts
// renderCount == 8, batch of 8, allowedCardIds of 20. Run it whenever this
// file's needles change; this file stays because it names *why* each line
// matters, which a passing assertion does not.
//
// What can silently regress is still structural: someone deletes `.take(...)`
// (first paint goes back to proportional with queue length), or swaps the
// allowed set back to the assembled batch (the session is permanently
// truncated to the window). Both are pinned here at the source level, the same
// way `fidelity_webview_csp_guard_test.dart` pins its wiring.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const loaderPath =
      'lib/application/anki_official/review/official_formal_review_production_loader.dart';
  const coordinatorPath =
      'lib/application/anki_official/review/official_formal_review_coordinator.dart';

  group('first batch renders a window, not the queue', () {
    late String loader;

    setUpAll(() => loader = File(loaderPath).readAsStringSync());

    test('the render loop is bounded by the window', () {
      expect(
        loader.contains('.take(officialInitialRenderWindow)'),
        isTrue,
        reason: 'without this the loader renders every card in the queue '
            'before anything appears — first paint proportional to queue length',
      );
    });

    test('the window is taken from eligible cards, not the raw queue', () {
      // A window over the raw queue can be eight unintroduced or retired cards:
      // the batch then comes out empty and the page reports "nothing due".
      expect(
        RegExp(r'\.where\(\(card\) => eligibleIds\.contains\(card\.cardId\)\)')
            .hasMatch(loader),
        isTrue,
        reason: 'the window must be filtered by eligibility first',
      );
    });

    test('the allowed set keeps every eligible card minus first-batch failures',
        () {
      expect(loader.contains('eligibleIds.difference(failedIds)'), isTrue,
          reason: 'restricting to the assembled batch would permanently '
              'truncate the session to the window');
      // Asked of the code, not the file: the comment above `allowedIds`
      // explains what the old variable did, and a whole-file scan would read
      // that explanation as a regression. Same trap the sqlite-dispatch guard
      // recorded — a needle that also matches its own doc makes the correct
      // implementation fail.
      final code = loader
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('assembledIds'), isFalse,
          reason: 'the old variable is exactly the trap: it looks like the '
              'right set and is the one that loses cards past the window');
    });
  });

  group('the live queue keeps a rolling window', () {
    late String coordinator;

    setUpAll(() => coordinator = File(coordinatorPath).readAsStringSync());

    test('rebuild stops after the window', () {
      expect(coordinator.contains('rendered >= officialInitialRenderWindow'),
          isTrue,
          reason: 'the rebuild used to render the whole queue on every answer');
    });

    test('the window starts at the scheduler current card', () {
      // Starting anywhere else can leave `currentSnapshot()` without a face on
      // the very card about to be rated.
      expect(coordinator.contains('startAtCardId'), isTrue);
      expect(
        coordinator.contains('cards.indexWhere((c) => c.cardId == startAtCardId)'),
        isTrue,
      );
    });

    test('a failed render does not consume a window slot', () {
      // Exactly two increments: one for a card that already has a face, one
      // after a successful render. A third inside the catch branch would let an
      // unrenderable card eat the window until it closes on itself.
      expect(
        RegExp(r'rendered \+= 1;').allMatches(coordinator).length,
        2,
        reason: 'a failure must not advance the window counter',
      );
    });
  });
}
