// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';

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

  /// Resolve the unit/lesson keys for [note] given its notetype definition.
  /// Either may be `null` when the card carries no such metadata.
  AnkiCardOrganization resolve(AnkiNote note, AnkiNotetype notetype) {
    final unitKey = _fromField(note, notetype, unitFieldPatterns) ??
        _fromTag(note.tags, unitTagPrefixes);
    final lessonKey = _fromField(note, notetype, lessonFieldPatterns) ??
        _fromTag(note.tags, lessonTagPrefixes);
    return AnkiCardOrganization(unitKey: unitKey, lessonKey: lessonKey);
  }

  /// A preview summary: how many distinct units/lessons the resolver detects
  /// across a collection (for the import wizard's organization card).
  AnkiOrganizationPreview preview({
    required List<AnkiNote> notes,
    required Map<int, AnkiNotetype> notetypes,
  }) {
    final units = <String>{};
    final lessons = <String>{};
    var resolved = 0;
    for (final note in notes) {
      final nt = notetypes[note.mid];
      if (nt == null) continue;
      final org = resolve(note, nt);
      if (org.unitKey != null || org.lessonKey != null) resolved++;
      if (org.unitKey != null) units.add(org.unitKey!);
      if (org.lessonKey != null) lessons.add(org.lessonKey!);
    }
    return AnkiOrganizationPreview(
      resolvedCardCount: resolved,
      unitCount: units.length,
      lessonCount: lessons.length,
      unitNames: units.toList()..sort(),
      lessonNames: lessons.toList()..sort(),
    );
  }

  String? _fromField(
    AnkiNote note,
    AnkiNotetype notetype,
    List<String> patterns,
  ) {
    for (var i = 0; i < notetype.fieldNames.length; i++) {
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

/// Resolved placement for a single Anki card. `null` means "no metadata -
/// use the deck-name + chunk fallback".
class AnkiCardOrganization {
  final String? unitKey;
  final String? lessonKey;

  const AnkiCardOrganization({this.unitKey, this.lessonKey});

  bool get hasAny => unitKey != null || lessonKey != null;
}

/// Aggregate of detected organization across a collection (for the wizard).
class AnkiOrganizationPreview {
  final int resolvedCardCount;
  final int unitCount;
  final int lessonCount;
  final List<String> unitNames;
  final List<String> lessonNames;

  const AnkiOrganizationPreview({
    required this.resolvedCardCount,
    required this.unitCount,
    required this.lessonCount,
    required this.unitNames,
    required this.lessonNames,
  });

  bool get hasAny => unitCount > 0 || lessonCount > 0;
}
