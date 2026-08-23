// Project imports:
import 'package:turna/application/anki/anki_models.dart';

/// Resolves where an Anki card should sit in the imported course tree by
/// reading unit/lesson metadata the card carries.
///
/// Anki cards don't have a native "unit/lesson" field, but authors commonly
/// encode it in three places, checked here in priority order:
///   1. a notetype field whose name matches unit/lesson patterns;
///   2. a tag like `unit::2`, `lesson::greetings`, `chapter:3`;
///   3. (deck hierarchy is handled by [AnkiDeckAssembler] directly).
///
/// Returns `null` keys when nothing is found - the assembler then falls back
/// to the deck-name + 20-card-chunk default. Pure functions for testability.
class AnkiOrganizationResolver {
  const AnkiOrganizationResolver();

  /// Field-name substrings (lower-cased) that mark a unit-level field.
  static const List<String> unitFieldPatterns = [
    'unit',
    'chapter',
    'section',
    '单元',
    '章',
  ];

  /// Field-name substrings (lower-cased) that mark a lesson-level field.
  static const List<String> lessonFieldPatterns = [
    'lesson',
    'topic',
    'subunit',
    '课',
    '节',
  ];

  /// Tag prefixes (lower-cased) that carry a unit value, e.g. `unit::2`.
  static const List<String> unitTagPrefixes = [
    'unit::',
    'unit:',
    'chapter::',
    'chapter:',
    '单元::',
    '单元:',
  ];

  /// Tag prefixes (lower-cased) that carry a lesson value, e.g. `lesson::hw`.
  static const List<String> lessonTagPrefixes = [
    'lesson::',
    'lesson:',
    '课::',
    '课:',
  ];

  /// Field-name substrings (lower-cased) that mark a section-level field.
  /// Only consulted on the Section-Beta path; the default path intentionally
  /// keeps treating these as unit metadata (historical behavior).
  static const List<String> sectionFieldPatterns = [
    'section',
    'chapter',
    'part',
    '章',
    '部分',
  ];

  /// Tag prefixes (lower-cased) that carry a section value, e.g. `chapter::2`.
  static const List<String> sectionTagPrefixes = [
    'section::',
    'section:',
    'chapter::',
    'chapter:',
    '章::',
    '章:',
  ];

  /// Resolve the unit/lesson keys for [note] given its notetype definition.
  /// Either may be `null` when the card carries no such metadata.
  ///
  /// With [sectionBeta] on, an explicit section/chapter/章 field or tag is
  /// lifted into [AnkiCardOrganization.sectionKey] (with evidence and
  /// confidence) instead of folding into the unit key, and the unit lookup
  /// skips the field that supplied the section.
  AnkiCardOrganization resolve(
    AnkiNote note,
    AnkiNotetype notetype, {
    bool sectionBeta = false,
  }) {
    String? sectionKey;
    var sectionEvidence = AnkiSectionEvidence.deckHierarchy;
    var sectionConfidence = 0.0;
    var sectionFieldIndex = -1;

    if (sectionBeta) {
      final fromField = _sectionFromField(note, notetype);
      if (fromField != null) {
        sectionKey = fromField.$2;
        sectionFieldIndex = fromField.$1;
        sectionEvidence = AnkiSectionEvidence.explicitField;
        sectionConfidence = 0.9;
      } else {
        final fromTag = _fromTag(note.tags, sectionTagPrefixes);
        if (fromTag != null) {
          sectionKey = fromTag;
          sectionEvidence = AnkiSectionEvidence.explicitTag;
          sectionConfidence = 0.85;
        }
      }
    }

    var unitKey = _fromField(note, notetype, unitFieldPatterns,
            skipIndex: sectionFieldIndex) ??
        _fromTag(note.tags, unitTagPrefixes);
    final lessonKey = _fromField(note, notetype, lessonFieldPatterns) ??
        _fromTag(note.tags, lessonTagPrefixes);
    return AnkiCardOrganization(
      sectionKey: sectionKey,
      unitKey: unitKey,
      lessonKey: lessonKey,
      sectionEvidence: sectionEvidence,
      sectionConfidence: sectionConfidence,
    );
  }

