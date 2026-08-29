// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i83;

import 'package:auto_route/auto_route.dart' as _i57;
import 'package:collection/collection.dart' as _i73;
import 'package:flutter/foundation.dart' as _i62;
import 'package:flutter/material.dart' as _i58;
import 'package:turna/application/ai/ai_hint_provider.dart' as _i60;
import 'package:turna/application/ai/ai_tutor_chat_provider.dart' as _i61;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart'
    as _i65;
import 'package:turna/application/anki_official/engine/official_anki_engine.dart'
    as _i69;
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart'
    as _i68;
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart'
    as _i71;
import 'package:turna/application/anki_official/migration/official_anki_census.dart'
    as _i66;
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart'
    as _i67;
import 'package:turna/application/anki_official/official_anki_feature_flags.dart'
    as _i40;
import 'package:turna/application/anki_official/official_anki_paths.dart'
    as _i70;
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart'
    as _i64;
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart'
    as _i79;
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart'
    as _i72;
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart'
    as _i74;
import 'package:turna/application/anki_official/render/official_anki_render_state.dart'
    as _i75;
import 'package:turna/application/anki_official/storage/official_anki_database.dart'
    as _i76;
import 'package:turna/application/course_provider.dart' as _i78;
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart'
    as _i82;
import 'package:turna/application/diagnostics/runtime_memory_snapshot.dart'
    as _i84;
import 'package:turna/application/maintenance/storage_inventory_service.dart'
    as _i81;
import 'package:turna/application/review_progress_provider.dart' as _i80;
import 'package:turna/application/settings/app_build_info.dart' as _i59;
import 'package:turna/data/course_database.dart' as _i77;
import 'package:turna/domain/course/mistake_entry.dart' as _i63;
import 'package:turna/domain/review/recall_outcome.dart' as _i87;
import 'package:turna/domain/review/review_item.dart' as _i85;
import 'package:turna/domain/review/review_ledger.dart' as _i88;
import 'package:turna/domain/review/review_ledger_resolver.dart' as _i86;
import 'package:turna/views/ai/ai_api_config_page.dart' as _i7;
import 'package:turna/views/ai/ai_diagnosis_page.dart' as _i8;
import 'package:turna/views/ai/ai_feature_guide_page.dart' as _i9;
import 'package:turna/views/ai/ai_hint_chat_page.dart' as _i10;
import 'package:turna/views/ai/ai_hub_page.dart' as _i11;
import 'package:turna/views/ai/ai_saved_list_page.dart' as _i12;
import 'package:turna/views/ai/ai_tutor_chat_page.dart' as _i13;
import 'package:turna/views/ai/ai_wish_chat_page.dart' as _i14;
import 'package:turna/views/ai/textbook/textbook_import_page.dart' as _i53;
import 'package:turna/views/anki/anki_card_browser_page.dart' as _i15;
import 'package:turna/views/anki/anki_deck_stats_page.dart' as _i16;
import 'package:turna/views/anki/anki_import_screen.dart' as _i17;
import 'package:turna/views/anki/anki_review_screen.dart' as _i18;
import 'package:turna/views/anki/anki_review_session_page.dart' as _i19;
import 'package:turna/views/anki_official/official_anki_mapping_page.dart'
    as _i37;
import 'package:turna/views/anki_official/official_anki_migration_center_page.dart'
    as _i38;
import 'package:turna/views/anki_official/official_anki_migration_preview_page.dart'
    as _i39;
import 'package:turna/views/anki_official/official_anki_review_page.dart'
    as _i41;
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart'
    as _i42;
import 'package:turna/views/anki_official/official_anki_source_management_page.dart'
    as _i43;
import 'package:turna/views/courses/course_management_page.dart' as _i23;
import 'package:turna/views/courses/section_picker_page.dart' as _i48;
import 'package:turna/views/dictionary/dictionary_page.dart' as _i27;
import 'package:turna/views/home/home_page.dart' as _i29;
import 'package:turna/views/lesson/new_lesson_screen.dart' as _i36;
import 'package:turna/views/play/daily_challenge_screen.dart' as _i24;
import 'package:turna/views/play/weak_words_page.dart' as _i56;
import 'package:turna/views/playground/language_playground_page.dart' as _i30;
import 'package:turna/views/profile/achievements_page.dart' as _i5;
import 'package:turna/views/review/grammar_review_screen.dart' as _i28;
import 'package:turna/views/review/learning_insights_page.dart' as _i31;
import 'package:turna/views/review/mistake_list_page.dart' as _i33;
import 'package:turna/views/review/mistake_practice_screen.dart' as _i34;
import 'package:turna/views/review/mistake_review_page.dart' as _i35;
import 'package:turna/views/review/review_progress_page.dart' as _i46;
import 'package:turna/views/review/review_source_detail_page.dart' as _i47;
import 'package:turna/views/review/srs_review_screen.dart' as _i50;
import 'package:turna/views/review/unified_review_page.dart' as _i55;
import 'package:turna/views/settings/about_turna_page.dart' as _i2;
import 'package:turna/views/settings/avatar_rings_page.dart' as _i21;
import 'package:turna/views/settings/changelog_page.dart' as _i22;
import 'package:turna/views/settings/pages/about_settings_page.dart' as _i1;
import 'package:turna/views/settings/pages/accessibility_settings_page.dart'
    as _i3;
