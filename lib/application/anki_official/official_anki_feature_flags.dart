/// Release defaults are all false. Internal builds may override in tests.
class OfficialAnkiFeatureFlags {
  const OfficialAnkiFeatureFlags({
    this.engine = false,
    this.import = false,
    this.diagnostics = false,
    this.catalogReady = false,
    this.runtimeCapable = false,
    this.platformReady = false,
  });

  final bool engine;
  final bool import;
  final bool diagnostics;
  final bool catalogReady;
  final bool runtimeCapable;
  final bool platformReady;

  static OfficialAnkiFeatureFlags current = const OfficialAnkiFeatureFlags();

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
