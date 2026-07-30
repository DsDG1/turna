// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i24;
import 'package:flutter/material.dart' as _i25;
import 'package:varnamala/application/ai/ai_hint_provider.dart' as _i26;
import 'package:varnamala/domain/course/mistake_entry.dart' as _i27;
import 'package:varnamala/views/ai/ai_hint_chat_page.dart' as _i1;
import 'package:varnamala/views/ai/ai_hub_page.dart' as _i2;
import 'package:varnamala/views/ai/ai_wish_chat_page.dart' as _i3;
import 'package:varnamala/views/ai/textbook/textbook_import_page.dart' as _i21;
import 'package:varnamala/views/anki/anki_import_screen.dart' as _i4;
import 'package:varnamala/views/anki/anki_review_screen.dart' as _i5;
import 'package:varnamala/views/anki/anki_review_session_page.dart' as _i6;
import 'package:varnamala/views/characters/character_drawing.dart' as _i22;
import 'package:varnamala/views/courses/course_management_page.dart' as _i7;
import 'package:varnamala/views/courses/section_picker_page.dart' as _i18;
import 'package:varnamala/views/dictionary/dictionary_page.dart' as _i9;
import 'package:varnamala/views/home/home_page.dart' as _i11;
import 'package:varnamala/views/lesson/new_lesson_screen.dart' as _i16;
import 'package:varnamala/views/play/daily_challenge_screen.dart' as _i8;
import 'package:varnamala/views/play/match_words.dart' as _i12;
import 'package:varnamala/views/play/weak_words_page.dart' as _i23;
import 'package:varnamala/views/review/grammar_review_screen.dart' as _i10;
import 'package:varnamala/views/review/mistake_list_page.dart' as _i13;
import 'package:varnamala/views/review/mistake_practice_screen.dart' as _i14;
import 'package:varnamala/views/review/mistake_review_page.dart' as _i15;
import 'package:varnamala/views/review/review_progress_page.dart' as _i17;
import 'package:varnamala/views/review/srs_review_screen.dart' as _i20;
import 'package:varnamala/views/splash/splash_page.dart' as _i19;

/// generated route for
/// [_i1.AiHintChatPage]
class AiHintChatRoute extends _i24.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i25.Key? key,
    _i26.AiQuestionContext? context,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(key: key, context: context),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiHintChatRouteArgs>(
        orElse: () => const AiHintChatRouteArgs(),
      );
      return _i1.AiHintChatPage(key: args.key, context: args.context);
    },
  );
}

class AiHintChatRouteArgs {
  const AiHintChatRouteArgs({this.key, this.context});

  final _i25.Key? key;

  final _i26.AiQuestionContext? context;

  @override
  String toString() {
    return 'AiHintChatRouteArgs{key: $key, context: $context}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AiHintChatRouteArgs) return false;
    return key == other.key && context == other.context;
  }

  @override
  int get hashCode => key.hashCode ^ context.hashCode;
}

/// generated route for
/// [_i2.AiHubPage]
class AiHubRoute extends _i24.PageRouteInfo<void> {
  const AiHubRoute({List<_i24.PageRouteInfo>? children})
      : super(AiHubRoute.name, initialChildren: children);

  static const String name = 'AiHubRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i2.AiHubPage();
    },
  );
}

/// generated route for
/// [_i3.AiWishChatPage]
class AiWishChatRoute extends _i24.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i24.PageRouteInfo>? children})
      : super(AiWishChatRoute.name, initialChildren: children);

  static const String name = 'AiWishChatRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i3.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i4.AnkiImportPage]
class AnkiImportRoute extends _i24.PageRouteInfo<AnkiImportRouteArgs> {
  AnkiImportRoute({
    _i25.Key? key,
    bool startWithSample = false,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          AnkiImportRoute.name,
          args: AnkiImportRouteArgs(key: key, startWithSample: startWithSample),
          initialChildren: children,
        );

  static const String name = 'AnkiImportRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiImportRouteArgs>(
        orElse: () => const AnkiImportRouteArgs(),
      );
      return _i4.AnkiImportPage(
        key: args.key,
        startWithSample: args.startWithSample,
      );
    },
  );
}

class AnkiImportRouteArgs {
  const AnkiImportRouteArgs({this.key, this.startWithSample = false});

