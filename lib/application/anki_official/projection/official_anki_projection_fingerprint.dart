import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';

String officialAnkiOrderedCardSetFingerprint(Iterable<int> cardIdsAscending) {
  return sha256.convert(utf8.encode(cardIdsAscending.join(','))).toString();
}

String officialAnkiConfirmedMappingHash(
  Map<int, OfficialAnkiMappingSuggestion> mappings,
) {
  final entries = mappings.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final payload = [
    for (final entry in entries)
      if (entry.value.userConfirmed ||
          entry.value.status == OfficialAnkiMappingStatus.skipped)
        '${entry.key}:${jsonEncode(entry.value.toJson())}',
  ];
  return sha256.convert(utf8.encode(payload.join('|'))).toString();
}

String officialAnkiSchemaSetFingerprint(
  Iterable<OfficialAnkiProjectionSchema> schemas,
) {
  final rows = schemas
      .map((schema) => '${schema.notetypeId}+${schema.schemaFingerprint}')
      .toList()
    ..sort();
  return sha256.convert(utf8.encode(rows.join('|'))).toString();
}

/// Doc 38 P5: every factor of [officialAnkiProjectionFingerprint] except
/// the row payloads. Comparing it against the persisted `scan_fingerprint`
/// proves the source is unchanged WITHOUT reading every projection row —
/// the cheap gate in front of the (authoritative) full comparison.
String officialAnkiProjectionScanFingerprint({
  required int contractMajor,
  required int contractMinor,
  required String backendCommit,
  required String profileId,
  required String sourceId,
  required String orderedCardSetFingerprint,
  required int collectionGeneration,
  required String schemasFingerprint,
  required int mappingVersion,
  required String confirmedMappingHash,
  int algorithmVersion = officialAnkiProjectionAlgorithmVersion,
}) {
  return sha256
      .convert(
        utf8.encode(
          [
            contractMajor,
            contractMinor,
            backendCommit,
            profileId,
            sourceId,
            orderedCardSetFingerprint,
            collectionGeneration,
            schemasFingerprint,
            mappingVersion,
            confirmedMappingHash,
            algorithmVersion,
          ].join('|'),
        ),
      )
      .toString();
}

String officialAnkiProjectionFingerprint({
  required int contractMajor,
  required int contractMinor,
  required String backendCommit,
  required String profileId,
  required String sourceId,
  required String orderedCardSetFingerprint,
  required int collectionGeneration,
  required Iterable<OfficialAnkiProjectionSchema> schemas,
  required int mappingVersion,
  required String confirmedMappingHash,
  required Iterable<OfficialAnkiProjectionRow> rows,
  int algorithmVersion = officialAnkiProjectionAlgorithmVersion,
}) {
  final schemaKeys = schemas
      .map((schema) => '${schema.notetypeId}+${schema.schemaFingerprint}')
      .toList()
    ..sort();
  final rowKeys = rows
      .map((row) => '${row.cardId}+${row.sourceFingerprint}')
      .toList()
    ..sort();
  return sha256
      .convert(
        utf8.encode(
          [
            contractMajor,
            contractMinor,
            backendCommit,
            profileId,
            sourceId,
            orderedCardSetFingerprint,
            collectionGeneration,
            schemaKeys.join(','),
            mappingVersion,
            confirmedMappingHash,
            rowKeys.join(','),
            algorithmVersion,
          ].join('|'),
        ),
      )
      .toString();
}
