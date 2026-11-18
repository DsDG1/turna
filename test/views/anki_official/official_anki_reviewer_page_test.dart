import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';

class _SilentAvPlayer implements OfficialAnkiAvPlayer {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> playFile(String path) async {}

  @override
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices = const <String>[],
    double? speed,
    List<String> otherArgs = const <String>[],
  }) async =>
      true;

  @override
  Future<void> stop() async {}
}

class _FlakyBootController extends OfficialAnkiReviewerController {
  _FlakyBootController({
    required super.facade,
    required super.av,
    required super.typed,
  });

  int attempts = 0;
  bool alwaysFail = false;

  @override
  Future<void> loadAndShowQuestion(int cardId) async {
    attempts++;
    if (alwaysFail || attempts == 1) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.renderFailed,
        messageKey: 'official_anki.render_failed',
      );
    }
    await super.loadAndShowQuestion(cardId);
  }
}

void main() {
  late OfficialAnkiFeatureFlags savedFlags;
  late Directory root;
  late OfficialAnkiPaths paths;
  late FakeOfficialAnkiEngine engine;
  late _FlakyBootController controller;

  setUp(() async {
    savedFlags = OfficialAnkiFeatureFlags.current;
    OfficialAnkiFeatureFlags.current =
        OfficialAnkiFeatureFlags.productionAndroid;
    root = Directory.systemTemp.createTempSync('turna-reviewer-page-');
    paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    engine = FakeOfficialAnkiEngine()
      ..seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final facade = OfficialAnkiRenderFacade(
      info: await engine.engineInfo(),
      engine: engine,
    );
    controller = _FlakyBootController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(paths.mediaFolder),
        player: _SilentAvPlayer(),
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
  });

  tearDown(() async {
    await controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
    OfficialAnkiFeatureFlags.current = savedFlags;
  });

  testWidgets('boot error offers retry and recovers to reviewer stage',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiReviewerPage(
          sourceId: 'source-test',
          cardId: 1,
          paths: paths,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('official-review-stage')), findsNothing);
    expect(find.byType(OfficialAnkiReviewerErrorView), findsOneWidget);
    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsOneWidget);
    expect(find.text(AppStrings.commonBack), findsOneWidget);

    await tester.tap(find.text(AppStrings.officialAnkiRetryCurrentSide));
    await tester.pumpAndSettle();

    expect(controller.attempts, 2);
    expect(find.byKey(const Key('official-review-stage')), findsOneWidget);
  });

  testWidgets('boot error back button pops the route', (tester) async {
    controller.alwaysFail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OfficialAnkiReviewerPage(
                        sourceId: 'source-test',
                        cardId: 1,
                        paths: paths,
                        controller: controller,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialAnkiReviewerErrorView), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonBack));
    await tester.pumpAndSettle();

    expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