  final _i25.Key? key;

  final bool startWithSample;

  @override
  String toString() {
    return 'AnkiImportRouteArgs{key: $key, startWithSample: $startWithSample}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiImportRouteArgs) return false;
    return key == other.key && startWithSample == other.startWithSample;
  }

  @override
  int get hashCode => key.hashCode ^ startWithSample.hashCode;
}

/// generated route for
/// [_i5.AnkiReviewPage]
class AnkiReviewRoute extends _i24.PageRouteInfo<void> {
  const AnkiReviewRoute({List<_i24.PageRouteInfo>? children})
      : super(AnkiReviewRoute.name, initialChildren: children);

  static const String name = 'AnkiReviewRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i5.AnkiReviewPage();
    },
  );
}

/// generated route for
/// [_i6.AnkiReviewSessionPage]
class AnkiReviewSessionRoute
    extends _i24.PageRouteInfo<AnkiReviewSessionRouteArgs> {
  AnkiReviewSessionRoute({
    _i25.Key? key,
    String? sectionId,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          AnkiReviewSessionRoute.name,
          args: AnkiReviewSessionRouteArgs(key: key, sectionId: sectionId),
          initialChildren: children,
        );

  static const String name = 'AnkiReviewSessionRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiReviewSessionRouteArgs>(
        orElse: () => const AnkiReviewSessionRouteArgs(),
      );
      return _i6.AnkiReviewSessionPage(
        key: args.key,
        sectionId: args.sectionId,
      );
    },
  );
}

class AnkiReviewSessionRouteArgs {
  const AnkiReviewSessionRouteArgs({this.key, this.sectionId});

  final _i25.Key? key;

  final String? sectionId;

  @override
  String toString() {
    return 'AnkiReviewSessionRouteArgs{key: $key, sectionId: $sectionId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiReviewSessionRouteArgs) return false;
    return key == other.key && sectionId == other.sectionId;
  }

  @override
  int get hashCode => key.hashCode ^ sectionId.hashCode;
}

/// generated route for
/// [_i7.CourseManagementPage]
class CourseManagementRoute extends _i24.PageRouteInfo<void> {
  const CourseManagementRoute({List<_i24.PageRouteInfo>? children})
      : super(CourseManagementRoute.name, initialChildren: children);

  static const String name = 'CourseManagementRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i7.CourseManagementPage();
    },
  );
}

/// generated route for
/// [_i8.DailyChallengePage]
class DailyChallengeRoute extends _i24.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i24.PageRouteInfo>? children})
      : super(DailyChallengeRoute.name, initialChildren: children);

  static const String name = 'DailyChallengeRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i8.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i9.DictionaryPage]
class DictionaryRoute extends _i24.PageRouteInfo<void> {
  const DictionaryRoute({List<_i24.PageRouteInfo>? children})
      : super(DictionaryRoute.name, initialChildren: children);

  static const String name = 'DictionaryRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i9.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i10.GrammarReviewPage]
class GrammarReviewRoute extends _i24.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i24.PageRouteInfo>? children})
      : super(GrammarReviewRoute.name, initialChildren: children);

  static const String name = 'GrammarReviewRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i10.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i11.HomePage]
class HomeRoute extends _i24.PageRouteInfo<void> {
  const HomeRoute({List<_i24.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i11.HomePage();
    },
  );
}

/// generated route for
/// [_i12.MatchWordsPage]
class MatchWordsRoute extends _i24.PageRouteInfo<void> {
  const MatchWordsRoute({List<_i24.PageRouteInfo>? children})
      : super(MatchWordsRoute.name, initialChildren: children);

  static const String name = 'MatchWordsRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i12.MatchWordsPage();
    },
  );
}

/// generated route for
/// [_i13.MistakeListPage]
class MistakeListRoute extends _i24.PageRouteInfo<void> {
  const MistakeListRoute({List<_i24.PageRouteInfo>? children})
      : super(MistakeListRoute.name, initialChildren: children);

  static const String name = 'MistakeListRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i13.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i14.MistakePracticePage]
class MistakePracticeRoute
    extends _i24.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i25.Key? key,
    required _i27.MistakeEntry entry,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(key: key, entry: entry),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i14.MistakePracticePage(key: args.key, entry: args.entry);
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({this.key, required this.entry});

