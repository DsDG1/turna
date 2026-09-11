// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/service/locator.dart';

@lazySingleton
class LanguageProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  String selectedLanguageCode = LanguageCodes.turkish;

  LanguageProvider(this.appPrefs);

  String get displayName =>
      ImportedLanguageRegistry.instance.displayNameOrNull(selectedLanguageCode) ??
      LanguageRegistry.instance.displayName(selectedLanguageCode);

  String get ttsLanguageCode {
    final locale = ttsLocale;
    final normalized = locale.replaceAll('_', '-');
    final dash = normalized.indexOf('-');
    if (dash <= 0) return normalized.toLowerCase();
    return normalized.substring(0, dash).toLowerCase();
  }

  String get ttsLocale =>
      ImportedLanguageRegistry.instance.ttsLocaleOrNull(selectedLanguageCode) ??
      LanguageRegistry.instance.ttsLocale(selectedLanguageCode);

  void initLanguage() {
    selectedLanguageCode = LanguageCodes.canonicalize(
      appPrefs.currentLanguage.getValue(),
    );
    notifyListeners();
  }

  /// Re-reads the persisted language selection. Used after a backup restore
  /// (PostRestoreReloadRegistry step); identical to [initLanguage] but named
  /// for its restore role.
  void reload() => initLanguage();

  void setLanguageCode(String code) {
    selectedLanguageCode = LanguageCodes.canonicalize(code);
    notifyListeners();
  }

  /// Persist the current language selection. Callers fire-and-forget via
  /// `unawaited(...)` — the selection is already in memory, this just durably
  /// writes it so a fast app-kill doesn't lose the choice.
  Future<void> cacheLanguage() async {
    await appPrefs.setString(
        PrefsConstants.currentLanguage, selectedLanguageCode);

    notifyListeners();
  }
}
