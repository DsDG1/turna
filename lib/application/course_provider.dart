// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/course_lookup.dart';
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
/// Sections are loaded lazily: [load] populates [_sections] with lightweight
/// shells (units empty) from the course index and pre-loads the first
/// section's body. Switching to a section triggers [ensureSectionLoaded] to
/// fetch that section's full body on demand (cached per id). [findUnitById]
/// and [findLessonById] therefore only search sections whose bodies have been
/// loaded — in practice the user only navigates within the current section,
/// so this is behavior-preserving.
@lazySingleton
class CourseProvider extends ChangeNotifier {
  CourseProvider([this._appPrefs]);

  /// Prefs backing for [courseScope] persistence. Optional so tests can
  /// construct the provider without a prefs store (scope then stays '').
  final AppPrefs? _appPrefs;

  // --- Section hierarchy ---
  List<Section> _sections = const [];

  /// Unfiltered section shells/bodies (built-in course + imported Anki
  /// decks). [_sections] is the [courseScope]-filtered view of this list;
  /// consumers that must stay scope-independent (Anki review hub, daily
  /// challenge) read [allSections] instead.
  List<Section> _allSections = const [];
  String? _currentSectionId;
  String? _selectedUnitId;
  String? _selectedLessonId;
  bool _isLoaded = false;

  /// Active course scope: '' = built-in course (Anki decks hidden),
  /// 'anki:<importId>' = only that imported deck's sections.
  String _courseScope = '';

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

  /// True while the current section's body is being fetched on demand.
  bool get _currentSectionLoading =>
      _currentSectionId != null &&
      _sectionLoadStates[_currentSectionId] == SectionLoadState.loading;

  /// Immutable view of the section shells (and any loaded bodies). Order is
  /// the on-disk order. Shells have empty `units` until loaded.
  ///
  /// This is the [courseScope]-filtered view — see [allSections] for the
  /// unfiltered list.
  List<Section> get sections => List.unmodifiable(_sections);

  /// How many sections have their full body loaded. Cheap fingerprint input
  /// for content-revision cache keys (Playground, AI context): changes only
  /// when section bodies actually load or reset.
  int get loadedSectionCount => _loadedSectionIds.length;

  /// Unfiltered view of every section (built-in course + all imported Anki
  /// decks), regardless of [courseScope].
  List<Section> get allSections => List.unmodifiable(_allSections);

  /// The active course scope: '' = built-in course, 'anki:<importId>' = a
  /// single imported Anki deck.
  String get courseScope => _courseScope;

  /// One entry per imported Anki deck (importId + display name), computed
  /// from the unfiltered section list so the language menu can list all
  /// decks regardless of the current [courseScope].
  List<({String importId, String name})> get ankiDeckEntries {
    final seen = <String>{};
    final entries = <({String importId, String name})>[];
    for (final s in _allSections) {
      if (s.level != 'Anki' && s.level != 'OfficialAnki') continue;
      final importId = _importIdFromSectionId(s.id);
      if (importId.isEmpty || !seen.add(importId)) continue;
      entries.add((importId: importId, name: s.name));
    }
    return List.unmodifiable(entries);
  }

  /// Extract the import id from an Anki section id
  /// ('anki-<importId>-s<deckId>' or 'official-anki-<sourceId>-s<deckId>' → importId).
  static String _importIdFromSectionId(String sectionId) {
    if (sectionId.startsWith('anki-')) {
      return sectionId.substring(5).split('-').first;
    }
    if (sectionId.startsWith('official-anki-')) {
      return sectionId.substring('official-anki-'.length).split('-').first;
    }
    return '';
  }

