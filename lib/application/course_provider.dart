// Flutter imports:
import 'package:flutter/cupertino.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/core/logger.dart';
import 'package:words625/courses/course_loader.dart';
import 'package:words625/courses/languages/kannada.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/unit.dart';
import 'package:words625/domain/course/lesson.dart';

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
  final Map<String, Future<void>> _sectionLoadFutures = {};

  /// True while the current section's body is being fetched on demand.
  bool get _currentSectionLoading =>
      _currentSectionId != null &&
      _sectionLoadFutures.containsKey(_currentSectionId);

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
  bool isSectionLoading(String id) => _sectionLoadFutures.containsKey(id);

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

  /// Load the Swahili course shells from the index and pre-load the first
  /// section's body so the course tree has something to show immediately.
  Future<void> load() async {
    logger.w("Loading Swahili sections");
    _sections = await loadSwahiliSectionShells();
    _currentSectionId = _sections.isNotEmpty ? _sections.first.id : null;
    _selectedUnitId = null;
    _selectedLessonId = null;
    _isLoaded = true;
    notifyListeners();
    if (_currentSectionId != null) {
      await ensureSectionLoaded(_currentSectionId!);
    }
  }

  /// Ensure the section's full body (units/lessons) is loaded and replace
  /// its shell with the populated [Section]. Cached per id via
  /// [SwahiliCourse.loadSection]; concurrent calls coalesce. Sets
  /// [isCurrentSectionLoading] while fetching (the caller is responsible for
  /// the section being the current one when relying on that flag).
  Future<void> ensureSectionLoaded(String id) async {
    if (_loadedSectionIds.contains(id)) return;
    if (findSectionById(id) == null) return;
    final inFlight = _sectionLoadFutures[id];
    if (inFlight != null) return inFlight;

    final future = () async {
      notifyListeners();
      try {
        final full = await SwahiliCourse.loadSection(id);
        _replaceSection(full);
        _loadedSectionIds.add(id);
      } finally {
        _sectionLoadFutures.remove(id);
        notifyListeners();
      }
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

  void selectUnit(String id) {
    if (findUnitById(id) == null) return;
    _selectedUnitId = id;
    _selectedLessonId = null;
    notifyListeners();
  }

  void selectLesson(String id) {
    if (findLessonById(id) == null) return;
    _selectedLessonId = id;
    notifyListeners();
  }
}