import 'package:turna/views/settings/pages/account_settings_page.dart' as _i4;
import 'package:turna/views/settings/pages/advanced_settings_page.dart' as _i6;
import 'package:turna/views/settings/pages/appearance_sound_settings_page.dart'
    as _i20;
import 'package:turna/views/settings/pages/data_backup_settings_page.dart'
    as _i25;
import 'package:turna/views/settings/pages/developer_settings_page.dart'
    as _i26;
import 'package:turna/views/settings/pages/learning_settings_page.dart' as _i32;
import 'package:turna/views/settings/privacy_details_page.dart' as _i44;
import 'package:turna/views/settings/remote_backup_page.dart' as _i45;
import 'package:turna/views/settings/storage_diagnostics_page.dart' as _i51;
import 'package:turna/views/settings/system_health_page.dart' as _i52;
import 'package:turna/views/settings/transparency_log_page.dart' as _i54;
import 'package:turna/views/splash/splash_page.dart' as _i49;

/// generated route for
/// [_i1.AboutSettingsPage]
class AboutSettingsRoute extends _i57.PageRouteInfo<void> {
  const AboutSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AboutSettingsRoute.name, initialChildren: children);

  static const String name = 'AboutSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i1.AboutSettingsPage();
    },
  );
}

/// generated route for
/// [_i2.AboutTurnaPage]
class AboutTurnaRoute extends _i57.PageRouteInfo<AboutTurnaRouteArgs> {
  AboutTurnaRoute({
    _i58.Key? key,
    _i59.AppBuildInfo? buildInfo,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          AboutTurnaRoute.name,
          args: AboutTurnaRouteArgs(key: key, buildInfo: buildInfo),
          initialChildren: children,
        );

  static const String name = 'AboutTurnaRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AboutTurnaRouteArgs>(
        orElse: () => const AboutTurnaRouteArgs(),
      );
      return _i2.AboutTurnaPage(key: args.key, buildInfo: args.buildInfo);
    },
  );
}

class AboutTurnaRouteArgs {
  const AboutTurnaRouteArgs({this.key, this.buildInfo});

  final _i58.Key? key;

  final _i59.AppBuildInfo? buildInfo;

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
/// [_i3.AccessibilitySettingsPage]
class AccessibilitySettingsRoute extends _i57.PageRouteInfo<void> {
  const AccessibilitySettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AccessibilitySettingsRoute.name, initialChildren: children);

  static const String name = 'AccessibilitySettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i3.AccessibilitySettingsPage();
    },
  );
}

/// generated route for
/// [_i4.AccountSettingsPage]
class AccountSettingsRoute extends _i57.PageRouteInfo<void> {
  const AccountSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AccountSettingsRoute.name, initialChildren: children);

  static const String name = 'AccountSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i4.AccountSettingsPage();
    },
  );
}

/// generated route for
/// [_i5.AchievementsPage]
class AchievementsRoute extends _i57.PageRouteInfo<void> {
  const AchievementsRoute({List<_i57.PageRouteInfo>? children})
      : super(AchievementsRoute.name, initialChildren: children);

  static const String name = 'AchievementsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i5.AchievementsPage();
    },
  );
}

/// generated route for
/// [_i6.AdvancedSettingsPage]
class AdvancedSettingsRoute extends _i57.PageRouteInfo<void> {
  const AdvancedSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AdvancedSettingsRoute.name, initialChildren: children);

  static const String name = 'AdvancedSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i6.AdvancedSettingsPage();
    },
  );
}

/// generated route for
/// [_i7.AiApiConfigPage]
class AiApiConfigRoute extends _i57.PageRouteInfo<void> {
  const AiApiConfigRoute({List<_i57.PageRouteInfo>? children})
      : super(AiApiConfigRoute.name, initialChildren: children);

  static const String name = 'AiApiConfigRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i7.AiApiConfigPage();
    },
  );
}

/// generated route for
/// [_i8.AiDiagnosisPage]
class AiDiagnosisRoute extends _i57.PageRouteInfo<void> {
  const AiDiagnosisRoute({List<_i57.PageRouteInfo>? children})
      : super(AiDiagnosisRoute.name, initialChildren: children);

  static const String name = 'AiDiagnosisRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i8.AiDiagnosisPage();
    },
  );
}

/// generated route for
/// [_i9.AiFeatureGuidePage]
class AiFeatureGuideRoute extends _i57.PageRouteInfo<void> {
  const AiFeatureGuideRoute({List<_i57.PageRouteInfo>? children})
      : super(AiFeatureGuideRoute.name, initialChildren: children);

  static const String name = 'AiFeatureGuideRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i9.AiFeatureGuidePage();
    },
  );
}

