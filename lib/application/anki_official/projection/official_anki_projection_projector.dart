import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';

enum OfficialAnkiProjectionKind {
  showWord,
  flip,
  multipleChoice,
  multiSelect,
  listenPick,
  typeAnswer,
  fillBlank,
  translate,
  canonicalLink,
}

class OfficialAnkiPlacementOverride {
  const OfficialAnkiPlacementOverride({
    this.sectionKey,
    this.unitKey,
    this.lessonKey,
    this.locked = false,
  });

  final String? sectionKey;
  final String? unitKey;
  final String? lessonKey;
  final bool locked;
}

class OfficialAnkiProjectedItem {
  const OfficialAnkiProjectedItem({
    required this.kind,
    required this.cardId,
    required this.wordId,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.sectionName,
    required this.unitName,
    required this.lessonName,
    required this.payload,
    required this.sourceFingerprint,
  });

  final OfficialAnkiProjectionKind kind;
  final int cardId;
  final String wordId;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final String sectionName;
  final String unitName;
  final String lessonName;
  final Map<String, Object?> payload;
  final String sourceFingerprint;
}

class OfficialAnkiProjectionIssue {
  const OfficialAnkiProjectionIssue({
    required this.code,
    required this.cardId,
    required this.detail,
  });

  final String code;
  final int cardId;
  final String detail;
}

class OfficialAnkiProjectionPlan {
  const OfficialAnkiProjectionPlan({
    required this.items,
    required this.issues,
  });

  final List<OfficialAnkiProjectedItem> items;
  final List<OfficialAnkiProjectionIssue> issues;
}

class OfficialAnkiProjectionProjector {
  OfficialAnkiProjectionProjector({
    this.lessonSize = 20,
    this.validatorCap = 200,
  });

  final int lessonSize;
  final int validatorCap;
  final _mapper = OfficialAnkiProjectionMapper();
  final _payloads = OfficialAnkiProjectionPayloads();

