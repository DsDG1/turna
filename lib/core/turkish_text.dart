/// Turkish-aware folding for **grading** typed answers.
///
/// Dart's default `toLowerCase()` is Unicode default case mapping, not
/// Turkish locale mapping:
/// - `'İ'` (U+0130 LATIN CAPITAL LETTER I WITH DOT ABOVE) becomes
///   `'i'` + combining dot above (U+0307) — two code units.
/// - `'I'` becomes `'i'`.
///
/// A learner who types the visually correct `iyi` against the keyed answer
/// `İyi` therefore fails a naive `toLowerCase()` compare. Dictionary lookup
/// (`LanguageCodes.lookupFoldKey`) keeps the linguistic `I → ı` rule; lesson
/// matching must stay **symmetric** for both sides of the compare.
///
/// This helper strips combining marks (U+0300–U+036F) and collapses the
/// dotted/dotless I family (`İ`, `I`, `ı`) to plain `i` so keyboard layout
/// (ASCII vs Turkish) does not change the grade. Apply the same function to
/// input and expected.
String foldTurkish(String s) {
  final buf = StringBuffer();
  for (final rune in s.runes) {
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    if (rune == 0x0130 || rune == 0x0049 || rune == 0x0131) {
      // İ, ASCII I, and dotless ı all fold to `i` for compare-only grading.
      buf.writeCharCode(0x0069);
      continue;
    }
    buf.writeCharCode(rune);
  }
  return buf.toString().toLowerCase();
}