  /// A preview summary: how many distinct units/lessons the resolver detects
  /// across a collection (for the import wizard's organization card).
  /// With [sectionBeta] the summary also reports detected semantic sections
  /// and their evidence mix, including Unit-name prefixes (weaker evidence).
  AnkiOrganizationPreview preview({
    required List<AnkiNote> notes,
    required Map<int, AnkiNotetype> notetypes,
    bool sectionBeta = false,
  }) {
    final units = <String>{};
    final lessons = <String>{};
    final sectionEvidenceByKey = <String, AnkiSectionEvidence>{};
    var resolved = 0;
    var sectionResolved = 0;
    for (final note in notes) {
      final nt = notetypes[note.mid];
      if (nt == null) continue;
      final org = resolve(note, nt, sectionBeta: sectionBeta);
      if (org.unitKey != null || org.lessonKey != null) resolved++;
      if (org.unitKey != null) units.add(org.unitKey!);
      if (org.lessonKey != null) lessons.add(org.lessonKey!);
      if (sectionBeta) {
        var sectionKey = org.sectionKey;
        var evidence = org.sectionEvidence;
        if (sectionKey == null && org.unitKey != null) {
          final derived = sectionKeyFromUnitName(org.unitKey!);
          if (derived != null) {
            sectionKey = derived.$2;
            evidence = AnkiSectionEvidence.unitPrefix;
          }
        }
        if (sectionKey != null) {
          sectionResolved++;
          final existing = sectionEvidenceByKey[sectionKey];
          // Explicit evidence outranks the prefix heuristic for the same key.
          if (existing == null ||
              (existing == AnkiSectionEvidence.unitPrefix &&
                  evidence != AnkiSectionEvidence.unitPrefix)) {
            sectionEvidenceByKey[sectionKey] = evidence;
          }
        }
      }
    }
    final sections = sectionEvidenceByKey.keys.toList()..sort();
    final evidenceCounts = <AnkiSectionEvidence, int>{};
    for (final evidence in sectionEvidenceByKey.values) {
      evidenceCounts[evidence] = (evidenceCounts[evidence] ?? 0) + 1;
    }
    return AnkiOrganizationPreview(
      resolvedCardCount: resolved,
      unitCount: units.length,
      lessonCount: lessons.length,
      unitNames: units.toList()..sort(),
      lessonNames: lessons.toList()..sort(),
      sectionNames: sections,
      sectionResolvedCardCount: sectionResolved,
      sectionEvidenceCounts: evidenceCounts,
    );
  }

  /// (normalized key, display name) for a unit name that carries a
  /// chapter-ish prefix, e.g. "Chapter 1: Greetings" -> ("chapter 1",
  /// "Chapter 1"). Null when the name has no such structure — those units
  /// stay in the base bucket and never count as semantic grouping.
  /// Shared with [AnkiDeckAssembler.buildSemanticSections] so the preview
  /// and the built tree agree on what the prefix evidence means.
  static (String, String)? sectionKeyFromUnitName(String unitName) {
    final match = RegExp(
      r'^\s*(chapter|ch\.?|part|section|第|章|部分)'
      r'\s*(\d+|[0-9〇零一二三四五六七八九十]+)',
      caseSensitive: false,
    ).firstMatch(unitName);
    if (match == null) return null;
    final label = match.group(1)!.trim().toLowerCase();
    final number = match.group(2)!.trim();
    return ('$label $number', match.group(0)!.trim());
  }

  /// First (fieldIndex, value) whose name matches a section pattern and whose
  /// value is non-empty, or null. The index lets [resolve] exclude that field
  /// from the unit lookup so one field never serves two levels.
  (int, String)? _sectionFromField(AnkiNote note, AnkiNotetype notetype) {
    for (var i = 0; i < notetype.fieldNames.length; i++) {
      final name = notetype.fieldNames[i].toLowerCase();
      if (sectionFieldPatterns.any(name.contains) && i < note.fields.length) {
        final value = _stripHtml(note.fields[i]).trim();
        if (value.isNotEmpty) return (i, value);
      }
    }
    return null;
  }

