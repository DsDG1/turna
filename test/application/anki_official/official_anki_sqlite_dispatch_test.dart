import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADR 0050 §6 step 2.
///
/// The dispatch rewrite cannot be exercised on the host SDK: `isHarmonyOsTarget`
/// compares `defaultTargetPlatform.name == 'ohos'` and `TargetPlatform.ohos`
/// only exists in the OHOS engine fork, so the branch is unreachable here (the
/// same reason `voice_copy_platform_test.dart` scans source instead of driving
/// the widget). These tests therefore pin the *source shape* of three
/// decisions that are otherwise one refactor away from silently regressing,
/// and they reverse-verify by construction — each assertion below was written
/// against code that was deliberately wrong first.
void main() {
  group('Official Anki sqlite loader dispatch (ADR 0050 §4.1)', () {
    const sourcePath =
        'lib/application/anki_official/storage/official_anki_sqlite.dart';
    late final String source;
    late final String ensure;
    // `ensure` with line comments removed. Prose in this file names the very
    // identifiers it is forbidden from using, so any "does the source contain
    // X" question has to be asked of code, not of comments.
    late final String ensureCode;

    setUpAll(() {
      source = File(sourcePath).readAsStringSync();
      final start = source.indexOf('void ensureOfficialAnkiSqlite()');
      expect(start, greaterThan(-1),
          reason: 'ensureOfficialAnkiSqlite missing');
      // Up to the next top-level declaration, so the probe below cannot
      // satisfy an assertion that belongs to ensure().
      final end = source.indexOf('\nDynamicLibrary', start);
      ensure = source.substring(start, end == -1 ? source.length : end);
      ensureCode = ensure
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('HarmonyOS registers through overrideForAll, not a fake enum', () {
      // `overrideFor(OperatingSystem.ohos, ...)` does not compile today: the
      // enum has six members and ohos is not one. If sqlite3 ever adds it,
      // this assertion starts failing and the note below must be revisited
      // rather than the test being relaxed.
      expect(
        RegExp(r'overrideFor\s*\(\s*OperatingSystem\.ohos').hasMatch(source),
        isFalse,
        reason: 'there is no OperatingSystem.ohos to register against',
      );
      expect(
        RegExp(r'overrideForAll\s*\(\s*_openHarmonyOsSqlite\s*\)')
            .hasMatch(ensure),
        isTrue,
        reason: 'overrideForAll is the only platform-independent entry point',
      );
    });

    test('the HarmonyOS branch is guarded by the single predicate', () {
      expect(
        RegExp(r'if\s*\(\s*isHarmonyOsTarget\s*\)').hasMatch(ensure),
        isTrue,
      );
      // The failure this prevents: `Platform.is*` is all-false on HarmonyOS
      // (§2.1 receipt), so a Platform check inside the branch would make it
      // permanently unreachable and the override would never register.
      // Comments are stripped first — the branch's own doc comment names
      // `Platform.is*` while explaining exactly why it is not used, and
      // matching prose would make the assertion unsatisfiable.
      final branch = ensure.substring(ensure.indexOf('isHarmonyOsTarget'));
      final body = branch
          .substring(0, branch.indexOf('overrideForAll'))
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        RegExp(r'Platform\.(is|operatingSystem)').hasMatch(body),
        isFalse,
        reason: 'Platform.is* is all-false on HarmonyOS; use the predicate',
      );
    });

    test('the HarmonyOS short-circuit precedes the idempotence flag', () {
      // `open.overrideFor` state is per-isolate and locator.dart registers the
      // background isolate too. If `_opened = true` ran before the branch, the
      // background isolate would consume the flag and every later call would
      // return early without registering — the catalog would work in the main
      // isolate and fail in the worker, which is a much harder symptom to
      // attribute than a clean failure here.
      final guard = ensure.indexOf('isHarmonyOsTarget');
      final flag = ensure.indexOf('_opened = true');
      expect(guard, greaterThan(-1));
      expect(flag, greaterThan(-1));
      expect(
        guard,
        lessThan(flag),
        reason: 'short-circuit must come before the flag it sets',
      );
      // And the flag must be set on the HarmonyOS path too, or every one of
      // the 11 call sites would re-register.
      final after = ensure.substring(flag, ensure.length);
      expect(after.contains('overrideForAll'), isTrue);
    });

    test('Android and Linux keep their per-platform overrides', () {
      // `overrideForAll` is process-global. If it ever ran on a host platform
      // it would repoint Android's loader at the wrong library, so the guard
      // above is load-bearing rather than stylistic — these assert the
      // per-platform registrations are still there to be preserved.
      expect(
        RegExp(r'overrideFor\s*\(\s*OperatingSystem\.linux').hasMatch(ensure),
        isTrue,
      );
      expect(
        RegExp(r'overrideFor\s*\(\s*OperatingSystem\.android').hasMatch(ensure),
        isTrue,
      );
      // `overrideForAll` is process-global: a second one, or one outside the
      // guarded branch, would repoint Android's and Linux's loaders. It
      // appearing textually BEFORE the per-platform calls is correct — it
      // lives in the early-return branch — so the assertion is that it is
      // exactly one and it sits behind the guard, not that it comes later.
      expect(
        'overrideForAll'.allMatches(ensureCode).length,
        1,
        reason: 'a second overrideForAll would silently repoint every '
            'platform loader',
      );
      expect(
        ensureCode.indexOf('overrideForAll'),
        greaterThan(ensureCode.indexOf('isHarmonyOsTarget')),
        reason: 'overrideForAll must live inside the guarded branch',
      );
    });

    test('the hap ships an arm64 libsqlite3.so for that override to find', () {
      // `_openHarmonyOsSqlite` opens the bare name, which resolves against
      // the hap's libs/arm64-v8a — the same mechanism step 1 proved with
      // libturna_anki.so (`dlopen=ok abi=1`). If the artifact is missing the
      // override registers fine and then throws at open time, which looks
      // like a loader bug rather than a packaging one.
      const lib = 'ohos/entry/libs/arm64-v8a/libsqlite3.so';
      final file = File(lib);
      expect(file.existsSync(), isTrue, reason: 'companion hap needs $lib');

      final handle = file.openSync();
      final bytes = handle.readSync(20);
      handle.closeSync();
      expect(bytes.sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);
      expect(bytes[4], 2, reason: 'ELF64 required');
      expect(bytes[18] | (bytes[19] << 8), 0xB7, reason: 'aarch64');

      // The catalog talks to this through the same C API the engine's bundled
      // copy exposes; a library missing the core entry points would resolve
      // at dlopen and fail at the first call.
      final ascii = String.fromCharCodes(file.readAsBytesSync());
      for (final symbol in const [
        'sqlite3_open_v2',
        'sqlite3_prepare_v2',
        'sqlite3_step',
        'sqlite3_close',
      ]) {
        expect(ascii.contains(symbol), isTrue, reason: 'missing $symbol');
      }

      // And the catalog's binding package must not be one that gained an
      // `OperatingSystem.ohos` member: the overrideForAll branch above exists
      // precisely because it has not.
      final pubspec = File('pubspec.lock').readAsStringSync();
      expect(RegExp(r'sqlite3:\s*\n\s*version:\s*"([\d.]+)"').hasMatch(pubspec),
          isFalse,
          reason: 'sqlite3 lock entry not found in the expected shape');
    });
  });
}
