enum PosTag {
  noun,
  verb,
  adjective,
  adverb,
  pronoun,
  preposition,
  conjunction,
  interjection,
  numeral,
  determiner;

  /// Parse a POS string from course JSON into a [PosTag], or `null` when
  /// the value is missing / unknown (POS is optional; old assets have none).
  /// Never throws — the closed set must match the GUI mirror
  /// (`tool/gui/src/backend/experience/pos_constants.py`).
  static PosTag? parse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    for (final v in PosTag.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Short Chinese label for display (mirrors GUI `POS_LABELS`).
String posTagLabel(PosTag? pos) {
  if (pos == null) return '';
  const labels = <PosTag, String>{
    PosTag.noun: '名词',
    PosTag.verb: '动词',
    PosTag.adjective: '形容词',
    PosTag.adverb: '副词',
    PosTag.pronoun: '代词',
    PosTag.preposition: '介词',
    PosTag.conjunction: '连词',
    PosTag.interjection: '叹词',
    PosTag.numeral: '数词',
    PosTag.determiner: '限定词',
  };
  return labels[pos] ?? pos.name;
}