  final _i25.Key? key;

  final _i27.MistakeEntry entry;

  @override
  String toString() {
    return 'MistakePracticeRouteArgs{key: $key, entry: $entry}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MistakePracticeRouteArgs) return false;
    return key == other.key && entry == other.entry;
  }

  @override
  int get hashCode => key.hashCode ^ entry.hashCode;
}

/// generated route for
/// [_i15.MistakeReviewPage]
class MistakeReviewRoute extends _i24.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i24.PageRouteInfo>? children})
      : super(MistakeReviewRoute.name, initialChildren: children);

  static const String name = 'MistakeReviewRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i15.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i16.NewLessonPage]
class NewLessonRoute extends _i24.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i25.Key? key,
    required String lessonId,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(key: key, lessonId: lessonId),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i16.NewLessonPage(key: args.key, lessonId: args.lessonId);
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({this.key, required this.lessonId});

  final _i25.Key? key;

  final String lessonId;

  @override
  String toString() {
    return 'NewLessonRouteArgs{key: $key, lessonId: $lessonId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NewLessonRouteArgs) return false;
    return key == other.key && lessonId == other.lessonId;
  }

  @override
  int get hashCode => key.hashCode ^ lessonId.hashCode;
}

/// generated route for
/// [_i17.ReviewProgressPage]
class ReviewProgressRoute extends _i24.PageRouteInfo<void> {
  const ReviewProgressRoute({List<_i24.PageRouteInfo>? children})
      : super(ReviewProgressRoute.name, initialChildren: children);

  static const String name = 'ReviewProgressRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i17.ReviewProgressPage();
    },
  );
}

/// generated route for
/// [_i18.SectionPickerPage]
class SectionPickerRoute extends _i24.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i24.PageRouteInfo>? children})
      : super(SectionPickerRoute.name, initialChildren: children);

  static const String name = 'SectionPickerRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i18.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i19.SplashPage]
class SplashRoute extends _i24.PageRouteInfo<void> {
  const SplashRoute({List<_i24.PageRouteInfo>? children})
      : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i19.SplashPage();
    },
  );
}

/// generated route for
/// [_i20.SrsReviewPage]
class SrsReviewRoute extends _i24.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i24.PageRouteInfo>? children})
      : super(SrsReviewRoute.name, initialChildren: children);

  static const String name = 'SrsReviewRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i20.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i21.TextbookImportPage]
class TextbookImportRoute extends _i24.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i24.PageRouteInfo>? children})
      : super(TextbookImportRoute.name, initialChildren: children);

  static const String name = 'TextbookImportRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i21.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i22.VowelAndConsonantLearningPage]
class VowelAndConsonantLearningRoute
    extends _i24.PageRouteInfo<VowelAndConsonantLearningRouteArgs> {
  VowelAndConsonantLearningRoute({
    _i25.Key? key,
    required _i22.CharacterLearningMode mode,
    List<_i24.PageRouteInfo>? children,
  }) : super(
          VowelAndConsonantLearningRoute.name,
          args: VowelAndConsonantLearningRouteArgs(key: key, mode: mode),
          initialChildren: children,
        );

  static const String name = 'VowelAndConsonantLearningRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VowelAndConsonantLearningRouteArgs>();
      return _i22.VowelAndConsonantLearningPage(key: args.key, mode: args.mode);
    },
  );
}

class VowelAndConsonantLearningRouteArgs {
  const VowelAndConsonantLearningRouteArgs({this.key, required this.mode});

  final _i25.Key? key;

  final _i22.CharacterLearningMode mode;

  @override
  String toString() {
    return 'VowelAndConsonantLearningRouteArgs{key: $key, mode: $mode}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VowelAndConsonantLearningRouteArgs) return false;
    return key == other.key && mode == other.mode;
  }

  @override
  int get hashCode => key.hashCode ^ mode.hashCode;
}

/// generated route for
/// [_i23.WeakWordsPage]
class WeakWordsRoute extends _i24.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i24.PageRouteInfo>? children})
      : super(WeakWordsRoute.name, initialChildren: children);

  static const String name = 'WeakWordsRoute';

  static _i24.PageInfo page = _i24.PageInfo(
    name,
    builder: (data) {
      return const _i23.WeakWordsPage();
    },
  );
}
