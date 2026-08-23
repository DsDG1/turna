// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i77;

import 'package:auto_route/auto_route.dart' as _i50;
import 'package:collection/collection.dart' as _i67;
import 'package:flutter/foundation.dart' as _i55;
import 'package:flutter/material.dart' as _i51;
import 'package:turna/application/ai/ai_hint_provider.dart' as _i53;
import 'package:turna/application/ai/ai_tutor_chat_provider.dart' as _i54;
import 'package:turna/application/anki/anki_importer.dart' as _i56;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart'
    as _i59;
import 'package:turna/application/anki_official/engine/official_anki_engine.dart'
    as _i63;
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart'
    as _i62;
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart'
    as _i65;
import 'package:turna/application/anki_official/migration/official_anki_census.dart'
    as _i60;
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart'
    as _i61;
import 'package:turna/application/anki_official/official_anki_feature_flags.dart'
    as _i33;
import 'package:turna/application/anki_official/official_anki_internal_page.dart'
    as _i30;
import 'package:turna/application/anki_official/official_anki_paths.dart'
    as _i64;
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart'
    as _i58;
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart'
    as _i73;
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart'
    as _i66;
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart'
    as _i68;
import 'package:turna/application/anki_official/render/official_anki_render_state.dart'
    as _i69;
import 'package:turna/application/anki_official/storage/official_anki_database.dart'
    as _i70;
import 'package:turna/application/course_provider.dart' as _i72;
import 'package:turna/application/maintenance/storage_inventory_service.dart'
    as _i74;
import 'package:turna/application/settings/app_build_info.dart' as _i52;
import 'package:turna/data/course_database.dart' as _i71;
import 'package:turna/domain/course/mistake_entry.dart' as _i57;
import 'package:turna/domain/review/recall_outcome.dart' as _i78;
import 'package:turna/domain/review/review_item.dart' as _i75;
import 'package:turna/domain/review/review_ledger.dart' as _i79;
import 'package:turna/domain/review/review_ledger_resolver.dart' as _i76;
import 'package:turna/views/ai/ai_api_config_page.dart' as _i3;
import 'package:turna/views/ai/ai_diagnosis_page.dart' as _i4;
import 'package:turna/views/ai/ai_feature_guide_page.dart' as _i5;
import 'package:turna/views/ai/ai_hint_chat_page.dart' as _i6;
import 'package:turna/views/ai/ai_hub_page.dart' as _i7;
import 'package:turna/views/ai/ai_saved_list_page.dart' as _i8;
import 'package:turna/views/ai/ai_tutor_chat_page.dart' as _i9;
import 'package:turna/views/ai/ai_wish_chat_page.dart' as _i10;
import 'package:turna/views/ai/textbook/textbook_import_page.dart' as _i45;
import 'package:turna/views/anki/anki_card_browser_page.dart' as _i11;
import 'package:turna/views/anki/anki_deck_stats_page.dart' as _i12;
import 'package:turna/views/anki/anki_import_screen.dart' as _i13;
import 'package:turna/views/anki/anki_review_screen.dart' as _i14;
import 'package:turna/views/anki/anki_review_session_page.dart' as _i15;
import 'package:turna/views/anki_official/official_anki_mapping_page.dart'
    as _i31;
import 'package:turna/views/anki_official/official_anki_migration_preview_page.dart'
    as _i32;
import 'package:turna/views/anki_official/official_anki_review_page.dart'
    as _i34;
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart'
    as _i35;
import 'package:turna/views/anki_official/official_anki_source_management_page.dart'
    as _i36;
import 'package:turna/views/characters/character_drawing.dart' as _i48;
import 'package:turna/views/courses/course_management_page.dart' as _i18;
import 'package:turna/views/courses/section_picker_page.dart' as _i40;
import 'package:turna/views/dictionary/dictionary_page.dart' as _i20;
import 'package:turna/views/home/home_page.dart' as _i22;
import 'package:turna/views/lesson/new_lesson_screen.dart' as _i29;
import 'package:turna/views/play/daily_challenge_screen.dart' as _i19;
import 'package:turna/views/play/match_words.dart' as _i25;
import 'package:turna/views/play/weak_words_page.dart' as _i49;
import 'package:turna/views/playground/language_playground_page.dart' as _i23;
import 'package:turna/views/profile/achievements_page.dart' as _i2;
import 'package:turna/views/review/grammar_review_screen.dart' as _i21;
import 'package:turna/views/review/learning_insights_page.dart' as _i24;
import 'package:turna/views/review/mistake_list_page.dart' as _i26;
import 'package:turna/views/review/mistake_practice_screen.dart' as _i27;
import 'package:turna/views/review/mistake_review_page.dart' as _i28;
import 'package:turna/views/review/review_progress_page.dart' as _i39;
import 'package:turna/views/review/srs_review_screen.dart' as _i42;
import 'package:turna/views/review/unified_review_page.dart' as _i47;
import 'package:turna/views/settings/about_turna_page.dart' as _i1;
import 'package:turna/views/settings/avatar_rings_page.dart' as _i16;
import 'package:turna/views/settings/changelog_page.dart' as _i17;
import 'package:turna/views/settings/privacy_details_page.dart' as _i37;
import 'package:turna/views/settings/remote_backup_page.dart' as _i38;
import 'package:turna/views/settings/storage_diagnostics_page.dart' as _i43;
import 'package:turna/views/settings/system_health_page.dart' as _i44;
import 'package:turna/views/settings/transparency_log_page.dart' as _i46;
import 'package:turna/views/splash/splash_page.dart' as _i41;

