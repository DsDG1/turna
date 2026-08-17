import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

import 'official_anki_reviewer_behavior_test.dart';

void main() {
  Future<OfficialAnkiReviewerController> controllerWith({
    required OfficialAnkiAvPlayer player,
    required Directory root,
    OfficialAnkiRenderedCard? card,
  }) async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    fake.renders[1] = card ??
        OfficialAnkiRenderedCard(
          cardId: 1,
          questionHtml: 'Q',
          answerHtml: 'A',
          questionDisplayHtml: 'Q',
          answerDisplayHtml: 'A',
          css: '',
          questionAvTags: const [OfficialAnkiAvTag.sound('a.mp3')],
          answerAvTags: const [OfficialAnkiAvTag.sound('b.mp3')],
        );
    final info = await fake.engineInfo();
    final facade = OfficialAnkiRenderFacade(info: info, engine: fake);
    return OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(root),
        player: player,
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
  }

  test('DOM/renderComplete happens before that side autoplay', () async {
    final root = Directory.systemTemp.createTempSync('turna-ui-av-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    File('${root.path}/b.mp3').writeAsBytesSync([2]);
    final player = _HoldPlayPlayer();
    final controller = await controllerWith(player: player, root: root);
    await controller.loadCard(1);
    await controller.showAnswer();
    expect(controller.showingAnswer, isTrue);
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.rendering);
    expect(
      player.events.where((e) => e.startsWith('play:')),
      isEmpty,
      reason: 'flip must not wait for AV',
    );
    controller.onRenderComplete(
      generation: controller.presentGeneration,
      side: 'answer',
    );
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.visible);
    await player.started.future;
    expect(player.events, contains('play:${root.path}/b.mp3'));
    player.release.complete();
  });

  test('old-generation autoplay completion does not mutate current UI', () async {
    final root = Directory.systemTemp.createTempSync('turna-ui-stale-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    File('${root.path}/b.mp3').writeAsBytesSync([2]);
    final player = RecordingOfficialAnkiAvPlayer();
    final controller = await controllerWith(player: player, root: root);
    await controller.loadCard(1);
    await controller.showQuestion();
    final staleGeneration = controller.presentGeneration;
    await controller.showAnswer();
    controller.onRenderComplete(generation: staleGeneration, side: 'question');
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.rendering);
    expect(controller.showingAnswer, isTrue);
    controller.onRenderComplete(
      generation: controller.presentGeneration,
      side: 'answer',
    );
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.visible);
    expect(controller.ui.side, 'answer');
  });

  test('replay sets busy/disabled and missing media stays visible', () async {
    final root = Directory.systemTemp.createTempSync('turna-ui-replay-');
    addTearDown(() => root.deleteSync(recursive: true));
    final player = _HoldPlayPlayer();
    final controller = await controllerWith(
      player: player,
      root: root,
      card: const OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: 'Q',
        answerHtml: 'A',
        questionDisplayHtml: 'Q',
        answerDisplayHtml: 'A',
        css: '',
        questionAvTags: [OfficialAnkiAvTag.sound('missing.mp3')],
      ),
    );
    await controller.loadCard(1);
    await controller.showQuestion();
    controller.onRenderComplete(
      generation: controller.presentGeneration,
      side: 'question',
    );
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.visible);
    expect(controller.avHint, contains('media_missing'));
    final replay = controller.replay();
    expect(controller.replayBusy, isTrue);
    player.release.complete();
    await replay;
    expect(controller.replayBusy, isFalse);
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.visible);
  });

  test('listed render codes offer retry-current-side and back', () async {
    final root = Directory.systemTemp.createTempSync('turna-ui-err-');
    addTearDown(() => root.deleteSync(recursive: true));
    final controller = await controllerWith(
      player: RecordingOfficialAnkiAvPlayer(),
      root: root,
    );
    const codes = [
      'RENDER_TIMEOUT',
      'RENDER_SUPERSEDED',
      'MATHJAX_ASSET_MISSING',
      'MATHJAX_TYPESET_FAILED',
      'SHELL_ASSET_MISSING',
      'FRAME_ASSET_MISSING',
      'WEBVIEW_MAIN_FRAME_ERROR',
    ];
    for (final code in codes) {
      controller.presentGeneration = 3;
      controller.onRenderFailure(code: code, side: 'answer', generation: 3);
      expect(controller.ui.surface, OfficialAnkiReviewerSurface.recoverableError);
      expect(controller.ui.code, code);
      expect(controller.ui.offersRetryCurrentSide, isTrue);
      expect(controller.ui.offersBack, isTrue);
      final view = OfficialAnkiReviewerErrorView.fromUi(
        ui: controller.ui,
        error: controller.error,
        onRetry: () {},
        onBack: () {},
      );
      expect(view.onRetry, isNotNull, reason: code);
      expect(view.onBack, isNotNull, reason: code);
      expect(view.code, code);
    }
  });

  test('unknown render code is fatal and still offers back', () async {
    final root = Directory.systemTemp.createTempSync('turna-ui-fatal-');
    addTearDown(() => root.deleteSync(recursive: true));
    final controller = await controllerWith(
      player: RecordingOfficialAnkiAvPlayer(),
      root: root,
    );
    controller.presentGeneration = 1;
    controller.onRenderFailure(
      code: 'BACKEND_PANIC',
      side: 'question',
      generation: 1,
    );
    expect(controller.ui.surface, OfficialAnkiReviewerSurface.fatalError);
    expect(controller.ui.offersRetryCurrentSide, isFalse);
    expect(controller.ui.offersBack, isTrue);
  });
}

class _HoldPlayPlayer implements OfficialAnkiAvPlayer {
  final events = <String>[];
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> playFile(String path) async {
    events.add('play:$path');
    if (!started.isCompleted) started.complete();
    if (!release.isCompleted) await release.future;
  }

  @override
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices = const <String>[],
    double? speed,
    List<String> otherArgs = const <String>[],
  }) async {
    events.add('tts:$text');
    return true;
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}
