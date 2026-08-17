/// Single HTTP Range parser. Multi-range is rejected with 416.
class OfficialAnkiHttpRange {
  const OfficialAnkiHttpRange._({
    required this.satisfiable,
    required this.start,
    required this.end,
    required this.length,
    required this.status,
  });

  factory OfficialAnkiHttpRange.unsatisfiable(int length) => OfficialAnkiHttpRange._(
        satisfiable: false,
        start: 0,
        end: -1,
        length: length,
        status: 416,
      );

  factory OfficialAnkiHttpRange.full(int length) => OfficialAnkiHttpRange._(
        satisfiable: true,
        start: 0,
        end: length <= 0 ? -1 : length - 1,
        length: length,
        status: 200,
      );

  final bool satisfiable;
  final int start;
  final int end;
  final int length;
  final int status;

  int get contentLength =>
      satisfiable && end >= start ? end - start + 1 : 0;

  String get contentRange =>
      satisfiable ? 'bytes $start-$end/$length' : 'bytes */$length';

  static OfficialAnkiHttpRange parse(String? header, int length) {
    if (header == null || header.trim().isEmpty) {
      return OfficialAnkiHttpRange.full(length);
    }
    final trimmed = header.trim();
    if (!trimmed.toLowerCase().startsWith('bytes=')) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    final spec = trimmed.substring(6).trim();
    if (spec.isEmpty || spec.contains(',')) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    final dash = spec.indexOf('-');
    if (dash < 0) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    final left = spec.substring(0, dash).trim();
    final right = spec.substring(dash + 1).trim();
    if (length <= 0) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    if (left.isEmpty && right.isEmpty) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    if (left.isEmpty) {
      final suffix = int.tryParse(right);
      if (suffix == null || suffix <= 0) {
        return OfficialAnkiHttpRange.unsatisfiable(length);
      }
      final start = length > suffix ? length - suffix : 0;
      return OfficialAnkiHttpRange._(
        satisfiable: true,
        start: start,
        end: length - 1,
        length: length,
        status: 206,
      );
    }
    final start = int.tryParse(left);
    if (start == null || start < 0 || start >= length) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    final end = right.isEmpty
        ? length - 1
        : int.tryParse(right);
    if (end == null || end < start) {
      return OfficialAnkiHttpRange.unsatisfiable(length);
    }
    final clampedEnd = end >= length ? length - 1 : end;
    return OfficialAnkiHttpRange._(
      satisfiable: true,
      start: start,
      end: clampedEnd,
      length: length,
      status: 206,
    );
  }

  List<int> slice(List<int> bytes) {
    if (!satisfiable || bytes.length != length) {
      return const <int>[];
    }
    if (end < start) return const <int>[];
    return bytes.sublist(start, end + 1);
  }
}