/// generated route for
/// [_i1.AboutTurnaPage]
class AboutTurnaRoute extends _i50.PageRouteInfo<AboutTurnaRouteArgs> {
  AboutTurnaRoute({
    _i51.Key? key,
    _i52.AppBuildInfo? buildInfo,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          AboutTurnaRoute.name,
          args: AboutTurnaRouteArgs(key: key, buildInfo: buildInfo),
          initialChildren: children,
        );

  static const String name = 'AboutTurnaRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AboutTurnaRouteArgs>(
        orElse: () => const AboutTurnaRouteArgs(),
      );
      return _i1.AboutTurnaPage(key: args.key, buildInfo: args.buildInfo);
    },
  );
}

class AboutTurnaRouteArgs {
  const AboutTurnaRouteArgs({this.key, this.buildInfo});

  final _i51.Key? key;

  final _i52.AppBuildInfo? buildInfo;

  @override
  String toString() {
    return 'AboutTurnaRouteArgs{key: $key, buildInfo: $buildInfo}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AboutTurnaRouteArgs) return false;
    return key == other.key && buildInfo == other.buildInfo;
  }

  @override
  int get hashCode => key.hashCode ^ buildInfo.hashCode;
}

/// generated route for
/// [_i2.AchievementsPage]
class AchievementsRoute extends _i50.PageRouteInfo<void> {
  const AchievementsRoute({List<_i50.PageRouteInfo>? children})
      : super(AchievementsRoute.name, initialChildren: children);

  static const String name = 'AchievementsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i2.AchievementsPage();
    },
  );
}

/// generated route for
/// [_i3.AiApiConfigPage]
class AiApiConfigRoute extends _i50.PageRouteInfo<void> {
  const AiApiConfigRoute({List<_i50.PageRouteInfo>? children})
      : super(AiApiConfigRoute.name, initialChildren: children);

  static const String name = 'AiApiConfigRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i3.AiApiConfigPage();
    },
  );
}

/// generated route for
/// [_i4.AiDiagnosisPage]
class AiDiagnosisRoute extends _i50.PageRouteInfo<void> {
  const AiDiagnosisRoute({List<_i50.PageRouteInfo>? children})
      : super(AiDiagnosisRoute.name, initialChildren: children);

  static const String name = 'AiDiagnosisRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i4.AiDiagnosisPage();
    },
  );
}

/// generated route for
/// [_i5.AiFeatureGuidePage]
class AiFeatureGuideRoute extends _i50.PageRouteInfo<void> {
  const AiFeatureGuideRoute({List<_i50.PageRouteInfo>? children})
      : super(AiFeatureGuideRoute.name, initialChildren: children);

  static const String name = 'AiFeatureGuideRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i5.AiFeatureGuidePage();
    },
  );
}

/// generated route for
/// [_i6.AiHintChatPage]
class AiHintChatRoute extends _i50.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i51.Key? key,
    _i53.AiQuestionContext? context,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(key: key, context: context),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiHintChatRouteArgs>(
        orElse: () => const AiHintChatRouteArgs(),
      );
      return _i6.AiHintChatPage(key: args.key, context: args.context);
    },
  );
}

class AiHintChatRouteArgs {
  const AiHintChatRouteArgs({this.key, this.context});

  final _i51.Key? key;

  final _i53.AiQuestionContext? context;

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
/// [_i7.AiHubPage]
class AiHubRoute extends _i50.PageRouteInfo<void> {
  const AiHubRoute({List<_i50.PageRouteInfo>? children})
      : super(AiHubRoute.name, initialChildren: children);

  static const String name = 'AiHubRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i7.AiHubPage();
    },
  );
}

/// generated route for
/// [_i8.AiSavedListPage]
class AiSavedListRoute extends _i50.PageRouteInfo<void> {
  const AiSavedListRoute({List<_i50.PageRouteInfo>? children})
      : super(AiSavedListRoute.name, initialChildren: children);

  static const String name = 'AiSavedListRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i8.AiSavedListPage();
    },
  );
}

/// generated route for
/// [_i9.AiTutorChatPage]
class AiTutorChatRoute extends _i50.PageRouteInfo<AiTutorChatRouteArgs> {
  AiTutorChatRoute({
    _i51.Key? key,
    _i54.AiTutorChatMode? initialMode,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          AiTutorChatRoute.name,
          args: AiTutorChatRouteArgs(key: key, initialMode: initialMode),
          initialChildren: children,
        );

  static const String name = 'AiTutorChatRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiTutorChatRouteArgs>(
        orElse: () => const AiTutorChatRouteArgs(),
      );
      return _i9.AiTutorChatPage(key: args.key, initialMode: args.initialMode);
    },
  );
}

