// `_buildOhos` cannot be exercised from a host test: it is gated on
// `isHarmonyOsTarget`, which reads `defaultTargetPlatform.name == 'ohos'`, and
// the official SDK's `TargetPlatform` enum has no `ohos` member — there is no
// override value to assign. A widget test therefore cannot reach the OHOS
// branch at all, no matter how it injects a failing transport.
//
// That matters because the bug this guard protects against is invisible to
// every other test: the error screens are full-screen over a Flutter page the
// learner cannot reach, so dropping `onBack` leaves them stranded with only the
// system gesture. Nothing fails to compile, and the error view's own unit tests
// stay green (they pass callbacks directly).
//
// The repository's existing answer for unreachable platform branches is a
// source-level guard — see `test/views/anki/fidelity_webview_csp_guard_test.dart`
// and `test/views/pop_scope_pop_loop_guard_test.dart`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const stagePath = 'lib/views/anki_official/official_anki_reviewer_stage.dart';

  /// Everything between `Widget _buildOhos(` and the next method.
  String buildOhosBody(String source) {
    final start = source.indexOf('Widget _buildOhos(');
    expect(start, greaterThan(-1),
        reason: '$stagePath no longer declares `_buildOhos`; update this guard '
            'if the OHOS branch moved, do not delete it.');
    final end = source.indexOf('Widget _buildSurface(', start);
    expect(end, greaterThan(start),
        reason: 'could not find the method after `_buildOhos`; the slice this '
            'guard relies on is broken.');
    return source.substring(start, end);
  }

  group('OHOS reviewer error screens always offer an exit', () {
    late String body;
    late String failClosed;
    late String startFailure;

    setUpAll(() {
      final source = File(stagePath).readAsStringSync();
      body = buildOhosBody(source);

      // Two branches, split on the line between them. `!allowJs` returns early;
      // everything from `_blockedJsGeneration` on is the start-failure path.
      final failClosedStart = body.indexOf('if (!allowJs)');
      final startFailureStart = body.indexOf('_blockedJsGeneration = null;');
      expect(failClosedStart, greaterThan(-1),
          reason: 'the JS fail-closed branch disappeared from `_buildOhos`');
      expect(startFailureStart, greaterThan(failClosedStart),
          reason: 'the two OHOS branches changed shape; re-anchor this guard');

      failClosed = body.substring(failClosedStart, startFailureStart);
      startFailure = body.substring(startFailureStart);
    });

    test('the fail-closed branch renders a back entry and no retry', () {
      expect(RegExp(r'OfficialAnkiReviewerErrorView\(').allMatches(failClosed),
          hasLength(1));
      expect(failClosed.contains('onBack: _ohosBack'), isTrue,
          reason: 'scripts-off is a user setting, not a transient failure: the '
              'screen must still let the learner leave.');
      expect(failClosed.contains('onRetry:'), isFalse,
          reason: 're-running the same boot with scripts still off fails the '
              'same way — a retry button here would be a lie.');
      expect(
          failClosed.contains("'official_anki.renderer_flag_fail_closed'"),
          isTrue,
          reason: 'this branch is fail-closed, not a render failure; the two '
              'messages must not be swapped.');
    });

    test('the start-failure branch renders both retry and back', () {
      expect(RegExp(r'OfficialAnkiReviewerErrorView\(').allMatches(startFailure),
          hasLength(1));
      expect(startFailure.contains('onBack: _ohosBack'), isTrue,
          reason: 'ability launch can fail permanently (missing ability, bad '
              'want); without back the error page is a dead end.');
      expect(startFailure.contains('onRetry:'), isTrue,
          reason: 'a failed launch is worth one more attempt.');
      expect(startFailure.contains("'official_anki.render_failed'"), isTrue);
    });

    test('the back callback falls back to popping this page', () {
      // Formal review reaches the stage through `OfficialTemplateWebViewBody`,
      // which passes no `onBack`. A bare `widget.onBack` would render a button
      // (it is also the visibility switch) that does nothing when tapped.
      expect(
        RegExp(r'VoidCallback get _ohosBack =>\s*widget\.onBack \?\?').hasMatch(
          File(stagePath).readAsStringSync(),
        ),
        isTrue,
        reason: 'the back entry must degrade to `maybePop`, not to a no-op.',
      );
    });
  });
}