  String? _fromField(
    AnkiNote note,
    AnkiNotetype notetype,
    List<String> patterns, {
    int skipIndex = -1,
  }) {
    for (var i = 0; i < notetype.fieldNames.length; i++) {
      if (i == skipIndex) continue;
      final name = notetype.fieldNames[i].toLowerCase();
      if (patterns.any(name.contains) && i < note.fields.length) {
        final value = _stripHtml(note.fields[i]).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _fromTag(String tags, List<String> prefixes) {
    if (tags.isEmpty) return null;
    for (final raw in tags.split(' ')) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      for (final p in prefixes) {
        if (lower.startsWith(p)) {
          final value = t.substring(p.length).trim();
          if (value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }

  // Minimal HTML strip so a field value like "<b>2</b>" becomes "2". Reuses
  // the same substitutions as AnkiCardAdapter for consistency.
  static String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>'), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}

/// Where a resolved section key came from, in the plan's evidence priority
/// order (1 highest). The safety chunk fallback lives in the assembler and
/// must never be presented as "smart" grouping.
enum AnkiSectionEvidence {
  explicitField,
  explicitTag,
  deckHierarchy,
  unitPrefix,
}

/// Resolved placement for a single Anki card. `null` keys mean "no metadata
/// - use the deck-name + chunk fallback". [sectionKey]/[sectionEvidence]/
/// [sectionConfidence] are only populated on the Section-Beta path
/// ([resolve] with `sectionBeta: true`); the default path keeps the
/// historical behavior where section/chapter fields fold into units.
class AnkiCardOrganization {
  final String? sectionKey;
  final String? unitKey;
  final String? lessonKey;
  final AnkiSectionEvidence sectionEvidence;
  final double sectionConfidence;

  const AnkiCardOrganization({
    this.sectionKey,
    this.unitKey,
    this.lessonKey,
    this.sectionEvidence = AnkiSectionEvidence.deckHierarchy,
    this.sectionConfidence = 0,
  });

  bool get hasAny => unitKey != null || lessonKey != null || sectionKey != null;
}

/// Aggregate of detected organization across a collection (for the wizard).
class AnkiOrganizationPreview {
  final int resolvedCardCount;
  final int unitCount;
  final int lessonCount;
  final List<String> unitNames;
  final List<String> lessonNames;

  /// Section-Beta detections: distinct semantic section keys, how many cards
  /// resolved to one, and how many sections each evidence kind supplied.
  final List<String> sectionNames;
  final int sectionResolvedCardCount;
  final Map<AnkiSectionEvidence, int> sectionEvidenceCounts;

  const AnkiOrganizationPreview({
    required this.resolvedCardCount,
    required this.unitCount,
    required this.lessonCount,
    required this.unitNames,
    required this.lessonNames,
    this.sectionNames = const [],
    this.sectionResolvedCardCount = 0,
    this.sectionEvidenceCounts = const {},
  });

  bool get hasAny => unitCount > 0 || lessonCount > 0 || sectionNames.isNotEmpty;

  /// Human-readable section summary for the wizard, e.g. "3 个（字段 2，标签 1）".
  String get sectionCountLabel {
    final parts = <String>[];
    for (final e in AnkiSectionEvidence.values) {
      final count = sectionEvidenceCounts[e];
      if (count != null && count > 0) parts.add('${e.label} $count');
    }
    final detail = parts.isEmpty ? '' : '（${parts.join('，')}）';
    return '${sectionNames.length} 个$detail';
  }

  /// Warn when every detected section rests only on Unit-name prefixes —
  /// weaker evidence the user should double-check before importing.
  String? get lowConfidenceSectionHint {
    if (sectionNames.isEmpty) return null;
    final strong = sectionEvidenceCounts.entries
        .where((e) =>
            e.key != AnkiSectionEvidence.unitPrefix &&
            e.key != AnkiSectionEvidence.deckHierarchy)
        .fold<int>(0, (s, e) => s + e.value);
    if (strong > 0) return null;
    return 'Section 仅由 Unit 名称前缀推断，置信度较低，导入前请检查预览';
  }
}

extension AnkiSectionEvidenceLabel on AnkiSectionEvidence {
  String get label {
    switch (this) {
      case AnkiSectionEvidence.explicitField:
        return '字段';
      case AnkiSectionEvidence.explicitTag:
        return '标签';
      case AnkiSectionEvidence.deckHierarchy:
        return '牌组层级';
      case AnkiSectionEvidence.unitPrefix:
        return 'Unit 前缀';
    }
  }
}