class AiTutorChatRouteArgs {
  const AiTutorChatRouteArgs({this.key, this.initialMode});

  final _i51.Key? key;

  final _i54.AiTutorChatMode? initialMode;

  @override
  String toString() {
    return 'AiTutorChatRouteArgs{key: $key, initialMode: $initialMode}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AiTutorChatRouteArgs) return false;
    return key == other.key && initialMode == other.initialMode;
  }

  @override
  int get hashCode => key.hashCode ^ initialMode.hashCode;
}

/// generated route for
/// [_i10.AiWishChatPage]
class AiWishChatRoute extends _i50.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i50.PageRouteInfo>? children})
      : super(AiWishChatRoute.name, initialChildren: children);

  static const String name = 'AiWishChatRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i10.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i11.AnkiCardBrowserPage]
class AnkiCardBrowserRoute
    extends _i50.PageRouteInfo<AnkiCardBrowserRouteArgs> {
  AnkiCardBrowserRoute({
    _i51.Key? key,
    required String importId,
    required String title,
    String? sectionId,
    List<_i50.PageRouteInfo>? children,
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

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiCardBrowserRouteArgs>();
      return _i11.AnkiCardBrowserPage(
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

  final _i51.Key? key;

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
/// [_i12.AnkiDeckStatsPage]
class AnkiDeckStatsRoute extends _i50.PageRouteInfo<AnkiDeckStatsRouteArgs> {
  AnkiDeckStatsRoute({
    _i51.Key? key,
    required String importId,
    required String title,
    List<_i50.PageRouteInfo>? children,
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

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiDeckStatsRouteArgs>();
      return _i12.AnkiDeckStatsPage(
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

  final _i51.Key? key;

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
/// [_i13.AnkiImportPage]
class AnkiImportRoute extends _i50.PageRouteInfo<AnkiImportRouteArgs> {
  AnkiImportRoute({
    _i55.Key? key,
    bool startWithSample = false,
    _i56.AnkiImporter? importerForTest,
    List<_i50.PageRouteInfo>? children,
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

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiImportRouteArgs>(
        orElse: () => const AnkiImportRouteArgs(),
      );
      return _i13.AnkiImportPage(
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

  final _i55.Key? key;

  final bool startWithSample;

  final _i56.AnkiImporter? importerForTest;

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
/// [_i14.AnkiReviewPage]
class AnkiReviewRoute extends _i50.PageRouteInfo<void> {
  const AnkiReviewRoute({List<_i50.PageRouteInfo>? children})
      : super(AnkiReviewRoute.name, initialChildren: children);

  static const String name = 'AnkiReviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i14.AnkiReviewPage();
    },
  );
}

/// generated route for
/// [_i15.AnkiReviewSessionPage]
class AnkiReviewSessionRoute
    extends _i50.PageRouteInfo<AnkiReviewSessionRouteArgs> {
  AnkiReviewSessionRoute({
    _i51.Key? key,
    String? sectionId,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          AnkiReviewSessionRoute.name,
          args: AnkiReviewSessionRouteArgs(key: key, sectionId: sectionId),
          initialChildren: children,
        );

  static const String name = 'AnkiReviewSessionRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiReviewSessionRouteArgs>(
        orElse: () => const AnkiReviewSessionRouteArgs(),
      );
      return _i15.AnkiReviewSessionPage(
        key: args.key,
        sectionId: args.sectionId,
      );
    },
  );
}

class AnkiReviewSessionRouteArgs {
  const AnkiReviewSessionRouteArgs({this.key, this.sectionId});

  final _i51.Key? key;

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
/// [_i16.AvatarRingsPage]
class AvatarRingsRoute extends _i50.PageRouteInfo<void> {
  const AvatarRingsRoute({List<_i50.PageRouteInfo>? children})
      : super(AvatarRingsRoute.name, initialChildren: children);

  static const String name = 'AvatarRingsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i16.AvatarRingsPage();
    },
  );
}

/// generated route for
/// [_i17.ChangelogPage]
class ChangelogRoute extends _i50.PageRouteInfo<void> {
  const ChangelogRoute({List<_i50.PageRouteInfo>? children})
      : super(ChangelogRoute.name, initialChildren: children);

  static const String name = 'ChangelogRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i17.ChangelogPage();
    },
  );
}

/// generated route for
/// [_i18.CourseManagementPage]
class CourseManagementRoute extends _i50.PageRouteInfo<void> {
  const CourseManagementRoute({List<_i50.PageRouteInfo>? children})
      : super(CourseManagementRoute.name, initialChildren: children);

  static const String name = 'CourseManagementRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i18.CourseManagementPage();
    },
  );
}

/// generated route for
/// [_i19.DailyChallengePage]
class DailyChallengeRoute extends _i50.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i50.PageRouteInfo>? children})
      : super(DailyChallengeRoute.name, initialChildren: children);

  static const String name = 'DailyChallengeRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i19.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i20.DictionaryPage]
class DictionaryRoute extends _i50.PageRouteInfo<void> {
  const DictionaryRoute({List<_i50.PageRouteInfo>? children})
      : super(DictionaryRoute.name, initialChildren: children);

  static const String name = 'DictionaryRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i20.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i21.GrammarReviewPage]
class GrammarReviewRoute extends _i50.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i50.PageRouteInfo>? children})
      : super(GrammarReviewRoute.name, initialChildren: children);

  static const String name = 'GrammarReviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i21.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i22.HomePage]
