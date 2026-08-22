import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipped card-frame and reviewer scripts pass the five protocol cases', () async {
    final script = File('test/application/anki_official/js/card_frame_protocol_test.mjs');
    expect(script.existsSync(), isTrue);
    final result = await Process.run(
      'node',
      [script.path],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(result.stdout.toString(), contains('all protocol cases passed'));
  });
}
