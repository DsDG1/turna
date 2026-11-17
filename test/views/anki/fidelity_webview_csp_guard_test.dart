// Guard for `official_template_webview_body.dart`'s `ankiForceDisableJs`
// setting gate.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const templateBody =
      'lib/views/review/components/official_template_webview_body.dart';

  group('fidelity WebView CSP guard', () {
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