class HomeRoute extends _i50.PageRouteInfo<void> {
  const HomeRoute({List<_i50.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i22.HomePage();
    },
  );
}

/// generated route for
/// [_i23.LanguagePlaygroundPage]
class LanguagePlaygroundRoute extends _i50.PageRouteInfo<void> {
  const LanguagePlaygroundRoute({List<_i50.PageRouteInfo>? children})
      : super(LanguagePlaygroundRoute.name, initialChildren: children);

  static const String name = 'LanguagePlaygroundRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i23.LanguagePlaygroundPage();
    },
  );
}

/// generated route for
/// [_i24.LearningInsightsPage]
class LearningInsightsRoute extends _i50.PageRouteInfo<void> {
  const LearningInsightsRoute({List<_i50.PageRouteInfo>? children})
      : super(LearningInsightsRoute.name, initialChildren: children);

  static const String name = 'LearningInsightsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i24.LearningInsightsPage();
    },
  );
}

/// generated route for
/// [_i25.MatchWordsPage]
class MatchWordsRoute extends _i50.PageRouteInfo<void> {
  const MatchWordsRoute({List<_i50.PageRouteInfo>? children})
      : super(MatchWordsRoute.name, initialChildren: children);

  static const String name = 'MatchWordsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i25.MatchWordsPage();
    },
  );
}

/// generated route for
/// [_i26.MistakeListPage]
class MistakeListRoute extends _i50.PageRouteInfo<void> {
  const MistakeListRoute({List<_i50.PageRouteInfo>? children})
      : super(MistakeListRoute.name, initialChildren: children);

  static const String name = 'MistakeListRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i26.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i27.MistakePracticePage]
class MistakePracticeRoute
    extends _i50.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i51.Key? key,
    required _i57.MistakeEntry entry,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(key: key, entry: entry),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i27.MistakePracticePage(key: args.key, entry: args.entry);
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({this.key, required this.entry});

  final _i51.Key? key;

  final _i57.MistakeEntry entry;

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
/// [_i28.MistakeReviewPage]
class MistakeReviewRoute extends _i50.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i50.PageRouteInfo>? children})
      : super(MistakeReviewRoute.name, initialChildren: children);

  static const String name = 'MistakeReviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i28.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i29.NewLessonPage]
class NewLessonRoute extends _i50.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i51.Key? key,
    required String lessonId,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(key: key, lessonId: lessonId),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i29.NewLessonPage(key: args.key, lessonId: args.lessonId);
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({this.key, required this.lessonId});

  final _i51.Key? key;

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
/// [_i30.OfficialAnkiInternalPage]
class OfficialAnkiInternalRoute extends _i50.PageRouteInfo<void> {
  const OfficialAnkiInternalRoute({List<_i50.PageRouteInfo>? children})
      : super(OfficialAnkiInternalRoute.name, initialChildren: children);

  static const String name = 'OfficialAnkiInternalRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i30.OfficialAnkiInternalPage();
    },
  );
}