/// generated route for
/// [_i10.AiHintChatPage]
class AiHintChatRoute extends _i57.PageRouteInfo<AiHintChatRouteArgs> {
  AiHintChatRoute({
    _i58.Key? key,
    _i60.AiQuestionContext? context,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          AiHintChatRoute.name,
          args: AiHintChatRouteArgs(key: key, context: context),
          initialChildren: children,
        );

  static const String name = 'AiHintChatRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiHintChatRouteArgs>(
        orElse: () => const AiHintChatRouteArgs(),
      );
      return _i10.AiHintChatPage(key: args.key, context: args.context);
    },
  );
}

class AiHintChatRouteArgs {
  const AiHintChatRouteArgs({this.key, this.context});

  final _i58.Key? key;

  final _i60.AiQuestionContext? context;

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
/// [_i11.AiHubPage]
class AiHubRoute extends _i57.PageRouteInfo<void> {
  const AiHubRoute({List<_i57.PageRouteInfo>? children})
      : super(AiHubRoute.name, initialChildren: children);

  static const String name = 'AiHubRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i11.AiHubPage();
    },
  );
}

/// generated route for
/// [_i12.AiSavedListPage]
class AiSavedListRoute extends _i57.PageRouteInfo<void> {
  const AiSavedListRoute({List<_i57.PageRouteInfo>? children})
      : super(AiSavedListRoute.name, initialChildren: children);

  static const String name = 'AiSavedListRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i12.AiSavedListPage();
    },
  );
}

/// generated route for
/// [_i13.AiTutorChatPage]
class AiTutorChatRoute extends _i57.PageRouteInfo<AiTutorChatRouteArgs> {
  AiTutorChatRoute({
    _i58.Key? key,
    _i61.AiTutorChatMode? initialMode,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          AiTutorChatRoute.name,
          args: AiTutorChatRouteArgs(key: key, initialMode: initialMode),
          initialChildren: children,
        );

  static const String name = 'AiTutorChatRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AiTutorChatRouteArgs>(
        orElse: () => const AiTutorChatRouteArgs(),
      );
      return _i13.AiTutorChatPage(key: args.key, initialMode: args.initialMode);
    },
  );
}

class AiTutorChatRouteArgs {
  const AiTutorChatRouteArgs({this.key, this.initialMode});

  final _i58.Key? key;

  final _i61.AiTutorChatMode? initialMode;

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
/// [_i14.AiWishChatPage]
class AiWishChatRoute extends _i57.PageRouteInfo<void> {
  const AiWishChatRoute({List<_i57.PageRouteInfo>? children})
      : super(AiWishChatRoute.name, initialChildren: children);

  static const String name = 'AiWishChatRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i14.AiWishChatPage();
    },
  );
}

/// generated route for
/// [_i15.AnkiCardBrowserPage]
class AnkiCardBrowserRoute
    extends _i57.PageRouteInfo<AnkiCardBrowserRouteArgs> {
  AnkiCardBrowserRoute({
    _i58.Key? key,
    required String importId,
    required String title,
    String? sectionId,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiCardBrowserRouteArgs>();
      return _i15.AnkiCardBrowserPage(
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

  final _i58.Key? key;

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
/// [_i16.AnkiDeckStatsPage]
class AnkiDeckStatsRoute extends _i57.PageRouteInfo<AnkiDeckStatsRouteArgs> {
  AnkiDeckStatsRoute({
    _i58.Key? key,
    required String importId,
    required String title,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiDeckStatsRouteArgs>();
      return _i16.AnkiDeckStatsPage(
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

  final _i58.Key? key;

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
/// [_i17.AnkiImportPage]
class AnkiImportRoute extends _i57.PageRouteInfo<void> {
  const AnkiImportRoute({List<_i57.PageRouteInfo>? children})
      : super(AnkiImportRoute.name, initialChildren: children);

  static const String name = 'AnkiImportRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i17.AnkiImportPage();
    },
  );
}

/// generated route for
/// [_i18.AnkiReviewPage]
class AnkiReviewRoute extends _i57.PageRouteInfo<void> {
  const AnkiReviewRoute({List<_i57.PageRouteInfo>? children})
      : super(AnkiReviewRoute.name, initialChildren: children);

  static const String name = 'AnkiReviewRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i18.AnkiReviewPage();
    },
  );
}

/// generated route for
/// [_i19.AnkiReviewSessionPage]
class AnkiReviewSessionRoute
    extends _i57.PageRouteInfo<AnkiReviewSessionRouteArgs> {
  AnkiReviewSessionRoute({
    _i62.Key? key,
    String? sectionId,
    bool? officialOwner,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          AnkiReviewSessionRoute.name,
          args: AnkiReviewSessionRouteArgs(
            key: key,
            sectionId: sectionId,
            officialOwner: officialOwner,
          ),
          initialChildren: children,
        );

  static const String name = 'AnkiReviewSessionRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AnkiReviewSessionRouteArgs>(
        orElse: () => const AnkiReviewSessionRouteArgs(),
      );
      return _i19.AnkiReviewSessionPage(
        key: args.key,
        sectionId: args.sectionId,
        officialOwner: args.officialOwner,
      );
    },
  );
}

class AnkiReviewSessionRouteArgs {
  const AnkiReviewSessionRouteArgs({
    this.key,
    this.sectionId,
    this.officialOwner,
  });

  final _i62.Key? key;

  final String? sectionId;

  final bool? officialOwner;

  @override
  String toString() {
    return 'AnkiReviewSessionRouteArgs{key: $key, sectionId: $sectionId, officialOwner: $officialOwner}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnkiReviewSessionRouteArgs) return false;
    return key == other.key &&
        sectionId == other.sectionId &&
        officialOwner == other.officialOwner;
  }

  @override
  int get hashCode =>
      key.hashCode ^ sectionId.hashCode ^ officialOwner.hashCode;
}

/// generated route for
/// [_i20.AppearanceSoundSettingsPage]
class AppearanceSoundSettingsRoute extends _i57.PageRouteInfo<void> {
  const AppearanceSoundSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AppearanceSoundSettingsRoute.name, initialChildren: children);

  static const String name = 'AppearanceSoundSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i20.AppearanceSoundSettingsPage();
    },
  );
}

