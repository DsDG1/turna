/// Strongly-typed identity for one Anki card.
///
/// UI, session, and renderer layers must not infer backend from string
/// prefixes. Legacy string IDs are parsed only at adapter boundaries.
enum AnkiBackendKind {
  official,
  localCanonical,
  legacyTurna,
}

class CanonicalCardKey {
  const CanonicalCardKey({
    required this.backend,
    required this.profileId,
    required this.sourceId,
    required this.cardId,
  });

  final AnkiBackendKind backend;
  final String profileId;
  final String sourceId;
  final int cardId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalCardKey &&
          backend == other.backend &&
          profileId == other.profileId &&
          sourceId == other.sourceId &&
          cardId == other.cardId;

  @override
  int get hashCode => Object.hash(backend, profileId, sourceId, cardId);

  @override
  String toString() =>
      'CanonicalCardKey(${backend.name}, profile=$profileId, source=$sourceId, card=$cardId)';
}

class CanonicalTemplateRef {
  const CanonicalTemplateRef({
    required this.notetypeId,
    required this.ordinal,
    this.fingerprint = '',
  });

  final int notetypeId;
  final int ordinal;
  final String fingerprint;
}

class CanonicalFieldValue {
  const CanonicalFieldValue({
    required this.name,
    required this.value,
    this.index = 0,
  });

  final String name;
  final String value;
  final int index;
}

class CanonicalMediaRef {
  const CanonicalMediaRef({
    required this.filename,
    this.kind = CanonicalMediaKind.other,
  });

  final String filename;
  final CanonicalMediaKind kind;
}

enum CanonicalMediaKind { audio, image, other }

class CanonicalCard {
  const CanonicalCard({
    required this.key,
    required this.noteId,
    required this.noteGuid,
    required this.templateOrd,
    required this.deckId,
    required this.sourceFingerprint,
    required this.template,
    this.fields = const [],
    this.media = const [],
  });

  final CanonicalCardKey key;
  final int noteId;
  final String noteGuid;
  final int templateOrd;
  final int deckId;
  final String sourceFingerprint;
  final CanonicalTemplateRef template;
  final List<CanonicalFieldValue> fields;
  final List<CanonicalMediaRef> media;
}

/// Parses legacy/product string IDs once at an adapter boundary.
///
/// Production session and UI code must not call this. Tests assert that
/// [CanonicalCardKey] itself contains no prefix inference.
class CanonicalCardKeyAdapter {
  CanonicalCardKeyAdapter._();

  static CanonicalCardKey fromOfficial({
    required String profileId,
    required String sourceId,
    required int cardId,
  }) {
    return CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: profileId,
      sourceId: sourceId,
      cardId: cardId,
    );
  }

  static CanonicalCardKey fromLegacyImport({
    required String profileId,
    required String importId,
    required int cardId,
  }) {
    return CanonicalCardKey(
      backend: AnkiBackendKind.legacyTurna,
      profileId: profileId,
      sourceId: importId,
      cardId: cardId,
    );
  }

  /// One-shot parse of a stored word id such as `anki-<import>-c<cardId>`
  /// or `official-anki-<source>-c<cardId>`. Returns null when the string
  /// is not a known Anki card id.
  static CanonicalCardKey? tryParseStoredWordId({
    required String profileId,
    required String rawId,
  }) {
    final official = RegExp(r'^official-anki-([^-]+(?:-[^-]+)*)-c(\d+)$');
    final officialMatch = official.firstMatch(rawId);
    if (officialMatch != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: officialMatch.group(1)!,
        cardId: int.parse(officialMatch.group(2)!),
      );
    }
    final legacy = RegExp(r'^anki-([^-]+(?:-[^-]+)*)-c(\d+)$');
    final legacyMatch = legacy.firstMatch(rawId);
    if (legacyMatch != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: profileId,
        sourceId: legacyMatch.group(1)!,
        cardId: int.parse(legacyMatch.group(2)!),
      );
    }
    return null;
  }
}