  OfficialAnkiProjectionPlan project({
    required String sourceId,
    required String profileId,
    required List<OfficialAnkiProjectionRow> rows,
    required Map<int, OfficialAnkiMappingSuggestion> mappings,
    bool typeAnswerEnabled = false,
    Set<int> lockedCardIds = const <int>{},
    Map<int, OfficialAnkiPlacementOverride> placementOverrides =
        const <int, OfficialAnkiPlacementOverride>{},
    Map<String, int> topDeckIds = const <String, int>{},
  }) {
    final items = <OfficialAnkiProjectedItem>[];
    final issues = <OfficialAnkiProjectionIssue>[];
    final assigned = <_AssignedRow>[];
    for (final row in rows) {
      assigned.add(
        _assign(
          sourceId: sourceId,
          row: row,
          mapping: mappings[row.notetypeId],
          override: placementOverrides[row.cardId],
          locked: lockedCardIds.contains(row.cardId),
          topDeckIds: topDeckIds,
          issues: issues,
        ),
      );
    }
    assigned.sort((a, b) {
      final section = a.sectionId.compareTo(b.sectionId);
      if (section != 0) return section;
      final unit = a.unitId.compareTo(b.unitId);
      if (unit != 0) return unit;
      final lesson = a.lessonGroup.compareTo(b.lessonGroup);
      if (lesson != 0) return lesson;
      return a.row.cardId.compareTo(b.row.cardId);
    });
    final buckets = <String, List<_AssignedRow>>{};
    for (final row in assigned) {
      buckets.putIfAbsent(row.bucketKey, () => <_AssignedRow>[]).add(row);
    }
    for (final bucket in buckets.values) {
      final siblingPool = <String>[];
      final seenSiblings = <String>{};
      for (final row in bucket) {
        final m = mappings[row.row.notetypeId];
        final nativeCand = m?.role(OfficialAnkiFieldRole.nativeText);
        final targetCand = m?.role(OfficialAnkiFieldRole.targetText);
        String s = '';
        if (nativeCand != null &&
            nativeCand.fieldIndex >= 0 &&
            nativeCand.fieldIndex < row.row.fields.length) {
          s = _mapper.shortText(row.row.fields[nativeCand.fieldIndex]);
        } else if (targetCand != null &&
            targetCand.fieldIndex >= 0 &&
            targetCand.fieldIndex < row.row.fields.length) {
          s = _mapper.shortText(row.row.fields[targetCand.fieldIndex]);
        } else if (row.row.fields.isNotEmpty) {
          s = _mapper.shortText(row.row.fields[0]);
        }
        if (s.trim().isNotEmpty && s.length <= 80 && seenSiblings.add(s.toLowerCase())) {
          siblingPool.add(s.trim());
        }
      }

      for (var i = 0; i < bucket.length; i++) {
        final assignedRow = bucket[i];
        final part = assignedRow.hasExplicitLesson
            ? (i ~/ validatorCap) + 1
            : (i ~/ lessonSize) + 1;
        final lessonId = assignedRow.lockedLessonId ??
            officialAnkiLessonId(
              sourceId: sourceId,
              groupKey: '${assignedRow.lessonGroup}::p$part',
              part: part,
            );
        final lessonName = assignedRow.lessonName ?? 'Lesson $part';
        final mapping = mappings[assignedRow.row.notetypeId];
        final values = _payloads.values(
          assignedRow.row,
          mapping,
          siblingAnswers: siblingPool,
        );
        if (values.truncatedRequired) {
          issues.add(
            OfficialAnkiProjectionIssue(
              code: 'truncated_required_role',
              cardId: assignedRow.row.cardId,
              detail: 'required role truncated',
            ),
          );
        }
        final kinds = _payloads.kindsFor(
          values: values,
          mapping: mapping,
          typeAnswerEnabled: typeAnswerEnabled,
        );
        final wordId = officialAnkiWordId(
          profileId: profileId,
          cardId: assignedRow.row.cardId,
        );
        for (final kind in kinds) {
          final draft = OfficialAnkiProjectedItem(
            kind: kind,
            cardId: assignedRow.row.cardId,
            wordId: wordId,
            sectionId: assignedRow.sectionId,
            unitId: assignedRow.unitId,
            lessonId: lessonId,
            sectionName: assignedRow.sectionName,
            unitName: assignedRow.unitName,
            lessonName: lessonName,
            sourceFingerprint: assignedRow.row.sourceFingerprint,
            payload: const <String, Object?>{},
          );
          try {
            items.add(
              OfficialAnkiProjectedItem(
                kind: kind,
                cardId: assignedRow.row.cardId,
                wordId: wordId,
                sectionId: assignedRow.sectionId,
                unitId: assignedRow.unitId,
                lessonId: lessonId,
                sectionName: assignedRow.sectionName,
                unitName: assignedRow.unitName,
                lessonName: lessonName,
                sourceFingerprint: assignedRow.row.sourceFingerprint,
                payload: _payloads.interactionJson(
                  kind: kind,
                  item: draft,
                  values: values,
                  sourceId: sourceId,
                ),
              ),
            );
          } on OfficialAnkiPayloadOverflow {
            issues.add(
              OfficialAnkiProjectionIssue(
                code: 'item_json_overflow',
                cardId: assignedRow.row.cardId,
                detail: kind.name,
              ),
            );
            if (kind != OfficialAnkiProjectionKind.canonicalLink) {
              final link = OfficialAnkiProjectedItem(
                kind: OfficialAnkiProjectionKind.canonicalLink,
                cardId: assignedRow.row.cardId,
                wordId: wordId,
                sectionId: assignedRow.sectionId,
                unitId: assignedRow.unitId,
                lessonId: lessonId,
                sectionName: assignedRow.sectionName,
                unitName: assignedRow.unitName,
                lessonName: lessonName,
                sourceFingerprint: assignedRow.row.sourceFingerprint,
                payload: const <String, Object?>{},
              );
              items.add(
                OfficialAnkiProjectedItem(
                  kind: OfficialAnkiProjectionKind.canonicalLink,
                  cardId: assignedRow.row.cardId,
                  wordId: wordId,
                  sectionId: assignedRow.sectionId,
                  unitId: assignedRow.unitId,
                  lessonId: lessonId,
                  sectionName: assignedRow.sectionName,
                  unitName: assignedRow.unitName,
                  lessonName: lessonName,
                  sourceFingerprint: assignedRow.row.sourceFingerprint,
                  payload: _payloads.interactionJson(
                    kind: OfficialAnkiProjectionKind.canonicalLink,
                    item: link,
                    values: values,
                    sourceId: sourceId,
                  ),
                ),
              );
            }
          }
        }
      }
    }
    return OfficialAnkiProjectionPlan(
      items: officialAnkiSplitLessons(sourceId: sourceId, items: items),
      issues: issues,
    );
  }