/// generated route for
/// [_i31.OfficialAnkiMappingPage]
class OfficialAnkiMappingRoute
    extends _i50.PageRouteInfo<OfficialAnkiMappingRouteArgs> {
  OfficialAnkiMappingRoute({
    _i51.Key? key,
    required String notetypeName,
    required _i58.OfficialAnkiMappingSuggestion suggestion,
    _i59.OfficialAnkiProjectionSchema? schema,
    int affectedCardCount = 0,
    _i51.ValueChanged<_i58.OfficialAnkiMappingSuggestion>? onConfirm,
    _i51.VoidCallback? onSkip,
    _i51.VoidCallback? onRestore,
    _i51.VoidCallback? onGenerateCourse,
    _i51.ValueChanged<_i58.OfficialAnkiMappingSuggestion>? onChanged,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          OfficialAnkiMappingRoute.name,
          args: OfficialAnkiMappingRouteArgs(
            key: key,
            notetypeName: notetypeName,
            suggestion: suggestion,
            schema: schema,
            affectedCardCount: affectedCardCount,
            onConfirm: onConfirm,
            onSkip: onSkip,
            onRestore: onRestore,
            onGenerateCourse: onGenerateCourse,
            onChanged: onChanged,
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiMappingRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiMappingRouteArgs>();
      return _i31.OfficialAnkiMappingPage(
        key: args.key,
        notetypeName: args.notetypeName,
        suggestion: args.suggestion,
        schema: args.schema,
        affectedCardCount: args.affectedCardCount,
        onConfirm: args.onConfirm,
        onSkip: args.onSkip,
        onRestore: args.onRestore,
        onGenerateCourse: args.onGenerateCourse,
        onChanged: args.onChanged,
      );
    },
  );
}

class OfficialAnkiMappingRouteArgs {
  const OfficialAnkiMappingRouteArgs({
    this.key,
    required this.notetypeName,
    required this.suggestion,
    this.schema,
    this.affectedCardCount = 0,
    this.onConfirm,
    this.onSkip,
    this.onRestore,
    this.onGenerateCourse,
    this.onChanged,
  });

  final _i51.Key? key;

  final String notetypeName;

  final _i58.OfficialAnkiMappingSuggestion suggestion;

  final _i59.OfficialAnkiProjectionSchema? schema;

  final int affectedCardCount;

  final _i51.ValueChanged<_i58.OfficialAnkiMappingSuggestion>? onConfirm;

  final _i51.VoidCallback? onSkip;

  final _i51.VoidCallback? onRestore;

  final _i51.VoidCallback? onGenerateCourse;

  final _i51.ValueChanged<_i58.OfficialAnkiMappingSuggestion>? onChanged;

  @override
  String toString() {
    return 'OfficialAnkiMappingRouteArgs{key: $key, notetypeName: $notetypeName, suggestion: $suggestion, schema: $schema, affectedCardCount: $affectedCardCount, onConfirm: $onConfirm, onSkip: $onSkip, onRestore: $onRestore, onGenerateCourse: $onGenerateCourse, onChanged: $onChanged}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OfficialAnkiMappingRouteArgs) return false;
    return key == other.key &&
        notetypeName == other.notetypeName &&
        suggestion == other.suggestion &&
        schema == other.schema &&
        affectedCardCount == other.affectedCardCount &&
        onConfirm == other.onConfirm &&
        onSkip == other.onSkip &&
        onRestore == other.onRestore &&
        onGenerateCourse == other.onGenerateCourse &&
        onChanged == other.onChanged;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      notetypeName.hashCode ^
      suggestion.hashCode ^
      schema.hashCode ^
      affectedCardCount.hashCode ^
      onConfirm.hashCode ^
      onSkip.hashCode ^
      onRestore.hashCode ^
      onGenerateCourse.hashCode ^
      onChanged.hashCode;
}

/// generated route for
/// [_i32.OfficialAnkiMigrationPreviewPage]
class OfficialAnkiMigrationPreviewRoute
    extends _i50.PageRouteInfo<OfficialAnkiMigrationPreviewRouteArgs> {
  OfficialAnkiMigrationPreviewRoute({
    _i51.Key? key,
    required _i60.LegacyAnkiCensusReport census,
    required _i61.LegacyAnkiDryRunResult dryRun,
    int diskFreeBytes = 0,
    String displayName = 'Legacy source',
    String? importId,
    String? sourceHash,
    _i33.OfficialAnkiFeatureFlags flags = const _i33.OfficialAnkiFeatureFlags(),
    _i62.OfficialAnkiOperationCoordinator? coordinator,
    _i51.VoidCallback? onFixturePilot,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          OfficialAnkiMigrationPreviewRoute.name,
          args: OfficialAnkiMigrationPreviewRouteArgs(
            key: key,
            census: census,
            dryRun: dryRun,
            diskFreeBytes: diskFreeBytes,
            displayName: displayName,
            importId: importId,
            sourceHash: sourceHash,
            flags: flags,
            coordinator: coordinator,
            onFixturePilot: onFixturePilot,
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiMigrationPreviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiMigrationPreviewRouteArgs>();
      return _i32.OfficialAnkiMigrationPreviewPage(
        key: args.key,
        census: args.census,
        dryRun: args.dryRun,
        diskFreeBytes: args.diskFreeBytes,
        displayName: args.displayName,
        importId: args.importId,
        sourceHash: args.sourceHash,
        flags: args.flags,
        coordinator: args.coordinator,
        onFixturePilot: args.onFixturePilot,
      );
    },
  );
}

class OfficialAnkiMigrationPreviewRouteArgs {
  const OfficialAnkiMigrationPreviewRouteArgs({
    this.key,
    required this.census,
    required this.dryRun,
    this.diskFreeBytes = 0,
    this.displayName = 'Legacy source',
    this.importId,
    this.sourceHash,
    this.flags = const _i33.OfficialAnkiFeatureFlags(),
    this.coordinator,
    this.onFixturePilot,
  });

  final _i51.Key? key;

  final _i60.LegacyAnkiCensusReport census;

  final _i61.LegacyAnkiDryRunResult dryRun;

  final int diskFreeBytes;

  final String displayName;

  final String? importId;

  final String? sourceHash;

  final _i33.OfficialAnkiFeatureFlags flags;

  final _i62.OfficialAnkiOperationCoordinator? coordinator;

  final _i51.VoidCallback? onFixturePilot;

  @override
  String toString() {
    return 'OfficialAnkiMigrationPreviewRouteArgs{key: $key, census: $census, dryRun: $dryRun, diskFreeBytes: $diskFreeBytes, displayName: $displayName, importId: $importId, sourceHash: $sourceHash, flags: $flags, coordinator: $coordinator, onFixturePilot: $onFixturePilot}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OfficialAnkiMigrationPreviewRouteArgs) return false;
    return key == other.key &&
        census == other.census &&
        dryRun == other.dryRun &&
        diskFreeBytes == other.diskFreeBytes &&
        displayName == other.displayName &&
        importId == other.importId &&
        sourceHash == other.sourceHash &&
        flags == other.flags &&
        coordinator == other.coordinator &&
        onFixturePilot == other.onFixturePilot;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      census.hashCode ^
      dryRun.hashCode ^
      diskFreeBytes.hashCode ^
      displayName.hashCode ^
      importId.hashCode ^
      sourceHash.hashCode ^
      flags.hashCode ^
      coordinator.hashCode ^
      onFixturePilot.hashCode;
}

/// generated route for
/// [_i34.OfficialAnkiReviewPage]
class OfficialAnkiReviewRoute
    extends _i50.PageRouteInfo<OfficialAnkiReviewRouteArgs> {
  OfficialAnkiReviewRoute({
    _i51.Key? key,
    required _i63.OfficialAnkiEngine engine,
    required _i64.OfficialAnkiPaths paths,
    int? deckId,
    Set<int>? allowedCardIds,
    _i33.OfficialAnkiFeatureFlags? flags,
    _i65.OfficialReviewSession? session,
    _i66.OfficialAnswerPresenter? presenter,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          OfficialAnkiReviewRoute.name,
          args: OfficialAnkiReviewRouteArgs(
            key: key,
            engine: engine,
            paths: paths,
            deckId: deckId,
            allowedCardIds: allowedCardIds,
            flags: flags,
            session: session,
            presenter: presenter,
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiReviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiReviewRouteArgs>();
      return _i34.OfficialAnkiReviewPage(
        key: args.key,
        engine: args.engine,
        paths: args.paths,
        deckId: args.deckId,
        allowedCardIds: args.allowedCardIds,
        flags: args.flags,
        session: args.session,
        presenter: args.presenter,
      );
    },
  );
}

class OfficialAnkiReviewRouteArgs {
  const OfficialAnkiReviewRouteArgs({
    this.key,
    required this.engine,
    required this.paths,
    this.deckId,
    this.allowedCardIds,
    this.flags,
    this.session,
    this.presenter,
  });

  final _i51.Key? key;

  final _i63.OfficialAnkiEngine engine;

  final _i64.OfficialAnkiPaths paths;

  final int? deckId;

  final Set<int>? allowedCardIds;

  final _i33.OfficialAnkiFeatureFlags? flags;

  final _i65.OfficialReviewSession? session;

  final _i66.OfficialAnswerPresenter? presenter;

  @override
  String toString() {
    return 'OfficialAnkiReviewRouteArgs{key: $key, engine: $engine, paths: $paths, deckId: $deckId, allowedCardIds: $allowedCardIds, flags: $flags, session: $session, presenter: $presenter}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OfficialAnkiReviewRouteArgs) return false;
    return key == other.key &&
        engine == other.engine &&
        paths == other.paths &&
        deckId == other.deckId &&
        const _i67.SetEquality<int>().equals(
          allowedCardIds,
          other.allowedCardIds,
        ) &&
        flags == other.flags &&
        session == other.session &&
        presenter == other.presenter;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      engine.hashCode ^
      paths.hashCode ^
      deckId.hashCode ^
      const _i67.SetEquality<int>().hash(allowedCardIds) ^
      flags.hashCode ^
      session.hashCode ^
      presenter.hashCode;
}

/// generated route for
/// [_i35.OfficialAnkiReviewerPage]
class OfficialAnkiReviewerRoute
    extends _i50.PageRouteInfo<OfficialAnkiReviewerRouteArgs> {
  OfficialAnkiReviewerRoute({
    _i55.Key? key,
    required String sourceId,
    required int cardId,
    required _i64.OfficialAnkiPaths paths,
    _i68.OfficialAnkiRenderFacade? facade,
    _i69.OfficialAnkiReviewerController? controller,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          OfficialAnkiReviewerRoute.name,
          args: OfficialAnkiReviewerRouteArgs(
            key: key,
            sourceId: sourceId,
            cardId: cardId,
            paths: paths,
            facade: facade,
            controller: controller,
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiReviewerRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiReviewerRouteArgs>();
      return _i35.OfficialAnkiReviewerPage(
        key: args.key,
        sourceId: args.sourceId,
        cardId: args.cardId,
        paths: args.paths,
        facade: args.facade,
        controller: args.controller,
      );
    },
  );
}

class OfficialAnkiReviewerRouteArgs {
  const OfficialAnkiReviewerRouteArgs({
    this.key,
    required this.sourceId,
    required this.cardId,
    required this.paths,
    this.facade,
    this.controller,
  });

  final _i55.Key? key;

  final String sourceId;

  final int cardId;

  final _i64.OfficialAnkiPaths paths;

  final _i68.OfficialAnkiRenderFacade? facade;

  final _i69.OfficialAnkiReviewerController? controller;

  @override
  String toString() {
    return 'OfficialAnkiReviewerRouteArgs{key: $key, sourceId: $sourceId, cardId: $cardId, paths: $paths, facade: $facade, controller: $controller}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OfficialAnkiReviewerRouteArgs) return false;
    return key == other.key &&
        sourceId == other.sourceId &&
        cardId == other.cardId &&
        paths == other.paths &&
        facade == other.facade &&
        controller == other.controller;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      sourceId.hashCode ^
      cardId.hashCode ^
      paths.hashCode ^
      facade.hashCode ^
      controller.hashCode;
}

/// generated route for
/// [_i36.OfficialAnkiSourceManagementPage]
class OfficialAnkiSourceManagementRoute
    extends _i50.PageRouteInfo<OfficialAnkiSourceManagementRouteArgs> {
  OfficialAnkiSourceManagementRoute({
    _i51.Key? key,
    required _i63.OfficialAnkiEngine engine,
    required _i70.OfficialAnkiDatabase catalog,
    required _i71.CourseDatabase course,
    required String profileId,
    _i33.OfficialAnkiFeatureFlags? flags,
    _i72.CourseProvider? courseProvider,
    _i73.OfficialAnkiCourseProjectionService Function(String)? serviceOf,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          OfficialAnkiSourceManagementRoute.name,
          args: OfficialAnkiSourceManagementRouteArgs(
            key: key,
            engine: engine,
            catalog: catalog,
            course: course,
            profileId: profileId,
            flags: flags,
            courseProvider: courseProvider,
            serviceOf: serviceOf,
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiSourceManagementRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiSourceManagementRouteArgs>();
      return _i36.OfficialAnkiSourceManagementPage(
        key: args.key,
        engine: args.engine,
        catalog: args.catalog,
        course: args.course,
        profileId: args.profileId,
        flags: args.flags,
        courseProvider: args.courseProvider,
        serviceOf: args.serviceOf,
      );
    },
  );
}

class OfficialAnkiSourceManagementRouteArgs {
  const OfficialAnkiSourceManagementRouteArgs({
    this.key,
    required this.engine,
    required this.catalog,
    required this.course,
    required this.profileId,
    this.flags,
    this.courseProvider,
    this.serviceOf,
  });

  final _i51.Key? key;

  final _i63.OfficialAnkiEngine engine;

  final _i70.OfficialAnkiDatabase catalog;

  final _i71.CourseDatabase course;

  final String profileId;

  final _i33.OfficialAnkiFeatureFlags? flags;

  final _i72.CourseProvider? courseProvider;

  final _i73.OfficialAnkiCourseProjectionService Function(String)? serviceOf;

  @override
  String toString() {
    return 'OfficialAnkiSourceManagementRouteArgs{key: $key, engine: $engine, catalog: $catalog, course: $course, profileId: $profileId, flags: $flags, courseProvider: $courseProvider, serviceOf: $serviceOf}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OfficialAnkiSourceManagementRouteArgs) return false;
    return key == other.key &&
        engine == other.engine &&
        catalog == other.catalog &&
        course == other.course &&
        profileId == other.profileId &&
        flags == other.flags &&
        courseProvider == other.courseProvider;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      engine.hashCode ^
      catalog.hashCode ^
      course.hashCode ^
      profileId.hashCode ^
      flags.hashCode ^
      courseProvider.hashCode;
}

/// generated route for
/// [_i37.PrivacyDetailsPage]
class PrivacyDetailsRoute extends _i50.PageRouteInfo<void> {
  const PrivacyDetailsRoute({List<_i50.PageRouteInfo>? children})
      : super(PrivacyDetailsRoute.name, initialChildren: children);

  static const String name = 'PrivacyDetailsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i37.PrivacyDetailsPage();
    },
  );
}

/// generated route for
/// [_i38.RemoteBackupPage]
class RemoteBackupRoute extends _i50.PageRouteInfo<void> {
  const RemoteBackupRoute({List<_i50.PageRouteInfo>? children})
      : super(RemoteBackupRoute.name, initialChildren: children);

  static const String name = 'RemoteBackupRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i38.RemoteBackupPage();
    },
  );
}

/// generated route for
/// [_i39.ReviewProgressPage]
class ReviewProgressRoute extends _i50.PageRouteInfo<void> {
  const ReviewProgressRoute({List<_i50.PageRouteInfo>? children})
      : super(ReviewProgressRoute.name, initialChildren: children);

  static const String name = 'ReviewProgressRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i39.ReviewProgressPage();
    },
  );
}

/// generated route for
/// [_i40.SectionPickerPage]
class SectionPickerRoute extends _i50.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i50.PageRouteInfo>? children})
      : super(SectionPickerRoute.name, initialChildren: children);

  static const String name = 'SectionPickerRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i40.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i41.SplashPage]
class SplashRoute extends _i50.PageRouteInfo<void> {
  const SplashRoute({List<_i50.PageRouteInfo>? children})
      : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i41.SplashPage();
    },
  );
}

