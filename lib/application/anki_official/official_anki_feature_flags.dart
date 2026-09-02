/// Production Android replica: one product bundle (Official import / render /
/// scheduler / official-first). Constructor stays all-false for tests; use
/// [copyWith] to opt capabilities on. Per-capability dart-defines were
/// collapsed (doc 34 C4).
///
/// Remaining dart-defines on this class are **opt-in only**:
/// - `TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS`
/// - `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER`
///
/// `TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN` was retired at R4 (2026-09-02):
/// productionAndroid ships `v2ImportChain: true`, and feeding the define
/// through [copyWith] would overwrite that constant with the absent-define
/// `false` — its C3 feeding mission is complete, so it is no longer read.
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
  /// stay off. v2ImportChain flipped at R4 (2026-09-02; step4.md receipts) —
  /// rollback = flip it back to false (re-routes NEW imports only).
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
    v2ImportChain: true,
  );

  factory OfficialAnkiFeatureFlags.fromEnvironment() {
    const reviewerDiagnostics =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS');
    const courseGradesScheduler =
        bool.fromEnvironment('TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER');
    // v2ImportChain deliberately NOT copied here: an absent define reads
    // false and would clobber the productionAndroid constant (R4 trap).
    return productionAndroid.copyWith(
      reviewerDiagnostics: reviewerDiagnostics,
      courseGradesScheduler: courseGradesScheduler,
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

  /// v2 single-source chain (step4.md A1). [productionAndroid] ships it on
  /// since R4 (2026-09-02); rollback = flip the constant back to false.
  /// Rolling back only re-routes NEW imports — already-imported v2 sources
  /// stay learnable (ledger rows, config decisions and the view table all
  /// remain; the read path serves both generations).
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