  _AssignedRow _assign({
    required String sourceId,
    required OfficialAnkiProjectionRow row,
    required OfficialAnkiMappingSuggestion? mapping,
    required OfficialAnkiPlacementOverride? override,
    required bool locked,
    required Map<String, int> topDeckIds,
    required List<OfficialAnkiProjectionIssue> issues,
  }) {
    final lockedPlacement = locked && override != null;
    if (lockedPlacement &&
        override.sectionKey != null &&
        override.unitKey != null &&
        override.lessonKey != null) {
      final sectionId = _ownedOrDerived(
        sourceId: sourceId,
        key: override.sectionKey!,
        derive: () => officialAnkiSectionIdForTopDeck(
          sourceId: sourceId,
          topDeckName: override.sectionKey!,
          topDeckIds: topDeckIds,
        ),
      );
      final unitId = _ownedOrDerived(
        sourceId: sourceId,
        key: override.unitKey!,
        derive: () => officialAnkiUnitId(
          sourceId: sourceId,
          deckPath: [override.sectionKey!, override.unitKey!],
        ),
      );
      final lessonId = _ownedOrDerived(
        sourceId: sourceId,
        key: override.lessonKey!,
        derive: () => officialAnkiLessonId(
          sourceId: sourceId,
          groupKey: override.lessonKey!,
          part: 1,
        ),
      );
      if (sectionId != null && unitId != null && lessonId != null) {
        return _AssignedRow(
          row: row,
          sectionId: sectionId,
          unitId: unitId,
          lessonGroup: lessonId,
          sectionName: override.sectionKey!,
          unitName: override.unitKey!,
          lessonName: override.lessonKey,
          hasExplicitLesson: true,
          lockedLessonId: lessonId,
        );
      }
      issues.add(
        OfficialAnkiProjectionIssue(
          code: 'placement_rejected',
          cardId: row.cardId,
          detail: 'override left official namespace',
        ),
      );
    }
    final recovered = _cyclicOrMissing(row.deckPath);
    if (recovered) {
      issues.add(
        OfficialAnkiProjectionIssue(
          code: 'recovered_deck',
          cardId: row.cardId,
          detail: row.deckPath.join('::'),
        ),
      );
    }
    final topName = recovered ? 'Recovered' : row.deckPath.first;
    final sectionId = officialAnkiSectionIdForTopDeck(
      sourceId: sourceId,
      topDeckName: topName,
      topDeckIds: topDeckIds,
    );
    final unitLabel = _fieldValue(row, mapping, OfficialAnkiFieldRole.unitLabel);
    final lessonLabel =
        _fieldValue(row, mapping, OfficialAnkiFieldRole.lessonLabel);
    final unitTag = _tagValue(row.tags, const [
      'unit::',
      'unit:',
      'chapter::',
      'chapter:',
      'section::',
      'section:',
      '单元::',
      '单元:',
      '章::',
      '章:',
    ]);
    final lessonTag = _tagValue(row.tags, const [
      'lesson::',
      'lesson:',
      'topic::',
      'topic:',
      '课::',
      '课:',
      '节::',
      '节:',
    ]);
    final unitKey = (unitLabel != null && unitLabel.isNotEmpty)
        ? unitLabel
        : (unitTag ??
            (recovered
                ? 'Recovered'
                : row.deckPath.skip(1).join('\u001f').ifEmpty(row.deckPath.join('\u001f'))));
    final unitId = officialAnkiUnitId(
      sourceId: sourceId,
      deckPath: [topName, unitKey],
    );
    final unitName = recovered
        ? 'Recovered'
        : (unitLabel ??
            unitTag ??
            (row.deckPath.length > 1
                ? row.deckPath.skip(1).join(' › ')
                : row.deckPath.join(' › ')));
    final explicitLesson = (lessonLabel != null && lessonLabel.isNotEmpty)
        ? lessonLabel
        : lessonTag;
    return _AssignedRow(
      row: row,
      sectionId: sectionId,
      unitId: unitId,
      lessonGroup: explicitLesson ?? '$sectionId|$unitId|default',
      sectionName: topName,
      unitName: unitName,
      lessonName: explicitLesson,
      hasExplicitLesson: explicitLesson != null,
    );
  }

