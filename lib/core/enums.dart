enum TargetLanguage {
  turkish;

  /// Human-readable name used in UI surfaces and AI prompts (e.g. the
  /// in-lesson AI hint assistant's persona). Add an entry here whenever a
  /// new target language is introduced so those surfaces stay in sync.
  String get displayName {
    return switch (this) {
      TargetLanguage.turkish => 'Turkish',
    };
  }
}
