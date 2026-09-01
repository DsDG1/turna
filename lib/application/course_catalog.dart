import 'package:drift/drift.dart' show Variable;
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/course_lookup.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart' hide Section;
import 'package:turna/domain/course/course_scope.dart';
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
/// - The built-in language course is always first and always present.
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

  /// Loads the catalog. [shells] are the (unfiltered) section shells; pass
  /// null to load them here.
  static Future<List<CourseCatalogEntry>> load({
    List<Section>? shells,
    CourseDatabase? courseDb,
  }) async {
    final sections = shells ?? await loadSectionShells();
    CourseDatabase? db = courseDb;
    try {
      db ??= CourseLoader.databaseOrNull();
    } catch (_) {
      db = null;
    }

    final entries = <CourseCatalogEntry>[
      CourseCatalogEntry(
        scope: const BuiltinCourseScope('turkish'),
        displayName: 'Turkish',
        isBuiltin: true,
        sectionCount: sections
            .where((s) =>
                s.level != 'Anki' &&
                !OfficialAnkiCourseEntry.isOfficialSectionId(s.id))
            .length,
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

    // Official sources — authority rows first, then manifest-only sources
    // imported before the authority table was introduced.
    final officialIds = <String>{};
    if (db != null) {
      Future<int> officialCardCount(String sourceId) async {
        try {
          final rows = await db!.customSelect(
            'SELECT COUNT(*) AS n FROM official_anki_projection_index '
            'WHERE source_id = ?',
            variables: [Variable.withString(sourceId)],
          ).get();
          return rows.isEmpty ? 0 : rows.single.read<int>('n');
        } catch (_) {
          return 0;
        }
      }

      final dao = AnkiOwnerAuthorityDao(db);
      try {
        // Read every authority row, not only active ones. A pending/retired
        // row still owns its source id and must suppress the legacy manifest
        // fallback below; otherwise an uninstalling or already-uninstalled
        // source is resurrected as a zero-card course.
        for (final row in await dao.listSources(officialProfileId)) {
          if (!officialIds.add(row.sourceId)) continue;
          if (row.backendKind != 'official' ||
              row.state != AnkiSourceVisibility.active) {
            continue;
          }
          entries.add(CourseCatalogEntry(
            scope: OfficialAnkiCourseScope(
              profileId: officialProfileId,
              sourceId: row.sourceId,
            ),
            displayName: row.displayName,
            isBuiltin: false,
            officialSourceId: row.sourceId,
            sectionCount: sections
                .where(
                    (s) => officialSourceIdFromSectionId(s.id) == row.sourceId)
                .length,
            cardCount: await officialCardCount(row.sourceId),
          ));
        }
      } catch (e) {
        logger.w('CourseCatalog: authority lookup failed: $e');
      }

      // Manifest fallback for pre-v21 imports.
      try {
        final manifests = await db
            .customSelect(
              'SELECT source_id, source_fingerprint '
              'FROM official_anki_projection_manifest',
            )
            .get();
        for (final manifest in manifests) {
          final sourceId = manifest.read<String>('source_id');
          if (officialIds.contains(sourceId)) continue;
          final fingerprint = manifest.read<String>('source_fingerprint');
          final rows = await db.customSelect(
            'SELECT DISTINCT section_id, source_fingerprint '
            'FROM official_anki_projection_index WHERE source_id = ?',
            variables: [Variable.withString(sourceId)],
          ).get();
          if (rows.isEmpty) continue;
          final consistent = rows.every(
            (row) => row.read<String>('source_fingerprint') == fingerprint,
          );
          if (!consistent) continue;
          final sectionIds = rows
              .map((row) => row.read<String>('section_id'))
              .where(
                  (id) => officialAnkiIsOwnedTreeId(sourceId: sourceId, id: id))
              .toSet();
          if (sectionIds.isEmpty) continue;
          if (!officialIds.add(sourceId)) continue;
          final name = sections
              .where((s) => sectionIds.contains(s.id))
              .map((s) => s.name)
              .firstOrNull;
          entries.add(CourseCatalogEntry(
            scope: OfficialAnkiCourseScope(
              profileId: officialProfileId,
              sourceId: sourceId,
            ),
            displayName: name ?? sourceId,
            isBuiltin: false,
            officialSourceId: sourceId,
            sectionCount: sectionIds.length,
            cardCount: await officialCardCount(sourceId),
          ));
        }
      } catch (e) {
        logger.w('CourseCatalog: manifest fallback failed: $e');
      }
    }

    // v2 视图条目（B6 读面）：视图 + 账本 chain='v2' active 合成；
    // flag 关时为空（回退后 v2 旧来源条目不可见，但账本/配置区/视图
    // 数据都在——翻回 flag 即恢复，回退语义的对称面）。
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog != null && db != null) {
        final activeSources = {
          for (final source in OfficialAnkiSourceDao(catalog).listV2Sources(
            officialProfileId,
            states: {'active'},
          ))
            source.sourceId: source,
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
          if (officialIds.contains(sourceId)) continue;
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
  static bool sectionBelongsToScope(CourseScope scope, String sectionId) {
    return switch (scope) {
      BuiltinCourseScope() => false,
      LegacyAnkiCourseScope(importId: final id) =>
        legacyImportIdFromSectionId(sectionId) == id,
      OfficialAnkiCourseScope(sourceId: final id) =>
        officialSourceIdFromSectionId(sectionId) == id,
    };
  }
}
