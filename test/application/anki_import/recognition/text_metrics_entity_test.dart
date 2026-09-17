import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';

void main() {
  group('HTML entity decoding order', () {
    test('CardText.stripHtml decodes &amp; last without double-unescaping', () {
      // &amp;lt; should decode to &lt;, NOT to <
      expect(CardText.stripHtml('&amp;lt;b&amp;gt;'), '&lt;b&gt;');
      // Literal &amp; should decode to &
      expect(CardText.stripHtml('Tom &amp; Jerry'), 'Tom & Jerry');
      // Standard entities
      expect(CardText.stripHtml('&lt;hello&gt;'), '<hello>');
      expect(CardText.stripHtml('&quot;quoted&quot;'), '"quoted"');
      expect(CardText.stripHtml('&#39;single&#39;'), "'single'");
      expect(CardText.stripHtml('&apos;single&apos;'), "'single'");
    });

    test('EmbeddedOptionsParser.normalizeForOptionScan decodes &amp; last', () {
      expect(
        EmbeddedOptionsParser.normalizeForOptionScan('&amp;lt;A&amp;gt;'),
        '&lt;A&gt;',
      );
      expect(
        EmbeddedOptionsParser.normalizeForOptionScan('A. &amp;lt;test&amp;gt;'),
        'A. &lt;test&gt;',
      );
      expect(
        EmbeddedOptionsParser.normalizeForOptionScan(
            '&lt;b&gt;Option A&lt;/b&gt;'),
        '<b>Option A</b>',
      );
    });
  });
}
