// crash-hunt 2026-09-02 & 2026-09-26: a page behind PopScope(canPop: false)
// that retries a blocked pop with `maybePop` enters an infinite microtask
// loop — each veto re-fires the pop callback, which calls maybePop again:
// on-device it presents as a frozen screen with ~100% isolate CPU until the
// OS kills the app. The import wizard hit this in 2026-09
// (anki_import_pop_loop_guard_test) and the lesson-completion /
// unified-review completion paths hit it again in 2026-09: the completion
// dialog's trailing `navigator.maybePop()` re-entered
// `_onClosePressed` forever after tapping 继续/返回.
// The fix is always the same shape: after the user confirms (or the session
// is complete), pop unconditionally — `Navigator.pop` bypasses the canPop
// gate and fires the callback once with didPop:true.
// This guard keeps maybePop out of every file that sits behind
// PopScope(canPop: false), and out of the shared completion dialog that
// pops the lesson page's navigator.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pages wrapped in PopScope(canPop: false): any maybePop inside them is a
  // blocked pop that re-enters the pop callback — infinite loop.
  const guardedPages = [
    'lib/views/lesson/new_lesson_screen.dart',
    'lib/views/review/unified_review_page.dart',
    'lib/views/anki/anki_import_screen.dart',
    'lib/views/ai/ai_api_config_page.dart',
    'lib/views/settings/storage_category_items_page.dart',
  ];

  // Shared dialogs that pop a guarded page's navigator from the outside.
  const guardedDialogs = [
    'lib/views/lesson/components/lesson_dialogs.dart',
  ];

  group('pop-loop guard (crash-hunt)', () {
    for (final path in [...guardedPages, ...guardedDialogs]) {
      test('$path has no maybePop behind the canPop gate', () {
        final source = File(path).readAsStringSync();
        expect(
          RegExp(r'\.maybePop\(').hasMatch(source),
          isFalse,
          reason: '$path sits behind (or pops a route behind) '
              'PopScope(canPop: false); maybePop re-enters the blocked-pop '
              'callback forever. Pop unconditionally via '
              'Navigator.pop / context.router.pop instead.',
        );
      });
    }
  });
}
