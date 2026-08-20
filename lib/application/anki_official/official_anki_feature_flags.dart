/// Production Android replica defaults: import/render/scheduler on.
/// Constructor stays all-false for tests. Disable with `--dart-define=…=false`.
/// Diagnostics, projection, course-entry, and migration pilot stay opt-in.
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
    );
  }
}

enum OfficialAnkiExecutionMode {
  none,
  worker,
  inProcess,
  fake,
}