/// generated route for
/// [_i21.AvatarRingsPage]
class AvatarRingsRoute extends _i57.PageRouteInfo<void> {
  const AvatarRingsRoute({List<_i57.PageRouteInfo>? children})
      : super(AvatarRingsRoute.name, initialChildren: children);

  static const String name = 'AvatarRingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i21.AvatarRingsPage();
    },
  );
}

/// generated route for
/// [_i22.ChangelogPage]
class ChangelogRoute extends _i57.PageRouteInfo<void> {
  const ChangelogRoute({List<_i57.PageRouteInfo>? children})
      : super(ChangelogRoute.name, initialChildren: children);

  static const String name = 'ChangelogRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i22.ChangelogPage();
    },
  );
}

/// generated route for
/// [_i23.CourseManagementPage]
class CourseManagementRoute
    extends _i57.PageRouteInfo<CourseManagementRouteArgs> {
  CourseManagementRoute({
    _i58.Key? key,
    String? highlightWire,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          CourseManagementRoute.name,
          args: CourseManagementRouteArgs(
            key: key,
            highlightWire: highlightWire,
          ),
          initialChildren: children,
        );

  static const String name = 'CourseManagementRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<CourseManagementRouteArgs>(
        orElse: () => const CourseManagementRouteArgs(),
      );
      return _i23.CourseManagementPage(
        key: args.key,
        highlightWire: args.highlightWire,
      );
    },
  );
}

class CourseManagementRouteArgs {
  const CourseManagementRouteArgs({this.key, this.highlightWire});

  final _i58.Key? key;

  final String? highlightWire;

  @override
  String toString() {
    return 'CourseManagementRouteArgs{key: $key, highlightWire: $highlightWire}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CourseManagementRouteArgs) return false;
    return key == other.key && highlightWire == other.highlightWire;
  }

  @override
  int get hashCode => key.hashCode ^ highlightWire.hashCode;
}

/// generated route for
/// [_i24.DailyChallengePage]
class DailyChallengeRoute extends _i57.PageRouteInfo<void> {
  const DailyChallengeRoute({List<_i57.PageRouteInfo>? children})
      : super(DailyChallengeRoute.name, initialChildren: children);

  static const String name = 'DailyChallengeRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i24.DailyChallengePage();
    },
  );
}

/// generated route for
/// [_i25.DataBackupSettingsPage]
class DataBackupSettingsRoute extends _i57.PageRouteInfo<void> {
  const DataBackupSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(DataBackupSettingsRoute.name, initialChildren: children);

  static const String name = 'DataBackupSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i25.DataBackupSettingsPage();
    },
  );
}

/// generated route for
/// [_i26.DeveloperSettingsPage]
class DeveloperSettingsRoute extends _i57.PageRouteInfo<void> {
  const DeveloperSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(DeveloperSettingsRoute.name, initialChildren: children);

  static const String name = 'DeveloperSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i26.DeveloperSettingsPage();
    },
  );
}

/// generated route for
/// [_i27.DictionaryPage]
class DictionaryRoute extends _i57.PageRouteInfo<void> {
  const DictionaryRoute({List<_i57.PageRouteInfo>? children})
      : super(DictionaryRoute.name, initialChildren: children);

  static const String name = 'DictionaryRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i27.DictionaryPage();
    },
  );
}

/// generated route for
/// [_i28.GrammarReviewPage]
class GrammarReviewRoute extends _i57.PageRouteInfo<void> {
  const GrammarReviewRoute({List<_i57.PageRouteInfo>? children})
      : super(GrammarReviewRoute.name, initialChildren: children);

  static const String name = 'GrammarReviewRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i28.GrammarReviewPage();
    },
  );
}

/// generated route for
/// [_i29.HomePage]
class HomeRoute extends _i57.PageRouteInfo<void> {
  const HomeRoute({List<_i57.PageRouteInfo>? children})
      : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i29.HomePage();
    },
  );
}

