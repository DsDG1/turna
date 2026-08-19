import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_review_gate_decision.dart';

void main() {
  testWidgets('p5d_start_review_pushes_official_page_when_cutover_official', (tester) async {
    final decision = decideOfficialReviewGate(
      cutoverEnabled: true,
      routedEngine: AnkiEngineKind.official,
      catalogPresent: true,
      hasReviewTarget: true,
      canOpenOfficialReview: true,
    );
    expect(decision, OfficialAnkiReviewGateDecision.openOfficial);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('go-review'),
              onPressed: () async {
                if (decision == OfficialAnkiReviewGateDecision.openOfficial) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const OfficialAnkiReviewPageStub()),
                  );
                } else if (decision == OfficialAnkiReviewGateDecision.failClosed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('official_anki.review_fail_closed')),
                  );
                }
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('official-review-stub')), findsOneWidget);
    expect(find.byKey(const Key('legacy-session-stub')), findsNothing);
  });

  testWidgets('p5d_start_review_fail_closed_does_not_push_legacy_session', (tester) async {
    final decision = decideOfficialReviewGate(
      cutoverEnabled: true,
      routedEngine: AnkiEngineKind.official,
      catalogPresent: true,
      hasReviewTarget: false,
      canOpenOfficialReview: true,
    );
    expect(decision, OfficialAnkiReviewGateDecision.failClosed);

    var legacyPushed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const Key('go-review-fail'),
              onPressed: () async {
                if (decision == OfficialAnkiReviewGateDecision.openOfficial) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const OfficialAnkiReviewPageStub()),
                  );
                } else if (decision == OfficialAnkiReviewGateDecision.failClosed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('official_anki.review_fail_closed')),
                  );
                } else {
                  legacyPushed = true;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LegacySessionStub()),
                  );
                }
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go-review-fail')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(legacyPushed, isFalse);
    expect(find.byKey(const Key('legacy-session-stub')), findsNothing);
    expect(find.text('official_anki.review_fail_closed'), findsOneWidget);
  });
}

class OfficialAnkiReviewPageStub extends StatelessWidget {
  const OfficialAnkiReviewPageStub({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('official', key: Key('official-review-stub')));
  }
}

class LegacySessionStub extends StatelessWidget {
  const LegacySessionStub({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('legacy', key: Key('legacy-session-stub')));
  }
}
