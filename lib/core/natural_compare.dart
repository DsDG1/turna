/// Human-ordered string comparison for course-tree names.
///
/// Digit runs compare numerically and text compares case-insensitively, so
/// "Unit 2" sorts before "Unit 10" while "abc" and "ABC" order equally until
/// the tiebreak. When both sides match under those rules the raw code-unit
/// compare decides, keeping the result a deterministic total order regardless
/// of locale.
int naturalCompare(String a, String b) {
  var ai = 0;
  var bi = 0;
  while (ai < a.length && bi < b.length) {
    final ac = a.codeUnitAt(ai);
    final bc = b.codeUnitAt(bi);
    if (_isDigit(ac) && _isDigit(bc)) {
      final aEnd = _digitRunEnd(a, ai);
      final bEnd = _digitRunEnd(b, bi);
      final numeric =
          _compareDigitRuns(a, ai, aEnd, b, bi, bEnd);
      if (numeric != 0) return numeric;
      ai = aEnd;
      bi = bEnd;
      continue;
    }
    final text = _fold(ac).compareTo(_fold(bc));
    if (text != 0) return text;
    ai++;
    bi++;
  }
  if (ai < a.length) return 1;
  if (bi < b.length) return -1;
  return a.compareTo(b);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _digitRunEnd(String s, int start) {
  var end = start;
  while (end < s.length && _isDigit(s.codeUnitAt(end))) {
    end++;
  }
  return end;
}

/// Compares two digit runs by numeric value without parsing: strip leading
/// zeros, then shorter (i.e. smaller) runs sort first, equal-length runs
/// compare lexicographically. Overflow-free for arbitrarily long runs.
int _compareDigitRuns(String a, int aStart, int aEnd, String b, int bStart, int bEnd) {
  var ai = aStart;
  var bi = bStart;
  while (ai < aEnd - 1 && a.codeUnitAt(ai) == 0x30) {
    ai++;
  }
  while (bi < bEnd - 1 && b.codeUnitAt(bi) == 0x30) {
    bi++;
  }
  final aLen = aEnd - ai;
  final bLen = bEnd - bi;
  if (aLen != bLen) return aLen.compareTo(bLen);
  while (ai < aEnd) {
    final cmp = a.codeUnitAt(ai).compareTo(b.codeUnitAt(bi));
    if (cmp != 0) return cmp;
    ai++;
    bi++;
  }
  return 0;
}

/// ASCII-only case folding: non-ASCII code units compare by their raw value,
/// which keeps CJK deck names in a stable deterministic order.
int _fold(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit + 0x20;
  return codeUnit;
}
