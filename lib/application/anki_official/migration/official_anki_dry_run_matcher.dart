import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';

class LegacyAnkiCardIdentity {
  const LegacyAnkiCardIdentity({
    required this.legacyCardId,
    required this.legacyWordId,
    required this.templateOrd,
    this.legacyNoteId,
    this.noteGuid,
    this.contentFingerprint,
  });

  final int legacyCardId;
  final String legacyWordId;
  final int templateOrd;
  final int? legacyNoteId;
  final String? noteGuid;
  final String? contentFingerprint;
}

class OfficialAnkiCardIdentity {
  const OfficialAnkiCardIdentity({
    required this.officialCardId,
    required this.templateOrd,
    this.officialNoteId,
    this.noteGuid,
    this.contentFingerprint,
  });

  final int officialCardId;
  final int templateOrd;
  final int? officialNoteId;
  final String? noteGuid;
  final String? contentFingerprint;
}

class LegacyAnkiCardMapDraft {
  const LegacyAnkiCardMapDraft({
    required this.legacyCardId,
    required this.legacyWordId,
    required this.templateOrd,
    required this.matchMethod,
    required this.matchState,
    this.legacyNoteId,
    this.noteGuid,
    this.officialCardId,
    this.contentFingerprint,
  });

  final int legacyCardId;
  final String legacyWordId;
  final int? legacyNoteId;
  final String? noteGuid;
  final int templateOrd;
  final int? officialCardId;
  final LegacyAnkiMatchMethod matchMethod;
  final LegacyAnkiMatchState matchState;
  final String? contentFingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
        'legacyCardId': legacyCardId,
        'legacyWordId': legacyWordId,
        'legacyNoteId': legacyNoteId,
        'noteGuid': noteGuid,
        'templateOrd': templateOrd,
        'officialCardId': officialCardId,
        'matchMethod': matchMethod.name,
        'matchState': matchState.name,
        'contentFingerprint': contentFingerprint,
      };
}

class LegacyAnkiDryRunResult {
  const LegacyAnkiDryRunResult({required this.rows});

  final List<LegacyAnkiCardMapDraft> rows;

  int get matchedCount => rows
      .where((row) => row.matchState == LegacyAnkiMatchState.matched)
      .length;
  int get unresolvedCount => rows
      .where(
        (row) =>
            row.matchState == LegacyAnkiMatchState.unresolved ||
            row.matchState == LegacyAnkiMatchState.needsUserAction ||
            row.matchState == LegacyAnkiMatchState.collision,
      )
      .length;

  bool get isFullyMatched =>
      rows.isNotEmpty &&
      rows.every((row) => row.matchState == LegacyAnkiMatchState.matched);

  Map<String, Object?> toJson() => <String, Object?>{
        'legacyCardCount': rows.length,
        'matchedCardCount': matchedCount,
        'unresolvedCardCount': unresolvedCount,
        'rows': [for (final row in rows) row.toJson()],
      };
}

/// Read-only identity matcher. Does not write official or legacy scheduling.
class LegacyAnkiDryRunMatcher {
  const LegacyAnkiDryRunMatcher();

  LegacyAnkiDryRunResult match({
    required List<LegacyAnkiCardIdentity> legacy,
    required List<OfficialAnkiCardIdentity> official,
    bool sameTrustedPackage = false,
    int? afterLegacyCardId,
    int? limit,
  }) {
    final byGuidOrd = <String, List<OfficialAnkiCardIdentity>>{};
    final byCardId = <int, List<OfficialAnkiCardIdentity>>{};
    final byFingerprint = <String, List<OfficialAnkiCardIdentity>>{};
    for (final card in official) {
      final guid = card.noteGuid;
      if (guid != null && guid.isNotEmpty) {
        byGuidOrd
            .putIfAbsent(
                '$guid#${card.templateOrd}', () => <OfficialAnkiCardIdentity>[])
            .add(card);
      }
      byCardId
          .putIfAbsent(card.officialCardId, () => <OfficialAnkiCardIdentity>[])
          .add(card);
      final fingerprint = card.contentFingerprint;
      if (fingerprint != null && fingerprint.isNotEmpty) {
        byFingerprint
            .putIfAbsent('$fingerprint#${card.templateOrd}',
                () => <OfficialAnkiCardIdentity>[])
            .add(card);
      }
    }

    final sorted = [...legacy]
      ..sort((a, b) => a.legacyCardId.compareTo(b.legacyCardId));
    final after = afterLegacyCardId ?? 0;
    var slice = sorted.where((card) => card.legacyCardId > after).toList();
    if (limit != null && limit >= 0 && slice.length > limit) {
      slice = slice.take(limit).toList();
    }
    final drafts = <LegacyAnkiCardMapDraft>[];
    for (final card in slice) {
      drafts.add(
        _matchOne(
          card: card,
          byGuidOrd: byGuidOrd,
          byCardId: byCardId,
          byFingerprint: byFingerprint,
          sameTrustedPackage: sameTrustedPackage,
        ),
      );
    }
    return LegacyAnkiDryRunResult(rows: _markOfficialCollisions(drafts));
  }

