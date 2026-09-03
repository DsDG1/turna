import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';

/// Locks the hand-maintained numeric-status table (and the name-based table)
/// against the Rust `STATUS_*` constants. Both tables drifted from the Rust
/// side before (10 of 31 statuses fell through to `unknown`, misclassifying
/// recoverable scheduler states as fatal), so this test parses the pinned
/// bridge source instead of re-declaring the numbers a third time.
void main() {
  final engineRs = File(
    'native/turna_anki_core/bridge/src/engine.rs',
  );

  test('every STATUS_* constant maps to a concrete Dart error code', () {
    expect(engineRs.existsSync(), isTrue, reason: 'bridge source must exist');
    final constants = _statusConstants(engineRs.readAsStringSync());
    expect(constants.length, greaterThanOrEqualTo(29));

    for (final entry in constants.entries) {
      final name = entry.key;
      final status = entry.value;
      final byStatus = officialAnkiErrorCodeFromStatus(status);
      expect(
        byStatus,
        isNot(OfficialAnkiErrorCode.unknown),
        reason: 'STATUS_$name ($status) has no numeric mapping',
      );
      final byName = officialAnkiErrorCodeFromName(name);
      expect(
        byName,
        byStatus,
        reason: 'STATUS_$name ($status): name-based and status-based '
            'mappings disagree ($byName vs $byStatus)',
      );
    }
  });

  test('status codes are unique and outside the reserved 1-9 range', () {
    final constants =
        _statusConstants(engineRs.readAsStringSync()).values.toList();
    expect(constants.toSet().length, constants.length);
    for (final status in constants) {
      expect(status, greaterThanOrEqualTo(10));
    }
  });
}

Map<String, int> _statusConstants(String source) {
  final out = <String, int>{};
  final pattern = RegExp(r'STATUS_([A-Z_]+):\s*i32\s*=\s*(\d+)\s*;');
  for (final match in pattern.allMatches(source)) {
    final name = match.group(1)!;
    final value = int.parse(match.group(2)!);
    if (name == 'OK') continue;
    out[name] = value;
  }
  return out;
}