/// generated route for
/// [_i30.LanguagePlaygroundPage]
class LanguagePlaygroundRoute extends _i57.PageRouteInfo<void> {
  const LanguagePlaygroundRoute({List<_i57.PageRouteInfo>? children})
      : super(LanguagePlaygroundRoute.name, initialChildren: children);

  static const String name = 'LanguagePlaygroundRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i30.LanguagePlaygroundPage();
    },
  );
}

/// generated route for
/// [_i31.LearningInsightsPage]
class LearningInsightsRoute extends _i57.PageRouteInfo<void> {
  const LearningInsightsRoute({List<_i57.PageRouteInfo>? children})
      : super(LearningInsightsRoute.name, initialChildren: children);

  static const String name = 'LearningInsightsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i31.LearningInsightsPage();
    },
  );
}

/// generated route for
/// [_i32.LearningSettingsPage]
class LearningSettingsRoute extends _i57.PageRouteInfo<void> {
  const LearningSettingsRoute({List<_i57.PageRouteInfo>? children})
      : super(LearningSettingsRoute.name, initialChildren: children);

  static const String name = 'LearningSettingsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i32.LearningSettingsPage();
    },
  );
}

/// generated route for
/// [_i6.LegacyCompatibilityPage]
class LegacyCompatibilityRoute extends _i57.PageRouteInfo<void> {
  const LegacyCompatibilityRoute({List<_i57.PageRouteInfo>? children})
      : super(LegacyCompatibilityRoute.name, initialChildren: children);

  static const String name = 'LegacyCompatibilityRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i6.LegacyCompatibilityPage();
    },
  );
}

/// generated route for
/// [_i33.MistakeListPage]
class MistakeListRoute extends _i57.PageRouteInfo<void> {
  const MistakeListRoute({List<_i57.PageRouteInfo>? children})
      : super(MistakeListRoute.name, initialChildren: children);

  static const String name = 'MistakeListRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i33.MistakeListPage();
    },
  );
}

/// generated route for
/// [_i34.MistakePracticePage]
class MistakePracticeRoute
    extends _i57.PageRouteInfo<MistakePracticeRouteArgs> {
  MistakePracticeRoute({
    _i58.Key? key,
    required _i63.MistakeEntry entry,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          MistakePracticeRoute.name,
          args: MistakePracticeRouteArgs(key: key, entry: entry),
          initialChildren: children,
        );

  static const String name = 'MistakePracticeRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MistakePracticeRouteArgs>();
      return _i34.MistakePracticePage(key: args.key, entry: args.entry);
    },
  );
}

class MistakePracticeRouteArgs {
  const MistakePracticeRouteArgs({this.key, required this.entry});

  final _i58.Key? key;

  final _i63.MistakeEntry entry;

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
/// [_i35.MistakeReviewPage]
class MistakeReviewRoute extends _i57.PageRouteInfo<void> {
  const MistakeReviewRoute({List<_i57.PageRouteInfo>? children})
      : super(MistakeReviewRoute.name, initialChildren: children);

  static const String name = 'MistakeReviewRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i35.MistakeReviewPage();
    },
  );
}

/// generated route for
/// [_i36.NewLessonPage]
class NewLessonRoute extends _i57.PageRouteInfo<NewLessonRouteArgs> {
  NewLessonRoute({
    _i58.Key? key,
    required String lessonId,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          NewLessonRoute.name,
          args: NewLessonRouteArgs(key: key, lessonId: lessonId),
          initialChildren: children,
        );

  static const String name = 'NewLessonRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewLessonRouteArgs>();
      return _i36.NewLessonPage(key: args.key, lessonId: args.lessonId);
    },
  );
}

class NewLessonRouteArgs {
  const NewLessonRouteArgs({this.key, required this.lessonId});

