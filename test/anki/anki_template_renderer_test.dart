// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_template_renderer.dart';

void main() {
  group('AnkiTemplateRenderer', () {
    test('substitutes plain fields', () {
      final out = AnkiTemplateRenderer.render(
        '{{Front}} — {{Back}}',
        {'Front': 'merhaba', 'Back': 'hello'},
      );
      expect(out, 'merhaba — hello');
    });

    test('renders reversed template direction-correctly', () {
      const qfmt = '{{Back}}';
      const afmt = '{{FrontSide}}<hr id="answer">{{Front}}';
      final fields = {'Front': 'merhaba', 'Back': 'hello'};

      final front = AnkiTemplateRenderer.render(qfmt, fields);
      final back = AnkiTemplateRenderer.render(afmt, fields, frontSide: '');
      expect(front, 'hello');
      expect(back, '<hr id="answer">merhaba');
    });

    test('FrontSide is substituted when provided', () {
      final out = AnkiTemplateRenderer.render(
        '{{FrontSide}}<hr>{{Back}}',
        {'Front': 'q', 'Back': 'a'},
        frontSide: 'q',
      );
      expect(out, 'q<hr>a');
    });

    test('conditional block renders only when field non-empty', () {
      const tpl = '{{#Extra}}[{{Extra}}]{{/Extra}}{{Front}}';
      expect(
        AnkiTemplateRenderer.render(tpl, {'Front': 'x', 'Extra': 'tip'}),
        '[tip]x',
      );
      expect(
        AnkiTemplateRenderer.render(tpl, {'Front': 'x', 'Extra': ''}),
        'x',
      );
      expect(
        AnkiTemplateRenderer.render(tpl, {'Front': 'x'}),
        'x',
      );
    });

    test('inverted conditional renders only when field empty', () {
      const tpl = '{{^Extra}}none{{/Extra}}{{Front}}';
      expect(
        AnkiTemplateRenderer.render(tpl, {'Front': 'x', 'Extra': 'tip'}),
        'x',
      );
      expect(
        AnkiTemplateRenderer.render(tpl, {'Front': 'x', 'Extra': ''}),
        'nonex',
      );
    });

    test('field containing only HTML tags counts as empty', () {
      const tpl = '{{#Extra}}yes{{/Extra}}{{^Extra}}no{{/Extra}}';
      expect(
        AnkiTemplateRenderer.render(tpl, {'Extra': '<br>  '}),
        'no',
      );
    });

    test('cloze filter keeps raw field value with markers', () {
      final out = AnkiTemplateRenderer.render(
        '{{cloze:Text}}',
        {'Text': 'Paris is the capital of {{c1::France}}'},
      );
      expect(out, 'Paris is the capital of {{c1::France}}');
    });

    test('hint filter is dropped, unknown filter degrades to field value', () {
      expect(
        AnkiTemplateRenderer.render('{{hint:Back}}', {'Back': 'secret'}),
        '',
      );
      expect(
        AnkiTemplateRenderer.render('{{type:Back}}', {'Back': 'secret'}),
        'secret',
      );
    });

    test('special fields render empty', () {
      final out = AnkiTemplateRenderer.render(
        '{{Tags}}|{{Deck}}|{{Card}}|{{Front}}',
        {'Front': 'x'},
      );
      expect(out, '|||x');
    });

    test('unknown field renders empty, unknown placeholder preserved', () {
      expect(
        AnkiTemplateRenderer.render('{{Missing}}!', {'Front': 'x'}),
        '!',
      );
    });

    test('nested conditionals resolve innermost first', () {
      const tpl = '{{#A}}a{{#B}}b{{/B}}{{/A}}';
      expect(
        AnkiTemplateRenderer.render(tpl, {'A': '1', 'B': '2'}),
        'ab',
      );
      expect(
        AnkiTemplateRenderer.render(tpl, {'A': '1', 'B': ''}),
        'a',
      );
      expect(
        AnkiTemplateRenderer.render(tpl, {'A': '', 'B': '2'}),
        '',
      );
    });
  });
}
