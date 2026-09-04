// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_course_read.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/course_lookup.dart';
import 'package:turna/data/course_database.dart' show CourseDatabase;
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/service/locator.dart';

/// Explicit state for per-section body loading.
///
/// Used by [CourseProvider] and consumed by [CourseTree] to decide whether
/// to show a spinner, the loaded content, an error retry button, or the empty
/// state.
enum SectionLoadState { initial, loading, loaded, error }

/// State holder for the loaded course tree and the user's current
/// selection within it. All selection is keyed by stable `String` ids so
/// that inserting a new section/unit/lesson in the middle of the tree
/// cannot shift the user's view onto a different node.
///
/// The active course is identified by a typed [CourseScope] (plan 34 D1):
/// the built-in language course, one Legacy Anki import, or one Official
/// Anki source. String scope matching lives only in [CourseScopeCodec] and
/// the one-time preference migrator — business code compares typed scopes.
///
/// Sections are loaded lazily: [load] populates [_sections] with lightweight
/// shells (units empty) from the course index and pre-loads the first
/// section's body. Switching to a section triggers [ensureSectionLoaded] to
/// fetch that section's full body on demand (cached per id).
@lazySingleton
class CourseProvider extends ChangeNotifier {
  CourseProvider([this._appPrefs]);

  /// Prefs backing for [scope] persistence. Optional so tests can
  /// construct the provider without a prefs store (scope then stays
  /// builtin).
  final AppPrefs? _appPrefs;

  // --- Section hierarchy ---
  List<Section> _sections = const [];

  /// Unfiltered section shells/bodies (built-in course + imported Anki
  /// decks). [_sections] is the [scope]-filtered view of this list;
  /// consumers that must stay scope-independent (Anki review hub, daily
  /// challenge) read [allSections] instead.
  List<Section> _allSections = const [];
  String? _currentSectionId;
  String? _selectedUnitId;
  String? _selectedLessonId;
  bool _isLoaded = false;

  /// Active course scope (typed). Built-in language course by default.
  CourseScope _scope = const BuiltinCourseScope('turkish');

  /// Catalog of selectable courses, loaded with the shells.
  List<CourseCatalogEntry> _catalogEntries = const [];

  /// Ids of sections whose full body (units/lessons) has been loaded.
  final Set<String> _loadedSectionIds = {};

  /// Cache of all loaded lessons for O(1) lookup by id.
  final Map<String, Lesson> _lessonCache = {};

  /// In-flight body loads keyed by section id (coalesces concurrent callers).
  /// The presence of a future only means a load was started; the authoritative
  /// state is tracked in [_sectionLoadStates].
  final Map<String, Future<void>> _sectionLoadFutures = {};

  /// Authoritative load state for each section body.
  final Map<String, SectionLoadState> _sectionLoadStates = {};

  /// Last error for each section body load, keyed by section id.
  final Map<String, Object> _sectionLoadErrors = {};

  bool get _currentSectionLoading =>
      _currentSectionId != null &&
      _sectionLoadStates[_currentSectionId] == SectionLoadState.loading;

  /// Immutable view of the section shells (and any loaded bodies). Order is
  /// the on-disk order. Shells have empty `units` until loaded.
  ///
  /// This is the [scope]-filtered view — see [allSections] for the
  /// unfiltered list.
  List<Section> get sections => List.unmodifiable(_sections);

  /// How many sections have their full body loaded. Cheap fingerprint input
  /// for content-revision cache keys (Playground, AI context): changes only
  /// when section bodies actually load or reset.
  int get loadedSectionCount => _loadedSectionIds.length;

  /// Unfiltered view of every section (built-in course + all imported Anki
  /// decks), regardless of [scope].
  List<Section> get allSections => List.unmodifiable(_allSections);

  /// The active typed course scope.
  CourseScope get scope => _scope;

  /// Wire key of the active scope (versioned codec). Persistence-facing
  /// consumers read this; comparisons should use [scope] instead.
  String get courseScope => _scope.wireKey;

