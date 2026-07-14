// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/courses/languages/course_lookup.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/domain/course/lesson.dart';

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
  // --- Section hierarchy ---
  List<Section> _sections = const [];
  String? _currentSectionId;
  String? _selectedUnitId;
  String? _selectedLessonId;
  bool _isLoaded = false;

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
  List<Section> get sections => List.unmodifiable(_sections);

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
    _sections = await loadSectionShells();
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
  Future<void> ensureSectionLoaded(String id) async {
    if (_loadedSectionIds.contains(id)) {
      _sectionLoadStates[id] = SectionLoadState.loaded;
      return;
    }
    if (findSectionById(id) == null) {
      logger.w('CourseProvider.ensureSectionLoaded($id): section not in index');
      _sectionLoadStates[id] = SectionLoadState.error;
      _sectionLoadErrors[id] = StateError('Section $id not found in index');
      notifyListeners();
      return;
    }
    final inFlight = _sectionLoadFutures[id];
    if (inFlight != null) return inFlight;

    final future = () async {
      logger.i('CourseProvider.ensureSectionLoaded($id): starting fetch');
      _sectionLoadStates[id] = SectionLoadState.loading;
      _sectionLoadErrors.remove(id);
      notifyListeners();
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
        _sectionLoadFutures.remove(id);
      }
      notifyListeners();
    }();
    _sectionLoadFutures[id] = future;
    return future;
  }

  void _replaceSection(Section full) {
    for (var i = 0; i < _sections.length; i++) {
      if (_sections[i].id == full.id) {
        final updated = List<Section>.of(_sections);
        updated[i] = full;
        _sections = List.unmodifiable(updated);
        for (final unit in full.units) {
          for (final lesson in unit.lessons) {
            _lessonCache[lesson.id] = lesson;
          }
        }
        return;
      }
    }
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
  /// Used by the course-tree empty-shell error UI so "Retry" can recover
  /// after a transient DB failure. Does not reseed assets — that still
  /// requires a content-version bump or clearing app data.
  Future<void> reloadCourse() async {
    logger.w('CourseProvider.reloadCourse: resetting and reloading shells');
    _isLoaded = false;
    _sections = const [];
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
