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

    test('decodes numeric character references (Turkish İ & friends)', () {
      // Anki exporters frequently emit İ (U+0130) as &#304; / &#x130; —
      // without numeric decoding TTS would read the entity aloud.
      expect(stripHtml('&#304;stanbul'), 'İstanbul');
      expect(stripHtml('&#x130;stanbul'), 'İstanbul');
      expect(stripHtml('caf&#233;'), 'café');
    });

    test('leaves malformed numeric references verbatim', () {
      expect(stripHtml('&#; and &#xzz;'), '&#; and &#xzz;');
      expect(stripHtml('&#xD800; lone surrogate'), '&#xD800; lone surrogate');
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