  /// The course catalog: one entry per selectable course (builtin + one
  /// entry per Anki source), ordered by the persisted course order.
  List<CourseCatalogEntry> get catalogEntries =>
      List.unmodifiable(_catalogEntries);

  /// Whether [sectionId] belongs to the active scope. Exact ownership only.
  bool sectionInActiveScope(String sectionId) =>
      CourseCatalog.sectionBelongsToScope(_scope, sectionId);

  /// Legacy view over [catalogEntries]. Prefer [catalogEntries].
  List<({String scope, String name, bool isBuiltin})> get courseEntries {
    return List.unmodifiable([
      for (final entry in _catalogEntries)
        (
          scope: entry.wireKey,
          name: entry.displayName,
          isBuiltin: entry.isBuiltin
        ),
    ]);
  }

  /// Persist the course order shown in the course-management page. [wires]
  /// uses the v1 codec wire keys (see [CourseScopeCodec]).
  Future<void> persistCourseOrder(List<String> wires) async {
    final prefs = _appPrefs;
    if (prefs == null) return;
    await prefs.setStringList(PrefsConstants.courseOrder, wires);
    await _reloadCatalog();
    notifyListeners();
  }

  /// Whether [load] has completed at least once.
  bool get isLoaded => _isLoaded;

  /// Id of the currently-focused section, or `null` if none selected
  /// (e.g. before [load] completes or the section list is empty).
  String? get currentSectionId => _currentSectionId;
  String? get selectedUnitId => _selectedUnitId;
  String? get selectedLessonId => _selectedLessonId;

  /// True while the current section's body is loading on demand. UI can use
  /// this (together with `currentSection.units.isEmpty`) to show a spinner.
  bool get isCurrentSectionLoading => _currentSectionLoading;

  /// Whether [id] is currently loading.
  bool isSectionLoading(String id) =>
      _sectionLoadStates[id] == SectionLoadState.loading;

  /// The load state for [id]. Defaults to [SectionLoadState.initial].
  SectionLoadState sectionLoadState(String id) =>
      _sectionLoadStates[id] ?? SectionLoadState.initial;

  /// The last error encountered while loading [id], or `null` if none.
  Object? sectionLoadError(String id) => _sectionLoadErrors[id];

  Section? get currentSection {
    if (_currentSectionId == null) return null;
    return findSectionById(_currentSectionId!);
  }

  Unit? get currentUnit {
    final section = currentSection;
    if (section == null || _selectedUnitId == null) return null;
    return findUnitById(_selectedUnitId!);
  }

  Lesson? get currentLesson {
    if (_selectedLessonId == null) return null;
    return findLessonById(_selectedLessonId!);
  }

  List<Unit> get currentUnits => currentSection?.units ?? const [];

  // --- Lookup helpers ---

  /// Look up a [Section] by id (shells are real Sections, so this works
  /// before a section's body is loaded).
  Section? findSectionById(String id) {
    for (final s in _sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Look up a [Unit] by id, searching only sections whose bodies have been
  /// loaded. An id in a not-yet-loaded section returns `null`.
  Unit? findUnitById(String id) {
    for (final section in _sections) {
      if (!_loadedSectionIds.contains(section.id)) continue;
      for (final unit in section.units) {
        if (unit.id == id) return unit;
      }
    }
    return null;
  }

  /// Look up a [Lesson] by id across loaded sections' units. An id in a
  /// not-yet-loaded section returns `null`.
  Lesson? findLessonById(String id) {
    final cached = _lessonCache[id];
    if (cached != null) return cached;
    for (final section in _sections) {
      if (!_loadedSectionIds.contains(section.id)) continue;
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          if (lesson.id == id) {
            _lessonCache[id] = lesson;
            return lesson;
          }
        }
      }
    }
    return null;
  }

  // --- Loading ---

