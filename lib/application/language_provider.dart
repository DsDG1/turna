// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/enums.dart';
import 'package:turna/service/locator.dart';

@lazySingleton
class LanguageProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  TargetLanguage selectedLanguage = TargetLanguage.turkish;

  LanguageProvider(this.appPrefs);

  /// TTS language code for the currently selected target language.
  String get ttsLanguageCode {
    switch (selectedLanguage) {
      case TargetLanguage.turkish:
        // See docs/decisions/0020-swahili-to-turkish-pivot.md
        return 'tr';
    }
  }

  initLanguage() {
    selectedLanguage = TargetLanguage.values.firstWhere(
      (element) => element.name == appPrefs.currentLanguage.getValue(),
      orElse: () => TargetLanguage.turkish,
    );

    notifyListeners();
  }

  void setLanguage(TargetLanguage language) {
    selectedLanguage = language;

    notifyListeners();
  }

  /// Persist the current language selection. Callers fire-and-forget via
  /// `unawaited(...)` — the selection is already in memory, this just durably
  /// writes it so a fast app-kill doesn't lose the choice.
  Future<void> cacheLanguage() async {
    await appPrefs.setString(PrefsConstants.currentLanguage, selectedLanguage.name);

    notifyListeners();
  }
}