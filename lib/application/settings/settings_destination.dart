// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/core/turna_icon_id.dart';
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
}

/// Second-level anchors inside [SettingsDestination.advanced], so external
/// callers can deep-link to e.g. Advanced -> AI connection in one hop.
enum SettingsAdvancedAnchor {
  aiConnection,
  storagePerformance,
  systemHealth,
  legacyCompatibility,
}

/// Display + navigation metadata for one [SettingsDestination].
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
    }
  }

  TurnaIconId get icon {
    switch (this) {
      case SettingsDestination.account:
        return TurnaIconId.person;
      case SettingsDestination.learning:
        return TurnaIconId.book;
      case SettingsDestination.appearanceAndSound:
        return TurnaIconId.palette;
      case SettingsDestination.accessibility:
        return TurnaIconId.accessibility;
      case SettingsDestination.dataAndBackup:
        return TurnaIconId.storage;
      case SettingsDestination.advanced:
        return TurnaIconId.wrench;
      case SettingsDestination.about:
        return TurnaIconId.info;
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