  final _i58.Key? key;

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
/// [_i37.OfficialAnkiMappingPage]
class OfficialAnkiMappingRoute
    extends _i57.PageRouteInfo<OfficialAnkiMappingRouteArgs> {
  OfficialAnkiMappingRoute({
    _i58.Key? key,
    required String notetypeName,
    required _i64.OfficialAnkiMappingSuggestion suggestion,
    _i65.OfficialAnkiProjectionSchema? schema,
    int affectedCardCount = 0,
    _i58.ValueChanged<_i64.OfficialAnkiMappingSuggestion>? onConfirm,
    _i58.VoidCallback? onSkip,
    _i58.VoidCallback? onRestore,
    _i58.VoidCallback? onGenerateCourse,
    _i58.ValueChanged<_i64.OfficialAnkiMappingSuggestion>? onChanged,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiMappingRouteArgs>();
      return _i37.OfficialAnkiMappingPage(
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

  final _i58.Key? key;

  final String notetypeName;

  final _i64.OfficialAnkiMappingSuggestion suggestion;

  final _i65.OfficialAnkiProjectionSchema? schema;

  final int affectedCardCount;

  final _i58.ValueChanged<_i64.OfficialAnkiMappingSuggestion>? onConfirm;

  final _i58.VoidCallback? onSkip;

  final _i58.VoidCallback? onRestore;

  final _i58.VoidCallback? onGenerateCourse;

  final _i58.ValueChanged<_i64.OfficialAnkiMappingSuggestion>? onChanged;

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
/// [_i38.OfficialAnkiMigrationCenterPage]
class OfficialAnkiMigrationCenterRoute extends _i57.PageRouteInfo<void> {
  const OfficialAnkiMigrationCenterRoute({List<_i57.PageRouteInfo>? children})
      : super(OfficialAnkiMigrationCenterRoute.name, initialChildren: children);

  static const String name = 'OfficialAnkiMigrationCenterRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i38.OfficialAnkiMigrationCenterPage();
    },
  );
}

/// generated route for
/// [_i39.OfficialAnkiMigrationPreviewPage]
class OfficialAnkiMigrationPreviewRoute
    extends _i57.PageRouteInfo<OfficialAnkiMigrationPreviewRouteArgs> {
  OfficialAnkiMigrationPreviewRoute({
    _i58.Key? key,
    required _i66.LegacyAnkiCensusReport census,
    required _i67.LegacyAnkiDryRunResult dryRun,
    int diskFreeBytes = 0,
    String displayName = 'Legacy source',
    String? importId,
    String? sourceHash,
    _i40.OfficialAnkiFeatureFlags flags = const _i40.OfficialAnkiFeatureFlags(),
    _i68.OfficialAnkiOperationCoordinator? coordinator,
    List<_i57.PageRouteInfo>? children,
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
          ),
          initialChildren: children,
        );

  static const String name = 'OfficialAnkiMigrationPreviewRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiMigrationPreviewRouteArgs>();
      return _i39.OfficialAnkiMigrationPreviewPage(
        key: args.key,
        census: args.census,
        dryRun: args.dryRun,
        diskFreeBytes: args.diskFreeBytes,
        displayName: args.displayName,
        importId: args.importId,
        sourceHash: args.sourceHash,
        flags: args.flags,
        coordinator: args.coordinator,
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
    this.flags = const _i40.OfficialAnkiFeatureFlags(),
    this.coordinator,
  });

  final _i58.Key? key;

  final _i66.LegacyAnkiCensusReport census;

  final _i67.LegacyAnkiDryRunResult dryRun;

  final int diskFreeBytes;

  final String displayName;

  final String? importId;

  final String? sourceHash;

  final _i40.OfficialAnkiFeatureFlags flags;

  final _i68.OfficialAnkiOperationCoordinator? coordinator;

  @override
  String toString() {
    return 'OfficialAnkiMigrationPreviewRouteArgs{key: $key, census: $census, dryRun: $dryRun, diskFreeBytes: $diskFreeBytes, displayName: $displayName, importId: $importId, sourceHash: $sourceHash, flags: $flags, coordinator: $coordinator}';
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
        coordinator == other.coordinator;
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
      coordinator.hashCode;
}

/// generated route for
/// [_i41.OfficialAnkiReviewPage]
class OfficialAnkiReviewRoute
    extends _i57.PageRouteInfo<OfficialAnkiReviewRouteArgs> {
  OfficialAnkiReviewRoute({
    _i58.Key? key,
    required _i69.OfficialAnkiEngine engine,
    required _i70.OfficialAnkiPaths paths,
    int? deckId,
    Set<int>? allowedCardIds,
    _i40.OfficialAnkiFeatureFlags? flags,
    _i71.OfficialReviewSession? session,
    _i72.OfficialAnswerPresenter? presenter,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiReviewRouteArgs>();
      return _i41.OfficialAnkiReviewPage(
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

  final _i58.Key? key;

  final _i69.OfficialAnkiEngine engine;

  final _i70.OfficialAnkiPaths paths;

  final int? deckId;

  final Set<int>? allowedCardIds;

  final _i40.OfficialAnkiFeatureFlags? flags;

  final _i71.OfficialReviewSession? session;

  final _i72.OfficialAnswerPresenter? presenter;

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
        const _i73.SetEquality<int>().equals(
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
      const _i73.SetEquality<int>().hash(allowedCardIds) ^
      flags.hashCode ^
      session.hashCode ^
      presenter.hashCode;
}

/// generated route for
/// [_i42.OfficialAnkiReviewerPage]
class OfficialAnkiReviewerRoute
    extends _i57.PageRouteInfo<OfficialAnkiReviewerRouteArgs> {
  OfficialAnkiReviewerRoute({
    _i62.Key? key,
    required String sourceId,
    required int cardId,
    required _i70.OfficialAnkiPaths paths,
    _i74.OfficialAnkiRenderFacade? facade,
    _i75.OfficialAnkiReviewerController? controller,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiReviewerRouteArgs>();
      return _i42.OfficialAnkiReviewerPage(
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

  final _i62.Key? key;

  final String sourceId;

  final int cardId;

  final _i70.OfficialAnkiPaths paths;

  final _i74.OfficialAnkiRenderFacade? facade;

  final _i75.OfficialAnkiReviewerController? controller;

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
/// [_i43.OfficialAnkiSourceManagementPage]
class OfficialAnkiSourceManagementRoute
    extends _i57.PageRouteInfo<OfficialAnkiSourceManagementRouteArgs> {
  OfficialAnkiSourceManagementRoute({
    _i58.Key? key,
    required _i69.OfficialAnkiEngine engine,
    required _i76.OfficialAnkiDatabase catalog,
    required _i77.CourseDatabase course,
    required String profileId,
    _i40.OfficialAnkiFeatureFlags? flags,
    _i78.CourseProvider? courseProvider,
    _i79.OfficialAnkiCourseProjectionService Function(String)? serviceOf,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<OfficialAnkiSourceManagementRouteArgs>();
      return _i43.OfficialAnkiSourceManagementPage(
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

  final _i58.Key? key;

  final _i69.OfficialAnkiEngine engine;

  final _i76.OfficialAnkiDatabase catalog;

  final _i77.CourseDatabase course;

  final String profileId;

  final _i40.OfficialAnkiFeatureFlags? flags;

  final _i78.CourseProvider? courseProvider;

  final _i79.OfficialAnkiCourseProjectionService Function(String)? serviceOf;

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
/// [_i44.PrivacyDetailsPage]
class PrivacyDetailsRoute extends _i57.PageRouteInfo<void> {
  const PrivacyDetailsRoute({List<_i57.PageRouteInfo>? children})
      : super(PrivacyDetailsRoute.name, initialChildren: children);

  static const String name = 'PrivacyDetailsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i44.PrivacyDetailsPage();
    },
  );
}

/// generated route for
/// [_i45.RemoteBackupPage]
class RemoteBackupRoute extends _i57.PageRouteInfo<void> {
  const RemoteBackupRoute({List<_i57.PageRouteInfo>? children})
      : super(RemoteBackupRoute.name, initialChildren: children);

  static const String name = 'RemoteBackupRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i45.RemoteBackupPage();
    },
  );
}

/// generated route for
/// [_i46.ReviewProgressPage]
class ReviewProgressRoute extends _i57.PageRouteInfo<void> {
  const ReviewProgressRoute({List<_i57.PageRouteInfo>? children})
      : super(ReviewProgressRoute.name, initialChildren: children);

  static const String name = 'ReviewProgressRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i46.ReviewProgressPage();
    },
  );
}

/// generated route for
/// [_i47.ReviewSourceDetailPage]
class ReviewSourceDetailRoute
    extends _i57.PageRouteInfo<ReviewSourceDetailRouteArgs> {
  ReviewSourceDetailRoute({
    _i58.Key? key,
    required _i80.ReviewSource source,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          ReviewSourceDetailRoute.name,
          args: ReviewSourceDetailRouteArgs(key: key, source: source),
          initialChildren: children,
        );

  static const String name = 'ReviewSourceDetailRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ReviewSourceDetailRouteArgs>();
      return _i47.ReviewSourceDetailPage(key: args.key, source: args.source);
    },
  );
}

class ReviewSourceDetailRouteArgs {
  const ReviewSourceDetailRouteArgs({this.key, required this.source});

  final _i58.Key? key;

  final _i80.ReviewSource source;

  @override
  String toString() {
    return 'ReviewSourceDetailRouteArgs{key: $key, source: $source}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReviewSourceDetailRouteArgs) return false;
    return key == other.key && source == other.source;
  }

  @override
  int get hashCode => key.hashCode ^ source.hashCode;
}

/// generated route for
/// [_i48.SectionPickerPage]
class SectionPickerRoute extends _i57.PageRouteInfo<void> {
  const SectionPickerRoute({List<_i57.PageRouteInfo>? children})
      : super(SectionPickerRoute.name, initialChildren: children);

  static const String name = 'SectionPickerRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i48.SectionPickerPage();
    },
  );
}

/// generated route for
/// [_i49.SplashPage]
class SplashRoute extends _i57.PageRouteInfo<void> {
  const SplashRoute({List<_i57.PageRouteInfo>? children})
      : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i49.SplashPage();
    },
  );
}

/// generated route for
/// [_i50.SrsReviewPage]
class SrsReviewRoute extends _i57.PageRouteInfo<void> {
  const SrsReviewRoute({List<_i57.PageRouteInfo>? children})
      : super(SrsReviewRoute.name, initialChildren: children);

  static const String name = 'SrsReviewRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i50.SrsReviewPage();
    },
  );
}

/// generated route for
/// [_i51.StorageDiagnosticsPage]
class StorageDiagnosticsRoute
    extends _i57.PageRouteInfo<StorageDiagnosticsRouteArgs> {
  StorageDiagnosticsRoute({
    _i58.Key? key,
    _i81.StorageInventoryService? scanner,
    _i82.CacheDiagnosticsRegistry? cacheRegistry,
    _i83.Future<_i84.RuntimeMemorySnapshot> Function()? memorySampler,
    List<_i57.PageRouteInfo>? children,
  }) : super(
          StorageDiagnosticsRoute.name,
          args: StorageDiagnosticsRouteArgs(
            key: key,
            scanner: scanner,
            cacheRegistry: cacheRegistry,
            memorySampler: memorySampler,
          ),
          initialChildren: children,
        );

  static const String name = 'StorageDiagnosticsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<StorageDiagnosticsRouteArgs>(
        orElse: () => const StorageDiagnosticsRouteArgs(),
      );
      return _i51.StorageDiagnosticsPage(
        key: args.key,
        scanner: args.scanner,
        cacheRegistry: args.cacheRegistry,
        memorySampler: args.memorySampler,
      );
    },
  );
}

