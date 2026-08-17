import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/stage.dart';

/// Canonical mapping JSON used for version compare. Order-independent.
Map<String, Object?> officialAnkiCanonicalMapping(
  OfficialAnkiMappingSuggestion mapping,
) {
  final roles = [
    for (final candidate in mapping.candidates)
      <String, Object?>{
        'role': candidate.role.name,
        'fieldIndex': candidate.fieldIndex,
        'fieldName': candidate.fieldName,
      },
  ]..sort((a, b) {
      final role = (a['role'] as String).compareTo(b['role'] as String);
      if (role != 0) return role;
      return (a['fieldIndex'] as int).compareTo(b['fieldIndex'] as int);
    });
  final kinds = List<String>.from(mapping.enabledKinds)..sort();
  return <String, Object?>{
    'notetypeId': mapping.notetypeId,
    'schemaFingerprint': mapping.schemaFingerprint,
    'direction': mapping.direction,
    'enabledKinds': kinds,
    'singleFieldMode': mapping.singleFieldMode,
    'userConfirmed': mapping.userConfirmed,
    'skipped': mapping.status == OfficialAnkiMappingStatus.skipped,
    'roles': roles,
  };
}

bool officialAnkiSameCanonicalMapping(
  OfficialAnkiMappingSuggestion left,
  OfficialAnkiMappingSuggestion right,
) {
  return jsonEncode(officialAnkiCanonicalMapping(left)) ==
      jsonEncode(officialAnkiCanonicalMapping(right));
}

String officialAnkiShuffleSeed({
  required String sourceFingerprint,
  required int cardId,
  required String kind,
  int algorithmVersion = officialAnkiProjectionAlgorithmVersion,
}) {
  return '$sourceFingerprint|$cardId|$kind|$algorithmVersion';
}

/// Deterministic Fisher–Yates. Same seed always yields the same permutation.
List<T> officialAnkiDeterministicShuffle<T>(List<T> items, String seed) {
  final out = List<T>.from(items);
  if (out.length < 2) return out;
  final digest = sha256.convert(utf8.encode(seed)).bytes;
  var state = ByteData.sublistView(Uint8List.fromList(digest)).getUint32(0);
  int next() {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    return state;
  }

  for (var i = out.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

String officialAnkiLessonJson(List<OfficialAnkiProjectedItem> items) {
  final content = LessonContent(
    stages: [
      Stage(
        id: 'official-stage-0',
        name: items.isEmpty ? '' : items.first.lessonName,
        items: [
          for (final item in items)
            Interaction.fromJson(Map<String, dynamic>.from(item.payload)),
        ],
      ),
    ],
  );
  return jsonEncode(content.toJson());
}

/// Projector-level split. Never remelts qualifying chunks into one JSON.
List<OfficialAnkiProjectedItem> officialAnkiSplitLessons({
  required String sourceId,
  required List<OfficialAnkiProjectedItem> items,
}) {
  final groups = <String, List<OfficialAnkiProjectedItem>>{};
  for (final item in items) {
    groups.putIfAbsent(item.lessonId, () => <OfficialAnkiProjectedItem>[]).add(
          item,
        );
  }
  final out = <OfficialAnkiProjectedItem>[];
  for (final entry in groups.entries) {
    final chunks = <List<OfficialAnkiProjectedItem>>[];
    _packChunks(entry.value, chunks);
    if (chunks.length == 1) {
      out.addAll(chunks.first);
      continue;
    }
    for (var i = 0; i < chunks.length; i++) {
      out.addAll(_rekeyPart(sourceId, chunks[i], i + 1));
    }
  }
  return out;
}

void _packChunks(
  List<OfficialAnkiProjectedItem> items,
  List<List<OfficialAnkiProjectedItem>> chunks,
) {
  if (items.isEmpty) return;
  final encoded = utf8.encode(officialAnkiLessonJson(items));
  if (encoded.length <= officialAnkiProjectionLessonJsonMaxBytes ||
      items.length == 1) {
    chunks.add(items);
    return;
  }
  final mid = items.length ~/ 2;
  _packChunks(items.sublist(0, mid), chunks);
  _packChunks(items.sublist(mid), chunks);
}

List<OfficialAnkiProjectedItem> _rekeyPart(
  String sourceId,
  List<OfficialAnkiProjectedItem> items,
  int part,
) {
  if (items.isEmpty) return items;
  final first = items.first;
  final lessonId = officialAnkiLessonId(
    sourceId: sourceId,
    groupKey: '${first.lessonId}::split',
    part: part,
  );
  return [
    for (final item in items)
      OfficialAnkiProjectedItem(
        kind: item.kind,
        cardId: item.cardId,
        wordId: item.wordId,
        sectionId: item.sectionId,
        unitId: item.unitId,
        lessonId: lessonId,
        sectionName: item.sectionName,
        unitName: item.unitName,
        lessonName: '${item.lessonName} ($part)',
        payload: item.payload,
        sourceFingerprint: item.sourceFingerprint,
      ),
  ];
}
