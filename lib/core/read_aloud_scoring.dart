// Project imports:
import 'package:turna/core/turkish_text.dart';

/// Word-level scoring for read-aloud (跟读) exercises (ADR 0061).
///
/// What this measures is **intelligibility at the word level**: which words of
/// the reference sentence a listener-with-a-transcript would have heard. It
/// deliberately does not score pronunciation quality — that tier has no
/// Turkish provider (see project-guide §15).
///
/// The pipeline is pure: fold (Turkish-aware, via [foldTurkish]) → strip
/// punctuation → tokenize → order-preserving alignment → ratio. Both sides of
/// the compare go through the same normalization, mirroring how typed-answer
/// grading works (`TypeTheWordRenderer`).

/// Pass threshold: the fraction of reference words the recognizer heard.
///
/// 0.6 tolerates one dropped word in a three-word sentence — a learner whose
/// pronunciation made the recognizer catch most of a sentence has
/// communicated it. Lowering this toward "every word" would grade accent
/// harshly (recognition is the proxy), which is exactly the bias §15 rules
/// out.
const double kReadAloudPassRatio = 0.6;

/// Per-word outcome: [word] is the reference token, [heard] the transcript
/// token it paired with (`null` = not heard). When [matched] is true and
/// [heard] differs from [word], the learner said a close variant (e.g. an
/// extra suffix) worth showing.
typedef ReadAloudWordOutcome = ({String word, bool matched, String? heard});

/// Whole-utterance outcome. [ratio] is matchedWords / totalWords (1.0 for an
/// empty reference — nothing was asked, so nothing was missed; the validator
/// forbids authoring that shape anyway).
typedef ReadAloudScore = ({
  double ratio,
  bool passed,
  List<ReadAloudWordOutcome> words,
});

/// Scores [transcript] (recognizer output) against [reference].
ReadAloudScore scoreReadAloud(String reference, String transcript) {
  final refWords = _tokenize(reference);
  final heardWords = _tokenize(transcript);
  final words = _align(refWords, heardWords);
  final matchedCount = words.where((w) => w.matched).length;
  final ratio = refWords.isEmpty ? 1.0 : matchedCount / refWords.length;
  return (
    ratio: ratio,
    passed: ratio >= kReadAloudPassRatio,
    words: words,
  );
}

/// One token: the display form [raw] (original case/punctuation-stripped)
/// and the compare form [folded] used for matching.
typedef ReadAloudToken = ({String raw, String folded});

/// Number-to-word mappings for common numbers in speech recognition.
/// Speech-to-text engines (Google / Apple) frequently transcribe spoken
/// number words (e.g. "bir", "iki") as digits ("1", "2").
const Map<String, String> _kNumberToWord = {
  '0': 'sıfır',
  '1': 'bir',
  '2': 'iki',
  '3': 'üç',
  '4': 'dört',
  '5': 'beş',
  '6': 'altı',
  '7': 'yedi',
  '8': 'sekiz',
  '9': 'dokuz',
  '10': 'on',
};

/// Folds and tokenizes: punctuation and everything non-letter becomes a
/// word boundary.
///
/// The rune whitelist is Latin-plus-extensions (covering Turkish, the builtin
/// French course and Latin-script imports); every other script's runes become
/// separators, so a transcript in the wrong language tokenizes to nothing and
/// scores zero rather than half-matching by accident.
List<ReadAloudToken> _tokenize(String text) {
  final buf = StringBuffer();
  for (final rune in text.runes) {
    buf.writeCharCode(_isWordRune(rune) ? rune : 0x20);
  }
  return buf
      .toString()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => (raw: w, folded: _normalizeFolded(w)))
      .toList();
}

String _normalizeFolded(String token) {
  final folded = foldTurkish(token);
  // Apostrophes in proper nouns (e.g. Türkiye'de ↔ Türkiyede) are stripped
  // in the folded comparison form so transcriptions without apostrophes match.
  return folded.replaceAll("'", '').replaceAll('’', '');
}

