// Package imports:
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/service/locator.dart';

/// Application-layer access point for the local learner profile ([LocalUser]
/// display name, avatar, and daily goals), shielding views from `AppPrefs`.
abstract final class ProfilePrefsFacade {
  /// Returns the reactive [LocalUser] preference when [SettingsProvider] or
  /// [AppPrefs] is available, or `null` in minimal test subtrees.
  static Preference<LocalUser>? authUserPreference({
    SettingsProvider? settings,
  }) {
    if (settings != null) return settings.authUserPreference;
    if (getIt.isRegistered<SettingsProvider>()) {
      return getIt<SettingsProvider>().authUserPreference;
    }
    if (getIt.isRegistered<AppPrefs>()) {
      return getIt<AppPrefs>().authUser;
    }
    return null;
  }

  /// Synchronous snapshot of the current [LocalUser], defaulting to
  /// [LocalUser.local] if neither [SettingsProvider] nor [AppPrefs] is wired.
  static LocalUser currentUser({SettingsProvider? settings}) {
    if (settings != null) return settings.localUser;
    if (getIt.isRegistered<SettingsProvider>()) {
      return getIt<SettingsProvider>().localUser;
    }
    if (getIt.isRegistered<AppPrefs>()) {
      return getIt<AppPrefs>().authUser.getValue();
    }
    return LocalUser.local;
  }

  /// Persists an updated [LocalUser] through [SettingsProvider] when wired,
  /// falling back to [AppPrefs] for isolated widget tests.
  static Future<void> saveUser(
    LocalUser user, {
    SettingsProvider? settings,
  }) async {
    if (settings != null) {
      await settings.setLocalUser(user);
      return;
    }
    if (getIt.isRegistered<SettingsProvider>()) {
      await getIt<SettingsProvider>().setLocalUser(user);
      return;
    }
    if (getIt.isRegistered<AppPrefs>()) {
      await getIt<AppPrefs>().setLocalUser(user);
    }
  }
}
