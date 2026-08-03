// Cloze rendering tests for the fidelity track (deep-adaptation plan §5.3).
// Verifies the three cloze modes on AnkiTemplateRenderer.render: default
// (preserve markers, adapter path), front-side mask, back-side reveal.

// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/anki/anki_template_renderer.dart';

void main() {
  group('AnkiTemplateRenderer cloze (fidelity track)', () {
    const fields = {'Text': 'The {{c1::sun}} is a {{c2::star}}'};

    test('default preserves cloze markers (adapter extraction path)', () {
      final out = AnkiTemplateRenderer.render('{{cloze:Text}}', fields);
      expect(out, 'The {{c1::sun}} is a {{c2::star}}');
    });

    test('front side masks the active deletion, reveals others', () {
      final out = AnkiTemplateRenderer.render(
        '{{cloze:Text}}',
        fields,
        clozeOrd: 1,
      );
      expect(out, 'The <span class="cloze">[…]</span> is a star');
    });

    test('non-active cloze on front is revealed', () {
      final out = AnkiTemplateRenderer.render(
        '{{cloze:Text}}',
        fields,
        clozeOrd: 2,
      );
      expect(out, 'The sun is a <span class="cloze">[…]</span>');
    });

    test('front side with hint shows [hint]', () {
      const f = {'Text': 'Capital of {{c1::France::country}}'};
      final out = AnkiTemplateRenderer.render('{{cloze:Text}}', f, clozeOrd: 1);
      expect(out, 'Capital of <span class="cloze">[country]</span>');
    });

    test('back side reveals all deletions', () {
      final out = AnkiTemplateRenderer.render(
        '{{cloze:Text}}',
        fields,
        revealAllClozes: true,
      );
      expect(out, 'The sun is a star');
    });

    test('FrontSide substitution works alongside cloze', () {
      const f = {'Text': '{{c1::answer}}'};
      final front = AnkiTemplateRenderer.render('{{cloze:Text}}', f, clozeOrd: 1);
      final back = AnkiTemplateRenderer.render(
        '{{FrontSide}}<hr id="answer">{{cloze:Text}}',
        f,
        frontSide: front,
        revealAllClozes: true,
      );
      expect(back,
          '<span class="cloze">[…]</span><hr id="answer">answer');
    });
  });
}