class StorageDiagnosticsRouteArgs {
  const StorageDiagnosticsRouteArgs({
    this.key,
    this.scanner,
    this.cacheRegistry,
    this.memorySampler,
  });

  final _i58.Key? key;

  final _i81.StorageInventoryService? scanner;

  final _i82.CacheDiagnosticsRegistry? cacheRegistry;

  final _i83.Future<_i84.RuntimeMemorySnapshot> Function()? memorySampler;

  @override
  String toString() {
    return 'StorageDiagnosticsRouteArgs{key: $key, scanner: $scanner, cacheRegistry: $cacheRegistry, memorySampler: $memorySampler}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StorageDiagnosticsRouteArgs) return false;
    return key == other.key &&
        scanner == other.scanner &&
        cacheRegistry == other.cacheRegistry;
  }

  @override
  int get hashCode => key.hashCode ^ scanner.hashCode ^ cacheRegistry.hashCode;
}

/// generated route for
/// [_i52.SystemHealthPage]
class SystemHealthRoute extends _i57.PageRouteInfo<void> {
  const SystemHealthRoute({List<_i57.PageRouteInfo>? children})
      : super(SystemHealthRoute.name, initialChildren: children);

  static const String name = 'SystemHealthRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i52.SystemHealthPage();
    },
  );
}

