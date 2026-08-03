// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i26;
import 'package:flutter/foundation.dart' as _i29;
import 'package:flutter/material.dart' as _i27;
import 'package:varnamala/application/ai/ai_hint_provider.dart' as _i28;
import 'package:varnamala/domain/course/mistake_entry.dart' as _i30;
import 'package:varnamala/views/ai/ai_hint_chat_page.dart' as _i1;
import 'package:varnamala/views/ai/ai_hub_page.dart' as _i2;
import 'package:varnamala/views/ai/ai_wish_chat_page.dart' as _i3;
import 'package:varnamala/views/ai/textbook/textbook_import_page.dart' as _i23;
import 'package:varnamala/views/anki/anki_card_browser_page.dart' as _i4;
import 'package:varnamala/views/anki/anki_deck_stats_page.dart' as _i5;
import 'package:varnamala/views/anki/anki_import_screen.dart' as _i6;
import 'package:varnamala/views/anki/anki_review_screen.dart' as _i7;
import 'package:varnamala/views/anki/anki_review_session_page.dart' as _i8;
import 'package:varnamala/views/characters/character_drawing.dart' as _i24;
import 'package:varnamala/views/courses/course_management_page.dart' as _i9;
import 'package:varnamala/views/courses/section_picker_page.dart' as _i20;
import 'package:varnamala/views/dictionary/dictionary_page.dart' as _i11;
import 'package:varnamala/views/home/home_page.dart' as _i13;
import 'package:varnamala/views/lesson/new_lesson_screen.dart' as _i18;
import 'package:varnamala/views/play/daily_challenge_screen.dart' as _i10;
import 'package:varnamala/views/play/match_words.dart' as _i14;
import 'package:varnamala/views/play/weak_words_page.dart' as _i25;
import 'package:varnamala/views/review/grammar_review_screen.dart' as _i12;
import 'package:varnamala/views/review/mistake_list_page.dart' as _i15;
import 'package:varnamala/views/review/mistake_practice_screen.dart' as _i16;
import 'package:varnamala/views/review/mistake_review_page.dart' as _i17;
import 'package:varnamala/views/review/review_progress_page.dart' as _i19;
import 'package:varnamala/views/review/srs_review_screen.dart' as _i22;
import 'package:varnamala/views/splash/splash_page.dart' as _i21;

/// generated route for
/// [_i1.AiHintChatPage]
class AiHintChatRoute extends _i26.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i27.Key? key,
    _i28.AiQuestionContext? context,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(key: key, context: context),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i26.PageInfo page = _i26.PageInfo(
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

  final _i27.Key? key;

  final _i28.AiQuestionContext? context;

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
class AiHubRoute extends _i26.PageRouteInfo<void> {
  const AiHubRoute({List<_i26.PageRouteInfo>? children})
      : super(AiHubRoute.name, initialChildren: children);

  static const String name = 'AiHubRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i2.AiHubPage();
    },
  );
}

/// generated route for
/// [_i3.AiWishChatPage]
class AiWishChatRoute extends _i26.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i26.PageRouteInfo>? children})
      : super(AiWishChatRoute.name, initialChildren: children);

  static const String name = 'AiWishChatRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i3.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i4.AnkiCardBrowserPage]
class AnkiCardBrowserRoute
    extends _i26.PageRouteInfo<AnkiCardBrowserRouteArgs> {
  AnkiCardBrowserRoute({
    _i27.Key? key,
    required String importId,
    required String title,
    String? sectionId,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          AnkiCardBrowserRoute.name,
          args: AnkiCardBrowserRouteArgs(
            key: key,
            importId: importId,
            title: title,
            sectionId: sectionId,
          ),
          initialChildren: children,
        );

  static const String name = 'AnkiCardBrowserRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiCardBrowserRouteArgs>();
      return _i4.AnkiCardBrowserPage(
        key: args.key,
        importId: args.importId,
        title: args.title,
        sectionId: args.sectionId,
      );
    },
  );
}

class AnkiCardBrowserRouteArgs {
  const AnkiCardBrowserRouteArgs({
    this.key,
    required this.importId,
    required this.title,
    this.sectionId,
  });

  final _i27.Key? key;

  final String importId;

  final String title;

  final String? sectionId;

  @override
  String toString() {
    return 'AnkiCardBrowserRouteArgs{key: $key, importId: $importId, title: $title, sectionId: $sectionId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiCardBrowserRouteArgs) return false;
    return key == other.key &&
        importId == other.importId &&
        title == other.title &&
        sectionId == other.sectionId;
  }

