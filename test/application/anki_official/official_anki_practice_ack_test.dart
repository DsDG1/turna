import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import '../../support/official_anki_practice_review_surface_fixture.dart';
import '../../support/official_anki_review_fixture.dart';

import 'official_anki_reviewer_behavior_test.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

void main() {
  testWidgets('practice surface question frame enables show-answer',
      (tester) async {
    final harness = await _mount(tester);
    expect(find.byType(OfficialAnkiPracticeReviewSurface), findsOneWidget);
    expect(harness.presenter.hasQuestionPresentAck, isTrue);
    final show = tester.widget<FilledButton>(
      find.byKey(const Key('official-review-show-answer')),
    );
    expect(show.onPressed, isNotNull);
  });

  testWidgets('show-answer button and card tap share the presenter reveal',
      (tester) async {
    final harness = await _mount(tester);
    final generationBefore = harness.presenter.presentGeneration;
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    await tester.pump();
    expect(harness.presenter.currentSide, 'answer');
    expect(harness.presenter.hasAnswerPresentAck, isTrue);
    expect(harness.session.phase, OfficialReviewPhase.showingAnswer);
    expect(find.byKey(const Key('official-review-show-answer')), findsNothing);
    expect(harness.presenter.presentGeneration, generationBefore + 1);

    await tester.tap(find.byType(OfficialAnkiPracticeReviewSurface));
    await tester.pump();
    expect(harness.presenter.presentGeneration, generationBefore + 1);
  });

  testWidgets('rating is enabled only after the answer receipt', (tester) async {
    await _mount(tester);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    await tester.pump();
    final good = tester.widget<FilledButton>(
      find.byKey(const Key('official-review-good')),
    );
    expect(good.onPressed, isNotNull);
  });
}

Future<_AckHarness> _mount(WidgetTester tester) async {
  final fake = FakeOfficialAnkiEngine();
  fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
  final session = OfficialReviewSession(engine: fake, flags: _flags);
  await session.openDeck(1);
  final paths = OfficialAnkiPaths(
    profileId: 'profile-practice-ack',
    profileRoot: Directory.systemTemp.createTempSync('turna-practice-ack-'),
  );
  addTearDown(() {
    if (paths.profileRoot.existsSync()) {
      paths.profileRoot.deleteSync(recursive: true);
    }
  });
  final facade = OfficialAnkiRenderFacade(
    info: await fake.engineInfo(),
    engine: fake,
  );
  final root = Directory.systemTemp.createTempSync('turna-practice-presenter-');
  addTearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
  final presenter = OfficialAnkiReviewerController(
    facade: facade,
    av: OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: RecordingOfficialAnkiAvPlayer(),
    ),
    typed: OfficialAnkiTypedAnswerController(facade),
  );
  addTearDown(presenter.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: OfficialAnkiReviewPage(
        engine: fake,
        paths: paths,
        flags: _flags,
        session: session,
        presenter: presenter,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _AckHarness(session: session, presenter: presenter);
}

class _AckHarness {
  const _AckHarness({
    required this.session,
    required this.presenter,
  });

  final OfficialReviewSession session;
  final OfficialAnkiReviewerController presenter;
}
