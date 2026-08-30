// Diagnostics release guard tests (plan 34 R8-1 / OS-23): internal
// Official-Anki routes are unreachable in release builds — deep links are
// redirected, and diagnostics builds must opt in explicitly.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/routing/diagnostics_release_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every internal Official surface is in the guarded set', () {
    expect(
      DiagnosticsReleaseGuard.guardedRouteNames,
      containsAll([
        // OfficialAnkiInternalRoute was deleted with the fixture pilot
        // scaffold (doc 38 P1-A); its route and guard entry are gone.
        // OfficialAnkiReviewRoute (doc 39 P1-A) and
        // OfficialAnkiMigrationPreviewRoute (doc 39 P1-B) likewise.
        'OfficialAnkiMappingRoute',
        'OfficialAnkiReviewerRoute',
        'OfficialAnkiSourceManagementRoute',
      ]),
    );
  });

  test('product routes are never guarded', () {
    expect(
      DiagnosticsReleaseGuard.guards('HomeRoute'),
      isFalse,
    );
    expect(
      DiagnosticsReleaseGuard.guards('AnkiImportRoute'),
      isFalse,
    );
    expect(
      DiagnosticsReleaseGuard.guards('AnkiCardBrowserRoute'),
      isFalse,
    );
    expect(
      DiagnosticsReleaseGuard.guards('AnkiDeckStatsRoute'),
      isFalse,
    );
    expect(
      DiagnosticsReleaseGuard.guards('AnkiReviewSessionRoute'),
      isFalse,
    );
  });

  test('in a release-blocked build, guarded routes are all blocked', () {
    // The guard's static predicates are pure functions of the guarded set
    // and the diagnostics flag; exercising them with the built-in set keeps
    // the contract honest even though the flag itself is a compile-time
    // constant in real builds.
    for (final name in DiagnosticsReleaseGuard.guardedRouteNames) {
      expect(
        DiagnosticsReleaseGuard.guards(name),
        DiagnosticsReleaseGuard.isReleaseBlocked,
        reason: '$name must follow the release-blocked state',
      );
    }
  });

  test('diagnostics opt-in disables the block', () {
    // The dart-define cannot be flipped at runtime; the invariant instead:
    // diagnosticsEnabled implies isReleaseBlocked is false.
    expect(
      DiagnosticsReleaseGuard.diagnosticsEnabled ==
          !DiagnosticsReleaseGuard.isReleaseBlocked,
      isTrue,
    );
  });
}
