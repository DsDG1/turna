// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i18;
import 'package:flutter/material.dart' as _i19;
import 'package:varnamala/application/ai/ai_hint_provider.dart' as _i20;
import 'package:varnamala/domain/course/mistake_entry.dart' as _i21;
import 'package:varnamala/views/ai/ai_hint_chat_page.dart' as _i1;
import 'package:varnamala/views/ai/ai_wish_chat_page.dart' as _i2;
import 'package:varnamala/views/ai/textbook/textbook_import_page.dart' as _i15;
import 'package:varnamala/views/characters/character_drawing.dart' as _i16;
import 'package:varnamala/views/courses/section_picker_page.dart' as _i12;
import 'package:varnamala/views/dictionary/dictionary_page.dart' as _i4;
import 'package:varnamala/views/home/home_page.dart' as _i6;
import 'package:varnamala/views/lesson/new_lesson_screen.dart' as _i11;
import 'package:varnamala/views/play/daily_challenge_screen.dart' as _i3;
import 'package:varnamala/views/play/match_words.dart' as _i7;
import 'package:varnamala/views/play/weak_words_page.dart' as _i17;
import 'package:varnamala/views/review/grammar_review_screen.dart' as _i5;
import 'package:varnamala/views/review/mistake_list_page.dart' as _i8;
import 'package:varnamala/views/review/mistake_practice_screen.dart' as _i9;
import 'package:varnamala/views/review/mistake_review_page.dart' as _i10;
import 'package:varnamala/views/review/srs_review_screen.dart' as _i14;
import 'package:varnamala/views/splash/splash_page.dart' as _i13;

/// generated route for
/// [_i1.AiHintChatPage]
class AiHintChatRoute extends _i18.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i19.Key? key,
    _i20.AiQuestionContext? context,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(
            key: key,
            context: context,
          ),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiHintChatRouteArgs>(
          orElse: () => const AiHintChatRouteArgs());
      return _i1.AiHintChatPage(
        key: args.key,
        context: args.context,
      );
    },
  );
}

class AiHintChatRouteArgs {
  const AiHintChatRouteArgs({
    this.key,
    this.context,
  });

  final _i19.Key? key;

  final _i20.AiQuestionContext? context;

  @override
  String toString() {
    return 'AiHintChatRouteArgs{key: $key, context: $context}';
  }
}

/// generated route for
/// [_i2.AiWishChatPage]
class AiWishChatRoute extends _i18.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i18.PageRouteInfo>? children})
      : super(
          AiWishChatRoute.name,
          initialChildren: children,
        );

  static const String name = 'AiWishChatRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i2.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i3.DailyChallengePage]
class DailyChallengeRoute extends _i18.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i18.PageRouteInfo>? children})
      : super(
          DailyChallengeRoute.name,
          initialChildren: children,
        );

  static const String name = 'DailyChallengeRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i3.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i4.DictionaryPage]
class DictionaryRoute extends _i18.PageRouteInfo<void> {
  const DictionaryRoute({List<_i18.PageRouteInfo>? children})
      : super(
          DictionaryRoute.name,
          initialChildren: children,
        );

  static const String name = 'DictionaryRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i4.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i5.GrammarReviewPage]
class GrammarReviewRoute extends _i18.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i18.PageRouteInfo>? children})
      : super(
          GrammarReviewRoute.name,
          initialChildren: children,
        );

  static const String name = 'GrammarReviewRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i5.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i6.HomePage]
class HomeRoute extends _i18.PageRouteInfo<void> {
  const HomeRoute({List<_i18.PageRouteInfo>? children})
      : super(
          HomeRoute.name,
          initialChildren: children,
        );

  static const String name = 'HomeRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i6.HomePage();
    },
  );
}

/// generated route for
/// [_i7.MatchWordsPage]
class MatchWordsRoute extends _i18.PageRouteInfo<void> {
  const MatchWordsRoute({List<_i18.PageRouteInfo>? children})
      : super(
          MatchWordsRoute.name,
          initialChildren: children,
        );

  static const String name = 'MatchWordsRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i7.MatchWordsPage();
    },
  );
}

