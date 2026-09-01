/// Production Android replica: one product bundle (Official import / render /
/// scheduler / official-first). Constructor stays all-false for tests; use
/// [copyWith] to opt capabilities on. Per-capability dart-defines were
/// collapsed (doc 34 C4).
///
/// Remaining dart-defines on this class are **opt-in only**:
/// - `TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS`
/// - `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER`
/// - `TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN` (C3 matrix / internal builds only;
///   absent define = false, so production bundles keep the v2 chain off)
///
/// `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` is the release diagnostics route
/// guard, not a field here.
///
/// Product pause is [LegacyAnkiMigrationFlags.cutoverEnabled]
/// (`TURNA_OFFICIAL_ANKI_CUTOVER`, default true) — not a second flag matrix.
///
/// v2 import chain (ADR 0043 / step4.md A1): exactly one boolean routes new
/// imports and the course-tree read path. Default false; productionAndroid
/// stays false until the K1–K14 on-device matrix is green plus one internal
/// release observation window. Rolling back only re-routes NEW imports —
/// already-imported v2 sources stay learnable (ledger rows, config decisions
/// and the view table all remain; the read path serves both generations).
class OfficialAnkiFeatureFlags {
  const OfficialAnkiFeatureFlags({
    this.engine = false,
    this.import = false,
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
    this.v2ImportChain = false,
  });

  /// Android production product flags. Opt-in reviewer diagnostics / grades
  /// stay off.
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
    const reviewerDiagnostics =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS');
    const courseGradesScheduler =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER');
    const v2ImportChain =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN');
    return productionAndroid.copyWith(
      reviewerDiagnostics: reviewerDiagnostics,
      courseGradesScheduler: courseGradesScheduler,
      v2ImportChain: v2ImportChain,
    );
  }

  final bool engine;
  final bool import;
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

  /// v2 single-source chain (step4.md A1). Off here means constructor
  /// default; [productionAndroid] keeps it off until the kill matrix is
  /// green. Dev/QA builds opt in via [copyWith].
  final bool v2ImportChain;

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

  /// v2 chain gate (step4.md A1): rides on the v1 capability floor — v2 is
  /// a routing change of the publish/read stages, not a new engine surface.
  bool get allowsV2ImportChain =>
      v2ImportChain && allowsOfficialFirstImport;

  OfficialAnkiFeatureFlags copyWith({
    bool? engine,
    bool? import,
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
    bool? v2ImportChain,
  }) {
    return OfficialAnkiFeatureFlags(
      engine: engine ?? this.engine,
      import: import ?? this.import,
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
      v2ImportChain: v2ImportChain ?? this.v2ImportChain,
    );
  }
}

enum OfficialAnkiExecutionMode {
  none,
  worker,
  inProcess,
  fake,
}
