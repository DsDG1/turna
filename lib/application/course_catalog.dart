import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/course_lookup.dart';
import 'package:turna/data/course_database.dart' hide Section;
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/section.dart';

/// One selectable course in the course catalog (plan 34 D2).
///
/// Entries are built from the source catalog — never by reverse-parsing
/// section ids — so a full Official `sourceId` (e.g. `src-4f8b…`) survives
/// switching, ordering and uninstall.
class CourseCatalogEntry {
  const CourseCatalogEntry({
    required this.scope,
    required this.displayName,
    required this.isBuiltin,
    this.legacyImportId,
    this.officialSourceId,
    this.sectionCount = 0,
    this.cardCount = 0,
  });

  final CourseScope scope;
  final String displayName;
  final bool isBuiltin;

  /// Non-null for Legacy Anki imports.
  final String? legacyImportId;

  /// Non-null for Official Anki sources (the complete sourceId).
  final String? officialSourceId;

  final int sectionCount;

  /// Cards owned by this source (projection index for Official, cards_meta
  /// for Legacy). Shown in the uninstall confirmation (plan 34 R1-7).
  final int cardCount;

  String get wireKey => scope.wireKey;

  /// Short stable identifier for the uninstall confirmation dialog.
  String get shortId {
    if (officialSourceId != null) {
      final id = officialSourceId!;
      return id.length <= 12 ? id : id.substring(0, 12);
    }
    return legacyImportId ?? '';
  }
}

/// Loads the authoritative course catalog.
///
/// - Built-in language courses: one entry per language with content in the
///   DB (or, when the DB has no builtin content at all, per manifest
///   language), minus languages the user uninstalled.
/// - Legacy Anki decks come from the section shells (level `Anki`).
/// - Official Anki sources come from `anki_course_sources` (the v21
///   authority) plus the projection manifest for sources imported before
///   the authority table existed — both validated so staging generations
///   are never visible.
class CourseCatalog {
  CourseCatalog._();

  /// Same profile id the composition root pins for the official backend.
  static const String officialProfileId = 'profile-default-01';

  /// Full sourceId parsed from a section id using the LAST `-s<digits>`
  /// boundary — never `split('-').first`, which truncates `src-…` ids
  /// to the bogus `src` (plan 34 R1-1).
  static String? officialSourceIdFromSectionId(String sectionId) {
    if (!sectionId.startsWith('official-anki-')) return null;
    var body = sectionId.substring('official-anki-'.length);
    // Section ids end with `-s<topDeckId>`; cut at the last boundary.
    final marker = body.lastIndexOf('-s');
    if (marker <= 0) return null;
    final sourceId = body.substring(0, marker);
    final deck = body.substring(marker + 2);
    if (sourceId.isEmpty || int.tryParse(deck) == null) return null;
    return sourceId;
  }

  /// Legacy import id from a `anki-<importId>-s<deckId>` section id.
  static String? legacyImportIdFromSectionId(String sectionId) {
    if (!sectionId.startsWith('anki-')) return null;
    final body = sectionId.substring('anki-'.length);
    final marker = body.lastIndexOf('-s');
    if (marker <= 0) return null;
    final importId = body.substring(0, marker);
    final deck = body.substring(marker + 2);
    if (importId.isEmpty || int.tryParse(deck) == null) return null;
    return importId;
  }

  /// Attribute a section to a builtin language: its recorded `language_code`,
  /// or `'tr'` ONLY when the whole [languageBySection] map is empty (a failed
  /// `sectionLanguageCodes` query must degrade to the historical behavior
  /// rather than blank the course). When the map loaded fine, a missing id
  /// means a non-DB shell (e.g. the v2 view) — it belongs to no builtin
  /// language, so return `null` instead of dumping it under Turkish.
  static String? builtinLanguageOf(
    String sectionId,
    Map<String, String> languageBySection,
  ) {
    final code = languageBySection[sectionId];
    if (code != null) return LanguageCodes.canonicalize(code);
    return languageBySection.isEmpty ? LanguageCodes.turkish : null;
  }