/// generated route for
/// [_i8.MistakeListPage]
class MistakeListRoute extends _i18.PageRouteInfo<void> {
  const MistakeListRoute({List<_i18.PageRouteInfo>? children})
      : super(
          MistakeListRoute.name,
          initialChildren: children,
        );

  static const String name = 'MistakeListRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i8.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i9.MistakePracticePage]
class MistakePracticeRoute
    extends _i18.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i19.Key? key,
    required _i21.MistakeEntry entry,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(
            key: key,
            entry: entry,
          ),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i9.MistakePracticePage(
        key: args.key,
        entry: args.entry,
      );
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({
    this.key,
    required this.entry,
  });

  final _i19.Key? key;

  final _i21.MistakeEntry entry;

  @override
  String toString() {
    return 'MistakePracticeRouteArgs{key: $key, entry: $entry}';
  }
}

/// generated route for
/// [_i10.MistakeReviewPage]
class MistakeReviewRoute extends _i18.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i18.PageRouteInfo>? children})
      : super(
          MistakeReviewRoute.name,
          initialChildren: children,
        );

  static const String name = 'MistakeReviewRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i10.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i11.NewLessonPage]
class NewLessonRoute extends _i18.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i19.Key? key,
    required String lessonId,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(
            key: key,
            lessonId: lessonId,
          ),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i11.NewLessonPage(
        key: args.key,
        lessonId: args.lessonId,
      );
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({
    this.key,
    required this.lessonId,
  });

  final _i19.Key? key;

  final String lessonId;

  @override
  String toString() {
    return 'NewLessonRouteArgs{key: $key, lessonId: $lessonId}';
  }
}

/// generated route for
/// [_i12.SectionPickerPage]
class SectionPickerRoute extends _i18.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i18.PageRouteInfo>? children})
      : super(
          SectionPickerRoute.name,
          initialChildren: children,
        );

  static const String name = 'SectionPickerRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i12.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i13.SplashPage]
class SplashRoute extends _i18.PageRouteInfo<void> {
  const SplashRoute({List<_i18.PageRouteInfo>? children})
      : super(
          SplashRoute.name,
          initialChildren: children,
        );

  static const String name = 'SplashRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i13.SplashPage();
    },
  );
}

/// generated route for
/// [_i14.SrsReviewPage]
class SrsReviewRoute extends _i18.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i18.PageRouteInfo>? children})
      : super(
          SrsReviewRoute.name,
          initialChildren: children,
        );

  static const String name = 'SrsReviewRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i14.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i15.TextbookImportPage]
class TextbookImportRoute extends _i18.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i18.PageRouteInfo>? children})
      : super(
          TextbookImportRoute.name,
          initialChildren: children,
        );

  static const String name = 'TextbookImportRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i15.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i16.VowelAndConsonantLearningPage]
class VowelAndConsonantLearningRoute
    extends _i18.PageRouteInfo<VowelAndConsonantLearningRouteArgs> {
  VowelAndConsonantLearningRoute({
    _i19.Key? key,
    required _i16.CharacterLearningMode mode,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          VowelAndConsonantLearningRoute.name,
          args: VowelAndConsonantLearningRouteArgs(
            key: key,
            mode: mode,
          ),
          initialChildren: children,
        );

  static const String name = 'VowelAndConsonantLearningRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VowelAndConsonantLearningRouteArgs>();
      return _i16.VowelAndConsonantLearningPage(
        key: args.key,
        mode: args.mode,
      );
    },
  );
}

class VowelAndConsonantLearningRouteArgs {
  const VowelAndConsonantLearningRouteArgs({
    this.key,
    required this.mode,
  });

  final _i19.Key? key;

  final _i16.CharacterLearningMode mode;

  @override
  String toString() {
    return 'VowelAndConsonantLearningRouteArgs{key: $key, mode: $mode}';
  }
}

/// generated route for
/// [_i17.WeakWordsPage]
class WeakWordsRoute extends _i18.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i18.PageRouteInfo>? children})
      : super(
          WeakWordsRoute.name,
          initialChildren: children,
        );

  static const String name = 'WeakWordsRoute';

  static _i18.PageInfo page = _i18.PageInfo(
    name,
    builder: (data) {
      return const _i17.WeakWordsPage();
    },
  );
}
