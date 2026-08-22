// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';

/// One language [Interaction] eligible for Playground, with the lesson it
/// came from (provenance for mistake attribution and stats, 计划 §7.4).
class PlaygroundInteractionCandidate {
  final Interaction interaction;
  final String lessonId;

  const PlaygroundInteractionCandidate({
    required this.interaction,
    required this.lessonId,
  });
}

/// Language-only content collected for one content scope.
class PlaygroundContentBundle {
  /// Every language interaction found in the resolved scope (ShowWord
  /// display cards included; mode filtering happens in the assembler).
  final List<PlaygroundInteractionCandidate> candidates;

  /// Deduplicated `ShowWord.wordId`s of the scope — the word-match word-pair
  /// source (计划 §7.3). Never falls back to a global fixed word list.
  final Set<String> wordIds;

  /// Sections that failed to load in the resolved scope. Failed sections
  /// are skipped; the ids stay here for diagnostics.
  final Set<String> failedSectionIds;

  /// The scope actually served. `recent` falls back to `currentUnit` in P1
  /// (no reliable lesson-completion records yet), surfaced so the UI can
  /// explain the fallback with a light hint (计划 §4.2).
  final PlaygroundContentScope resolvedScope;

  const PlaygroundContentBundle({
    required this.candidates,
    required this.wordIds,
    required this.failedSectionIds,
    required this.resolvedScope,
  });

  /// True when a section-backed scope wanted sections but every one of them
  /// failed to load — the caller should surface `sectionLoadFailed` instead
  /// of an empty "success".
  bool get allSectionsFailed =>
      failedSectionIds.isNotEmpty &&
      candidates.isEmpty &&
      wordIds.isEmpty;
}

/// Collects Playground content strictly from the CURRENT language course
/// (计划 §6.2 第三层隔离):
/// * only reads [CourseProvider.sections] (the courseScope-filtered view),
///   never `allSections`;
/// * Section-level filter — Anki / OfficialAnki level sections are rejected;
/// * Interaction-level filter — [AnkiCard] / [AnkiHtmlCard] never enter any
///   candidate pool, including snapshots restored from mistake entries;
/// * never pads from a global fixed word list or another course's content.
class PlaygroundContentSource {
  final CourseProvider _courseProvider;

  PlaygroundContentSource(this._courseProvider);

  /// Section may contribute Playground content only if it is a language
  /// section (Anki / OfficialAnki levels are Anki decks by construction).
  static bool isLanguageSection(Section section) =>
      section.level != 'Anki' && section.level != 'OfficialAnki';

  /// Interaction may enter a Playground pool only if it is a language
  /// interaction — Anki card types are rejected regardless of caller.
  static bool isLanguageInteraction(Interaction interaction) =>
      interaction is! AnkiCard && interaction is! AnkiHtmlCard;

  /// Gather every language interaction (with lesson provenance) and every
  /// `ShowWord.wordId` from the given (already loaded) sections.
  ///
  /// [unitId] restricts the scan to one unit (the current-unit scope); when
  /// null every unit of each section contributes.
  static PlaygroundContentBundle collectFromSections(
    Iterable<Section> sections, {
    PlaygroundContentScope resolvedScope = PlaygroundContentScope.currentUnit,
    String? unitId,
  }) {
    final candidates = <PlaygroundInteractionCandidate>[];
    final wordIds = <String>{};
    for (final section in sections) {
      if (!isLanguageSection(section)) continue;
      for (final unit in section.units) {
        if (unitId != null && unit.id != unitId) continue;
        for (final lesson in unit.lessons) {
          for (final stage in lesson.flattenedStages) {
            for (final item in stage.items) {
              if (!isLanguageInteraction(item)) continue;
              candidates.add(
                PlaygroundInteractionCandidate(
                  interaction: item,
                  lessonId: lesson.id,
                ),
              );
              if (item is ShowWord && item.wordId.isNotEmpty) {
                wordIds.add(item.wordId);
              }
            }
          }
        }
      }
    }
    return PlaygroundContentBundle(
      candidates: candidates,
      wordIds: wordIds,
      failedSectionIds: const {},
      resolvedScope: resolvedScope,
    );
  }