  /// Load the course shells from the index and pre-load the first
  /// section's body so the course tree has something to show immediately.
  ///
  /// Idempotent: a second invocation while [_isLoaded] is already true is a
  /// v2 视图 section id 集（flag 关时空）：这些 section 的壳自带完整
  /// units/lessons，[ensureSectionLoaded] 无需再走 drift 装载。
  Set<String> _v2SectionIds = <String>{};

  /// v1 壳 + v2 视图壳（B6 读面分叉；flag 关时 v2 侧为空）。
  Future<List<Section>> _shellsWithV2() async {
    final shells = await loadSectionShells();
    final read = _v2Read();
    if (read == null) return shells;
    try {
      final v2Shells = await read.sectionShells();
      if (v2Shells.isEmpty) return shells;
      return [...shells, ...v2Shells];
    } catch (error) {
      logger.w('CourseProvider: v2 section shells unavailable: $error');
      return shells;
    }
  }

  Future<Set<String>> _loadV2SectionIds() async {
    final read = _v2Read();
    if (read == null) return const {};
    try {
      return await read.activeSectionIds();
    } catch (_) {
      return const {};
    }
  }

  OfficialAnkiV2CourseRead? _v2Read() {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    CourseDatabase? course;
    try {
      course = CourseLoader.databaseOrNull();
    } catch (_) {
      course = null;
    }
    if (catalog == null || course == null) return null;
    return OfficialAnkiV2CourseRead(catalog: catalog, course: course);
  }

  /// no-op. This was previously unconditional, which let widget rebuilds
  /// (e.g. switching away from the Learn tab and back via [AnimatedSwitcher])
  /// reset [_sections] back to shells while [_loadedSectionIds] still
  /// claimed they were populated — the user saw a blank Course Tree.
  Future<void> load() async {
    if (_isLoaded) {
      logger.i('CourseProvider.load: already loaded, skipping re-entry');
      return;
    }
    logger.w('CourseProvider.load: first load, fetching from DB');
    await _restoreScopeFromPrefs();
    _v2SectionIds = await _loadV2SectionIds();
    Set<String>? officialActive;
    if (OfficialAnkiCourseEntry.flagsOf().allowsCourseEntry) {
      officialActive = await OfficialAnkiCourseEntry.resolveActiveSectionIds();
    }
    final rawShells = await _shellsWithV2();
    _allSections = OfficialAnkiCourseEntry.filterShells(
      rawShells,
      activeIds: officialActive,
    );
    await _reloadCatalog(shells: _allSections);
    _sections = _applyScopeFilter(_allSections);
    if (_scope case BuiltinCourseScope() when _sections.isEmpty) {
      // No builtin content (data wipe): keep the builtin scope with an
      // empty tree rather than thrashing the preference.
    } else if (_sections.isEmpty && _catalogStillHasScope(_scope)) {
      // Visibility (manifest fingerprint / catalogOf) missed an installed
      // source. Do not treat that as uninstall — bounce-to-builtin is what
      // made "开始学习" look stuck on the built-in tree.
      logger.w(
        'CourseProvider.load: scope "$_scope" visibility missed sections; '
        'keeping installed source',
      );
      final ownedIds = {
        for (final section in rawShells)
          if (_sectionInScope(section)) section.id,
      };
      _allSections = OfficialAnkiCourseEntry.filterShells(
        rawShells,
        activeIds: ownedIds,
      );
      await _reloadCatalog(shells: _allSections);
      _sections = _applyScopeFilter(_allSections);
    } else if (_sections.isEmpty) {
      // The scoped source was uninstalled — fall back to the built-in
      // course rather than showing an empty tree.
      logger.w(
        'CourseProvider.load: scope "$_scope" matches no sections, '
        'falling back to built-in course',
      );
      _scope = const BuiltinCourseScope('turkish');
      await _persistScope();
      _sections = _applyScopeFilter(_allSections);
    }
    _currentSectionId = _sections.isNotEmpty ? _sections.first.id : null;
    _selectedUnitId = null;
    _selectedLessonId = null;
    _isLoaded = true;
    for (final section in _sections) {
      _sectionLoadStates.putIfAbsent(
        section.id,
        () => SectionLoadState.initial,
      );
    }
    notifyListeners();
    if (_currentSectionId != null) {
      await ensureSectionLoaded(_currentSectionId!);
    }
  }

