/// Production Android replica defaults: import/render/scheduler on.
/// Constructor stays all-false for tests. Disable with `--dart-define=…=false`.
/// Diagnostics, migration pilot, course-grades scheduler, and the P5F
/// official-first import path stay opt-in.
///
/// Production default policy (single source of truth): exactly one owner per
/// import — official-capable builds import through the official saga and
/// never re-mirror the same package into the legacy store afterwards. The
/// legacy→official background mirror is a development-only escape hatch via
/// `TURNA_OFFICIAL_ANKI_LEGACY_MIRROR`.
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
    this.migrationPilot = false,
    this.courseGradesScheduler = false,
    this.officialFirstImport = false,
    this.legacyMirror = false,
  });

  factory OfficialAnkiFeatureFlags.fromEnvironment() {
    const engine = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_ENGINE',
      defaultValue: true,
    );
    const import = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_IMPORT',
      defaultValue: true,
    );
    const diagnostics = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_DIAGNOSTICS');
    const catalogReady = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_CATALOG',
      defaultValue: true,
    );
    const runtimeCapable = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_RUNTIME',
      defaultValue: true,
    );
    const platformReady = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_PLATFORM',
      defaultValue: true,
    );
    const renderer = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_RENDERER',
      defaultValue: true,
    );
    const reviewerDiagnostics =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS');
    const projection = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_PROJECTION',
      defaultValue: true,
    );
    const courseEntry = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_COURSE_ENTRY',
      defaultValue: true,
    );
    const scheduler = bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_SCHEDULER',
      defaultValue: true,
    );
    const migrationPilot =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_MIGRATION_PILOT');
    const courseGradesScheduler =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER');
    const officialFirstImport =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT');
    const legacyMirror =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_LEGACY_MIRROR');
    return const OfficialAnkiFeatureFlags(
      engine: engine,
      import: import,
      diagnostics: diagnostics,
      catalogReady: catalogReady,
      runtimeCapable: runtimeCapable,
      platformReady: platformReady,
      renderer: renderer,
      reviewerDiagnostics: reviewerDiagnostics,
      projection: projection,
      courseEntry: courseEntry,
      scheduler: scheduler,
      migrationPilot: migrationPilot,
      courseGradesScheduler: courseGradesScheduler,
      officialFirstImport: officialFirstImport,
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
  final bool migrationPilot;
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

  /// P5F: official saga runs before Turna-side writes and the course tree is
  /// projected from the official collection (no Dart apkg parse on this path).
  /// Opt-in only; requires the full projection/course-entry capability set.
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
    bool? migrationPilot,
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
      migrationPilot: migrationPilot ?? this.migrationPilot,
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
