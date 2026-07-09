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
        // Current vocab.json still holds Kannada words; use 'kn' so TTS can
        // actually pronounce them. Switch back to 'sw' once real Swahili
        // vocabulary replaces the Kannada placeholder data.
        return 'kn';
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