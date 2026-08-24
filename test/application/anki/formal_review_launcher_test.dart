import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  const launcher = FormalReviewLauncher();

  group('FormalReviewLauncher', () {
    test('every production entry maps to the same session host', () {
      final snapshot = launcher.productionHostSnapshot(
        officialOwner: false,
        schedulerRuntimeAvailable: true,
      );
      expect(snapshot.length, FormalReviewEntryKind.values.length);
      for (final entry in FormalReviewEntryKind.values) {
        expect(
          snapshot[entry],
          FormalReviewLauncher.sessionRouteName,
          reason: '$entry must not pick a different-semantics page',
        );
      }
      expect(
        snapshot.values.toSet(),
        {FormalReviewLaunchDecision.sessionRouteName},
      );
    });

    test('Official-unavailable is fail-closed for every entry', () {
      final snapshot = launcher.productionHostSnapshot(
        officialOwner: true,
        schedulerRuntimeAvailable: false,
      );
      expect(snapshot.values.toSet(), {'failClosed'});
      final decision = launcher.resolve(
        entry: FormalReviewEntryKind.playHub,
        courseId: 'anki',
        officialOwner: true,
        schedulerRuntimeAvailable: false,
      );
      expect(decision.host, FormalReviewHostKind.failClosed);
      expect(decision.isFailClosed, isTrue);
    });

    test('Official-capable still uses the shared session host', () {
      final decision = launcher.resolve(
        entry: FormalReviewEntryKind.courseReview,
        courseId: 'anki-src',
        sectionId: 'sec',
        officialOwner: true,
        schedulerRuntimeAvailable: true,
      );
      expect(decision.host, FormalReviewHostKind.sharedSession);
      expect(decision.scope.courseId, 'anki-src');
      expect(decision.scope.sectionId, 'sec');
    });

    test('production entries only change study scope', () {
      final play = launcher.resolve(
        entry: FormalReviewEntryKind.playHub,
        courseId: 'anki',
        officialOwner: false,
        schedulerRuntimeAvailable: true,
      );
      final stats = launcher.resolve(
        entry: FormalReviewEntryKind.statsContinue,
        courseId: 'anki',
        sectionId: 'anki-import-1',
        officialOwner: false,
        schedulerRuntimeAvailable: true,
      );
      expect(play.host, stats.host);
      expect(play.scope.sectionId, isNull);
      expect(stats.scope.sectionId, 'anki-import-1');
    });

    testWidgets('open() uses FormalReviewNavigator shared session',
        (tester) async {
      String? openedRoute;
      String? openedSection;
      FormalReviewNavigator.debugOpenSession = (context, sectionId) async {
        openedRoute = FormalReviewLauncher.sessionRouteName;
        openedSection = sectionId;
      };
      addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  const FormalReviewLauncher().open(
                    context,
                    entry: FormalReviewEntryKind.playHub,
                    courseId: 'anki',
                    sectionId: 'anki-sec-1',
                    officialOwner: false,
                    schedulerRuntimeAvailable: true,
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(openedRoute, FormalReviewLauncher.sessionRouteName);
      expect(openedSection, 'anki-sec-1');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('open() fail-closed does not open a session', (tester) async {
      var opened = false;
      FormalReviewNavigator.debugOpenSession = (context, sectionId) async {
        opened = true;
      };
      addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  const FormalReviewLauncher().open(
                    context,
                    entry: FormalReviewEntryKind.statsContinue,
                    courseId: 'anki',
                    officialOwner: true,
                    schedulerRuntimeAvailable: false,
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(opened, isFalse);
      expect(
        find.text(
          AppStrings.officialAnkiError(FormalReviewLauncher.failClosedMessage),
        ),
        findsOneWidget,
      );
    });

    test('production entries call FormalReviewLauncher.open and shared session',
        () {
      const paths = {
        'lib/views/play/play_hub_screen.dart',
        'lib/views/profile/widgets/profile_quick_actions.dart',
        'lib/views/anki/anki_review_screen.dart',
        'lib/views/anki/anki_card_browser_page.dart',
      };
      for (final path in paths) {
        final text = File(path).readAsStringSync();
        expect(text.contains('FormalReviewLauncher().open'), isTrue, reason: path);
        expect(text.contains('OfficialAnkiReviewPage'), isFalse, reason: path);
        expect(
          text.contains('AnkiReviewRoute()') &&
              path.contains('play_hub_screen'),
          isFalse,
          reason: 'Play Hub must not stay on the deck-list route',
        );
      }
      final session =
          File('lib/views/anki/anki_review_session_page.dart').readAsStringSync();
      expect(session.contains('StudySessionController'), isTrue);
      expect(session.contains('ReviewSessionController'), isFalse);
      expect(session.contains('OfficialAnkiReviewPage'), isFalse);
      final gate =
          File('lib/views/anki/anki_official_review_gate.dart').readAsStringSync();
      expect(gate.contains('official_anki_review_page.dart'), isFalse);
      expect(gate.contains('Navigator.of(context).push'), isFalse);
    });

    test('production review UI does not pass raw quality or reclassify', () {
      const paths = [
        'lib/views/play/play_hub_screen.dart',
        'lib/views/profile/widgets/profile_quick_actions.dart',
        'lib/views/anki/anki_review_screen.dart',
        'lib/views/anki/anki_review_session_page.dart',
        'lib/views/anki/anki_card_browser_page.dart',
        'lib/views/anki_official/official_anki_review_page.dart',
        'lib/views/anki_official/official_anki_practice_review_surface.dart',
      ];
      for (final path in paths) {
        final text = File(path).readAsStringSync();
        expect(
          text.contains('FormalReviewLauncher') ||
              path.contains('official_anki_review_page') ||
              path.contains('practice_review_surface'),
          isTrue,
          reason: '$path should go through FormalReviewLauncher or be the host surface',
        );
        expect(
          text.contains(
            "package:turna/application/anki_practice/card_classifier.dart",
          ),
          isFalse,
          reason: '$path runtime-reclassifies on the formal path',
        );
        expect(text.contains('reviewHard'), isFalse, reason: path);
        expect(text.contains('reviewEasy'), isFalse, reason: path);
      }
    });
  });
}