  /// Load the content bundle for [scope], loading section bodies on demand.
  ///
  /// [weakEntries] supplies mistake snapshots for
  /// [PlaygroundContentScope.weak]; Anki snapshots inside it are re-filtered
  /// here (计划 §6.2: 错题快照恢复时再次执行同一类型过滤).
  Future<PlaygroundContentBundle> load(
    PlaygroundContentScope scope, {
    List<MistakeEntry> weakEntries = const [],
  }) async {
    switch (scope) {
      case PlaygroundContentScope.weak:
        return _fromWeakEntries(weakEntries);
      case PlaygroundContentScope.currentUnit:
        return _fromCurrentUnit(
          resolvedScope: PlaygroundContentScope.currentUnit,
        );
      case PlaygroundContentScope.recent:
        // P1: no reliable recent-lesson records yet — fall back to the
        // current unit and surface the fallback via `resolvedScope`.
        return _fromCurrentUnit(
          resolvedScope: PlaygroundContentScope.currentUnit,
        );
      case PlaygroundContentScope.wholeCourse:
        return _fromWholeCourse();
    }
  }

  Future<PlaygroundContentBundle> _fromCurrentUnit({
    required PlaygroundContentScope resolvedScope,
  }) async {
    final sectionId = _courseProvider.currentSectionId;
    final section = _courseProvider.currentSection;
    if (sectionId == null || section == null) {
      return PlaygroundContentBundle(
        candidates: const [],
        wordIds: const {},
        failedSectionIds: const {},
        resolvedScope: resolvedScope,
      );
    }
    await _courseProvider.ensureSectionLoaded(sectionId);
    // A failed load keeps the section shell in place (`currentSection` stays
    // non-null with empty units), so detect the failure via the load state —
    // matching `_fromWholeCourse` — instead of relying on a null section.
    final loaded = _courseProvider.currentSection;
    if (loaded == null ||
        _courseProvider.sectionLoadState(sectionId) == SectionLoadState.error) {
      return PlaygroundContentBundle(
        candidates: const [],
        wordIds: const {},
        failedSectionIds: {sectionId},
        resolvedScope: resolvedScope,
      );
    }
    final unit = _courseProvider.currentUnit;
    // Only the current unit contributes; with no unit selected the section's
    // loaded units stand in (the user has not narrowed their position yet).
    return collectFromSections(
      [loaded],
      resolvedScope: resolvedScope,
      unitId: unit?.id,
    );
  }

  Future<PlaygroundContentBundle> _fromWholeCourse() async {
    // Positive language whitelist from the scope-filtered view — an Anki
    // course scope yields no language sections at all here.
    final languageSections = _courseProvider.sections
        .where(isLanguageSection)
        .toList(growable: false);
    final failed = <String>{};
    // Sequential on-demand loads: trivially bounded concurrency, and failed
    // sections are skipped (with diagnostics) rather than aborting the run.
    for (final section in languageSections) {
      if (_courseProvider.sectionLoadState(section.id) ==
          SectionLoadState.loaded) {
        continue;
      }
      await _courseProvider.ensureSectionLoaded(section.id);
      if (_courseProvider.sectionLoadState(section.id) ==
          SectionLoadState.error) {
        failed.add(section.id);
      }
    }
    // Re-read from the provider so loaded bodies replace shells.
    final loadedSections = _courseProvider.sections
        .where(isLanguageSection)
        .toList(growable: false);
    final bundle = collectFromSections(
      loadedSections,
      resolvedScope: PlaygroundContentScope.wholeCourse,
    );
    if (failed.isEmpty) return bundle;
    return PlaygroundContentBundle(
      candidates: bundle.candidates,
      wordIds: bundle.wordIds,
      failedSectionIds: failed,
      resolvedScope: bundle.resolvedScope,
    );
  }

  PlaygroundContentBundle _fromWeakEntries(List<MistakeEntry> entries) {
    final candidates = <PlaygroundInteractionCandidate>[];
    final wordIds = <String>{};
    for (final entry in entries) {
      final snapshot = entry.interactionSnapshot;
      // Snapshots may predate the isolation rules — re-run the same Anki
      // interaction filter here instead of trusting the stored snapshot.
      if (snapshot == null || !isLanguageInteraction(snapshot)) continue;
      candidates.add(
        PlaygroundInteractionCandidate(
          interaction: snapshot,
          lessonId: entry.lessonId,
        ),
      );
      final wordId = entry.wordId;
      if (wordId != null && wordId.isNotEmpty) {
        wordIds.add(wordId);
      }
    }
    return PlaygroundContentBundle(
      candidates: candidates,
      wordIds: wordIds,
      failedSectionIds: const {},
      resolvedScope: PlaygroundContentScope.weak,
    );
  }
}
