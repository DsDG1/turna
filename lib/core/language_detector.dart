/// Detects the spoken language of a short text string so TTS can pick a
/// matching voice.
///
/// Returns a BCP-47 base language code (e.g. `tr`, `zh`, `en`, `ru`).
///
/// Detection is reliable for non-Latin scripts and for Latin text containing
/// target-language signature letters (Turkish `ğ ı ş İ`, French `à é è ç`,
/// …). Plain ASCII Latin - which could be the target *or* a translation
/// language (English, Spanish, …) - cannot be disambiguated by script alone,
/// so it falls back to [nativeLanguage]: the per-course "translation
/// language" the user configures. The signature letter set comes from the
/// language manifest (`signatureChars`); callers pass it via the
/// `signatureChars` parameter — `null` keeps the original Turkish set.
/// Callers that know a string is in the target language (vocab terms,
/// listening transcripts) should bypass detection and speak with the target
/// voice directly.
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
  static final _turkishSpecific = RegExp('[ğĞıİşŞ]');

  /// Default signature used when a caller passes no [signatureChars]: the
  /// Turkish set above (this app's original target language).
  static const String defaultSignatureChars = 'ğĞıİşŞ';

  /// Compile a per-language "signature" character class. [signatureChars] is
  /// the set of letters that appear in the target language but (almost) never
  /// in the learner's native language — a reliable target-language signal for
  /// Latin-script text. `null` falls back to the Turkish default for
  /// backwards compatibility; an empty/blank string means "no signature"
  /// (Latin-only detection for languages without distinguishing letters).
  static RegExp? _signaturePattern(String? signatureChars) {
    if (signatureChars == null) return _turkishSpecific;
    if (signatureChars.trim().isEmpty) return null;
    final body = signatureChars.split('').map(RegExp.escape).join();
    return RegExp('[$body]');
  }

  static bool _signatureMatch(String text, RegExp? signature) =>
      signature != null && signature.hasMatch(text);

  // Non-Latin script ranges - each maps to a definite TTS language.
  static final _kana = RegExp('[぀-ヿㇰ-ㇿ]');
  static final _hangul = RegExp('[가-힯ᄀ-ᇿ]');
  static final _han = RegExp('[一-鿿㐀-䶿豈-﫿]');
  static final _cyrillic = RegExp('[Ѐ-ӿԀ-ԯ]');
  static final _arabic = RegExp('[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
  static final _thai = RegExp('[฀-๿]');
  static final _devanagari = RegExp('[ऀ-ॿ]');
  static final _greek = RegExp('[Ͱ-Ͽἀ-῿]');
  static final _hebrew = RegExp('[֐-׿]');
  static final _latinLetter = RegExp('[A-Za-zÀ-ɏḀ-ỿ]');

  /// True when [text] carries a "reliable" language signal: a non-Latin
  /// script run or a target-language signature letter. Such text routes to a
  /// definite voice regardless of the ambiguous-Latin fallback.
  bool hasReliableSignal(String text, {String? signatureChars}) {
    return _signatureMatch(text, _signaturePattern(signatureChars)) ||
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
  /// [targetLanguage] is the course's target language, used for signature
  /// letters and as the unknown-text fallback. [nativeLanguage] is the
  /// per-course translation language, used as the fallback for plain-Latin
  /// text. [signatureChars] is the target language's distinguishing-letter
  /// set (see [_signaturePattern]).
  String detect(
    String text, {
    required String targetLanguage,
    required String nativeLanguage,
    String? signatureChars,
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

    // Target-language signature letters -> target language.
    if (_signatureMatch(t, _signaturePattern(signatureChars))) {
      return targetLanguage;
    }

    // Plain Latin -> configured native/translation language.
    if (_latinLetter.hasMatch(t)) return nativeLanguage;

    // Digits / punctuation only -> target.
    return targetLanguage;
  }

  /// Infer the language MCQ answer options are in, given the [prompt].
  ///
  /// In a translation drill the options are the *opposite* language of the
  /// prompt. Plain-ASCII target-language text cannot be told apart from the
  /// native language by script, so we use the prompt's reliable signal: if the
  /// prompt looks like the target language (signature letters) the options
  /// are the native language; otherwise (English, Chinese, Russian, …) the
  /// options are the target language. Defaulting ambiguous options to the
  /// target language is the right call in a language-learning app -
  /// mis-pronouncing the target as the native language is worse than the
  /// reverse.
  String inferOptionLanguage(
    String prompt, {
    required String targetLanguage,
    required String nativeLanguage,
    String? signatureChars,
  }) {
    if (_signatureMatch(prompt, _signaturePattern(signatureChars))) {
      return nativeLanguage;
    }
    return targetLanguage;
  }

  /// Resolve the spoken language for a single MCQ [option], given the
  /// inferred [optionLanguage] for the whole question.
  ///
  /// Options that carry a reliable script signal (target-language signature
  /// letters / non-Latin script) override the inferred language; plain-Latin
  /// options follow [optionLanguage].
  String detectOption(
    String option, {
    required String optionLanguage,
    required String targetLanguage,
    required String nativeLanguage,
    String? signatureChars,
  }) {
    if (hasReliableSignal(option, signatureChars: signatureChars)) {
      return detect(option,
          targetLanguage: targetLanguage,
          nativeLanguage: nativeLanguage,
          signatureChars: signatureChars);
    }
    return optionLanguage;
  }

  /// Detect the languages of an Anki card's front/back pair.
  ///
  /// If exactly one face carries a target-language signature letter, that
  /// face is the target language and the other is detected independently (so
  /// a Chinese back face still routes to `zh`, a plain-Latin back face to the
  /// native language). If both or neither face has signature letters, each
  /// face is detected independently.
  ({String front, String back}) detectCardPair(
    String front,
    String back, {
    required String targetLanguage,
    required String nativeLanguage,
    String? signatureChars,
  }) {
    final signature = _signaturePattern(signatureChars);
    final frontTarget = _signatureMatch(front, signature);
    final backTarget = _signatureMatch(back, signature);
    if (frontTarget && !backTarget) {
      return (
        front: targetLanguage,
        back: detect(back,
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            signatureChars: signatureChars),
      );
    }
    if (backTarget && !frontTarget) {
      return (
        front: detect(front,
            targetLanguage: targetLanguage,
            nativeLanguage: nativeLanguage,
            signatureChars: signatureChars),
        back: targetLanguage,
      );
    }
    return (
      front: detect(front,
          targetLanguage: targetLanguage,
          nativeLanguage: nativeLanguage,
          signatureChars: signatureChars),
      back: detect(back,
          targetLanguage: targetLanguage,
          nativeLanguage: nativeLanguage,
          signatureChars: signatureChars),
    );
  }
}