  String? _fieldValue(
    OfficialAnkiProjectionRow row,
    OfficialAnkiMappingSuggestion? mapping,
    OfficialAnkiFieldRole role,
  ) {
    final match = mapping?.candidates.where((c) => c.role == role);
    if (match != null && match.isNotEmpty) {
      final index = match.first.fieldIndex;
      if (index >= 0 && index < row.fields.length) {
        final text = _mapper.shortText(row.fields[index]);
        if (text.isNotEmpty) return text;
      }
    }
    // Heuristic lookup if not mapped explicitly:
    if (mapping != null) {
      final patterns = role == OfficialAnkiFieldRole.unitLabel
          ? const ['unit', 'chapter', 'section', '单元', '章']
          : const ['lesson', 'topic', 'subunit', '课', '节'];
      for (final cand in mapping.candidates) {
        final lower = cand.fieldName.toLowerCase();
        if (patterns.any(lower.contains)) {
          if (cand.fieldIndex >= 0 && cand.fieldIndex < row.fields.length) {
            final text = _mapper.shortText(row.fields[cand.fieldIndex]);
            if (text.isNotEmpty) return text;
          }
        }
      }
    }
    return null;
  }

  String? _tagValue(List<String> tags, List<String> prefixes) {
    for (final rawTag in tags) {
      final tag = rawTag.trim();
      final lower = tag.toLowerCase();
      for (final prefix in prefixes) {
        if (lower.startsWith(prefix) && tag.length > prefix.length) {
          final val = tag.substring(prefix.length).trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
    return null;
  }

  bool _cyclicOrMissing(List<String> path) {
    if (path.isEmpty) return true;
    return path.toSet().length != path.length;
  }

  String? _ownedOrDerived({
    required String sourceId,
    required String key,
    required String Function() derive,
  }) {
    if (key.startsWith('official-anki-')) {
      return officialAnkiIsOwnedTreeId(sourceId: sourceId, id: key) ? key : null;
    }
    if (key.startsWith('anki-')) return null;
    return derive();
  }
}

class _AssignedRow {
  _AssignedRow({
    required this.row,
    required this.sectionId,
    required this.unitId,
    required this.lessonGroup,
    required this.sectionName,
    required this.unitName,
    required this.lessonName,
    required this.hasExplicitLesson,
    this.lockedLessonId,
  });

  final OfficialAnkiProjectionRow row;
  final String sectionId;
  final String unitId;
  final String lessonGroup;
  final String sectionName;
  final String unitName;
  final String? lessonName;
  final bool hasExplicitLesson;
  final String? lockedLessonId;

  String get bucketKey => '$sectionId|$unitId|$lessonGroup';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
