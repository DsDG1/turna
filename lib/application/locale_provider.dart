// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/service/locator.dart';

/// UI display language (the app chrome / interface language), independent of
/// [LanguageProvider] (which tracks the *target* learning language, e.g.
/// Turkish). Supports English, Chinese (Simplified), and following the
/// system locale.
@lazySingleton
class LocaleProvider extends ChangeNotifier {
  final AppPrefs _appPrefs;

  /// `null` means "follow the system locale".
  Locale? _locale;

  LocaleProvider(this._appPrefs) {
    _load();
  }

  /// The user-chosen UI locale, or `null` to follow the system.
  Locale? get locale => _locale;

  /// All UI locales the app ships translations for.
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  void _load() {
    final stored = _appPrefs.preferences
        .getString(LocalStateKeys.uiLocale, defaultValue: 'system')
        .getValue();
    _locale = _parse(stored);
  }

  /// Sets the UI locale. Pass `null` to follow the system locale.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    await _appPrefs.setString(
      LocalStateKeys.uiLocale,
      locale?.languageCode ?? 'system',
    );
    notifyListeners();
  }

  static Locale? _parse(String value) {
    switch (value) {
      case 'en':
        return const Locale('en');
      case 'zh':
        return const Locale('zh');
      case 'system':
      default:
        return null;
    }
  }
}