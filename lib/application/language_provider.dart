// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/language_registry.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/service/locator.dart';

@lazySingleton
class LanguageProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  String selectedLanguageCode = LanguageCodes.turkish;

  LanguageProvider(this.appPrefs);

  String get displayName =>
      LanguageRegistry.instance.displayName(selectedLanguageCode);

  /// TTS language code for the currently selected target language.
  String get ttsLanguageCode =>
      LanguageRegistry.instance.ttsLanguageCode(selectedLanguageCode);

  String get ttsLocale =>
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
