// Card HTML reaching the fidelity WebView is attacker-controlled input
// (imported decks) rendered with `loadHtmlString` +
// `JavaScriptMode.unrestricted`. The `NavigationDelegate` in
// `AnkiHtmlCardView` only intercepts *top-level navigations* — subresource
// loads (`<script src="https://…">`, `<img src="https://…">`,
// `fetch`/XHR/beacon) never reach it. The CSP injected by
// `AnkiFidelityCsp` is therefore the only layer that denies them.
//
// The unit tests in `anki_fidelity_csp_test.dart` pin the policy text, but
// they cannot tell whether the policy is still *applied*. A refactor could
// drop the `AnkiFidelityCsp.inject` call and leave every one of them green.
// This guard closes that gap by asserting the wiring at the source level,
// the same way `pop_scope_pop_loop_guard_test.dart` does.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cardView = 'lib/views/anki/anki_html_card_view.dart';
  const templateBody =
      'lib/views/review/components/official_template_webview_body.dart';

  group('fidelity WebView CSP guard', () {
    test('$cardView injects the policy on every load path', () {
      final source = File(cardView).readAsStringSync();

      expect(
        source.contains('AnkiFidelityCsp.inject('),
        isTrue,
        reason: '$cardView loads attacker-controlled card HTML. The policy '
            'must be applied in the html-building path so both the initial '
            'load and the face swap in didUpdateWidget go through it.',
      );
      // Every loadHtmlString call site must build from _themedHtml(); a raw
      // inline document would bypass the injection entirely.
      final rawLoads = RegExp(r'loadHtmlString\((?!_themedHtml\(\))')
          .allMatches(source)
          .length;
      expect(
        rawLoads,
        0,
        reason: '$cardView has a loadHtmlString call that does not pass '
            '_themedHtml(), so it renders without the CSP.',
      );
    });

    test('$cardView keeps the navigation delegate as the second layer', () {
      final source = File(cardView).readAsStringSync();

      expect(
        source.contains('NavigationDecision.prevent'),
        isTrue,
        reason: 'The delegate is the top-level navigation layer; removing it '
            'would leave subresource-only protection in place.',
      );
    });

    test('$templateBody honours the ankiForceDisableJs switch', () {
      final source = File(templateBody).readAsStringSync();

      expect(
        RegExp(r'allowJs:\s*!\s*forceDisableJs').hasMatch(source),
        isTrue,
        reason: '$templateBody hardcoded `allowJs: true` once, which left the '
            'ankiForceDisableJs setting a dead switch (declared, persisted, '
            'backed up, and read by nobody). It must gate allowJs.',
      );
      expect(
        RegExp(r'allowJs:\s*true').hasMatch(source),
        isFalse,
        reason: 'A literal allowJs: true re-creates the dead switch.',
      );
    });
  });
}
