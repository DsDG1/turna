// Tests for the read-aloud (跟读) word-matching scorer, ADR 0061.
//
// What is under test is the pure pipeline: Turkish-aware folding, the
// agglutination-tolerant word match, order-preserving alignment around
// filler words, and the pass threshold. The cases that matter most are the
// near-misses — the recognizer hearing a suffix variant or a wrong vowel —
// because those are exactly the situations a real learner's recording
// produces.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/read_aloud_scoring.dart';

void main() {
  group('folding and tokenizing', () {
    test('folds Turkish İ/ı/I on both sides of the compare', () {
      final score = scoreReadAloud('İyi akşamlar', 'iyi aksamlar');
      // 'aksamlar' vs 'akşamlar': one substitution in a ≥5 word → match.
      expect(score.ratio, 1.0);
      expect(score.passed, isTrue);
    });

    test('punctuation and case never change the score', () {
      expect(
        scoreReadAloud('Merhaba!', 'merhaba').ratio,
        scoreReadAloud('merhaba', 'Merhaba!').ratio,
      );
    });

    test('a non-Latin transcript scores zero, not half', () {
      final score = scoreReadAloud('merhaba', '你好');
      expect(score.ratio, 0.0);
      expect(score.passed, isFalse);
    });

    test('empty reference is vacuously perfect', () {
      final score = scoreReadAloud('', 'anything');
      expect(score.ratio, 1.0);
    });
  });

  group('word match tolerances', () {
    test('suffix extension counts as the same word', () {
      // merhaba ↔ merhabalar: stem preserved, extra suffix heard.
      final score = scoreReadAloud('merhaba', 'merhabalar');
      expect(score.ratio, 1.0);
    });

    test('short function words do not fuzzy-match', () {
      // 'bu' vs 'bi': both < 4 runes, no prefix carve-out applies.
      final score = scoreReadAloud('bu', 'bi');
      expect(score.ratio, 0.0);
    });

    test('two vowel-quality slips in one word are a miss', () {
      // ş→s and ü→u = two edits; the tolerance is one. A word differing in
      // more than one rune was not reliably heard.
      final score = scoreReadAloud('teşekkürler', 'tesekkurler');
      expect(score.words.single.matched, isFalse);
      expect(score.ratio, 0.0);
    });

    test('number word and digit match symmetrically', () {
      final score = scoreReadAloud('Bir çay lütfen', '1 çay lütfen');
      expect(score.ratio, 1.0);
      expect(score.passed, isTrue);
      expect(score.words.first.matched, isTrue);

      final reverse = scoreReadAloud('1 kahve', 'bir kahve');
      expect(reverse.ratio, 1.0);
      expect(reverse.passed, isTrue);
    });

    test('4-letter words tolerate single vowel/consonant slip (ADR 0061)', () {
      final score = scoreReadAloud('ışık', 'isik');
      expect(score.words.single.matched, isTrue);
      expect(score.ratio, 1.0);
      expect(score.passed, isTrue);
    });

    test('proper noun apostrophe matches transcript without apostrophe', () {
      final score = scoreReadAloud("Türkiye'de", 'Türkiyede');
      expect(score.words.single.matched, isTrue);
      expect(score.ratio, 1.0);
      expect(score.passed, isTrue);
    });

    test('circumflex vowels match unaccented transcript', () {
      final score = scoreReadAloud('hâlâ buradayım', 'hala buradayim');
      expect(score.ratio, 1.0);
      expect(score.passed, isTrue);
    });
  });

  group('alignment', () {
    test('filler words shift nothing and cost nothing', () {
      final score = scoreReadAloud(
        'merhaba teşekkürler',
        'merhaba yani teşekkürler',
      );
      expect(score.ratio, 1.0);
      expect(score.words.map((w) => w.matched), everyElement(isTrue));
    });

    test('a skipped word is a miss that can still pass', () {
      // 3 reference words, 2 heard: 2/3 ≥ 0.6 passes.
      final score = scoreReadAloud('bir çay lütfen', 'bir lütfen');
      expect(score.ratio, closeTo(2 / 3, 1e-9));
      expect(score.passed, isTrue);
      expect(
        score.words.where((w) => !w.matched).single.word,
        'çay',
      );
    });

    test('below the threshold fails', () {
      // 5 reference words, 2 heard: 0.4 < 0.6.
      final score = scoreReadAloud(
        'nasılsın iyiyim teşekkür ederim',
        'iyiyim ederim',
      );
      expect(score.passed, isFalse);
    });

    test('outcomes carry display forms, not folded ones', () {
      final score = scoreReadAloud('Merhaba Teşekkürler', 'merhaba');
      expect(score.words.first.word, 'Merhaba');
      expect(score.words.first.heard, 'merhaba');
    });

    test('the pass threshold constant stays put', () {
      // The threshold is a product decision (ADR 0061): one dropped word in
      // three passes, two in three does not. Pin it so a refactor cannot
      // silently change what learners experience.
      expect(kReadAloudPassRatio, 0.6);
    });
  });
}
