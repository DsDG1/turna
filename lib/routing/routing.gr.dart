// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i41;

import 'package:auto_route/auto_route.dart' as _i33;
import 'package:collection/collection.dart' as _i44;
import 'package:flutter/foundation.dart' as _i36;
import 'package:flutter/material.dart' as _i34;
import 'package:turna/application/ai/ai_hint_provider.dart' as _i35;
import 'package:turna/application/anki/anki_importer.dart' as _i37;
import 'package:turna/domain/course/mistake_entry.dart' as _i38;
import 'package:turna/domain/review/recall_outcome.dart' as _i42;
import 'package:turna/domain/review/review_item.dart' as _i39;
import 'package:turna/domain/review/review_ledger.dart' as _i43;
import 'package:turna/domain/review/review_ledger_resolver.dart' as _i40;
import 'package:turna/views/ai/ai_diagnosis_page.dart' as _i2;
import 'package:turna/views/ai/ai_feature_guide_page.dart' as _i3;
import 'package:turna/views/ai/ai_hint_chat_page.dart' as _i4;
import 'package:turna/views/ai/ai_hub_page.dart' as _i5;
import 'package:turna/views/ai/ai_saved_list_page.dart' as _i6;
import 'package:turna/views/ai/ai_tutor_chat_page.dart' as _i7;
import 'package:turna/views/ai/ai_wish_chat_page.dart' as _i8;
import 'package:turna/views/ai/textbook/textbook_import_page.dart' as _i29;
import 'package:turna/views/anki/anki_card_browser_page.dart' as _i9;
import 'package:turna/views/anki/anki_deck_stats_page.dart' as _i10;
import 'package:turna/views/anki/anki_import_screen.dart' as _i11;
import 'package:turna/views/anki/anki_review_screen.dart' as _i12;
import 'package:turna/views/anki/anki_review_session_page.dart' as _i13;
import 'package:turna/views/characters/character_drawing.dart' as _i31;
import 'package:turna/views/courses/course_management_page.dart' as _i14;
import 'package:turna/views/courses/section_picker_page.dart' as _i25;
import 'package:turna/views/dictionary/dictionary_page.dart' as _i16;
import 'package:turna/views/home/home_page.dart' as _i18;
import 'package:turna/views/lesson/new_lesson_screen.dart' as _i23;
import 'package:turna/views/play/daily_challenge_screen.dart' as _i15;
import 'package:turna/views/play/match_words.dart' as _i19;
import 'package:turna/views/play/weak_words_page.dart' as _i32;
import 'package:turna/views/profile/achievements_page.dart' as _i1;
import 'package:turna/views/review/grammar_review_screen.dart' as _i17;
import 'package:turna/views/review/mistake_list_page.dart' as _i20;
import 'package:turna/views/review/mistake_practice_screen.dart' as _i21;
import 'package:turna/views/review/mistake_review_page.dart' as _i22;
import 'package:turna/views/review/review_progress_page.dart' as _i24;
import 'package:turna/views/review/srs_review_screen.dart' as _i27;
import 'package:turna/views/review/unified_review_page.dart' as _i30;
import 'package:turna/views/settings/system_health_page.dart' as _i28;
import 'package:turna/views/splash/splash_page.dart' as _i26;

/// generated route for
/// [_i1.AchievementsPage]
class AchievementsRoute extends _i33.PageRouteInfo<void> {
  const AchievementsRoute({List<_i33.PageRouteInfo>? children})
      : super(AchievementsRoute.name, initialChildren: children);

  static const String name = 'AchievementsRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i1.AchievementsPage();
    },
  );
}

/// generated route for
/// [_i2.AiDiagnosisPage]
class AiDiagnosisRoute extends _i33.PageRouteInfo<void> {
  const AiDiagnosisRoute({List<_i33.PageRouteInfo>? children})
      : super(AiDiagnosisRoute.name, initialChildren: children);

  static const String name = 'AiDiagnosisRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i2.AiDiagnosisPage();
    },
  );
}

/// generated route for
/// [_i3.AiFeatureGuidePage]
class AiFeatureGuideRoute extends _i33.PageRouteInfo<void> {
  const AiFeatureGuideRoute({List<_i33.PageRouteInfo>? children})
      : super(AiFeatureGuideRoute.name, initialChildren: children);

  static const String name = 'AiFeatureGuideRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i3.AiFeatureGuidePage();
    },
  );
}

/// generated route for
/// [_i4.AiHintChatPage]
class AiHintChatRoute extends _i33.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i34.Key? key,
    _i35.AiQuestionContext? context,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(key: key, context: context),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiHintChatRouteArgs>(
        orElse: () => const AiHintChatRouteArgs(),
      );
      return _i4.AiHintChatPage(key: args.key, context: args.context);
    },
  );
}