  /// Ensure the section's full body (units/lessons) is loaded and replace
  /// its shell with the populated [Section]. Cached per id via
  /// [CourseLoader.loadSection]; concurrent calls coalesce.
  ///
  /// The load outcome is reflected in [sectionLoadState] and
  /// [sectionLoadError] so the UI can show loading / error / content states
  /// instead of falling back to a blank or gray empty state.
  ///
  /// The in-flight future is registered in [_sectionLoadFutures] BEFORE the
  /// loading-state [notifyListeners]: listeners run synchronously, and a
  /// listener that re-calls this method for the same id (e.g. the Playground
  /// availability reload) must coalesce onto the in-flight future — notifying
  /// first let the re-entrant call see an empty map and start a duplicate
  /// fetch (the repeated "starting fetch" log lines / self-sustaining retry
  /// storm). The future always completes normally; load failures are
  /// surfaced via [sectionLoadState]/[sectionLoadError] because several
  /// callers await it fire-and-forget without an error handler.
  Future<void> ensureSectionLoaded(String id) {
    if (_loadedSectionIds.contains(id)) {
      _sectionLoadStates[id] = SectionLoadState.loaded;
      return Future<void>.value();
    }
    if (findSectionById(id) == null) {
      logger.w('CourseProvider.ensureSectionLoaded($id): section not in index');
      _sectionLoadStates[id] = SectionLoadState.error;
      _sectionLoadErrors[id] = StateError('Section $id not found in index');
      notifyListeners();
      return Future<void>.value();
    }
    final inFlight = _sectionLoadFutures[id];
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    _sectionLoadFutures[id] = completer.future;
    _sectionLoadStates[id] = SectionLoadState.loading;
    _sectionLoadErrors.remove(id);
    notifyListeners();
    // v2 视图 section：壳即正文（units/lessons 已在壳里），无需 drift
    // 装载——直接置 loaded，课时卡映射由 lesson card index 的 v2 分支供。
    if (_v2SectionIds.contains(id)) {
      _loadedSectionIds.add(id);
      _sectionLoadStates[id] = SectionLoadState.loaded;
      notifyListeners();
      completer.complete();
      return completer.future;
    }
    logger.i('CourseProvider.ensureSectionLoaded($id): starting fetch');
    () async {
      try {
        final full = await CourseLoader.loadSection(id);
        logger.i(
          'CourseProvider.ensureSectionLoaded($id): body received, '
          'replacing shell',
        );
        _replaceSection(full);
        _loadedSectionIds.add(id);
        _sectionLoadStates[id] = SectionLoadState.loaded;
      } catch (e, st) {
        logger.e(
          'CourseProvider.ensureSectionLoaded($id) failed',
          error: e,
          stackTrace: st,
        );
        _sectionLoadStates[id] = SectionLoadState.error;
        _sectionLoadErrors[id] = e;
      } finally {
        // reloadSection may have reset the slot while this load was in
        // flight — only clear our own registration.
        if (identical(_sectionLoadFutures[id], completer.future)) {
          _sectionLoadFutures.remove(id);
        }
        notifyListeners();
        completer.complete();
      }
    }();
    return completer.future;
  }

  void _replaceSection(Section full) {
    _allSections = _replacedIn(_allSections, full);
    _sections = _replacedIn(_sections, full);
  }