/// generated route for
/// [_i53.TextbookImportPage]
class TextbookImportRoute extends _i57.PageRouteInfo<void> {
  const TextbookImportRoute({List<_i57.PageRouteInfo>? children})
      : super(TextbookImportRoute.name, initialChildren: children);

  static const String name = 'TextbookImportRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i53.TextbookImportPage();
    },
  );
}

/// generated route for
/// [_i54.TransparencyLogPage]
class TransparencyLogRoute extends _i57.PageRouteInfo<void> {
  const TransparencyLogRoute({List<_i57.PageRouteInfo>? children})
      : super(TransparencyLogRoute.name, initialChildren: children);

  static const String name = 'TransparencyLogRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i54.TransparencyLogPage();
    },
  );
}

/// generated route for
/// [_i55.UnifiedReviewPage]
class UnifiedReviewRoute extends _i57.PageRouteInfo<UnifiedReviewRouteArgs> {
  UnifiedReviewRoute({
    _i58.Key? key,
    required List<_i85.ReviewItem> items,
    required _i86.ReviewLedgerResolver ledgerResolver,
    String? title,
    _i83.Future<void> Function(_i85.ReviewItem, _i87.RecallOutcome)?
        onOutcomeRecorded,
    _i83.Future<void> Function(_i88.ReviewEventReceipt)? onOutcomeUndone,
    List<_i57.PageRouteInfo>? children,
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

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<UnifiedReviewRouteArgs>();
      return _i55.UnifiedReviewPage(
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

  final _i58.Key? key;

  final List<_i85.ReviewItem> items;

  final _i86.ReviewLedgerResolver ledgerResolver;

  final String? title;

  final _i83.Future<void> Function(_i85.ReviewItem, _i87.RecallOutcome)?
      onOutcomeRecorded;

  final _i83.Future<void> Function(_i88.ReviewEventReceipt)? onOutcomeUndone;

  @override
  String toString() {
    return 'UnifiedReviewRouteArgs{key: $key, items: $items, ledgerResolver: $ledgerResolver, title: $title, onOutcomeRecorded: $onOutcomeRecorded, onOutcomeUndone: $onOutcomeUndone}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnifiedReviewRouteArgs) return false;
    return key == other.key &&
        const _i73.ListEquality<_i85.ReviewItem>().equals(items, other.items) &&
        ledgerResolver == other.ledgerResolver &&
        title == other.title;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      const _i73.ListEquality<_i85.ReviewItem>().hash(items) ^
      ledgerResolver.hashCode ^
      title.hashCode;
}

/// generated route for
/// [_i56.WeakWordsPage]
class WeakWordsRoute extends _i57.PageRouteInfo<void> {
  const WeakWordsRoute({List<_i57.PageRouteInfo>? children})
      : super(WeakWordsRoute.name, initialChildren: children);

  static const String name = 'WeakWordsRoute';

  static _i57.PageInfo page = _i57.PageInfo(
    name,
    builder: (data) {
      return const _i56.WeakWordsPage();
    },
  );
}