class AiHintChatRouteArgs {
  const AiHintChatRouteArgs({this.key, this.context});

  final _i34.Key? key;

  final _i35.AiQuestionContext? context;

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
/// [_i5.AiHubPage]
class AiHubRoute extends _i33.PageRouteInfo<void> {
  const AiHubRoute({List<_i33.PageRouteInfo>? children})
      : super(AiHubRoute.name, initialChildren: children);

  static const String name = 'AiHubRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i5.AiHubPage();
    },
  );
}

/// generated route for
/// [_i6.AiSavedListPage]
class AiSavedListRoute extends _i33.PageRouteInfo<void> {
  const AiSavedListRoute({List<_i33.PageRouteInfo>? children})
      : super(AiSavedListRoute.name, initialChildren: children);

  static const String name = 'AiSavedListRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i6.AiSavedListPage();
    },
  );
}

/// generated route for
/// [_i7.AiTutorChatPage]
class AiTutorChatRoute extends _i33.PageRouteInfo<void> {
  const AiTutorChatRoute({List<_i33.PageRouteInfo>? children})
      : super(AiTutorChatRoute.name, initialChildren: children);

  static const String name = 'AiTutorChatRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i7.AiTutorChatPage();
    },
  );
}

/// generated route for
/// [_i8.AiWishChatPage]
class AiWishChatRoute extends _i33.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i33.PageRouteInfo>? children})
      : super(AiWishChatRoute.name, initialChildren: children);

  static const String name = 'AiWishChatRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i8.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i9.AnkiCardBrowserPage]
class AnkiCardBrowserRoute
    extends _i33.PageRouteInfo<AnkiCardBrowserRouteArgs> {
  AnkiCardBrowserRoute({
    _i34.Key? key,
    required String importId,
    required String title,
    String? sectionId,
    List<_i33.PageRouteInfo>? children,
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

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiCardBrowserRouteArgs>();
      return _i9.AnkiCardBrowserPage(
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

  final _i34.Key? key;

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
/// [_i10.AnkiDeckStatsPage]
class AnkiDeckStatsRoute extends _i33.PageRouteInfo<AnkiDeckStatsRouteArgs> {
  AnkiDeckStatsRoute({
    _i34.Key? key,
    required String importId,
    required String title,
    List<_i33.PageRouteInfo>? children,
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

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiDeckStatsRouteArgs>();
      return _i10.AnkiDeckStatsPage(
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

  final _i34.Key? key;

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
/// [_i11.AnkiImportPage]
class AnkiImportRoute extends _i33.PageRouteInfo<AnkiImportRouteArgs> {
  AnkiImportRoute({
    _i36.Key? key,
    bool startWithSample = false,
    _i37.AnkiImporter? importerForTest,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          AnkiImportRoute.name,
          args: AnkiImportRouteArgs(
            key: key,
            startWithSample: startWithSample,
            importerForTest: importerForTest,
          ),
          initialChildren: children,
        );

  static const String name = 'AnkiImportRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiImportRouteArgs>(
        orElse: () => const AnkiImportRouteArgs(),
      );
      return _i11.AnkiImportPage(
        key: args.key,
        startWithSample: args.startWithSample,
        importerForTest: args.importerForTest,
      );
    },
  );
}

class AnkiImportRouteArgs {
  const AnkiImportRouteArgs({
    this.key,
    this.startWithSample = false,
    this.importerForTest,
  });

  final _i36.Key? key;

  final bool startWithSample;

  final _i37.AnkiImporter? importerForTest;

  @override
  String toString() {
    return 'AnkiImportRouteArgs{key: $key, startWithSample: $startWithSample, importerForTest: $importerForTest}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiImportRouteArgs) return false;
    return key == other.key &&
        startWithSample == other.startWithSample &&
        importerForTest == other.importerForTest;
  }

  @override
  int get hashCode =>
      key.hashCode ^ startWithSample.hashCode ^ importerForTest.hashCode;
}

/// generated route for
/// [_i12.AnkiReviewPage]
class AnkiReviewRoute extends _i33.PageRouteInfo<void> {
  const AnkiReviewRoute({List<_i33.PageRouteInfo>? children})
      : super(AnkiReviewRoute.name, initialChildren: children);

  static const String name = 'AnkiReviewRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i12.AnkiReviewPage();
    },
  );
}

/// generated route for
/// [_i13.AnkiReviewSessionPage]
class AnkiReviewSessionRoute
    extends _i33.PageRouteInfo<AnkiReviewSessionRouteArgs> {
  AnkiReviewSessionRoute({
    _i34.Key? key,
    String? sectionId,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          AnkiReviewSessionRoute.name,
          args: AnkiReviewSessionRouteArgs(key: key, sectionId: sectionId),
          initialChildren: children,
        );

  static const String name = 'AnkiReviewSessionRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiReviewSessionRouteArgs>(
        orElse: () => const AnkiReviewSessionRouteArgs(),
      );
      return _i13.AnkiReviewSessionPage(
        key: args.key,
        sectionId: args.sectionId,
      );
    },
  );
}

class AnkiReviewSessionRouteArgs {
  const AnkiReviewSessionRouteArgs({this.key, this.sectionId});

  final _i34.Key? key;

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
/// [_i14.CourseManagementPage]
class CourseManagementRoute extends _i33.PageRouteInfo<void> {
  const CourseManagementRoute({List<_i33.PageRouteInfo>? children})
      : super(CourseManagementRoute.name, initialChildren: children);

  static const String name = 'CourseManagementRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i14.CourseManagementPage();
    },
  );
}

/// generated route for
/// [_i15.DailyChallengePage]
class DailyChallengeRoute extends _i33.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i33.PageRouteInfo>? children})
      : super(DailyChallengeRoute.name, initialChildren: children);

  static const String name = 'DailyChallengeRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i15.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i16.DictionaryPage]
