// Project imports:
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Read API for course content (DB-backed cache over JSON assets).
///
/// Concrete: [CourseRepository]. Phase 21 defines the interface only —
/// DI still registers the concrete class (see ADR 0007).
///
/// Loading is split for scale (~10k lessons):
/// - [sectionShells] — L0 index (no units)
/// - [section] — L1 tree metadata (units/lessons, **empty** [Lesson.content])
/// - [lessonById] — L2 full body (content JSON)
abstract class ICourseRepository {
  Future<List<Section>> sectionShells({String? languageCode});

  /// L1 section tree: units + lesson metadata only. [Lesson.content] is empty;
  /// load bodies with [lessonById]. [languageCode] scopes the lookup to one
  /// language (ids are unique per language only).
  Future<Section> section(String id, {String? languageCode});

  /// L2: single lesson with full [LessonContent]. [languageCode] scopes the
  /// lookup to one language.
  Future<Lesson> lessonById(String id, {String? languageCode});

  /// Load full lesson bodies whose `content_json` contains any of [needles]
  /// (substring match). Used by Anki review to resolve a small batch of
  /// word ids without loading an entire multi-thousand-card deck.
  ///
  /// Returns at most one [Lesson] per matching `lesson_id`. Empty [needles]
  /// yields an empty list.
  Future<List<Lesson>> lessonsContainingAny(Iterable<String> needles);

  /// Owning section id for [unitId], or `null` if the unit is unknown.
  Future<String?> sectionIdForUnit(String unitId);

  /// Owning section id for [lessonId], or `null` if the lesson is unknown.
  Future<String?> sectionIdForLesson(String lessonId);

  Future<List<WordEntry>> vocabulary({String? languageCode});
  Future<List<GrammarPoint>> grammarPoints({String? languageCode});
  Future<GrammarPoint?> grammarPointById(String id, {String? languageCode});
  Future<List<Expression>> expressions({String? languageCode});
  Future<Expression?> expressionById(String id, {String? languageCode});

  /// Bulk-write a full section tree (units + lessons + lesson contents) in a
  /// single transaction, upserting by id. Used by importers (Anki decks);
  /// language courses still flow through the seeder. [languageCode] tags the
  /// rows' `language_code`; `null` derives it (Anki-level sections → 'anki',
  /// otherwise 'tr').
  Future<void> bulkInsertCourseTree(Section section, {String? languageCode});

  /// Bulk-write vocabulary entries (upsert by id). Used by importers.
  /// [languageCode] tags the rows; `null` means 'anki' (the importer path).
  Future<void> bulkInsertVocabulary(List<WordEntry> words,
      {String? languageCode});

  /// Delete vocabulary entries whose tags contain [tag] (exact list-element
  /// match on the JSON-encoded tags column). Returns the number of rows
  /// removed. Used to uninstall imported decks (`anki:<importId>` tag).
  Future<int> deleteByTag(String tag);

  /// Delete a section and its whole tree (units, lessons, lesson contents).
  Future<void> deleteSection(String sectionId);

  /// Delete the official-Anki course projection tree for [sourceId]
  /// (sections/units/lessons with `official-anki-<sourceId>-` ids plus the
  /// projection index/manifest). No-op when no projection exists. P5F-31.
  Future<void> deleteOfficialProjection(String sourceId);

  /// The stored course content version (written by the seeder after
  /// seeding), or `null` if the DB has not been seeded yet. Used by the
  /// content-update prompt (ADR 0002) to detect version bumps.
  Future<String?> contentVersion({String? languageCode});

  /// Schema version of the backing database (diagnostics surface).
  int get schemaVersion;

  /// Remove the builtin course tree + all user state for [languageCode]
  /// (uninstall path) and mark the language uninstalled.
  Future<void> deleteBuiltinLanguage(String languageCode);

  /// Clear the uninstalled marker so [languageCode] is offered again.
  Future<void> clearLanguageUninstallMarker(String languageCode);

  /// Language codes currently marked uninstalled.
  Future<Set<String>> uninstalledLanguageCodes();

  /// Lesson ids belonging to [languageCode] (course tree + projections).
  Future<Set<String>> lessonIdsForLanguage(String languageCode);

  /// Media/resource ids belonging to [languageCode].
  Future<Set<String>> resourceIdsForLanguage(String languageCode);

  /// Whether [languageCode] has any course content installed.
  Future<bool> languageHasContent(String languageCode);

  /// Per-language builtin card counts for the catalog badges.
  Future<Map<String, int>> builtinCardCounts();
}
