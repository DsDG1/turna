/// Release defaults are all false. Internal builds may pass `--dart-define`.
class OfficialAnkiFeatureFlags {
  const OfficialAnkiFeatureFlags({
    this.engine = false,
    this.import = false,
    this.diagnostics = false,
    this.catalogReady = false,
    this.runtimeCapable = false,
    this.platformReady = false,
  });

  factory OfficialAnkiFeatureFlags.fromEnvironment() {
    const engine = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_ENGINE');
    const import = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_IMPORT');
    const diagnostics = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_DIAGNOSTICS');
    const catalogReady = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_CATALOG');
    const runtimeCapable = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_RUNTIME');
    const platformReady = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_PLATFORM');
    return const OfficialAnkiFeatureFlags(
      engine: engine,
      import: import,
      diagnostics: diagnostics,
      catalogReady: catalogReady,
      runtimeCapable: runtimeCapable,
      platformReady: platformReady,
    );
  }

  final bool engine;
  final bool import;
  final bool diagnostics;
  final bool catalogReady;
  final bool runtimeCapable;
  final bool platformReady;

  static OfficialAnkiFeatureFlags current =
      OfficialAnkiFeatureFlags.fromEnvironment();

  bool get allowsOfficialImport =>
      import && engine && catalogReady && runtimeCapable && platformReady;

  OfficialAnkiFeatureFlags copyWith({
    bool? engine,
    bool? import,
    bool? diagnostics,
    bool? catalogReady,
    bool? runtimeCapable,
    bool? platformReady,
  }) {
    return OfficialAnkiFeatureFlags(
      engine: engine ?? this.engine,
      import: import ?? this.import,
      diagnostics: diagnostics ?? this.diagnostics,
      catalogReady: catalogReady ?? this.catalogReady,
      runtimeCapable: runtimeCapable ?? this.runtimeCapable,
      platformReady: platformReady ?? this.platformReady,
    );
  }
}