class DictionaryRoute extends _i33.PageRouteInfo<void> {
  const DictionaryRoute({List<_i33.PageRouteInfo>? children})
      : super(DictionaryRoute.name, initialChildren: children);

  static const String name = 'DictionaryRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i16.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i17.GrammarReviewPage]
class GrammarReviewRoute extends _i33.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i33.PageRouteInfo>? children})
      : super(GrammarReviewRoute.name, initialChildren: children);

  static const String name = 'GrammarReviewRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i17.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i18.HomePage]
class HomeRoute extends _i33.PageRouteInfo<void> {
  const HomeRoute({List<_i33.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i18.HomePage();
    },
  );
}

/// generated route for
/// [_i19.MatchWordsPage]
class MatchWordsRoute extends _i33.PageRouteInfo<void> {
  const MatchWordsRoute({List<_i33.PageRouteInfo>? children})
      : super(MatchWordsRoute.name, initialChildren: children);

  static const String name = 'MatchWordsRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i19.MatchWordsPage();
    },
  );
}

/// generated route for
/// [_i20.MistakeListPage]
class MistakeListRoute extends _i33.PageRouteInfo<void> {
  const MistakeListRoute({List<_i33.PageRouteInfo>? children})
      : super(MistakeListRoute.name, initialChildren: children);

  static const String name = 'MistakeListRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i20.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i21.MistakePracticePage]
class MistakePracticeRoute
    extends _i33.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i34.Key? key,
    required _i38.MistakeEntry entry,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(key: key, entry: entry),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i21.MistakePracticePage(key: args.key, entry: args.entry);
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({this.key, required this.entry});

  final _i34.Key? key;

  final _i38.MistakeEntry entry;

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
/// [_i22.MistakeReviewPage]
class MistakeReviewRoute extends _i33.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i33.PageRouteInfo>? children})
      : super(MistakeReviewRoute.name, initialChildren: children);

  static const String name = 'MistakeReviewRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i22.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i23.NewLessonPage]
class NewLessonRoute extends _i33.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i34.Key? key,
    required String lessonId,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(key: key, lessonId: lessonId),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i23.NewLessonPage(key: args.key, lessonId: args.lessonId);
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({this.key, required this.lessonId});

  final _i34.Key? key;

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
/// [_i24.ReviewProgressPage]
class ReviewProgressRoute extends _i33.PageRouteInfo<void> {
  const ReviewProgressRoute({List<_i33.PageRouteInfo>? children})
      : super(ReviewProgressRoute.name, initialChildren: children);

  static const String name = 'ReviewProgressRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i24.ReviewProgressPage();
    },
  );
}

/// generated route for
/// [_i25.SectionPickerPage]
class SectionPickerRoute extends _i33.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i33.PageRouteInfo>? children})
      : super(SectionPickerRoute.name, initialChildren: children);

  static const String name = 'SectionPickerRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i25.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i26.SplashPage]
class SplashRoute extends _i33.PageRouteInfo<void> {
  const SplashRoute({List<_i33.PageRouteInfo>? children})
      : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i26.SplashPage();
    },
  );
}

/// generated route for
/// [_i27.SrsReviewPage]
class SrsReviewRoute extends _i33.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i33.PageRouteInfo>? children})
      : super(SrsReviewRoute.name, initialChildren: children);

  static const String name = 'SrsReviewRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i27.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i28.SystemHealthPage]
