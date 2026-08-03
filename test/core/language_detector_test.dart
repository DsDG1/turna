import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/language_detector.dart';

void main() {
  const detector = LanguageDetector();
  // Turkish is the only target language in this build; English is the default
  // per-course native language.
  const target = 'tr';
  const native = 'en';

  group('detect - non-Latin scripts', () {
    test('Chinese (Han) -> zh', () {
      expect(
          detector.detect('你好', targetLanguage: target, nativeLanguage: native),
          'zh');
      expect(
          detector.detect('谢谢', targetLanguage: target, nativeLanguage: native),
          'zh');
    });

    test('Japanese (Kana) -> ja even with Kanji', () {
      expect(
          detector.detect('こんにちは',
              targetLanguage: target, nativeLanguage: native),
          'ja');
      expect(
          detector.detect('おはよう',
              targetLanguage: target, nativeLanguage: native),
          'ja');
    });

    test('Korean (Hangul) -> ko', () {
      expect(
          detector.detect('안녕하세요',
              targetLanguage: target, nativeLanguage: native),
          'ko');
    });

    test('Cyrillic -> ru', () {
      expect(
          detector.detect('привет',
              targetLanguage: target, nativeLanguage: native),
          'ru');
      expect(
          detector.detect('спасибо',
              targetLanguage: target, nativeLanguage: native),
          'ru');
    });

    test('Arabic -> ar', () {
      expect(
          detector.detect('مرحبا',
              targetLanguage: target, nativeLanguage: native),
          'ar');
    });

    test('Thai -> th', () {
      expect(
          detector.detect('สวัสดี',
              targetLanguage: target, nativeLanguage: native),
          'th');
    });

    test('Devanagari -> hi', () {
      expect(
          detector.detect('नमस्ते',
              targetLanguage: target, nativeLanguage: native),
          'hi');
    });

    test('Greek -> el', () {
      expect(
          detector.detect('γεια',
              targetLanguage: target, nativeLanguage: native),
          'el');
    });

    test('Hebrew -> he', () {
      expect(
          detector.detect('שלום',
              targetLanguage: target, nativeLanguage: native),
          'he');
    });
  });

  group('detect - Latin script', () {
    test('Turkish-specific letters -> target language', () {
      expect(
          detector.detect('teşekkürler',
              targetLanguage: target, nativeLanguage: native),
          target);
      // 'günaydın' has dotless ı (U+0131) -> Turkish-specific.
      expect(
          detector.detect('günaydın',
              targetLanguage: target, nativeLanguage: native),
          target);
      // ı (dotless i) and İ (dotted I) are Turkish-specific.
      expect(
          detector.detect('hayır',
              targetLanguage: target, nativeLanguage: native),
          target);
      expect(
          detector.detect('İstanbul',
              targetLanguage: target, nativeLanguage: native),
          target);
    });

    test('plain ASCII Latin (incl. "Merhaba" with no diacritics) -> native',
        () {
      expect(
          detector.detect('hello',
              targetLanguage: target, nativeLanguage: native),
          native);
      expect(
          detector.detect('Merhaba',
              targetLanguage: target, nativeLanguage: native),
          native);
      expect(
          detector.detect('merhaba',
              targetLanguage: target, nativeLanguage: native),
          native);
    });

    test('plain ASCII Latin respects a different native language', () {
      // A Chinese-native course: plain Latin still falls back to the configured
      // native language.
      expect(
          detector.detect('hello',
              targetLanguage: target, nativeLanguage: 'zh'),
          'zh');
    });

    test('ç ö ü alone are NOT Turkish-specific (shared with French/German)',
        () {
      // "café" has é/ç-like Latin but no ğ/ı/ş -> native fallback.
      expect(
          detector.detect('café',
              targetLanguage: target, nativeLanguage: native),
          native);
      expect(
          detector.detect('über',
              targetLanguage: target, nativeLanguage: native),
          native);
    });
  });

  group('detect - edge cases', () {
    test('empty -> target', () {
      expect(
          detector.detect('', targetLanguage: target, nativeLanguage: native),
          target);
      expect(
          detector.detect('   ',
              targetLanguage: target, nativeLanguage: native),
          target);
    });

    test('digits / punctuation only -> target', () {
      expect(
          detector.detect('123',
              targetLanguage: target, nativeLanguage: native),
          target);
      expect(
          detector.detect('!!!',
              targetLanguage: target, nativeLanguage: native),
          target);
    });
  });

  group('hasReliableSignal', () {
    test('true for non-Latin and Turkish-specific', () {
      expect(detector.hasReliableSignal('你好'), isTrue);
      expect(detector.hasReliableSignal('teşekkürler'), isTrue);
      expect(detector.hasReliableSignal('привет'), isTrue);
    });

    test('false for plain ASCII Latin', () {
      expect(detector.hasReliableSignal('hello'), isFalse);
      expect(detector.hasReliableSignal('merhaba'), isFalse);
    });
  });

  group('inferOptionLanguage (MCQ direction inference)', () {
    test('Turkish prompt (Turkish-specific letters) -> options are native', () {
      // "What does teşekkürler mean?" -> options are English translations.
      expect(
        detector.inferOptionLanguage('teşekkürler',
            targetLanguage: target, nativeLanguage: native),
        native,
      );
    });

    test('English prompt (plain Latin) -> options are target', () {
      // "Pick the Turkish word for hello" -> options are Turkish.
      expect(
        detector.inferOptionLanguage('hello',
            targetLanguage: target, nativeLanguage: native),
        target,
      );
    });

    test('Chinese prompt (non-Latin) -> options are target', () {
      expect(
        detector.inferOptionLanguage('你好',
            targetLanguage: target, nativeLanguage: native),
        target,
      );
    });

    test(
        'plain-Latin Turkish prompt (no diacritics) defaults options to target',
        () {
      // Ambiguous: "merhaba" as a prompt. We default options to the target
      // language so Turkish pronunciation wins (accepted tradeoff).
      expect(
        detector.inferOptionLanguage('merhaba',
            targetLanguage: target, nativeLanguage: native),
        target,
      );
    });
  });

  group('detectOption', () {
    test('reliable-signal option overrides the inferred language', () {
      // A "pick Turkish" question whose options are mostly Turkish: optionLang
      // is target, and a Turkish-letter option stays target.
      expect(
        detector.detectOption('teşekkürler',
            optionLanguage: target,
            targetLanguage: target,
            nativeLanguage: native),
        target,
      );
      // A Chinese distractor in the same question routes to zh.
      expect(
        detector.detectOption('谢谢',
            optionLanguage: target,
            targetLanguage: target,
            nativeLanguage: native),
        'zh',
      );
    });

    test('plain-Latin option follows the inferred option language', () {
      // "pick Turkish for hello": optionLang = target, plain-Latin Turkish
      // option "merhaba" -> spoken as target (the whole point).
      expect(
        detector.detectOption('merhaba',
            optionLanguage: target,
            targetLanguage: target,
            nativeLanguage: native),
        target,
      );
      // "pick English for teşekkürler": optionLang = native, plain-Latin
      // English option "thank you" -> spoken as native.
      expect(
        detector.detectOption('thank you',
            optionLanguage: native,
            targetLanguage: target,
            nativeLanguage: native),
        native,
      );
    });
  });

  group('detectCardPair (Anki front/back)', () {
    test(
        'front Turkish-specific, back plain Latin -> front target, back native',
        () {
      final pair = detector.detectCardPair('teşekkürler', 'thank you',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, target);
      expect(pair.back, native);
    });

    test(
        'back Turkish-specific, front plain Latin -> back target, front native',
        () {
      final pair = detector.detectCardPair('hello', 'teşekkürler',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, native);
      expect(pair.back, target);
    });

    test(
        'both faces plain-Latin Turkish (no diacritics) -> independent -> native',
        () {
      // "merhaba" has no Turkish-specific letter, so the pair logic can't tell
      // which face is Turkish; each is detected independently -> native.
      final pair = detector.detectCardPair('hello', 'merhaba',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, native);
      expect(pair.back, native);
    });

    test('front Turkish-specific, back Chinese -> front target, back zh', () {
      final pair = detector.detectCardPair('günaydın', '早上好',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, target);
      expect(pair.back, 'zh');
    });

    test(
        'front Turkish-specific, back Turkish-specific -> both independent (target)',
        () {
      final pair = detector.detectCardPair('teşekkürler', 'günaydın',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, target);
      expect(pair.back, target);
    });

    test('neither face Turkish-specific -> each detected independently', () {
      final pair = detector.detectCardPair('hello', '你好',
          targetLanguage: target, nativeLanguage: native);
      expect(pair.front, native);
      expect(pair.back, 'zh');
    });
  });
}