  /// One entry per manageable course: the built-in course (scope `''`, marked
  /// `isBuiltin`, never deletable) plus one per imported Anki deck. Ordered
  /// by the persisted course order ([PrefsConstants.courseOrder]); decks
  /// missing from the stored order are appended at the end, and stored ids
  /// without a matching deck are dropped.
  ///
  /// The built-in entry's `name` is empty — its display name belongs to the
  /// language layer (`TargetLanguage`), so UI resolves it.
  List<({String scope, String name, bool isBuiltin})> get courseEntries {
    final decks = ankiDeckEntries;
    final nameByScope = <String, String>{
      for (final d in decks) 'anki:${d.importId}': d.name,
    };
    final stored = _appPrefs?.preferences
            .getStringList(PrefsConstants.courseOrder,
                defaultValue: const [''])
            .getValue() ??
        const [''];

    final ordered = <({String scope, String name, bool isBuiltin})>[];
    final seen = <String>{};
    for (final scope in stored) {
      if (!seen.add(scope)) continue;
      if (scope.isEmpty) {
        ordered.add((scope: '', name: '', isBuiltin: true));
      } else {
        final name = nameByScope[scope];
        if (name != null) {
          ordered.add((scope: scope, name: name, isBuiltin: false));
        }
      }
    }
    // The built-in course always exists, even if absent from the stored list.
    if (seen.add('')) {
      ordered.insert(0, (scope: '', name: '', isBuiltin: true));
    }
    // New decks not yet in the stored order go last.
    for (final d in decks) {
      final scope = 'anki:${d.importId}';
      if (seen.add(scope)) {
        ordered.add((scope: scope, name: d.name, isBuiltin: false));
      }
    }
    return List.unmodifiable(ordered);
  }

  /// Persist the course order shown in the course-management page and
  /// notify listeners so [courseEntries] re-resolves. [scopes] uses the same
  /// encoding as [courseScope]: `''` for the built-in course,
  /// `anki:<importId>` for a deck.
  Future<void> persistCourseOrder(List<String> scopes) async {
    final prefs = _appPrefs;
    if (prefs == null) return;
    await prefs.setStringList(PrefsConstants.courseOrder, scopes);
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
    _restoreScopeFromPrefs();
    Set<String>? officialActive;
    if (OfficialAnkiCourseEntry.flagsOf().allowsCourseEntry) {
      officialActive = await OfficialAnkiCourseEntry.resolveActiveSectionIds();
    }
    _allSections = OfficialAnkiCourseEntry.filterShells(
      await loadSectionShells(),
      activeIds: officialActive,
    );
    _sections = _applyScopeFilter(_allSections);
    if (_courseScope.isNotEmpty && _sections.isEmpty) {
      // The scoped deck was uninstalled — fall back to the built-in course.
      logger.w(
        'CourseProvider.load: scope "$_courseScope" matches no sections, '
        'falling back to built-in course',
      );
      _courseScope = '';
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
    // in [allSections] / [courseEntries].
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

  // --- Course scope ('' = built-in course, 'anki:<importId>' = one deck) ---

  /// Switch the course scope and reload the tree. Persists the choice so it
  /// survives restarts; [load] falls back to '' when the scoped deck no
  /// longer exists (e.g. after an uninstall that didn't go through here).
  Future<void> setCourseScope(String scope) async {
    if (scope == _courseScope && _isLoaded) return;
    _courseScope = scope;
    await _persistScope();
    CourseLoader.invalidateCaches();
    await reloadCourse();
  }

  /// Keep only the sections belonging to the active scope: built-in course
  /// (everything except Anki decks) or a single deck's `anki-<importId>-`
  /// id prefix.
  List<Section> _applyScopeFilter(List<Section> shells) {
    if (_courseScope.isEmpty) {
      return shells
          .where(
            (s) =>
                s.level != 'Anki' ||
                OfficialAnkiCourseEntry.isOfficialSectionId(s.id),
          )
          .toList(growable: false);
    }
    if (_courseScope.startsWith('anki:')) {
      final key = _courseScope.substring(5);
      final legacyPrefix = 'anki-$key-';
      final officialPrefix = 'official-anki-$key-';
      return shells
          .where((s) =>
              s.id.startsWith(legacyPrefix) ||
              s.id.startsWith(officialPrefix))
          .toList(growable: false);
    }
    return shells;
  }

  void _restoreScopeFromPrefs() {
    final prefs = _appPrefs;
    if (prefs == null) return;
    _courseScope = prefs.courseScope.getValue();
  }

  Future<void> _persistScope() async {
    final prefs = _appPrefs;
    if (prefs == null) return;
    await prefs.setString(PrefsConstants.courseScope, _courseScope);
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