  @override
  int get hashCode =>
      key.hashCode ^ importId.hashCode ^ title.hashCode ^ sectionId.hashCode;
}

/// generated route for
/// [_i5.AnkiDeckStatsPage]
class AnkiDeckStatsRoute extends _i26.PageRouteInfo<AnkiDeckStatsRouteArgs> {
  AnkiDeckStatsRoute({
    _i27.Key? key,
    required String importId,
    required String title,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          AnkiDeckStatsRoute.name,
          args: AnkiDeckStatsRouteArgs(
            key: key,
            importId: importId,
            title: title,
          ),
          initialChildren: children,
        );

  static const String name = 'AnkiDeckStatsRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiDeckStatsRouteArgs>();
      return _i5.AnkiDeckStatsPage(
        key: args.key,
        importId: args.importId,
        title: args.title,
      );
    },
  );
}

class AnkiDeckStatsRouteArgs {
  const AnkiDeckStatsRouteArgs({
    this.key,
    required this.importId,
    required this.title,
  });

  final _i27.Key? key;

  final String importId;

  final String title;

  @override
  String toString() {
    return 'AnkiDeckStatsRouteArgs{key: $key, importId: $importId, title: $title}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiDeckStatsRouteArgs) return false;
    return key == other.key &&
        importId == other.importId &&
        title == other.title;
  }

  @override
  int get hashCode => key.hashCode ^ importId.hashCode ^ title.hashCode;
}

/// generated route for
/// [_i6.AnkiImportPage]
class AnkiImportRoute extends _i26.PageRouteInfo<AnkiImportRouteArgs> {
  AnkiImportRoute({
    _i29.Key? key,
    bool startWithSample = false,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          AnkiImportRoute.name,
          args: AnkiImportRouteArgs(key: key, startWithSample: startWithSample),
          initialChildren: children,
        );

  static const String name = 'AnkiImportRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiImportRouteArgs>(
        orElse: () => const AnkiImportRouteArgs(),
      );
      return _i6.AnkiImportPage(
        key: args.key,
        startWithSample: args.startWithSample,
      );
    },
  );
}

class AnkiImportRouteArgs {
  const AnkiImportRouteArgs({this.key, this.startWithSample = false});

  final _i29.Key? key;

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
/// [_i7.AnkiReviewPage]
class AnkiReviewRoute extends _i26.PageRouteInfo<void> {
  const AnkiReviewRoute({List<_i26.PageRouteInfo>? children})
      : super(AnkiReviewRoute.name, initialChildren: children);

  static const String name = 'AnkiReviewRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i7.AnkiReviewPage();
    },
  );
}

/// generated route for
/// [_i8.AnkiReviewSessionPage]
class AnkiReviewSessionRoute
    extends _i26.PageRouteInfo<AnkiReviewSessionRouteArgs> {
  AnkiReviewSessionRoute({
    _i27.Key? key,
    String? sectionId,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          AnkiReviewSessionRoute.name,
          args: AnkiReviewSessionRouteArgs(key: key, sectionId: sectionId),
          initialChildren: children,
        );

  static const String name = 'AnkiReviewSessionRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiReviewSessionRouteArgs>(
        orElse: () => const AnkiReviewSessionRouteArgs(),
      );
      return _i8.AnkiReviewSessionPage(
        key: args.key,
        sectionId: args.sectionId,
      );
    },
  );
}

class AnkiReviewSessionRouteArgs {
  const AnkiReviewSessionRouteArgs({this.key, this.sectionId});

  final _i27.Key? key;

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
/// [_i9.CourseManagementPage]
class CourseManagementRoute extends _i26.PageRouteInfo<void> {
  const CourseManagementRoute({List<_i26.PageRouteInfo>? children})
      : super(CourseManagementRoute.name, initialChildren: children);

  static const String name = 'CourseManagementRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i9.CourseManagementPage();
    },
  );
}

/// generated route for
/// [_i10.DailyChallengePage]
class DailyChallengeRoute extends _i26.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i26.PageRouteInfo>? children})
      : super(DailyChallengeRoute.name, initialChildren: children);

  static const String name = 'DailyChallengeRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i10.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i11.DictionaryPage]
class DictionaryRoute extends _i26.PageRouteInfo<void> {
  const DictionaryRoute({List<_i26.PageRouteInfo>? children})
      : super(DictionaryRoute.name, initialChildren: children);

  static const String name = 'DictionaryRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i11.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i12.GrammarReviewPage]
class GrammarReviewRoute extends _i26.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i26.PageRouteInfo>? children})
      : super(GrammarReviewRoute.name, initialChildren: children);

  static const String name = 'GrammarReviewRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i12.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i13.HomePage]
