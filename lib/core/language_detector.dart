/// Detects the spoken language of a short text string so TTS can pick a
/// matching voice.
///
/// Returns a BCP-47 base language code (e.g. `tr`, `zh`, `en`, `ru`).
///
/// Detection is reliable for non-Latin scripts and for Latin text containing
/// Turkish-specific letters (`ğ ı ş İ`). Plain ASCII Latin - which could be
/// Turkish *or* a translation language (English, Spanish, …) - cannot be
/// disambiguated by script alone, so it falls back to [nativeLanguage]: the
/// per-course "translation language" the user configures. Callers that know a
/// string is in the target language (vocab terms, listening transcripts)
/// should bypass detection and speak with the target voice directly.
///
/// For paired content whose two halves are opposite languages (MCQ prompt vs.
/// options, Anki card front vs. back) use [inferOptionLanguage] /
/// [detectCardPair] - they use one side's reliable signal to infer the other,
/// so a plain-Latin Turkish word like "merhaba" is still spoken as Turkish
/// when its sibling carries a Turkish letter.
class LanguageDetector {
  const LanguageDetector();

  /// Turkish-specific letters. `ç ö ü` are shared with French/German/etc. so
  /// they are NOT treated as Turkish-specific; `ğ ı ş İ` (and their case
  /// variants) unambiguously indicate Turkish (or another Turkic language).
  static final _turkishSpecific =
      RegExp('[ğĞıİşŞ]');

  // Non-Latin script ranges - each maps to a definite TTS language.
  static final _kana = RegExp('[぀-ヿㇰ-ㇿ]');
  static final _hangul = RegExp('[가-힯ᄀ-ᇿ]');
  static final _han = RegExp('[一-鿿㐀-䶿豈-﫿]');
  static final _cyrillic = RegExp('[Ѐ-ӿԀ-ԯ]');
  static final _arabic =
      RegExp('[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
  static final _thai = RegExp('[฀-๿]');
  static final _devanagari = RegExp('[ऀ-ॿ]');
  static final _greek = RegExp('[Ͱ-Ͽἀ-῿]');
  static final _hebrew = RegExp('[֐-׿]');
  static final _latinLetter = RegExp('[A-Za-zÀ-ɏḀ-ỿ]');

  /// True when [text] carries a "reliable" language signal: a non-Latin
  /// script run or a Turkish-specific letter. Such text routes to a definite
  /// voice regardless of the ambiguous-Latin fallback.
  bool hasReliableSignal(String text) {
    return _turkishSpecific.hasMatch(text) ||
        _kana.hasMatch(text) ||
        _hangul.hasMatch(text) ||
        _han.hasMatch(text) ||
        _cyrillic.hasMatch(text) ||
        _arabic.hasMatch(text) ||
        _thai.hasMatch(text) ||
        _devanagari.hasMatch(text) ||
        _greek.hasMatch(text) ||
        _hebrew.hasMatch(text);
  }

  /// Detect the language of a single string.
  ///
  /// [targetLanguage] is the course's target language (Turkish in this build),
  /// used for Turkish-specific letters and as the unknown-text fallback.
  /// [nativeLanguage] is the per-course translation language, used as the
  /// fallback for plain-Latin text.
  String detect(
    String text, {
    required String targetLanguage,
    required String nativeLanguage,
  }) {
    final t = text.trim();
    if (t.isEmpty) return targetLanguage;

    // Kana before Han: Japanese mixes both, and kana is the Japanese marker.
    if (_kana.hasMatch(t)) return 'ja';
    if (_hangul.hasMatch(t)) return 'ko';
    if (_han.hasMatch(t)) return 'zh';
    if (_cyrillic.hasMatch(t)) return 'ru';
    if (_arabic.hasMatch(t)) return 'ar';
    if (_thai.hasMatch(t)) return 'th';
    if (_devanagari.hasMatch(t)) return 'hi';
    if (_greek.hasMatch(t)) return 'el';
    if (_hebrew.hasMatch(t)) return 'he';

    // Turkish-specific letters -> target language.
    if (_turkishSpecific.hasMatch(t)) return targetLanguage;

    // Plain Latin -> configured native/translation language.
    if (_latinLetter.hasMatch(t)) return nativeLanguage;

    // Digits / punctuation only -> target.
    return targetLanguage;
  }

  /// Infer the language MCQ answer options are in, given the [prompt].
  ///
  /// In a translation drill the options are the *opposite* language of the
  /// prompt. Plain-ASCII Turkish cannot be told apart from English by script,
  /// so we use the prompt's reliable signal: if the prompt looks Turkish
  /// (Turkish-specific letters) the options are the native language;
  /// otherwise (English, Chinese, Russian, …) the options are the target
  /// language. Defaulting ambiguous options to the target language is the
  /// right call in a language-learning app - mis-pronouncing Turkish as the
  /// native language is worse than the reverse.
  String inferOptionLanguage(
    String prompt, {
    required String targetLanguage,
    required String nativeLanguage,
  }) {
    if (_turkishSpecific.hasMatch(prompt)) return nativeLanguage;
    return targetLanguage;
  }

  /// Resolve the spoken language for a single MCQ [option], given the
  /// inferred [optionLanguage] for the whole question.
  ///
  /// Options that carry a reliable script signal (Turkish letters / non-Latin
  /// script) override the inferred language; plain-Latin options follow
  /// [optionLanguage].
  String detectOption(
    String option, {
    required String optionLanguage,
    required String targetLanguage,
    required String nativeLanguage,
  }) {
    if (hasReliableSignal(option)) {
      return detect(option,
          targetLanguage: targetLanguage, nativeLanguage: nativeLanguage);
    }
    return optionLanguage;
  }

  /// Detect the languages of an Anki card's front/back pair.
  ///
  /// If exactly one face carries a Turkish-specific letter, that face is the
  /// target language and the other is detected independently (so a Chinese
  /// back face still routes to `zh`, a plain-Latin back face to the native
  /// language). If both or neither face has Turkish letters, each face is
  /// detected independently.
  ({String front, String back}) detectCardPair(
    String front,
    String back, {
    required String targetLanguage,
    required String nativeLanguage,
  }) {
    final frontTurkish = _turkishSpecific.hasMatch(front);
    final backTurkish = _turkishSpecific.hasMatch(back);
    if (frontTurkish && !backTurkish) {
      return (
        front: targetLanguage,
        back: detect(back,
            targetLanguage: targetLanguage, nativeLanguage: nativeLanguage),
      );
    }
    if (backTurkish && !frontTurkish) {
      return (
        front: detect(front,
            targetLanguage: targetLanguage, nativeLanguage: nativeLanguage),
        back: targetLanguage,
      );
    }
    return (
      front: detect(front,
          targetLanguage: targetLanguage, nativeLanguage: nativeLanguage),
      back: detect(back,
          targetLanguage: targetLanguage, nativeLanguage: nativeLanguage),
    );
  }
}
