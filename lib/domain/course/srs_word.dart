// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'srs_word.freezed.dart';
part 'srs_word.g.dart';

/// Type of item tracked in the SRS queue.
enum SrsItemType { word, expression }

/// Spaced-repetition state for a [WordEntry] or [Expression]. Persisted per-id.
/// Uses SM-2 algorithm fields: interval, ease, repetitions, lapses.
@freezed
class SrsWord with _$SrsWord {
  const factory SrsWord({
    required String wordId,
    required DateTime dueAt,
    @Default(1) int intervalDays,
    @Default(2.5) double ease,
    @Default(0) int reps,
    @Default(0) int lapses,
    @Default(false) bool isLeech,
    @Default(SrsItemType.word) SrsItemType type,
  }) = _SrsWord;

  factory SrsWord.fromJson(Map<String, dynamic> json) =>
      _$SrsWordFromJson(json);

  /// Factory for a never-seen item (due immediately).
  factory SrsWord.fresh(String wordId) => SrsWord(
        wordId: wordId,
        dueAt: DateTime.now(),
      );
}