class SystemHealthRoute extends _i33.PageRouteInfo<void> {
  const SystemHealthRoute({List<_i33.PageRouteInfo>? children})
      : super(SystemHealthRoute.name, initialChildren: children);

  static const String name = 'SystemHealthRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i28.SystemHealthPage();
    },
  );
}

/// generated route for
/// [_i29.TextbookImportPage]
class TextbookImportRoute extends _i33.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i33.PageRouteInfo>? children})
      : super(TextbookImportRoute.name, initialChildren: children);

  static const String name = 'TextbookImportRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i29.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i30.UnifiedReviewPage]
class UnifiedReviewRoute extends _i33.PageRouteInfo<UnifiedReviewRouteArgs> {
  UnifiedReviewRoute({
    _i34.Key? key,
    required List<_i39.ReviewItem> items,
    required _i40.ReviewLedgerResolver ledgerResolver,
    String? title,
    _i41.Future<void> Function(_i39.ReviewItem, _i42.RecallOutcome)?
        onOutcomeRecorded,
    _i41.Future<void> Function(_i43.ReviewEventReceipt)? onOutcomeUndone,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          UnifiedReviewRoute.name,
          args: UnifiedReviewRouteArgs(
            key: key,
            items: items,
            ledgerResolver: ledgerResolver,
            title: title,
            onOutcomeRecorded: onOutcomeRecorded,
            onOutcomeUndone: onOutcomeUndone,
          ),
          initialChildren: children,
        );

  static const String name = 'UnifiedReviewRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<UnifiedReviewRouteArgs>();
      return _i30.UnifiedReviewPage(
        key: args.key,
        items: args.items,
        ledgerResolver: args.ledgerResolver,
        title: args.title,
        onOutcomeRecorded: args.onOutcomeRecorded,
        onOutcomeUndone: args.onOutcomeUndone,
      );
    },
  );
}

class UnifiedReviewRouteArgs {
  const UnifiedReviewRouteArgs({
    this.key,
    required this.items,
    required this.ledgerResolver,
    this.title,
    this.onOutcomeRecorded,
    this.onOutcomeUndone,
  });

  final _i34.Key? key;

  final List<_i39.ReviewItem> items;

  final _i40.ReviewLedgerResolver ledgerResolver;

  final String? title;

  final _i41.Future<void> Function(_i39.ReviewItem, _i42.RecallOutcome)?
      onOutcomeRecorded;

  final _i41.Future<void> Function(_i43.ReviewEventReceipt)? onOutcomeUndone;

  @override
  String toString() {
    return 'UnifiedReviewRouteArgs{key: $key, items: $items, ledgerResolver: $ledgerResolver, title: $title, onOutcomeRecorded: $onOutcomeRecorded, onOutcomeUndone: $onOutcomeUndone}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnifiedReviewRouteArgs) return false;
    return key == other.key &&
        const _i44.ListEquality<_i39.ReviewItem>().equals(items, other.items) &&
        ledgerResolver == other.ledgerResolver &&
        title == other.title;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      const _i44.ListEquality<_i39.ReviewItem>().hash(items) ^
      ledgerResolver.hashCode ^
      title.hashCode;
}

/// generated route for
/// [_i31.VowelAndConsonantLearningPage]
class VowelAndConsonantLearningRoute
    extends _i33.PageRouteInfo<VowelAndConsonantLearningRouteArgs> {
  VowelAndConsonantLearningRoute({
    _i34.Key? key,
    required _i31.CharacterLearningMode mode,
    List<_i33.PageRouteInfo>? children,
  }) : super(
          VowelAndConsonantLearningRoute.name,
          args: VowelAndConsonantLearningRouteArgs(key: key, mode: mode),
          initialChildren: children,
        );

  static const String name = 'VowelAndConsonantLearningRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VowelAndConsonantLearningRouteArgs>();
      return _i31.VowelAndConsonantLearningPage(key: args.key, mode: args.mode);
    },
  );
}

class VowelAndConsonantLearningRouteArgs {
  const VowelAndConsonantLearningRouteArgs({this.key, required this.mode});

  final _i34.Key? key;

  final _i31.CharacterLearningMode mode;

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
/// [_i32.WeakWordsPage]
class WeakWordsRoute extends _i33.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i33.PageRouteInfo>? children})
      : super(WeakWordsRoute.name, initialChildren: children);

  static const String name = 'WeakWordsRoute';

  static _i33.PageInfo page = _i33.PageInfo(
    name,
    builder: (data) {
      return const _i32.WeakWordsPage();
    },
  );
}
