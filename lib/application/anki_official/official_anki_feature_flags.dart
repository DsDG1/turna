/// Production Android replica: one product bundle (Official import / render /
/// scheduler / official-first). Constructor stays all-false for tests; use
/// [copyWith] to opt capabilities on. Per-capability dart-defines were
/// collapsed (doc 34 C4).
///
/// Remaining dart-defines are **opt-in only**:
/// - `TURNA_OFFICIAL_ANKI_DIAGNOSTICS`
/// - `TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS`
/// - `TURNA_OFFICIAL_ANKI_MIGRATION_PILOT`
/// - `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER`
/// - `TURNA_OFFICIAL_ANKI_LEGACY_MIRROR`
///
/// Product pause is [LegacyAnkiMigrationFlags.cutoverEnabled]
/// (`TURNA_OFFICIAL_ANKI_CUTOVER`, default true) — not a second flag matrix.
///
/// The legacy→official background mirror remains a development-only escape
/// hatch via `TURNA_OFFICIAL_ANKI_LEGACY_MIRROR` and must not be combined
/// with Official-first production traffic.
class OfficialAnkiFeatureFlags {
  const OfficialAnkiFeatureFlags({
    this.engine = false,
    this.import = false,
    this.diagnostics = false,
    this.catalogReady = false,
    this.runtimeCapable = false,
    this.platformReady = false,
    this.renderer = false,
    this.reviewerDiagnostics = false,
    this.projection = false,
    this.courseEntry = false,
    this.scheduler = false,
    this.courseGradesScheduler = false,
    this.officialFirstImport = false,
    this.legacyMirror = false,
  });

  /// Android production product flags. Opt-in diagnostics / pilot / grades /
  /// mirror stay off.
  static const productionAndroid = OfficialAnkiFeatureFlags(
    engine: true,
    import: true,
    catalogReady: true,
    runtimeCapable: true,
    platformReady: true,
    renderer: true,
    projection: true,
    courseEntry: true,
    scheduler: true,
    officialFirstImport: true,
  );

  factory OfficialAnkiFeatureFlags.fromEnvironment() {
    const diagnostics = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_DIAGNOSTICS');
    const reviewerDiagnostics =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS');
    const courseGradesScheduler =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER');
    const legacyMirror =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_LEGACY_MIRROR');
    return productionAndroid.copyWith(
      diagnostics: diagnostics,
      reviewerDiagnostics: reviewerDiagnostics,
      courseGradesScheduler: courseGradesScheduler,
      legacyMirror: legacyMirror,
    );
  }

  final bool engine;
  final bool import;
  final bool diagnostics;
  final bool catalogReady;
  final bool runtimeCapable;
  final bool platformReady;
  final bool renderer;
  final bool reviewerDiagnostics;
  final bool projection;
  final bool courseEntry;
  final bool scheduler;
  final bool courseGradesScheduler;
  final bool officialFirstImport;

  /// Development-only: after a successful legacy commit, mirror the same
  /// package into the official collection in the background. Production
  /// keeps exactly one owner per import, so this stays opt-in
  /// (`TURNA_OFFICIAL_ANKI_LEGACY_MIRROR`); mirrored imports are still
  /// deletable through the unified uninstall saga.
  final bool legacyMirror;

  static OfficialAnkiFeatureFlags current =
      OfficialAnkiFeatureFlags.fromEnvironment();

  bool get allowsOfficialImport =>
      import && engine && catalogReady && runtimeCapable && platformReady;

  bool get allowsOfficialRenderer =>
      renderer && engine && catalogReady && runtimeCapable && platformReady;

  bool get allowsProjection =>
      engine && import && catalogReady && runtimeCapable && projection;

  bool get allowsCourseEntry =>
      allowsProjection && courseEntry;

  bool get allowsOfficialScheduler =>
      engine &&
      import &&
      catalogReady &&
      runtimeCapable &&
      platformReady &&
      renderer &&
      scheduler;

  bool get allowsCourseGradesScheduler =>
      allowsOfficialScheduler && courseGradesScheduler;

  /// Official saga runs before any Turna-side write and the course tree is
  /// projected from the official collection (no Dart apkg parse on this path).
  /// Production default is on (doc 34); requires projection/course-entry.
  bool get allowsOfficialFirstImport =>
      officialFirstImport && allowsOfficialImport && allowsCourseEntry;

  OfficialAnkiFeatureFlags copyWith({
    bool? engine,
    bool? import,
    bool? diagnostics,
    bool? catalogReady,
    bool? runtimeCapable,
    bool? platformReady,
    bool? renderer,
    bool? reviewerDiagnostics,
    bool? projection,
    bool? courseEntry,
    bool? scheduler,
    bool? courseGradesScheduler,
    bool? officialFirstImport,
    bool? legacyMirror,
  }) {
    return OfficialAnkiFeatureFlags(
      engine: engine ?? this.engine,
      import: import ?? this.import,
      diagnostics: diagnostics ?? this.diagnostics,
      catalogReady: catalogReady ?? this.catalogReady,
      runtimeCapable: runtimeCapable ?? this.runtimeCapable,
      platformReady: platformReady ?? this.platformReady,
      renderer: renderer ?? this.renderer,
      reviewerDiagnostics: reviewerDiagnostics ?? this.reviewerDiagnostics,
      projection: projection ?? this.projection,
      courseEntry: courseEntry ?? this.courseEntry,
      scheduler: scheduler ?? this.scheduler,
      courseGradesScheduler:
          courseGradesScheduler ?? this.courseGradesScheduler,
      officialFirstImport: officialFirstImport ?? this.officialFirstImport,
      legacyMirror: legacyMirror ?? this.legacyMirror,
    );
  }
}

enum OfficialAnkiExecutionMode {
  none,
  worker,
  inProcess,
  fake,
}
