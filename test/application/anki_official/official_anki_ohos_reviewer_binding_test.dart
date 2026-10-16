import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_ohos_reviewer_binding.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';

void main() {
  late FakeOfficialAnkiEngine engine;
  late OfficialAnkiReviewerController controller;
  late OfficialAnkiPaths paths;
  late Directory media;
  late OfficialAnkiFeatureFlags savedFlags;

  setUp(() async {
    OfficialAnkiOhosReviewerBinding.resetForTest();
    savedFlags = OfficialAnkiFeatureFlags.current;
    OfficialAnkiFeatureFlags.current =
        OfficialAnkiFeatureFlags.productionAndroid;
    engine = FakeOfficialAnkiEngine()
      ..seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory.systemTemp.createTempSync('turna-ohos-reviewer-'),
    );
    media = paths.mediaFolder;
    final facade = OfficialAnkiRenderFacade(
      info: await engine.engineInfo(),
      engine: engine,
    );
    controller = OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(media),
        player: _SilentAv(),
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
  });

  tearDown(() async {
    OfficialAnkiOhosReviewerBinding.resetForTest();
    await controller.dispose();
    paths.profileRoot.deleteSync(recursive: true);
    OfficialAnkiFeatureFlags.current = savedFlags;
  });

  test('media is pushed before present, with the comparison html', () async {
    final transport = _FakeTransport();
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: '<img src="https://anki.local/media/cat.png">',
      answerHtml: 'back',
      questionDisplayHtml: '<img src="https://anki.local/media/cat.png">',
      answerDisplayHtml: 'back',
      css: '',
    );
    await controller.loadAndShowQuestion(7);
    final binding = OfficialAnkiOhosReviewerBinding(
      transport: transport,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
    );
    await binding.presentCard(
      controller: controller,
      card: controller.card!,
      showingAnswer: true,
      generation: controller.presentGeneration,
      dark: false,
      comparisonHtml: '<span class="typeGood">cat</span>',
    );

    expect(transport.calls, ['push:cat.png', 'present:answer']);
    expect(transport.lastPayload?['comparisonHtml'],
        '<span class="typeGood">cat</span>');
    expect(transport.lastPayload?['typedVisible'], isFalse);
  });

  test('a rating uses the word id and the time since the answer was shown',
      () async {
    final transport = _FakeTransport();
    var ticks = 0;
    final clock = DateTime.utc(2026, 1, 1);
    var cardIdSeen = 0;
    String? rating;
    var taken = -1;
    final grades = OfficialAnkiCourseGradesBridgeImpl(
      flags: OfficialAnkiFeatureFlags.productionAndroid.copyWith(
        courseGradesScheduler: true,
      ),
      onAnswer: (cardId, nextRating, millisecondsTaken) async {
        cardIdSeen = cardId;
        rating = nextRating;
        taken = millisecondsTaken;
        return true;
      },
    );
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
    );
    await controller.loadAndShowQuestion(7);
    var rated = '';
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: grades,
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: transport,
      now: () {
        ticks += 1;
        return clock.add(Duration(milliseconds: ticks * 1500));
      },
      onRated: (value) async {
        rated = value;
        return true;
      },
    );
    await transport.onShowAnswer?.call('typed');
    await pumpEventQueue();
    final receipt = await transport.onRate?.call('hard');
    await pumpEventQueue();

    expect(receipt, 'ok');
    expect(
      officialAnkiWordId(sourceId: 'source-test', cardId: cardIdSeen),
      'official-anki-source-test-c7',
    );
    expect(cardIdSeen, 7);
    expect(rating, 'hard');
    expect(taken, 1500);
    expect(rated, 'hard');
    expect(controller.typed.provided, 'typed');
    expect(controller.showingAnswer, isTrue);
  });

  test('a rating whose advance reports the queue finished answers ok_complete',
      () async {
    final transport = _FakeTransport();
    final grades = OfficialAnkiCourseGradesBridgeImpl(
      flags: OfficialAnkiFeatureFlags.productionAndroid.copyWith(
        courseGradesScheduler: true,
      ),
      onAnswer: (cardId, rating, millisecondsTaken) async => true,
    );
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
    );
    await controller.loadAndShowQuestion(7);
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: grades,
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: transport,
      onRated: (_) async => false,
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();

    expect(receipt, 'ok_complete');
  });

  test('an answer_not_ready rejection flips the card back to the question',
      () async {
    final transport = _FakeTransport();
    final grades = OfficialAnkiCourseGradesBridgeImpl(
      flags: OfficialAnkiFeatureFlags.productionAndroid.copyWith(
        courseGradesScheduler: true,
      ),
      onAnswer: (cardId, rating, millisecondsTaken) async {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.answer_not_ready',
        );
      },
    );
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
    );
    await controller.loadAndShowQuestion(7);
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: grades,
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: transport,
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    expect(controller.showingAnswer, isTrue);
    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();

    expect(receipt, 'answer_not_ready');
    expect(controller.showingAnswer, isFalse);
    expect(transport.calls, contains('present:question'));
  });

  test('a refused grade does not tell the host the card was answered',
      () async {
    final transport = _FakeTransport();
    var rated = false;
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
    );
    await controller.loadAndShowQuestion(7);
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: transport,
      onRated: (_) async {
        rated = true;
        return true;
      },
    );
    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();
    expect(rated, isFalse);
    expect(receipt, 'scheduler_unavailable');
  });
}

class _FakeTransport implements OfficialAnkiOhosReviewerTransport {
  final calls = <String>[];
  Map<String, Object?>? lastPayload;
  Future<void> Function(String typed)? onShowAnswer;
  Future<String> Function(String rating)? onRate;
  final _open = Completer<String>();

  @override
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
  }) async {
    this.onShowAnswer = (typed) async {
      onShowAnswer(typed);
    };
    this.onRate = onRate;
  }

  @override
  Future<String> open({required String mediaRoot}) => _open.future;

  @override
  Future<Map<String, Object?>?> present({
    required Map<String, Object?> payload,
    required String side,
  }) async {
    calls.add('present:$side');
    lastPayload = payload;
    return <String, Object?>{
      'type': 'renderComplete',
      'side': side,
      'generation': payload['generation'],
    };
  }

  @override
  Future<void> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  ) async {
    calls.add('push:${names.join(',')}');
  }

  @override
  Future<void> waitUntilReady() async {}
}

class _SilentAv implements OfficialAnkiAvPlayer {
  @override
  Future<void> playFile(String path) async {}

  @override
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices = const [],
    double? speed,
    List<String> otherArgs = const [],
  }) async =>
      true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