class HomeRoute extends _i26.PageRouteInfo<void> {
  const HomeRoute({List<_i26.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i13.HomePage();
    },
  );
}

/// generated route for
/// [_i14.MatchWordsPage]
class MatchWordsRoute extends _i26.PageRouteInfo<void> {
  const MatchWordsRoute({List<_i26.PageRouteInfo>? children})
      : super(MatchWordsRoute.name, initialChildren: children);

  static const String name = 'MatchWordsRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i14.MatchWordsPage();
    },
  );
}

/// generated route for
/// [_i15.MistakeListPage]
class MistakeListRoute extends _i26.PageRouteInfo<void> {
  const MistakeListRoute({List<_i26.PageRouteInfo>? children})
      : super(MistakeListRoute.name, initialChildren: children);

  static const String name = 'MistakeListRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i15.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i16.MistakePracticePage]
class MistakePracticeRoute
    extends _i26.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i27.Key? key,
    required _i30.MistakeEntry entry,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(key: key, entry: entry),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i16.MistakePracticePage(key: args.key, entry: args.entry);
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({this.key, required this.entry});

  final _i27.Key? key;

  final _i30.MistakeEntry entry;

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
/// [_i17.MistakeReviewPage]
class MistakeReviewRoute extends _i26.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i26.PageRouteInfo>? children})
      : super(MistakeReviewRoute.name, initialChildren: children);

  static const String name = 'MistakeReviewRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i17.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i18.NewLessonPage]
class NewLessonRoute extends _i26.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i27.Key? key,
    required String lessonId,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(key: key, lessonId: lessonId),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i18.NewLessonPage(key: args.key, lessonId: args.lessonId);
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({this.key, required this.lessonId});

  final _i27.Key? key;

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
/// [_i19.ReviewProgressPage]
class ReviewProgressRoute extends _i26.PageRouteInfo<void> {
  const ReviewProgressRoute({List<_i26.PageRouteInfo>? children})
      : super(ReviewProgressRoute.name, initialChildren: children);

  static const String name = 'ReviewProgressRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i19.ReviewProgressPage();
    },
  );
}

/// generated route for
/// [_i20.SectionPickerPage]
class SectionPickerRoute extends _i26.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i26.PageRouteInfo>? children})
      : super(SectionPickerRoute.name, initialChildren: children);

  static const String name = 'SectionPickerRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i20.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i21.SplashPage]
class SplashRoute extends _i26.PageRouteInfo<void> {
  const SplashRoute({List<_i26.PageRouteInfo>? children})
      : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i21.SplashPage();
    },
  );
}

/// generated route for
/// [_i22.SrsReviewPage]
class SrsReviewRoute extends _i26.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i26.PageRouteInfo>? children})
      : super(SrsReviewRoute.name, initialChildren: children);

  static const String name = 'SrsReviewRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i22.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i23.TextbookImportPage]
class TextbookImportRoute extends _i26.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i26.PageRouteInfo>? children})
      : super(TextbookImportRoute.name, initialChildren: children);

  static const String name = 'TextbookImportRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i23.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i24.VowelAndConsonantLearningPage]
class VowelAndConsonantLearningRoute
    extends _i26.PageRouteInfo<VowelAndConsonantLearningRouteArgs> {
  VowelAndConsonantLearningRoute({
    _i27.Key? key,
    required _i24.CharacterLearningMode mode,
    List<_i26.PageRouteInfo>? children,
  }) : super(
          VowelAndConsonantLearningRoute.name,
          args: VowelAndConsonantLearningRouteArgs(key: key, mode: mode),
          initialChildren: children,
        );

  static const String name = 'VowelAndConsonantLearningRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VowelAndConsonantLearningRouteArgs>();
      return _i24.VowelAndConsonantLearningPage(key: args.key, mode: args.mode);
    },
  );
}

class VowelAndConsonantLearningRouteArgs {
  const VowelAndConsonantLearningRouteArgs({this.key, required this.mode});

  final _i27.Key? key;

  final _i24.CharacterLearningMode mode;

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
/// [_i25.WeakWordsPage]
class WeakWordsRoute extends _i26.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i26.PageRouteInfo>? children})
      : super(WeakWordsRoute.name, initialChildren: children);

  static const String name = 'WeakWordsRoute';

  static _i26.PageInfo page = _i26.PageInfo(
    name,
    builder: (data) {
      return const _i25.WeakWordsPage();
    },
  );
}
