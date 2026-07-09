// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/service/locator.dart';
import 'package:words625/views/theme.dart';

@injectable
class ThemeProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  ThemeMode _themeMode = ThemeMode.light;

  ThemeProvider(this.appPrefs) {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  ThemeData get currentTheme => isDarkMode
      ? VarnamalaTheme.darkTheme
      : VarnamalaTheme.lightTheme;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    _persist();
    notifyListeners();
  }

  void setLightMode() {
    _themeMode = ThemeMode.light;
    _persist();
    notifyListeners();
  }

  void setDarkMode() {
    _themeMode = ThemeMode.dark;
    _persist();
    notifyListeners();
  }

  void setSystemMode() {
    _themeMode = ThemeMode.system;
    _persist();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _persist();
    notifyListeners();
  }

  void _loadThemeMode() {
    final stored = appPrefs.preferences
        .getString(LocalStateKeys.themeMode, defaultValue: 'system')
        .getValue();
    _themeMode = _parseThemeMode(stored);
  }

  void _persist() {
    final value = _themeMode.name; // 'light' | 'dark' | 'system'
    appPrefs.preferences.setString(LocalStateKeys.themeMode, value);
  }

  static ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