/// generated route for
/// [_i42.SrsReviewPage]
class SrsReviewRoute extends _i50.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i50.PageRouteInfo>? children})
      : super(SrsReviewRoute.name, initialChildren: children);

  static const String name = 'SrsReviewRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i42.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i43.StorageDiagnosticsPage]
class StorageDiagnosticsRoute
    extends _i50.PageRouteInfo<StorageDiagnosticsRouteArgs> {
  StorageDiagnosticsRoute({
    _i51.Key? key,
    _i74.StorageInventoryService? scanner,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          StorageDiagnosticsRoute.name,
          args: StorageDiagnosticsRouteArgs(key: key, scanner: scanner),
          initialChildren: children,
        );

  static const String name = 'StorageDiagnosticsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<StorageDiagnosticsRouteArgs>(
        orElse: () => const StorageDiagnosticsRouteArgs(),
      );
      return _i43.StorageDiagnosticsPage(key: args.key, scanner: args.scanner);
    },
  );
}

class StorageDiagnosticsRouteArgs {
  const StorageDiagnosticsRouteArgs({this.key, this.scanner});

  final _i51.Key? key;

  final _i74.StorageInventoryService? scanner;

  @override
  String toString() {
    return 'StorageDiagnosticsRouteArgs{key: $key, scanner: $scanner}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StorageDiagnosticsRouteArgs) return false;
    return key == other.key && scanner == other.scanner;
  }

