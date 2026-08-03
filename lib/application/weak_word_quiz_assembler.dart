// Dart imports:
import 'dart:math';

// Project imports:
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/domain/study/daily_stats.dart';

/// Builds a synthetic weak-word quiz lesson (ADR 0014).
///
/// Aggregation: mistakes in the last [windowDays] days, same [wordId] at least
/// [minMistakes] times. Cap [maxItems] questions.
///
/// For language-course words, display/translation come from the in-memory
/// `vocabById` table. For Anki-imported cards (word ids starting with
/// `anki-`), the vocab lookup misses — so we fall back to the mistake's frozen
/// [MistakeEntry.interactionSnapshot] (mirroring [MistakeReviewAssembler]) and
/// restore the AnkiCard front/back fields from there.
class WeakWordQuizAssembler {
  static const String lessonId = 'weak-words-quiz';
  static const String stageId = 'weak-words-stage';
  static const int defaultWindowDays = 30;
  static const int defaultMinMistakes = 2;
  static const int defaultMaxItems = 10;

  /// Filter mistake log → weak word ids (word-only; grammar keys skipped).
  ///
  /// [entries] is used both for counting and (for Anki word ids) as the source
  /// of the frozen interaction snapshot — so the most recent entry's snapshot
  /// wins when several entries share a word id.
  static List<WeakWord> aggregateWeakWords(
    List<MistakeEntry> entries, {
    DateTime? now,
    int windowDays = defaultWindowDays,
    int minMistakes = defaultMinMistakes,
    int limit = defaultMaxItems,
  }) {
    final cutoff =
        (now ?? DateTime.now()).subtract(Duration(days: windowDays));
    final counts = <String, ({int count, DateTime last, MistakeEntry? snapshot})>{};

    for (final e in entries) {
      if (e.timestamp.isBefore(cutoff)) continue;
      final id = e.wordId;
      if (id == null || id.isEmpty) continue;
      final prev = counts[id];
      if (prev == null) {
        counts[id] = (count: 1, last: e.timestamp, snapshot: e);
      } else {
        counts[id] = (
          count: prev.count + 1,
          last: e.timestamp.isAfter(prev.last) ? e.timestamp : prev.last,
          snapshot: e.timestamp.isAfter(prev.last) ? e : prev.snapshot,
        );
      }
    }

    final qualified = counts.entries
        .where((e) => e.value.count >= minMistakes)
        .toList()
      ..sort((a, b) {
        final byCount = b.value.count.compareTo(a.value.count);
        if (byCount != 0) return byCount;
        return b.value.last.compareTo(a.value.last);
      });

    final result = <WeakWord>[];
    for (final e in qualified) {
      if (result.length >= limit) break;
      // Anki word ids are not in vocabById — restore the display fields from
      // the most recent mistake snapshot's interaction (AnkiCard front/back).
      if (e.key.startsWith('anki-')) {
        final snap = e.value.snapshot?.interactionSnapshot;
        // Only AnkiCard (text flip) snapshots carry a term/translation the
        // weak-word quiz can render. Fidelity (ankiHtmlCard) and MCQ snapshots
        // have no gradable term for the quiz - skip them (deep-adaptation plan
        // §6.3: weak-word review is for vocab flip cards only).
        if (snap is! AnkiCard) continue;
        result.add(WeakWord(
          wordId: e.key,
          displayText: snap.front,
          translation: snap.back,
          mistakeCount: e.value.count,
          lastMistakeAt: e.value.last,
        ));
        continue;
      }
      final entry = vocabById[e.key];
      result.add(WeakWord(
        wordId: e.key,
        displayText: entry?.term ?? e.key,
        translation: entry?.translation,
        mistakeCount: e.value.count,
        lastMistakeAt: e.value.last,
      ));
    }
    return result;
  }

  /// Assemble a graded lesson: MCQ term→translation with distractors.
  ///
  /// For Anki weak words (no in-memory vocab distractor pool), the quiz falls
  /// back to a flip-card review (reusing the mistake snapshot's AnkiCard), so
  /// the user still re-encounters the card instead of being skipped.
  static Lesson assembleFromWeakWords(
    List<WeakWord> weakWords, {
    List<MistakeEntry>? mistakeEntries,
    Random? random,
    int maxItems = defaultMaxItems,
  }) {
    final rng = random ?? Random();
    final pool = weakWords.take(maxItems).toList();
    final vocabPool = vocabById.values.toList();
    final items = <Interaction>[];

    // Index of most-recent snapshot per word id (for Anki fallback).
    final snapshotByWordId = <String, MistakeEntry>{};
    if (mistakeEntries != null) {
      for (final e in mistakeEntries) {
        final wid = e.wordId;
        if (wid == null || wid.isEmpty) continue;
        final prev = snapshotByWordId[wid];
        if (prev == null || e.timestamp.isAfter(prev.timestamp)) {
          snapshotByWordId[wid] = e;
        }
      }
    }

    for (var i = 0; i < pool.length; i++) {
      final w = pool[i];

      // Anki weak word: fall back to the frozen AnkiCard snapshot (if any)
      // instead of synthesizing a vocab MCQ that would miss.
      if (w.wordId.startsWith('anki-')) {
        final snap = snapshotByWordId[w.wordId]?.interactionSnapshot;
        if (snap is AnkiCard) {
          items.add(snap.copyWith(id: 'weak-words-$i'));
          continue;
        }
        // No snapshot available — skip this weak word.
        continue;
      }

      final entry = vocabById[w.wordId];
      final translation = entry?.translation ?? w.translation;
      final term = entry?.term ?? w.displayText;

      if (translation == null || translation.isEmpty) {
        items.add(Interaction.typeTheWord(
          id: 'weak-words-$i',
          audioAsset: w.wordId,
          prompt: 'Type the meaning you keep missing',
          expected: term,
        ));
        continue;
      }

      final options = _buildOptions(
        correct: translation,
        vocabPool: vocabPool,
        excludeId: w.wordId,
        random: rng,
      );
      final correctIndex = options.indexOf(translation);

      items.add(Interaction.multipleChoice(
        id: 'weak-words-$i',
        prompt: 'What does "$term" mean?',
        options: options,
        correctIndex: correctIndex < 0 ? 0 : correctIndex,
      ));
    }

    return Lesson(
      id: lessonId,
      name: 'Weak Words',
      type: LessonType.review,
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [
          Stage(id: stageId, name: 'Weak Words', items: items),
        ],
      ),
    );
  }

  static List<String> _buildOptions({
    required String correct,
    required List<WordEntry> vocabPool,
    required String excludeId,
    required Random random,
  }) {
    final distractors = <String>{};
    final candidates = vocabPool
        .where((v) => v.id != excludeId && v.translation != correct)
        .map((v) => v.translation)
        .where((t) => t.isNotEmpty)
        .toList()
      ..shuffle(random);

    for (final t in candidates) {
      if (distractors.length >= 3) break;
      distractors.add(t);
    }

    // Pad if vocab too small.
    var pad = 0;
    while (distractors.length < 3) {
      distractors.add('—$pad—');
      pad++;
    }

    final options = [correct, ...distractors.take(3)]..shuffle(random);
    return options;
  }
}
