import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/card_media_extractor.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';

/// P2 contract: occurrence order, face ownership, and the rule that unproven
/// faces are never guessed (ADR 0057 §5).
void main() {
  test('keeps document order and keeps intentional duplicates', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '<img src="front.png">[sound:first.mp3]',
        '[sound:first.mp3]',
      ],
      frontFieldOrds: const {0},
      backFieldOrds: const {1},
    );

    expect(occurrences, hasLength(3));
    expect(
      occurrences.map((o) => o.filename),
      ['front.png', 'first.mp3', 'first.mp3'],
      reason: '同一文件出现两次是有意的两次 occurrence，不能去重成一次',
    );
    expect(occurrences.map((o) => o.order), [0, 1, 2]);
    expect(occurrences[0].kind, CanonicalMediaKind.image);
    expect(occurrences[1].kind, CanonicalMediaKind.audio);
  });

  test('assigns the face each field is actually rendered on', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '[sound:prompt.mp3]',
        '<img src="answer.png">',
      ],
      frontFieldOrds: const {0},
      backFieldOrds: const {1},
    );

    expect(occurrences[0].side, MediaOccurrenceSide.front);
    expect(occurrences[1].side, MediaOccurrenceSide.back);
  });

  test('a field on both faces counts as front (FrontSide re-display)', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const ['[sound:shared.mp3]'],
      frontFieldOrds: const {0},
      backFieldOrds: const {0},
    );

    expect(occurrences.single.side, MediaOccurrenceSide.front);
  });

  test('a field rendered on neither face is not harvested', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '<img src="rendered.png">',
        '<img src="hidden.png">',
      ],
      frontFieldOrds: const {0},
      backFieldOrds: const <int>{},
    );

    expect(occurrences.map((o) => o.filename), ['rendered.png']);
  });

  test('without face facts only the role-bound fields are scanned', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '[sound:bound.mp3]',
        '<img src="hidden.png">',
      ],
      fallbackFieldIndices: const {0},
    );

    expect(occurrences, hasLength(1));
    expect(occurrences.single.filename, 'bound.mp3');
    expect(
      occurrences.single.side,
      MediaOccurrenceSide.unknown,
      reason: '没有模板事实时面归属未证，不得当成正面',
    );
  });

  test('recognises [anki:play:] markers and srcset first candidates', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '[anki:play:1:clip.mp3]',
        '<img src="fallback.png" srcset="wide.png 2x, narrow.png 1x">',
      ],
      frontFieldOrds: const {0, 1},
    );

    expect(occurrences.map((o) => o.filename), ['clip.mp3', 'wide.png']);
  });

  test('decodes percent-encoding once and neutralises traversal', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const [
        '<img src="my%20photo.png">',
        '[sound:../../etc/passwd.mp3]',
      ],
      frontFieldOrds: const {0, 1},
    );

    expect(
      occurrences.map((o) => o.filename),
      ['my photo.png', 'passwd.mp3'],
      reason: '路径段在提取时被剥成 basename，解析器只会拿到媒体目录内的名字',
    );
  });

  test('an img tag with both src and srcset is one occurrence', () {
    final occurrences = CardMediaExtractor.extract(
      fields: const ['<img srcset="a.png 2x" src="b.png">'],
      frontFieldOrds: const {0},
    );

    expect(occurrences, hasLength(1));
    expect(occurrences.single.filename, 'a.png');
  });
}