  @override
  int get hashCode => key.hashCode ^ scanner.hashCode;
}

/// generated route for
/// [_i44.SystemHealthPage]
class SystemHealthRoute extends _i50.PageRouteInfo<void> {
  const SystemHealthRoute({List<_i50.PageRouteInfo>? children})
      : super(SystemHealthRoute.name, initialChildren: children);

  static const String name = 'SystemHealthRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i44.SystemHealthPage();
    },
  );
}

/// generated route for
/// [_i45.TextbookImportPage]
class TextbookImportRoute extends _i50.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i50.PageRouteInfo>? children})
      : super(TextbookImportRoute.name, initialChildren: children);

  static const String name = 'TextbookImportRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i45.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i46.TransparencyLogPage]
class TransparencyLogRoute extends _i50.PageRouteInfo<void> {
  const TransparencyLogRoute({List<_i50.PageRouteInfo>? children})
      : super(TransparencyLogRoute.name, initialChildren: children);

  static const String name = 'TransparencyLogRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i46.TransparencyLogPage();
    },
  );
}

/// generated route for
/// [_i47.UnifiedReviewPage]
class UnifiedReviewRoute extends _i50.PageRouteInfo<UnifiedReviewRouteArgs> {
  UnifiedReviewRoute({
    _i51.Key? key,
    required List<_i75.ReviewItem> items,
    required _i76.ReviewLedgerResolver ledgerResolver,
    String? title,
    _i77.Future<void> Function(_i75.ReviewItem, _i78.RecallOutcome)?
        onOutcomeRecorded,
    _i77.Future<void> Function(_i79.ReviewEventReceipt)? onOutcomeUndone,
    List<_i50.PageRouteInfo>? children,
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

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<UnifiedReviewRouteArgs>();
      return _i47.UnifiedReviewPage(
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

  final _i51.Key? key;

  final List<_i75.ReviewItem> items;

  final _i76.ReviewLedgerResolver ledgerResolver;

  final String? title;

  final _i77.Future<void> Function(_i75.ReviewItem, _i78.RecallOutcome)?
      onOutcomeRecorded;

  final _i77.Future<void> Function(_i79.ReviewEventReceipt)? onOutcomeUndone;

  @override
  String toString() {
    return 'UnifiedReviewRouteArgs{key: $key, items: $items, ledgerResolver: $ledgerResolver, title: $title, onOutcomeRecorded: $onOutcomeRecorded, onOutcomeUndone: $onOutcomeUndone}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnifiedReviewRouteArgs) return false;
    return key == other.key &&
        const _i67.ListEquality<_i75.ReviewItem>().equals(items, other.items) &&
        ledgerResolver == other.ledgerResolver &&
        title == other.title;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      const _i67.ListEquality<_i75.ReviewItem>().hash(items) ^
      ledgerResolver.hashCode ^
      title.hashCode;
}

/// generated route for
/// [_i48.VowelAndConsonantLearningPage]
class VowelAndConsonantLearningRoute
    extends _i50.PageRouteInfo<VowelAndConsonantLearningRouteArgs> {
  VowelAndConsonantLearningRoute({
    _i51.Key? key,
    required _i48.CharacterLearningMode mode,
    List<_i50.PageRouteInfo>? children,
  }) : super(
          VowelAndConsonantLearningRoute.name,
          args: VowelAndConsonantLearningRouteArgs(key: key, mode: mode),
          initialChildren: children,
        );

  static const String name = 'VowelAndConsonantLearningRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VowelAndConsonantLearningRouteArgs>();
      return _i48.VowelAndConsonantLearningPage(key: args.key, mode: args.mode);
    },
  );
}

class VowelAndConsonantLearningRouteArgs {
  const VowelAndConsonantLearningRouteArgs({this.key, required this.mode});

  final _i51.Key? key;

  final _i48.CharacterLearningMode mode;

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
/// [_i49.WeakWordsPage]
class WeakWordsRoute extends _i50.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i50.PageRouteInfo>? children})
      : super(WeakWordsRoute.name, initialChildren: children);

  static const String name = 'WeakWordsRoute';

  static _i50.PageInfo page = _i50.PageInfo(
    name,
    builder: (data) {
      return const _i49.WeakWordsPage();
    },
  );
}
