import 'dart:math' as math;

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/core/natural_compare.dart';
import 'package:turna/courses/course_validator.dart' show kMaxLessonsPerUnit, kMaxUnitsPerSection;

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
    this.vocabulary,
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

  /// P5F-33: dictionary-facing term data for this card, when the projected
  /// values carry a usable term/translation pair. The store writes one
  /// `vocabulary` row per card (tagged `official:<sourceId>`) so lookups and
  /// weak-word features see official words the same way legacy imports do.
  final OfficialAnkiProjectedVocabulary? vocabulary;
}

class OfficialAnkiProjectedVocabulary {
  const OfficialAnkiProjectedVocabulary({
    required this.term,
    required this.translation,
    this.pronunciation,
    this.audioAsset,
  });

  final String term;
  final String translation;
  final String? pronunciation;
  final String? audioAsset;
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
    this.maxUnitsPerSection = kMaxUnitsPerSection,
    this.maxLessonsPerUnit = kMaxLessonsPerUnit,
  });

  final int lessonSize;
  final int validatorCap;

  /// Design-contract tree ceilings from [validateSectionTree]. Oversized
  /// groups are split into `Part n` children at the end of [project] so the
  /// runtime L1 validator can never see a published section that fails.
  final int maxUnitsPerSection;
  final int maxLessonsPerUnit;
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
    // Human-ordered tree: sections/units/lessons sort by display name
    // (numeric-aware, case-insensitive), ids only break ties. Sorting by id
    // hashes here would scramble the deck order the user sees in Anki.
    assigned.sort((a, b) {
      final section = naturalCompare(a.sectionName, b.sectionName);
      if (section != 0) return section;
      final bySectionId = a.sectionId.compareTo(b.sectionId);
      if (bySectionId != 0) return bySectionId;
      final unit = naturalCompare(a.unitName, b.unitName);
      if (unit != 0) return unit;
      final byUnitId = a.unitId.compareTo(b.unitId);
      if (byUnitId != 0) return byUnitId;
      final lesson = naturalCompare(
        a.lessonName ?? a.lessonGroup,
        b.lessonName ?? b.lessonGroup,
      );
      if (lesson != 0) return lesson;
      final group = a.lessonGroup.compareTo(b.lessonGroup);
      if (group != 0) return group;
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
        final vocabulary =
            (values.target.isNotEmpty && values.native.isNotEmpty)
                ? OfficialAnkiProjectedVocabulary(
                    term: values.target,
                    translation: values.native,
                    pronunciation: values.pronunciation.isNotEmpty
                        ? values.pronunciation
                        : null,
                    audioAsset: values.audio,
                  )
                : null;
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
            vocabulary: vocabulary,
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
                vocabulary: vocabulary,
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
                vocabulary: vocabulary,
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
                  vocabulary: vocabulary,
                ),
              );
            }
          }
        }
      }
    }
    // Split by JSON size first (it can add lessons), then enforce the
    // units-per-section / lessons-per-unit ceilings on the final lesson set.
    final sized = officialAnkiSplitLessons(sourceId: sourceId, items: items);
    return OfficialAnkiProjectionPlan(
      items: _packTreeLimits(sized),
      issues: issues,
    );
  }

  /// Splits oversized units and sections so the published tree always
  /// satisfies the validator's hard ceilings. Unit splitting runs first
  /// because it can raise a section's unit count; the section pass then
  /// chunks the final unit set. Groups within the limits keep their ids
  /// byte-for-byte, so placement overrides stay valid.
  List<OfficialAnkiProjectedItem> _packTreeLimits(
    List<OfficialAnkiProjectedItem> items,
  ) {
    if (maxLessonsPerUnit > 0) {
      items = _splitOversizedGroups(
        items,
        limit: maxLessonsPerUnit,
        groupIdOf: (item) => item.unitId,
        groupNameOf: (item) => item.unitName,
        entryIdOf: (item) => item.lessonId,
        rebuild: (item, unitId, unitName) =>
            _copyItem(item, unitId: unitId, unitName: unitName),
      );
    }
    if (maxUnitsPerSection > 0) {
      items = _splitOversizedGroups(
        items,
        limit: maxUnitsPerSection,
        groupIdOf: (item) => item.sectionId,
        groupNameOf: (item) => item.sectionName,
        entryIdOf: (item) => item.unitId,
        rebuild: (item, sectionId, sectionName) =>
            _copyItem(item, sectionId: sectionId, sectionName: sectionName),
      );
    }
    return items;
  }

  /// Chunks a group's entries into `limit`-sized parts; part 1 keeps the
  /// original id/name, later parts get an `-xN` id suffix and a
  /// ` (Part N)` name suffix. `[rebuild]` rewrites the affected field pair.
  List<OfficialAnkiProjectedItem> _splitOversizedGroups(
    List<OfficialAnkiProjectedItem> items, {
    required int limit,
    required String Function(OfficialAnkiProjectedItem) groupIdOf,
    required String Function(OfficialAnkiProjectedItem) groupNameOf,
    required String Function(OfficialAnkiProjectedItem) entryIdOf,
    required OfficialAnkiProjectedItem Function(
      OfficialAnkiProjectedItem item,
      String groupId,
      String groupName,
    ) rebuild,
  }) {
    final entriesPerGroup = <String, List<String>>{};
    final groupNames = <String, String>{};
    final seenEntries = <String>{};
    for (final item in items) {
      final groupId = groupIdOf(item);
      final entryId = entryIdOf(item);
      groupNames.putIfAbsent(groupId, () => groupNameOf(item));
      // Items are sorted, so an entry's items are contiguous; the Set guard
      // makes the distinct-in-order list robust even if they are not.
      if (seenEntries.add(entryId)) {
        entriesPerGroup.putIfAbsent(groupId, () => <String>[]).add(entryId);
      }
    }
    final entryRemap = <String, (String, String)>{};
    for (final group in entriesPerGroup.entries) {
      final groupEntries = group.value;
      if (groupEntries.length <= limit) continue;
      final groupId = group.key;
      final groupName = groupNames[groupId] ?? groupId;
      final chunkCount = (groupEntries.length / limit).ceil();
      for (var c = 0; c < chunkCount; c++) {
        final newGroupId = c == 0 ? groupId : '$groupId-x${c + 1}';
        final newGroupName =
            c == 0 ? groupName : '$groupName (Part ${c + 1})';
        final start = c * limit;
        final end = math.min(start + limit, groupEntries.length);
        for (var i = start; i < end; i++) {
          entryRemap[groupEntries[i]] = (newGroupId, newGroupName);
        }
      }
    }
    if (entryRemap.isEmpty) return items;
    return [
      for (final item in items)
        entryRemap.containsKey(entryIdOf(item))
            ? rebuild(
                item,
                entryRemap[entryIdOf(item)]!.$1,
                entryRemap[entryIdOf(item)]!.$2,
              )
            : item,
    ];
  }

  OfficialAnkiProjectedItem _copyItem(
    OfficialAnkiProjectedItem item, {
    String? sectionId,
    String? sectionName,
    String? unitId,
    String? unitName,
  }) {
    return OfficialAnkiProjectedItem(
      kind: item.kind,
      cardId: item.cardId,
      wordId: item.wordId,
      sectionId: sectionId ?? item.sectionId,
      unitId: unitId ?? item.unitId,
      lessonId: item.lessonId,
      sectionName: sectionName ?? item.sectionName,
      unitName: unitName ?? item.unitName,
      lessonName: item.lessonName,
      payload: item.payload,
      sourceFingerprint: item.sourceFingerprint,
      vocabulary: item.vocabulary,
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
