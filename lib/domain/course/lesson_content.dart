// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'listening_phase.dart';
import 'reading_passage.dart';
import 'stage.dart';
import 'sub_lesson.dart';

part 'lesson_content.freezed.dart';
part 'lesson_content.g.dart';

/// The body of a [Lesson].
///
/// Different lesson templates use different parts of this union-like shape:
/// - **Normal / review / challenge** lessons use [stages].
/// - **Intro / practice** lessons use [subLessons].
/// - **Listening** lessons use [listeningPhases].
/// - **Reading** lessons use [readingPassage] plus [stages] for questions.
///
/// All fields are optional so existing JSON keeps working and the loader can
/// normalize flat `questions` into the appropriate structure.
@freezed
abstract class LessonContent with _$LessonContent {
  const factory LessonContent({
    /// Legacy / default flat stage list. Used by review, challenge, and
    /// reading-comprehension questions.
    @Default(<Stage>[]) List<Stage> stages,

    /// Intro / practice lessons split their content into sub-lessons.
    @Default(<SubLesson>[]) List<SubLesson> subLessons,

    /// Listening lessons divide into phases (word pairing, dialogue, summary).
    @Default(<ListeningPhase>[]) List<ListeningPhase> listeningPhases,

    /// Structured reading passage for reading lessons.
    ReadingPassage? readingPassage,

    /// Deprecated: optional reading passage as a plain string. Kept for
    /// backward compatibility; prefer [readingPassage].
    @Default('') String passage,

    /// Optional audio asset for listening lessons (legacy single-audio path).
    String? audioAsset,

    /// Grammar point ids this lesson teaches. Used to register grammar points
    /// into the grammar-review SRS queue when the lesson is opened.
    @Default(<String>[]) List<String> linkedGrammarPointIds,
  }) = _LessonContent;

  factory LessonContent.fromJson(Map<String, dynamic> json) =>
      _$LessonContentFromJson(json);
}
