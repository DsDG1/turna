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

    test('hint filter is dropped and type answer stays hidden on the front',
        () {
      expect(
        AnkiTemplateRenderer.render('{{hint:Back}}', {'Back': 'secret'}),
        '',
      );
      expect(
        AnkiTemplateRenderer.render('{{type:Back}}', {'Back': 'secret'}),
        contains('_____'),
      );
      final answer = AnkiTemplateRenderer.render(
        '{{type:Back}}',
        {'Back': 'secret'},
        revealTypeAnswers: true,
      );
      expect(answer, contains('data-anki-type-expected="secret"'));
      expect(answer, contains('secret'));
      expect(AnkiTemplateRenderer.extractTypeAnswer(answer), 'secret');
    });

    test('converts Anki sound markers to audio elements', () {
      final out = AnkiTemplateRenderer.render(
        '{{Front}}',
        {'Front': 'Listen [sound: hello.mp3]'},
      );
      expect(out, contains('<audio controls'));
      expect(out, contains('src="hello.mp3"'));
      expect(out, isNot(contains('[sound:')));
    });

    test('special fields render empty', () {
      final out = AnkiTemplateRenderer.render(
        '{{Tags}}|{{Deck}}|{{Card}}|{{Front}}',
        {'Front': 'x'},
      );
      expect(out, '|||x');
    });

    test('special fields and text filter use Anki context', () {
      final out = AnkiTemplateRenderer.render(
        '{{Tags}}|{{Deck}}|{{Subdeck}}|{{Card}}|{{text:Front}}',
        {'Front': '<b>hello</b><br>world'},
        tags: 'chapter::one important',
        deck: 'Spanish::A1',
        subdeck: 'A1',
        cardName: 'Card 2',
      );
      expect(out, 'chapter::one important|Spanish::A1|A1|Card 2|hello\nworld');
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