  /// Loads the catalog. [shells] are the (unfiltered) section shells; pass
  /// null to load them here. [uninstalledLanguageCodes] carries the
  /// `uninstalled:<code>` markers so marked languages stay out of the
  /// catalog; [builtinCardCounts] fills the builtin entries' [CourseCatalogEntry.cardCount].
  static Future<List<CourseCatalogEntry>> load({
    List<Section>? shells,
    CourseDatabase? courseDb,
    Set<String> uninstalledLanguageCodes = const {},
    Map<String, int> builtinCardCounts = const {},
  }) async {
    final sections = shells ?? await loadSectionShells();
    CourseDatabase? db = courseDb;
    try {
      db ??= CourseLoader.databaseOrNull();
    } catch (_) {
      db = null;
    }

    final languageBySection = <String, String>{};
    if (db != null) {
      try {
        languageBySection.addAll(await CourseLoader.sectionLanguageCodes());
      } catch (_) {}
    }
    final codesFromDb = <String>{};
    for (final section in sections) {
      if (section.level == 'Anki' ||
          OfficialAnkiCourseEntry.isOfficialSectionId(section.id)) {
        continue;
      }
      final sectionCode = builtinLanguageOf(section.id, languageBySection);
      if (sectionCode != null) codesFromDb.add(sectionCode);
    }
    final builtinCodes = <String>[
      for (final language in LanguageRegistry.instance.languages)
        if (codesFromDb.contains(language.code) &&
            !uninstalledLanguageCodes.contains(language.code))
          language.code,
      for (final code in codesFromDb)
        if (!LanguageRegistry.instance.languages.any((l) => l.code == code) &&
            !uninstalledLanguageCodes.contains(code))
          code,
    ];
    if (builtinCodes.isEmpty) {
      for (final language in LanguageRegistry.instance.languages) {
        if (uninstalledLanguageCodes.contains(language.code)) continue;
        builtinCodes.add(language.code);
      }
    }
    final entries = <CourseCatalogEntry>[
      for (final code in builtinCodes)
        CourseCatalogEntry(
          scope: BuiltinCourseScope(code),
          displayName: LanguageRegistry.instance.displayName(code),
          isBuiltin: true,
          sectionCount: sections.where((s) {
            if (s.level == 'Anki' ||
                OfficialAnkiCourseEntry.isOfficialSectionId(s.id)) {
              return false;
            }
            return builtinLanguageOf(s.id, languageBySection) == code;
          }).length,
          cardCount: builtinCardCounts[code] ?? 0,
        ),
    ];

    // Legacy decks — one entry per import id found in the shells.
    final legacyCardCounts = <String, int>{};
    if (db != null) {
      try {
        final rows = await db
            .customSelect(
              'SELECT import_id, COUNT(*) AS n FROM anki_cards_meta '
              'GROUP BY import_id',
            )
            .get();
        for (final row in rows) {
          legacyCardCounts[row.read<String>('import_id')] = row.read<int>('n');
        }
      } catch (_) {
        // Table may not exist in tests; counts stay zero.
      }
    }
    final legacyIds = <String>{};
    for (final section in sections) {
      if (section.level != 'Anki') continue;
      if (OfficialAnkiCourseEntry.isOfficialSectionId(section.id)) continue;
      final importId = legacyImportIdFromSectionId(section.id);
      if (importId == null) continue;
      if (!legacyIds.add(importId)) continue;
      entries.add(CourseCatalogEntry(
        scope: LegacyAnkiCourseScope(importId),
        displayName: section.name,
        isBuiltin: false,
        legacyImportId: importId,
        sectionCount: sections
            .where((s) =>
                legacyImportIdFromSectionId(s.id) == importId &&
                s.level == 'Anki')
            .length,
        cardCount: legacyCardCounts[importId] ?? 0,
      ));
    }

    // Official sources (v2 monolith read)
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog != null && db != null) {
        final activeSources = {
          for (final source in OfficialAnkiSourceDao(catalog).listSources(
            officialProfileId,
          ))
            if (source.state == 'active') source.sourceId: source,
        };
        final summaries = await OfficialAnkiV2ViewStore(db).sectionSummaries();
        final sectionCounts = <String, int>{};
        final cardCounts = <String, int>{};
        for (final summary in summaries) {
          if (!activeSources.containsKey(summary.sourceId)) continue;
          sectionCounts[summary.sourceId] =
              (sectionCounts[summary.sourceId] ?? 0) + 1;
          cardCounts[summary.sourceId] =
              (cardCounts[summary.sourceId] ?? 0) + summary.cardCount;
        }
        for (final sourceId in sectionCounts.keys) {
          entries.add(CourseCatalogEntry(
            scope: OfficialAnkiCourseScope(
              profileId: officialProfileId,
              sourceId: sourceId,
            ),
            displayName: activeSources[sourceId]?.displayName ?? sourceId,
            isBuiltin: false,
            officialSourceId: sourceId,
            sectionCount: sectionCounts[sourceId] ?? 0,
            cardCount: cardCounts[sourceId] ?? 0,
          ));
        }
      }
    } catch (e) {
      logger.w('CourseCatalog: v2 view entries failed: $e');
    }

    return entries;
  }

  /// Whether [sectionId] belongs to [scope]. Exact ownership only — never a
  /// prefix that could span two sources (plan 34 R1-3).
  static bool sectionBelongsToScope(
    CourseScope scope,
    String sectionId, {
    String? languageCode,
  }) {
    return switch (scope) {
      BuiltinCourseScope(languageCode: final code) =>
        languageCode != null &&
            LanguageCodes.canonicalize(languageCode) ==
                LanguageCodes.canonicalize(code),
      LegacyAnkiCourseScope(importId: final id) =>
        legacyImportIdFromSectionId(sectionId) == id,
      OfficialAnkiCourseScope(sourceId: final id) =>
        officialSourceIdFromSectionId(sectionId) == id,
    };
  }

  static CourseScope fallbackBuiltin(List<CourseCatalogEntry> catalog) {
    for (final entry in catalog) {
      if (entry.isBuiltin) return entry.scope;
    }
    return BuiltinCourseScope(LanguageRegistry.instance.defaultCode);
  }
}
