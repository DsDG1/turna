import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/html_stripper.dart';

void main() {
  group('stripHtml', () {
    test('decodes &amp; last so escaped entities stay literal', () {
      // `&amp;lt;` is the escaped form of "&lt;" — decoding &amp; first
      // would double-unescape it into "<".
      expect(stripHtml('&amp;lt;'), '&lt;');
      expect(stripHtml('a &amp;amp; b'), 'a &amp; b');
    });

    test('still decodes ordinary entities', () {
      expect(stripHtml('Fish &amp; Chips &lt;tag&gt;'), 'Fish & Chips <tag>');
      expect(stripHtml('&quot;hi&apos; &nbsp; x'), '"hi\' x');
    });

    test('drops script/style blocks and collapses whitespace', () {
      expect(
        stripHtml('<p>Hi<br>there</p><script>alert(1)</script>'),
        'Hi there',
      );
      expect(stripHtml(''), '');
    });
  });
}
