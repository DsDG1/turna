// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/service/locator.dart';

@lazySingleton
class LanguageProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  TargetLanguage selectedLanguage = TargetLanguage.swahili;

  LanguageProvider(this.appPrefs);

  /// TTS language code for the currently selected target language.
  String get ttsLanguageCode {
    switch (selectedLanguage) {
      case TargetLanguage.swahili:
        // See docs/decisions/0001-tts-language-code.md
        return 'sw';
    }
  }

  initLanguage() {
    selectedLanguage = TargetLanguage.values.firstWhere(
      (element) => element.name == appPrefs.currentLanguage.getValue(),
      orElse: () => TargetLanguage.swahili,
    );

    notifyListeners();
  }

  void setLanguage(TargetLanguage language) {
    selectedLanguage = language;

    notifyListeners();
  }

  void cacheLanguage() async {
    await appPrefs.setString(PrefsConstants.currentLanguage, selectedLanguage.name);

    notifyListeners();
  }
}