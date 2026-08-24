import 'package:drift/drift.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';

/// Joins Drift Legacy inventory with the Official catalog.
///
/// Keys are source hash, then import id / official source id — never display
/// name (doc 34 §7.4). SELECT-only; does not open the Anki Collection.
class JoinedOfficialAnkiSourceEvidenceReader
    implements OfficialAnkiSourceEvidenceReader {
  JoinedOfficialAnkiSourceEvidenceReader({
    required CourseDatabase course,
    OfficialAnkiDatabase? catalog,
  })  : _course = course,
        _catalog = catalog;

  final CourseDatabase _course;
  final OfficialAnkiDatabase? _catalog;

  @override
  Future<List<OfficialAnkiSourceEvidence>> loadEvidence({
    required String profileId,
  }) async {
    final catalog = _catalog;
    final catalogRows = catalog == null
        ? const <OfficialAnkiSourceEvidence>[]
        : await CatalogOfficialAnkiSourceEvidenceReader(catalog)
            .loadEvidence(profileId: profileId);
    final driftRows = await _loadDriftSeeds(profileId);
    return _merge(profileId, catalogRows, driftRows);
  }

  Future<List<_DriftSeed>> _loadDriftSeeds(String profileId) async {
    final imports = await _course.customSelect(
      'SELECT import_id, source_hash FROM anki_imports',
    ).get();
    final unification = await _course.customSelect(
      'SELECT source_id, source_hash, backend_kind, state '
      'FROM anki_course_sources WHERE profile_id = ?',
      variables: [Variable(profileId)],
    ).get();
    final unificationByHash = <String, QueryRow>{};
    final unificationBySource = <String, QueryRow>{};
    for (final row in unification) {
      final hash = (row.read<String>('source_hash')).trim();
      final sourceId = (row.read<String>('source_id')).trim();
      if (hash.isNotEmpty) unificationByHash[hash] = row;
      if (sourceId.isNotEmpty) unificationBySource[sourceId] = row;
    }

    final out = <_DriftSeed>[];
    for (final imp in imports) {
      final importId = imp.read<String>('import_id');
      final sourceHash = imp.read<String>('source_hash');
      final notes = await _course.customSelect(
        'SELECT COUNT(*) AS n FROM anki_notes WHERE import_id = ?',
        variables: [Variable(importId)],
      ).getSingle();
      final cards = await _course.customSelect(
        'SELECT COUNT(*) AS n FROM anki_cards_meta WHERE import_id = ?',
        variables: [Variable(importId)],
      ).getSingle();
      final srs = await _course.customSelect(
        "SELECT COUNT(*) AS n FROM srs_states WHERE word_id LIKE ?",
        variables: [Variable('anki-$importId-%')],
      ).getSingle();
      final uni = unificationByHash[sourceHash] ??
          unificationBySource[importId];
      out.add(
        _DriftSeed(
          importId: importId,
          sourceHash: sourceHash,
          noteCount: notes.read<int>('n'),
          cardCount: cards.read<int>('n'),
          srsCount: srs.read<int>('n'),
          unificationBackend: uni?.read<String?>('backend_kind'),
        ),
      );
    }
    return out;
  }

  List<OfficialAnkiSourceEvidence> _merge(
    String profileId,
    List<OfficialAnkiSourceEvidence> catalogRows,
    List<_DriftSeed> driftRows,
  ) {
    final byKey = <String, OfficialAnkiSourceEvidence>{};
    for (final row in catalogRows) {
      final key = _key(
        sourceHash: row.sourceHash,
        sourceId: row.sourceId,
        importId: row.importId,
      );
      if (key == null) continue;
      byKey[key] = row;
    }

    final usedDrift = <String>{};
    for (final seed in driftRows) {
      final hashKey = seed.sourceHash.isEmpty ? null : 'h:${seed.sourceHash}';
      final importKey = 'i:${seed.importId}';
      OfficialAnkiSourceEvidence? match;
      String? matchedKey;
      if (hashKey != null && byKey.containsKey(hashKey)) {
        match = byKey[hashKey];
        matchedKey = hashKey;
      } else if (byKey.containsKey(importKey)) {
        match = byKey[importKey];
        matchedKey = importKey;
      } else {
        for (final entry in byKey.entries) {
          if (entry.value.importId == seed.importId ||
              entry.value.sourceId == seed.importId) {
            match = entry.value;
            matchedKey = entry.key;
            break;
          }
        }
      }

      if (match != null && matchedKey != null) {
        usedDrift.add(seed.importId);
        final officialCount = match.officialCardCount;
        byKey[matchedKey] = OfficialAnkiSourceEvidence(
          profileId: profileId,
          sourceId: match.sourceId,
          importId: match.importId ?? seed.importId,
          sourceHash: match.sourceHash ?? seed.sourceHash,
          recordedOwner: match.recordedOwner,
          unificationBackend: seed.unificationBackend ?? match.unificationBackend,
          migrationRecordedKind: match.migrationRecordedKind,
          migrationOfficialSourceId: match.migrationOfficialSourceId,
          migrationState: match.migrationState,
          officialSourceState: match.officialSourceState,
          officialCardCount: officialCount,
          collectionPresent: match.collectionPresent,
          projectionPresent: match.projectionPresent,
          placementCount: match.placementCount,
          identityRowCount: match.identityRowCount,
          legacyImportPresent: true,
          legacyNoteCount: seed.noteCount,
          legacyCardCount: seed.cardCount,
          legacySrsCount: seed.srsCount,
          cardinalityConflict: officialCount > 0 &&
              seed.cardCount > 0 &&
              officialCount != seed.cardCount,
          identityConsistent: match.identityConsistent,
          fromLegacyPendingPath: match.fromLegacyPendingPath,
        );
      }
    }

    for (final seed in driftRows) {
      if (usedDrift.contains(seed.importId)) continue;
      final key = _key(
        sourceHash: seed.sourceHash,
        sourceId: null,
        importId: seed.importId,
      );
      if (key == null) continue;
      byKey.putIfAbsent(
        key,
        () => OfficialAnkiSourceEvidence(
          profileId: profileId,
          importId: seed.importId,
          sourceHash: seed.sourceHash,
          unificationBackend: seed.unificationBackend,
          recordedOwner: seed.unificationBackend == 'official'
              ? OfficialAnkiPersistedOwner.official
              : OfficialAnkiPersistedOwner.legacy,
          legacyImportPresent: true,
          legacyNoteCount: seed.noteCount,
          legacyCardCount: seed.cardCount,
          legacySrsCount: seed.srsCount,
        ),
      );
    }

    return byKey.values.toList();
  }

  static String? _key({
    String? sourceHash,
    String? sourceId,
    String? importId,
  }) {
    final hash = sourceHash?.trim() ?? '';
    if (hash.isNotEmpty) return 'h:$hash';
    final sid = sourceId?.trim() ?? '';
    if (sid.isNotEmpty) return 's:$sid';
    final iid = importId?.trim() ?? '';
    if (iid.isNotEmpty) return 'i:$iid';
    return null;
  }
}

class _DriftSeed {
  const _DriftSeed({
    required this.importId,
    required this.sourceHash,
    required this.noteCount,
    required this.cardCount,
    required this.srsCount,
    this.unificationBackend,
  });

  final String importId;
  final String sourceHash;
  final int noteCount;
  final int cardCount;
  final int srsCount;
  final String? unificationBackend;
}