bool _isWordRune(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) || // A-Z
    (rune >= 0x0061 && rune <= 0x007A) || // a-z
    (rune >= 0x0030 && rune <= 0x0039) || // 0-9
    (rune >= 0x00C0 && rune <= 0x024F) || // Latin Extended-A/B (ğ ı ş ç ö ü …)
    (rune >= 0x1E00 && rune <= 0x1EFF) || // Latin Extended Additional
    rune == 0x0027 || // apostrophe (ev'in)
    rune == 0x2019; // typographic apostrophe

/// Whether a heard word counts as the reference word. Exact after folding,
/// digit-word equivalent, or close enough that the difference is
/// agglutination / a single slip:
///
/// - **number equivalence** — digits and words match symmetrically
///   (`1` ↔ `bir`, `2` ↔ `iki`).
/// - **prefix extension** — one word extends the other with a shared stem of
///   ≥ 4 runes (`merhaba` ↔ `merhabalar`). Turkish suffixation preserves the
///   stem, so a stem heard with different suffixes was still pronounced.
/// - **single edit** — edit distance ≤ 1 for words of ≥ 4 runes
///   (`ışık` ↔ `isik`: wrong vowel quality, stem intact).
///
/// Both carve-outs require a minimum stem length so short function words
/// (`bu`, `ev`) never fuzzy-match their neighbors.
bool matchesWord(String reference, String heard) {
  if (reference == heard) return true;
  if (_kNumberToWord[reference] == heard || _kNumberToWord[heard] == reference) {
    return true;
  }
  if (reference.length < 4 || heard.length < 4) return false;
  final (short, long) = reference.length <= heard.length
      ? (reference, heard)
      : (heard, reference);
  if (long.startsWith(short) && short.length >= 4) return true;
  if (reference.length >= 4 &&
      heard.length >= 4 &&
      _editDistanceAtMost1(reference, heard)) {
    return true;
  }
  return false;
}

bool _editDistanceAtMost1(String a, String b) {
  // Classic two-pointer single-edit check; lengths differing by ≥ 2 are an
  // automatic no (and prefix extension already covered difference-at-end).
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a.codeUnitAt(i) == b.codeUnitAt(j)) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length == b.length) {
      i++;
      j++;
    } else if (a.length < b.length) {
      j++; // insertion in b
    } else {
      i++; // insertion in a
    }
  }
  // Trailing tail on the longer side is one more edit.
  edits += (a.length - i) + (b.length - j);
  return edits <= 1;
}

/// Order-preserving best alignment of reference words to heard words.
///
/// Longest-common-subsequence dynamics with [matchesWord] as the (fuzzy)
/// equality on folded forms: a reference word can pair with any later-unused
/// heard word, so filler words the learner inserted ("ah", "yani") simply
/// stay unpaired instead of shifting the whole alignment. Unpaired reference
/// words are misses; unpaired heard words are ignored.
List<ReadAloudWordOutcome> _align(
  List<ReadAloudToken> reference,
  List<ReadAloudToken> heard,
) {
  // dp[i][j] = best score for reference[i:] against heard[j:].
  final dp = List.generate(
    reference.length + 1,
    (_) => List<int>.filled(heard.length + 1, 0),
  );
  for (var i = reference.length - 1; i >= 0; i--) {
    for (var j = heard.length - 1; j >= 0; j--) {
      final skipEither =
          dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      final pairHere = matchesWord(reference[i].folded, heard[j].folded)
          ? 1 + dp[i + 1][j + 1]
          : 0;
      dp[i][j] = skipEither > pairHere ? skipEither : pairHere;
    }
  }
  // Walk the table: prefer pairing when it was part of the optimum, so each
  // reference word carries the heard word it actually matched (or null).
  final out = <ReadAloudWordOutcome>[];
  var i = 0;
  var j = 0;
  while (i < reference.length) {
    if (j < heard.length &&
        matchesWord(reference[i].folded, heard[j].folded) &&
        1 + dp[i + 1][j + 1] == dp[i][j]) {
      out.add(
        (word: reference[i].raw, matched: true, heard: heard[j].raw),
      );
      i++;
      j++;
    } else if (dp[i + 1][j] == dp[i][j]) {
      out.add((word: reference[i].raw, matched: false, heard: null));
      i++;
    } else {
      // The optimum skips this heard word (filler the learner inserted):
      // drop it without consuming the reference word.
      j++;
    }
  }
  return out;
}