  LegacyAnkiCardMapDraft _matchOne({
    required LegacyAnkiCardIdentity card,
    required Map<String, List<OfficialAnkiCardIdentity>> byGuidOrd,
    required Map<int, List<OfficialAnkiCardIdentity>> byCardId,
    required Map<String, List<OfficialAnkiCardIdentity>> byFingerprint,
    required bool sameTrustedPackage,
  }) {
    final guid = card.noteGuid;
    if (guid != null && guid.isNotEmpty) {
      final hits = byGuidOrd['$guid#${card.templateOrd}'] ??
          const <OfficialAnkiCardIdentity>[];
      if (hits.length > 1) {
        return _draft(card, LegacyAnkiMatchMethod.noteGuidAndOrdinal,
            LegacyAnkiMatchState.collision);
      }
      if (hits.length == 1) {
        return _draft(
          card,
          LegacyAnkiMatchMethod.noteGuidAndOrdinal,
          LegacyAnkiMatchState.matched,
          officialCardId: hits.single.officialCardId,
        );
      }
    }
    if (sameTrustedPackage) {
      final hits =
          byCardId[card.legacyCardId] ?? const <OfficialAnkiCardIdentity>[];
      if (hits.length == 1 && hits.single.templateOrd == card.templateOrd) {
        return _draft(
          card,
          LegacyAnkiMatchMethod.originalCardId,
          LegacyAnkiMatchState.matched,
          officialCardId: hits.single.officialCardId,
        );
      }
    }
    final fingerprint = card.contentFingerprint;
    if (fingerprint != null && fingerprint.isNotEmpty) {
      final hits = byFingerprint['$fingerprint#${card.templateOrd}'] ??
          const <OfficialAnkiCardIdentity>[];
      if (hits.length > 1) {
        return _draft(
          card,
          LegacyAnkiMatchMethod.fieldFingerprintAndOrdinal,
          LegacyAnkiMatchState.collision,
        );
      }
      if (hits.length == 1) {
        return _draft(
          card,
          LegacyAnkiMatchMethod.fieldFingerprintAndOrdinal,
          LegacyAnkiMatchState.matched,
          officialCardId: hits.single.officialCardId,
        );
      }
    }
    return _draft(
      card,
      guid == null || guid.isEmpty
          ? LegacyAnkiMatchMethod.noteGuidAndOrdinal
          : LegacyAnkiMatchMethod.fieldFingerprintAndOrdinal,
      guid == null || guid.isEmpty
          ? LegacyAnkiMatchState.needsUserAction
          : LegacyAnkiMatchState.unresolved,
    );
  }

  List<LegacyAnkiCardMapDraft> _markOfficialCollisions(
    List<LegacyAnkiCardMapDraft> rows,
  ) {
    final claimed = <int, int>{};
    for (final row in rows) {
      final officialId = row.officialCardId;
      if (officialId == null ||
          row.matchState != LegacyAnkiMatchState.matched) {
        continue;
      }
      claimed[officialId] = (claimed[officialId] ?? 0) + 1;
    }
    return [
      for (final row in rows)
        if (row.officialCardId != null &&
            row.matchState == LegacyAnkiMatchState.matched &&
            (claimed[row.officialCardId] ?? 0) > 1)
          LegacyAnkiCardMapDraft(
            legacyCardId: row.legacyCardId,
            legacyWordId: row.legacyWordId,
            legacyNoteId: row.legacyNoteId,
            noteGuid: row.noteGuid,
            templateOrd: row.templateOrd,
            officialCardId: row.officialCardId,
            matchMethod: row.matchMethod,
            matchState: LegacyAnkiMatchState.collision,
            contentFingerprint: row.contentFingerprint,
          )
        else
          row,
    ];
  }

  LegacyAnkiCardMapDraft _draft(
    LegacyAnkiCardIdentity card,
    LegacyAnkiMatchMethod method,
    LegacyAnkiMatchState state, {
    int? officialCardId,
  }) {
    return LegacyAnkiCardMapDraft(
      legacyCardId: card.legacyCardId,
      legacyWordId: card.legacyWordId,
      legacyNoteId: card.legacyNoteId,
      noteGuid: card.noteGuid,
      templateOrd: card.templateOrd,
      officialCardId: officialCardId,
      matchMethod: method,
      matchState: state,
      contentFingerprint: card.contentFingerprint,
    );
  }
}
