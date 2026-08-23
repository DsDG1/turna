// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/tab_router.dart';

/// Strongly-typed settings destinations (Plan 2 §5.3).
///
/// Category identity must not depend on display order: inserting, removing or
/// reordering home-page tiles must never shift another category's identity the
/// way the legacy integer `_category` indices did.
enum SettingsDestination {
  account,
  learning,
  appearanceAndSound,
  accessibility,
  dataAndBackup,
  advanced,
  about,

  /// Debug-only developer lab. Never surfaced in release/profile builds.
  developer,
}

/// Second-level anchors inside [SettingsDestination.advanced], so external
/// callers can deep-link to e.g. Advanced -> AI connection in one hop.
enum SettingsAdvancedAnchor {
  aiConnection,
  storagePerformance,
  systemHealth,
  legacyCompatibility,
}

/// Display + navigation metadata for one [SettingsDestination]. A single
/// descriptor per destination replaces the parallel title/icon/subtitle
/// switch statements the landing page used to carry; the exhaustive `for`
/// over [SettingsDestination.values] in tests fails to compile when a new
/// destination lacks a descriptor.
extension SettingsDestinationDescriptor on SettingsDestination {
  String get title {
    switch (this) {
      case SettingsDestination.account:
        return AppStrings.settingsCategoryAccount;
      case SettingsDestination.learning:
        return AppStrings.settingsCategoryLearning;
      case SettingsDestination.appearanceAndSound:
        return AppStrings.settingsCategoryAppearanceSound;
      case SettingsDestination.accessibility:
        return AppStrings.settingsCategoryAccessibility;
      case SettingsDestination.dataAndBackup:
        return AppStrings.settingsCategoryDataBackup;
      case SettingsDestination.advanced:
        return AppStrings.settingsCategoryAdvanced;
      case SettingsDestination.about:
        return AppStrings.settingsCategoryAbout;
      case SettingsDestination.developer:
        return AppStrings.settingsCategoryFunLab;
    }
  }

  String get subtitle {
    switch (this) {
      case SettingsDestination.account:
        return AppStrings.settingsCategoryAccountSubtitle;
      case SettingsDestination.learning:
        return AppStrings.settingsCategoryLearningSubtitle;
      case SettingsDestination.appearanceAndSound:
        return AppStrings.settingsCategoryAppearanceSoundSubtitle;
      case SettingsDestination.accessibility:
        return AppStrings.settingsCategoryAccessibilitySubtitle;
      case SettingsDestination.dataAndBackup:
        return AppStrings.settingsCategoryDataBackupSubtitle;
      case SettingsDestination.advanced:
        return AppStrings.settingsCategoryAdvancedSubtitle;
      case SettingsDestination.about:
        return AppStrings.settingsCategoryAboutSubtitle;
      case SettingsDestination.developer:
        return AppStrings.settingsCategoryFunLabSubtitle;
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsDestination.account:
        return Icons.person_rounded;
      case SettingsDestination.learning:
        return Icons.menu_book_rounded;
      case SettingsDestination.appearanceAndSound:
        return Icons.palette_rounded;
      case SettingsDestination.accessibility:
        return Icons.accessibility_new_rounded;
      case SettingsDestination.dataAndBackup:
        return Icons.storage_rounded;
      case SettingsDestination.advanced:
        return Icons.build_rounded;
      case SettingsDestination.about:
        return Icons.info_rounded;
      case SettingsDestination.developer:
        return Icons.science_rounded;
    }
  }

  /// Route pushed for this destination. Every formal category is a real,
  /// routable page — there is no in-page pseudo navigation left.
  PageRouteInfo get route {
    switch (this) {
      case SettingsDestination.account:
        return const AccountSettingsRoute();
      case SettingsDestination.learning:
        return const LearningSettingsRoute();
      case SettingsDestination.appearanceAndSound:
        return const AppearanceSoundSettingsRoute();
      case SettingsDestination.accessibility:
        return const AccessibilitySettingsRoute();
      case SettingsDestination.dataAndBackup:
        return const DataBackupSettingsRoute();
      case SettingsDestination.advanced:
        return const AdvancedSettingsRoute();
      case SettingsDestination.about:
        return const AboutSettingsRoute();
      case SettingsDestination.developer:
        return const DeveloperSettingsRoute();
    }
  }
}

/// Route for a second-level anchor inside Advanced.
PageRouteInfo routeForAdvancedAnchor(SettingsAdvancedAnchor anchor) {
  switch (anchor) {
    case SettingsAdvancedAnchor.aiConnection:
      return const AiApiConfigRoute();
    case SettingsAdvancedAnchor.storagePerformance:
      return StorageDiagnosticsRoute();
    case SettingsAdvancedAnchor.systemHealth:
      return const SystemHealthRoute();
    case SettingsAdvancedAnchor.legacyCompatibility:
      return const LegacyCompatibilityRoute();
  }
}

/// Unified entry point for opening a settings sub-page from anywhere in the
/// app: switches the Home tab to Settings, then pushes the destination's
/// real route. Because the destination is a router page, the request works
/// identically on cold start, before the Settings tab was ever visited, and
/// when repeated — no pending-request buffer can drop it, and there is no
/// ephemeral controller fallback to lose it in.
Future<void> openSettings(
  BuildContext context,
  SettingsDestination destination, {
  SettingsAdvancedAnchor? anchor,
}) async {
  getIt<TabRouter>().switchTo(TabDestination.settings);
  final target = anchor == null
      ? destination.route
      : (destination == SettingsDestination.advanced
          ? routeForAdvancedAnchor(anchor)
          : destination.route);
  await context.router.push(target);
}
