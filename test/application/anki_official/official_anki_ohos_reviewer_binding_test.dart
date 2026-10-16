import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
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

  test('an advance that throws after a commit answers advance_failed',
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
      onRated: (_) async => throw StateError('advance exploded'),
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();

    // The rating already committed in the scheduler; the receipt must be a
    // retryable advance failure, not a channel error that kills the buttons.
    expect(receipt, 'advance_failed');
  });

  test('an ok receipt is always followed by a present or ok_complete',
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
      onRated: (_) async => true,
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();

    // B5's page-level invariant, enforced where the page can see it: the
    // receipt reflects the advance callback's verdict, never a silent
    // no-op — an 'ok' the controller never moved behind would leave the
    // native page waiting for a present that nothing will schedule.
    expect(receipt, 'ok');
  });

  test('a render failure is pushed to the native page once per generation',
      () async {
    final transport = _FakeTransport();
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
    );
    controller.onRenderFailure(
      code: 'RENDER_TIMEOUT',
      side: 'question',
      generation: controller.presentGeneration,
    );
    // The controller re-notifies for the same failure before any retry
    // present can land; the page must not see a duplicate banner.
    controller.onRenderFailure(
      code: 'RENDER_TIMEOUT',
      side: 'question',
      generation: controller.presentGeneration,
    );
    await pumpEventQueue();
    expect(transport.reportedFailures, ['RENDER_TIMEOUT']);
  });

  test('retryAdvance re-runs only the advance and reports its verdict',
      () async {
    final transport = _FakeTransport();
    final grades = OfficialAnkiCourseGradesBridgeImpl(
      flags: OfficialAnkiFeatureFlags.productionAndroid.copyWith(
        courseGradesScheduler: true,
      ),
      onAnswer: (cardId, rating, millisecondsTaken) async => true,
    );
    var advanceCalls = 0;
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
      onRated: (_) async {
        advanceCalls += 1;
        if (advanceCalls == 1) {
          throw StateError('first advance exploded');
        }
        return true;
      },
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    final first = await transport.onRate?.call('good');
    expect(first, 'advance_failed');
    expect(advanceCalls, 1);

    // The page's retry entry: the rating is NOT re-committed (grades sees no
    // second answer), only the advance runs again and its verdict crosses.
    final second = await transport.onRetryAdvance?.call('good');
    expect(second, 'ok');
    expect(advanceCalls, 2);
  });

  test(
      'media is pushed once per card and re-pushed after a card switch (P2)',
      () async {
    final transport = _FakeTransport();
    const card7 = OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: '<img src="https://anki.local/media/cat.png">',
      answerHtml: 'back',
      questionDisplayHtml: '<img src="https://anki.local/media/cat.png">',
      answerDisplayHtml: 'back',
      css: '',
    );
    const card8 = OfficialAnkiRenderedCard(
      cardId: 8,
      questionHtml: '<img src="https://anki.local/media/dog.png">',
      answerHtml: 'back',
      questionDisplayHtml: '<img src="https://anki.local/media/dog.png">',
      answerDisplayHtml: 'back',
      css: '',
    );
    final binding = OfficialAnkiOhosReviewerBinding(
      transport: transport,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
    );
    await binding.presentCard(
      controller: controller,
      card: card7,
      showingAnswer: false,
      generation: 1,
      dark: false,
    );
    // Flipping the same card reuses the pushed bytes.
    await binding.presentCard(
      controller: controller,
      card: card7,
      showingAnswer: true,
      generation: 2,
      dark: false,
    );
    expect(
      transport.calls.where((c) => c.startsWith('push:')).toList(),
      ['push:cat.png'],
    );
    expect(transport.lastPayload?['mediaNames'], ['cat.png']);

    // A new card pushes its own media (and the payload carries the set the
    // origin server will keep).
    await binding.presentCard(
      controller: controller,
      card: card8,
      showingAnswer: false,
      generation: 3,
      dark: false,
    );
    expect(transport.calls, contains('push:dog.png'));
    expect(transport.lastPayload?['mediaNames'], ['dog.png']);

    // Revisiting card 7 re-pushes: the origin server evicted it when card 8
    // presented, and the binding mirrors that eviction.
    await binding.presentCard(
      controller: controller,
      card: card7,
      showingAnswer: false,
      generation: 4,
      dark: false,
    );
    expect(transport.calls.where((c) => c == 'push:cat.png').length, 2);
  });

  test('adoptRenderedCard shows a card without a second engine render (P5)',
      () async {
    final facade = _CountingFacade(
      info: await engine.engineInfo(),
      engine: engine,
    );
    final adopted = OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(media),
        player: _SilentAv(),
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
    const card = OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
    );
    await adopted.adoptRenderedCard(card);

    expect(facade.renderCalls, 0,
        reason: 'the loader already rendered this card for the batch');
    expect(adopted.card?.cardId, 7);
    expect(adopted.showingAnswer, isFalse);
    expect(adopted.phase, OfficialAnkiReviewerPhase.showingQuestion);
    await adopted.dispose();
  });
}

class _FakeTransport implements OfficialAnkiOhosReviewerTransport {
  final calls = <String>[];
  Map<String, Object?>? lastPayload;
  Future<void> Function(String typed)? onShowAnswer;
  Future<String> Function(String rating)? onRate;
  Future<String> Function(String rating)? onRetryAdvance;
  Future<void> Function()? onRetryPresent;
  final reportedFailures = <String>[];
  final _open = Completer<String>();

  @override
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
  }) async {
    this.onShowAnswer = (typed) async {
      onShowAnswer(typed);
    };
    this.onRate = onRate;
    this.onRetryAdvance = onRetryAdvance;
    this.onRetryPresent = onRetryPresent;
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

  @override
  Future<void> reportFailure(String code) async {
    reportedFailures.add(code);
  }
}

class _CountingFacade extends OfficialAnkiRenderFacade {
  _CountingFacade({
    required super.info,
    required OfficialAnkiEngine engine,
  }) : super(engine: engine);

  int renderCalls = 0;

  @override
  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) {
    renderCalls += 1;
    return super.renderCard(
      cardId: cardId,
      browser: browser,
      includeAvTags: includeAvTags,
    );
  }
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