  /// Return a copy of [list] with the section matching [full]'s id replaced,
  /// refreshing the lesson cache when a replacement happened.
  List<Section> _replacedIn(List<Section> list, Section full) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == full.id) {
        final updated = List<Section>.of(list);
        updated[i] = full;
        for (final unit in full.units) {
          for (final lesson in unit.lessons) {
            _lessonCache[lesson.id] = lesson;
          }
        }
        return List.unmodifiable(updated);
      }
    }
    return list;
  }

  /// Clear any cached error/state for [id] and reload its body from scratch.
  Future<void> reloadSection(String id) async {
    _loadedSectionIds.remove(id);
    _sectionLoadFutures.remove(id);
    _sectionLoadErrors.remove(id);
    _sectionLoadStates[id] = SectionLoadState.initial;
    notifyListeners();
    await ensureSectionLoaded(id);
  }

  /// Drop all shell/body state and re-run [load] from the database.
  ///
  /// Always invalidates [CourseLoader] process caches so callers that mutate
  /// the DB (Anki import, uninstall, AI course write) see fresh section shells
  /// and vocabulary without having to remember a separate invalidate step.
  ///
  /// Used by the course-tree empty-shell error UI so "Retry" can recover
  /// after a transient DB failure. Does not reseed assets — that still
  /// requires a content-version bump or clearing app data.
  Future<void> reloadCourse() async {
    logger.w('CourseProvider.reloadCourse: resetting and reloading shells');
    // Must drop CourseLoader's memoized shells/vocab — otherwise reload reads
    // the pre-mutation snapshot and newly imported Anki decks never appear
    // in [allSections] / [catalogEntries].
    CourseLoader.invalidateCaches();
    _isLoaded = false;
    _sections = const [];
    _allSections = const [];
    _currentSectionId = null;
    _selectedUnitId = null;
    _selectedLessonId = null;
    _loadedSectionIds.clear();
    _lessonCache.clear();
    _sectionLoadFutures.clear();
    _sectionLoadStates.clear();
    _sectionLoadErrors.clear();
    notifyListeners();
    await load();
  }

  // --- Course scope switching ---

  /// Switch the course scope (typed) and reload the tree. Persists the
  /// choice so it survives restarts; [load] falls back to the builtin
  /// course when the scoped source no longer exists.
  ///
  /// v2（B6/K14）：提交即持久化两层——prefs（兼容 v1 读面）+ 配置区决策
  /// 键 `turna.course.scope`（随 collection.anki2 备份走）；不等进程正常
  /// 退出。配置区写经引擎，best-effort 不阻塞切换。
  Future<void> setScope(CourseScope next) async {
    if (next == _scope && _isLoaded) return;
    _scope = next;
    await _persistScope();
    await _persistScopeDecisionToConfig(next);
    CourseLoader.invalidateCaches();
    await reloadCourse();
  }

  Future<void> _persistScopeDecisionToConfig(CourseScope next) async {
    try {
      final engine = OfficialAnkiCompositionRoot.engine;
      if (engine == null) return;
      await OfficialAnkiV2DecisionStore(engine).writeCourseScope(
        next.wireKey,
      );
    } catch (error) {
      logger.w('CourseProvider: scope decision write failed: $error');
    }
  }

  /// Compatibility entry point: accepts a v1 codec wire key or a legacy
  /// `'anki:<id>'` / `''` string. Legacy values resolve against the live
  /// catalog (one source → that source; ambiguous → builtin, never a
  /// guess). Prefer [setScope].
  Future<void> setCourseScope(String raw) async {
    final decoded = CourseScopeCodec.decode(raw.trim());
    if (decoded != null) {
      await setScope(decoded);
      return;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await setScope(const BuiltinCourseScope('turkish'));
      return;
    }
    if (trimmed.startsWith('anki:')) {
      final id = trimmed.substring(5);
      // Resolve against the catalog: legacy import first, then official
      // source; an id matching both is treated as ambiguous → builtin.
      final legacyHit = _catalogEntries.any(
        (e) => e.legacyImportId == id,
      );
      final officialHit = _catalogEntries.any(
        (e) => e.officialSourceId == id,
      );
      if (legacyHit && !officialHit) {
        await setScope(LegacyAnkiCourseScope(id));
        return;
      }
      if (officialHit && !legacyHit) {
        await setScope(OfficialAnkiCourseScope(
          profileId: CourseCatalog.officialProfileId,
          sourceId: id,
        ));
        return;
      }
    }
    logger.w('CourseProvider.setCourseScope: unresolvable scope "$raw", '
        'falling back to builtin');
    await setScope(const BuiltinCourseScope('turkish'));
  }

  /// Keep only the sections belonging to the active scope: built-in course
  /// (everything except ALL Anki sections — legacy and official alike,
  /// plan 34 R1-2) or exactly one source's sections.
  List<Section> _applyScopeFilter(List<Section> shells) {
    return [
      for (final s in shells)
        if (_sectionInScope(s)) s
    ];
  }

  bool _catalogStillHasScope(CourseScope scope) {
    return switch (scope) {
      BuiltinCourseScope() => true,
      LegacyAnkiCourseScope(importId: final id) =>
        _catalogEntries.any((e) => e.legacyImportId == id),
      OfficialAnkiCourseScope(sourceId: final id) =>
        _catalogEntries.any((e) => e.officialSourceId == id),
    };
  }

  bool _sectionInScope(Section s) {
    return switch (_scope) {
      BuiltinCourseScope() => _isAnyAnkiSection(s) == false,
      LegacyAnkiCourseScope(importId: final id) =>
        CourseCatalog.legacyImportIdFromSectionId(s.id) == id,
      OfficialAnkiCourseScope(sourceId: final id) =>
        CourseCatalog.officialSourceIdFromSectionId(s.id) == id,
    };
  }

  /// True for every Legacy or Official Anki section regardless of level
  /// tagging — the builtin language course must never show either
  /// (plan 34 R1-2).
  static bool _isAnyAnkiSection(Section s) {
    return s.level == 'Anki' ||
        s.level == 'OfficialAnki' ||
        OfficialAnkiCourseEntry.isOfficialSectionId(s.id);
  }

  Future<void> _reloadCatalog({List<Section>? shells}) async {
    final entries = await CourseCatalog.load(shells: shells ?? _allSections);
    final stored = _appPrefs?.preferences.getStringList(
            PrefsConstants.courseOrder,
            defaultValue: const []).getValue() ??
        const <String>[];

    final byWire = {for (final e in entries) e.wireKey: e};
    // Map legacy stored keys onto wires for orders written by older builds.
    final wireForStored = <String, String>{};
    byWire.forEach((wire, entry) {
      switch (entry.scope) {
        case BuiltinCourseScope():
          wireForStored[''] = wire;
        case LegacyAnkiCourseScope(importId: final id):
          wireForStored['anki:$id'] = wire;
        case OfficialAnkiCourseScope(sourceId: final id):
          wireForStored['anki:$id'] = wire;
      }
    });

    final ordered = <CourseCatalogEntry>[];
    final seen = <String>{};
    for (final storedKey in stored) {
      final wire = CourseScopeCodec.isEncodedKey(storedKey)
          ? storedKey
          : wireForStored[storedKey];
      if (wire == null) continue;
      final entry = byWire[wire];
      if (entry == null || !seen.add(wire)) continue;
      ordered.add(entry);
    }
    // The built-in course always exists, even if absent from stored order.
    final builtinWire = const BuiltinCourseScope('turkish').wireKey;
    if (byWire.containsKey(builtinWire) && seen.add(builtinWire)) {
      ordered.insert(0, byWire[builtinWire]!);
    }
    // Sources not yet in the stored order go last.
    for (final entry in entries) {
      if (seen.add(entry.wireKey)) ordered.add(entry);
    }
    _catalogEntries = List.unmodifiable(ordered);
  }

  Future<void> _restoreScopeFromPrefs() async {
    final prefs = _appPrefs;
    if (prefs == null) return;
    final raw = prefs.courseScope.getValue();
    final decoded = CourseScopeCodec.decode(raw);
    if (decoded != null) {
      _scope = decoded;
      return;
    }
    // Legacy value: resolve against the catalog (single source wins;
    // ambiguity falls back to builtin — never a guess).
    final entries = await CourseCatalog.load();
    if (raw.startsWith('anki:')) {
      final id = raw.substring(5);
      final legacyHit = <String>[
        for (final entry in entries)
          if (entry.legacyImportId == id) id,
      ];
      final officialHit = <String>[
        for (final entry in entries)
          if (entry.officialSourceId == id) id,
      ];
      if (legacyHit.length == 1 && officialHit.isEmpty) {
        _scope = LegacyAnkiCourseScope(id);
        return;
      }
      if (officialHit.length == 1 && legacyHit.isEmpty) {
        _scope = OfficialAnkiCourseScope(
          profileId: CourseCatalog.officialProfileId,
          sourceId: id,
        );
        return;
      }
      // `anki:src` truncation with exactly one official source re-binds to
      // it (the preference migrator also repairs this; keep behavior
      // aligned when it has not run yet).
      if (id == 'src' || id.isEmpty) {
        final officialSources = [
          for (final entry in entries)
            if (entry.officialSourceId != null) entry.officialSourceId!,
        ];
        if (officialSources.length == 1) {
          _scope = OfficialAnkiCourseScope(
            profileId: CourseCatalog.officialProfileId,
            sourceId: officialSources.single,
          );
          return;
        }
      }
    } else if (raw.isEmpty) {
      _scope = const BuiltinCourseScope('turkish');
      return;
    }
    _scope = const BuiltinCourseScope('turkish');
  }

  Future<void> _persistScope() async {
    final prefs = _appPrefs;
    if (prefs == null) return;
    await prefs.setString(PrefsConstants.courseScope, _scope.wireKey);
  }

  // --- Selection (all id-based, so middle-of-tree inserts are safe) ---

  void switchToSection(String id) {
    if (findSectionById(id) == null) return;
    _currentSectionId = id;
    _selectedUnitId = null;
    _selectedLessonId = null;
    notifyListeners();
    // Load the section's body on demand (fire-and-forget); keep this method
    // synchronous so PopupMenuButton.onSelected callers need no changes.
    ensureSectionLoaded(id);
  }

  /// Select a unit by id. If the unit lives in a not-yet-loaded section,
  /// loads **only that section's** L1 tree (via DB reverse lookup), not every
  /// unloaded section.
  Future<void> selectUnit(String id) async {
    if (findUnitById(id) != null) {
      _selectUnitInternal(id);
      return;
    }
    try {
      final sectionId = await CourseLoader.sectionIdForUnit(id);
      if (sectionId == null) return;
      await ensureSectionLoaded(sectionId);
    } catch (e, st) {
      logger.e('selectUnit($id) failed', error: e, stackTrace: st);
      return;
    }
    if (findUnitById(id) != null) {
      _selectUnitInternal(id);
    }
  }

  void _selectUnitInternal(String id) {
    _selectedUnitId = id;
    _selectedLessonId = null;
    notifyListeners();
  }

  /// Select a lesson by id; loads only the owning section's L1 tree when needed.
  Future<void> selectLesson(String id) async {
    if (findLessonById(id) != null) {
      _selectedLessonId = id;
      notifyListeners();
      return;
    }
    try {
      final sectionId = await CourseLoader.sectionIdForLesson(id);
      if (sectionId == null) return;
      await ensureSectionLoaded(sectionId);
    } catch (e, st) {
      logger.e('selectLesson($id) failed', error: e, stackTrace: st);
      return;
    }
    if (findLessonById(id) != null) {
      _selectedLessonId = id;
      notifyListeners();
    }
  }
}
