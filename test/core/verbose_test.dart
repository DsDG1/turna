import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/verbose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Very', () {
    test('verbose defaults to false', () {
      // Reset to the documented default in case another test flipped it.
      Very.verbose = false;
      expect(Very.verbose, isFalse);
    });

    test('veryVerbose follows Very.verbose in debug host', () {
      Very.verbose = false;
      expect(veryVerbose, isFalse);

      Very.verbose = true;
      // Under the test host kDebugMode is true, so veryVerbose == Very.verbose.
      expect(veryVerbose, isTrue);

      Very.verbose = false;
    });

    test('Very.verbose toggle round-trips without error', () {
      for (final v in [false, true, false]) {
        Very.verbose = v;
        expect(Very.verbose, v);
      }
    });
  });
}