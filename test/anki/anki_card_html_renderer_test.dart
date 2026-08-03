// Tests for AnkiCardHtmlRenderer (fidelity HTML pipeline) + AnkiMediaUrlResolver
// (deep-adaptation plan §5.1 / §5.2). HTML-string snapshot tests - WebView
// golden rendering is not feasible, so we assert on the produced HTML.

// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/anki/anki_card_html_renderer.dart';
import 'package:varnamala/application/anki/anki_media_url_resolver.dart';
import 'package:varnamala/application/anki/anki_models.dart';

void main() {
  group('AnkiCardHtmlRenderer', () {
    const renderer = AnkiCardHtmlRenderer();
    final nt = AnkiNotetype(
      id: 1,
      name: 'Basic',
      fieldNames: const ['Front', 'Back'],
      templates: const [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}',
          afmt: '{{FrontSide}}<hr id="answer">{{Back}}',
        ),
      ],
      css: '.card{color:blue}',
    );
    final note = AnkiNote(id: 100, mid: 1, fields: const ['What is 2+2?', '4']);
    final card = AnkiCardData(id: 200, nid: 100, did: 1, ord: 0);

    test('renderFront substitutes field and wraps with css + base href', () {
      final html = renderer.renderFront(
        notetype: nt,
        note: note,
        card: card,
        mediaBasePath: '/media/imp1',
      );
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('What is 2+2?'));
      expect(html, contains('.card{color:blue}'));
      expect(html, contains('<base href="file:///media/imp1/">'));
      // Front never shows the answer divider.
      expect(html, isNot(contains('<hr id="answer">')));
    });

    test('renderBack reveals answer with FrontSide prepended', () {
      final html = renderer.renderBack(notetype: nt, note: note, card: card);
      expect(html, contains('What is 2+2?'));
      expect(html, contains('4'));
      expect(html, contains('<hr id="answer">'));
    });

    test('cloze front masks active deletion, back reveals', () {
      const cnt = AnkiNotetype(
        id: 2,
        name: 'Cloze',
        isCloze: true,
        fieldNames: ['Text'],
        templates: [
          AnkiTemplate(
            name: 'Card 1',
            qfmt: '{{cloze:Text}}',
            afmt: '{{cloze:Text}}',
          ),
        ],
      );
      const cnote = AnkiNote(id: 1, mid: 2, fields: ['The {{c1::sun}}']);
      const ccard = AnkiCardData(id: 1, nid: 1, did: 1, ord: 0);

      final front =
          renderer.renderFront(notetype: cnt, note: cnote, card: ccard);
      expect(front, contains('[…]'));
      expect(front, isNot(contains('>sun<')));

      final back = renderer.renderBack(notetype: cnt, note: cnote, card: ccard);
      expect(back, contains('sun'));
    });

    test('multi-template notetype picks the ord-th template', () {
      final nt2 = AnkiNotetype(
        id: 3,
        name: 'Basic (and reversed)',
        fieldNames: const ['Front', 'Back'],
        templates: const [
          AnkiTemplate(
              name: 'Forward',
              qfmt: '{{Front}}',
              afmt: '{{FrontSide}}<hr>{{Back}}'),
          AnkiTemplate(
              name: 'Reverse',
              qfmt: '{{Back}}',
              afmt: '{{FrontSide}}<hr>{{Front}}'),
        ],
      );
      final card1 = AnkiCardData(id: 10, nid: 100, did: 1, ord: 1);
      final html = renderer.renderFront(notetype: nt2, note: note, card: card1);
      // ord=1 -> Reverse template -> qfmt {{Back}} -> shows "4".
      expect(html, contains('4'));
    });

    test('type-answer templates hide the answer on the front face', () {
      const typeNt = AnkiNotetype(
        id: 4,
        name: 'Type answer',
        fieldNames: ['Front', 'Back'],
        templates: [
          AnkiTemplate(
            name: 'Card 1',
            qfmt: '{{Front}}<br>{{type:Back}}',
            afmt: '{{FrontSide}}<hr id="answer">{{Back}}',
          ),
        ],
      );
      final front = renderer.renderFront(
        notetype: typeNt,
        note: note,
        card: card,
      );
      final back = renderer.renderBack(
        notetype: typeNt,
        note: note,
        card: card,
      );
      expect(front, contains('anki-type-answer'));
      expect(front, isNot(contains('secret')));
      expect(back, contains('4'));
    });

    test('sound markers become playable relative audio elements', () {
      final audioNote = AnkiNote(
        id: 101,
        mid: 1,
        fields: const ['Listen [sound:prompt.mp3]', 'answer'],
      );
      final html = renderer.renderFront(
        notetype: nt,
        note: audioNote,
        card: card,
        mediaBasePath: '/media/imp1',
      );
      expect(html, contains('<audio controls'));
      expect(html, contains('src="prompt.mp3"'));
      expect(html, isNot(contains('[sound:')));
    });

    test('blocks network and absolute local resources but keeps relative media',
        () {
      const unsafeNt = AnkiNotetype(
        id: 8,
        name: 'Unsafe',
        fieldNames: ['Front', 'Back'],
        templates: [
          AnkiTemplate(
            name: 'Card 1',
            qfmt: '<base href="file:///secret/">'
                '<img src="file:///secret/token.png">'
                '<img src="https://tracker.example/pixel">'
                '<img src="safe.png">'
                '<script>fetch("https://tracker.example/x")</script>'
                '{{Front}}',
            afmt: '{{Back}}',
          ),
        ],
      );
      final html = renderer.renderFront(
        notetype: unsafeNt,
        note: note,
        card: card,
        mediaBasePath: '/media/imp1',
      );

      expect(html, contains("connect-src 'none'"));
      expect(html, contains('<base href="file:///media/imp1/">'));
      expect(html, isNot(contains('<base href="file:///secret/">')));
      expect(html, contains('src="about:blank"'));
      expect(html, contains('src="safe.png"'));
    });
  });

  group('AnkiMediaUrlResolver', () {
    const r = AnkiMediaUrlResolver();

    test('anki:// -> media dir path', () {
      final out = r.resolve('anki://imp1/foo.jpg', mediaDir: '/m');
      expect(out, endsWith('foo.jpg'));
      expect(out, contains('/m'));
    });

    test('anki:// without importId segment -> media dir', () {
      expect(r.resolve('anki://bar.mp3', mediaDir: '/m'), endsWith('bar.mp3'));
    });

    test('relative -> media dir', () {
      expect(r.resolve('bar.mp3', mediaDir: '/m'), endsWith('bar.mp3'));
    });

    test('http(s) / data / file passthrough unchanged', () {
      expect(r.resolve('https://x/y.png', mediaDir: '/m'), 'https://x/y.png');
      expect(r.resolve('data:image/png;base64,xx', mediaDir: '/m'),
          'data:image/png;base64,xx');
      expect(r.resolve('file:///a/b.png', mediaDir: '/m'), 'file:///a/b.png');
    });
  });
}
