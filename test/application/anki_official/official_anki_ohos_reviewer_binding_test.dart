import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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
import 'package:turna/application/anki_official/render/official_anki_reviewer_channel.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';
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

  test(
      'presentCard forwards textZoom, previewOnly, hasAudio, and localized avHint',
      () async {
    final transport = _FakeTransport();
    const card = OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q [sound:missing.mp3]',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
      questionAvTags: <OfficialAnkiAvTag>[
        OfficialAnkiAvTag.sound('missing.mp3'),
      ],
    );
    engine.renders[7] = card;
    await controller.loadAndShowQuestion(7);
    final binding = OfficialAnkiOhosReviewerBinding(
      transport: transport,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      textZoom: 135,
      previewOnly: true,
    );
    await binding.presentCard(
      controller: controller,
      card: controller.card!,
      showingAnswer: false,
      generation: controller.presentGeneration,
      dark: false,
    );

    expect(transport.lastPayload?['textZoom'], 135);
    expect(transport.lastPayload?['previewOnly'], isTrue);
    expect(transport.lastPayload?['hasAudio'], isTrue);
    expect(transport.lastPayload?['avHint'], '媒体文件缺失：missing.mp3');
  });

  test(
      'previewOnly refuses rating without invoking grades and flips back on showQuestion',
      () async {
    final transport = _FakeTransport();
    var gradesCalled = false;
    final grades = OfficialAnkiCourseGradesBridgeImpl(
      flags: OfficialAnkiFeatureFlags.productionAndroid.copyWith(
        courseGradesScheduler: true,
      ),
      onAnswer: (cardId, rating, millisecondsTaken) async {
        gradesCalled = true;
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
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: grades,
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      previewOnly: true,
      transport: transport,
    );
    await transport.onShowAnswer?.call('');
    await pumpEventQueue();
    expect(controller.showingAnswer, isTrue);

    final receipt = await transport.onRate?.call('good');
    await pumpEventQueue();
    expect(receipt, 'scheduler_unavailable');
    expect(gradesCalled, isFalse);

    await transport.onShowQuestion?.call();
    await pumpEventQueue();
    expect(controller.showingAnswer, isFalse);
    expect(transport.calls.last, 'present:question');
  });

  test('replayAudio delegates to controller.replayAudio and returns avHint',
      () async {
    final transport = _FakeTransport();
    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q [sound:missing.mp3]',
      answerHtml: 'a',
      questionDisplayHtml: 'q',
      answerDisplayHtml: 'a',
      css: '',
      questionAvTags: <OfficialAnkiAvTag>[
        OfficialAnkiAvTag.sound('missing.mp3'),
      ],
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
    final hint = await transport.onReplayAudio?.call();
    expect(hint, '媒体文件缺失：missing.mp3');
  });

  test(
      'pushMedia warms small files and bypasses files above directReadBypassThreshold (O1)',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(OfficialAnkiReviewerProtocol.channelName);
    final cachedNames = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == OfficialAnkiReviewerProtocol.methodCacheReviewerMedia) {
        final args = call.arguments as Map<Object?, Object?>;
        cachedNames.add(args[OfficialAnkiReviewerProtocol.argName] as String);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    media.createSync(recursive: true);
    File('${media.path}/small.png').writeAsBytesSync(List<int>.filled(1024, 7));
    File('${media.path}/large.mp3').writeAsBytesSync(
      List<int>.filled(
        OfficialAnkiReviewerChannel.directReadBypassThreshold + 16,
        9,
      ),
    );

    final resolver = OfficialAnkiMediaResolver(media);
    await OfficialAnkiReviewerChannel.instance.pushMediaForCard(
      resolver,
      const <String>['small.png', 'large.mp3'],
    );

    expect(cachedNames, ['small.png']);
    expect(
      mediaNamesIn(
        '<img src="/media/rel.png"><style>@font-face{src:url("https://anki.local/media/font.woff2?v=1#sub")}</style>',
      ).toList(),
      ['rel.png', 'font.woff2'],
    );
  });

  test('media pushes never exceed the concurrency ceiling', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(OfficialAnkiReviewerProtocol.channelName);
    var inFlight = 0;
    var maxInFlight = 0;
    final cachedNames = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method !=
          OfficialAnkiReviewerProtocol.methodCacheReviewerMedia) {
        return null;
      }
      inFlight += 1;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final args = call.arguments as Map<Object?, Object?>;
      cachedNames.add(args[OfficialAnkiReviewerProtocol.argName] as String);
      inFlight -= 1;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    media.createSync(recursive: true);
    final names = <String>[];
    for (var i = 0; i < 8; i++) {
      final name = 'm$i.png';
      File('${media.path}/$name').writeAsBytesSync(List<int>.filled(512, i));
      names.add(name);
    }

    final settled = await OfficialAnkiReviewerChannel.instance
        .pushMediaForCard(OfficialAnkiMediaResolver(media), names);

    expect(settled, hasLength(8), reason: 'every name must be settled');
    expect(cachedNames, hasLength(8));
    // Only the ceiling is asserted. Whether two channel calls actually overlap
    // depends on the test messenger's scheduling, which this test neither owns
    // nor wants to pin — the invariant worth guarding is that the pool is
    // bounded, not that it saturates.
    expect(
      maxInFlight,
      lessThanOrEqualTo(OfficialAnkiReviewerChannel.mediaPushConcurrency),
      reason: 'unbounded Future.wait would spike memory on media-heavy cards',
    );
  });

  test('a failed media push stays out of the ledger and is retried', () async {
    final transport = _FakeTransport()..failNames.add('cat.png');
    const card = OfficialAnkiRenderedCard(
      cardId: 31,
      questionHtml: '<img src="https://anki.local/media/cat.png">'
          '<img src="https://anki.local/media/dog.png">',
      answerHtml: 'back',
      questionDisplayHtml: '<img src="https://anki.local/media/cat.png">'
          '<img src="https://anki.local/media/dog.png">',
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
      card: card,
      showingAnswer: false,
      generation: 1,
      dark: false,
    );
    expect(
      transport.calls.where((c) => c.startsWith('push:')),
      hasLength(1),
      reason: 'both names are attempted on the first present',
    );

    // Flipping the same card only retries the one that failed: `dog.png` was
    // settled and must not cost another read + channel trip.
    await binding.presentCard(
      controller: controller,
      card: card,
      showingAnswer: true,
      generation: 2,
      dark: false,
    );
    final pushes =
        transport.calls.where((c) => c.startsWith('push:')).toList();
    expect(pushes, hasLength(2), reason: 'cat.png must be retried');
    expect(pushes.last, 'push:cat.png');
  });

  test('a warm-up is adopted by the first attach, not opened twice (P0-1)',
      () async {
    final transport = _FakeTransport();
    final warmUp = await OfficialAnkiOhosReviewerBinding.warmUp(
      mediaRoot: media.path,
      transport: transport,
    );
    await warmUp.ready;
    expect(transport.openCalls, 1);

    final binding = await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: transport,
    );
    expect(identical(binding.transport, transport), isTrue);
    expect(transport.openCalls, 1,
        reason: 'attaching to a warmed reviewer must not launch a second one');
  });

  test('cancel closes the speculative reviewer and frees the slot (P0-1)',
      () async {
    final transport = _FakeTransport();
    final warmUp = await OfficialAnkiOhosReviewerBinding.warmUp(
      mediaRoot: media.path,
      transport: transport,
    );
    await warmUp.cancel();
    expect(transport.closeCalls, 1);

    // The abandoned binding is gone: the next attach opens its own reviewer
    // instead of adopting a page that is already closing.
    final second = _FakeTransport();
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: second,
    );
    expect(second.openCalls, 1);
  });

  test('a warm-up refuses a rating because no host is attached yet (P0-1)',
      () async {
    final transport = _FakeTransport();
    await OfficialAnkiOhosReviewerBinding.warmUp(
      mediaRoot: media.path,
      transport: transport,
    );

    final receipt = await transport.onRate!('good');
    expect(receipt, OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable,
        reason: 'a speculative open has no grades bridge; a rating there would '
            'silently vanish or crash on a null dereference');
  });

  test('a failed warm-up does not become the live binding (P0-1)', () async {
    final broken = _FakeTransport()..failReady = true;
    // `warmUp` returns the handle without waiting for the shell — awaiting it
    // here would put the boot back on the loader's critical path, which is the
    // whole thing the warm-up exists to avoid. So the failure surfaces on
    // `ready`, not on the call itself.
    final warmUp = await OfficialAnkiOhosReviewerBinding.warmUp(
      mediaRoot: media.path,
      transport: broken,
    );
    await expectLater(warmUp.ready, throwsA(isA<StateError>()));

    // Whatever went wrong, the next real attempt must open its own reviewer
    // rather than inherit a half-booted one.
    final healthy = _FakeTransport();
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-test',
      dark: false,
      transport: healthy,
    );
    expect(healthy.openCalls, 1);
  });

  test('a cancel with no ability behind it never sends close (P0-1)', () async {
    // The native side remembers a cancel that arrives with no session
    // (`cancelPending`) and the NEXT reviewer consumes it. So a boot that died
    // before `open` must not send one — otherwise the learner's next reviewer
    // flashes open and closes itself, which looks exactly like a crash.
    final transport = _FakeTransport()..failBind = true;
    final warmUp = await OfficialAnkiOhosReviewerBinding.warmUp(
      mediaRoot: media.path,
      transport: transport,
    );
    await expectLater(warmUp.ready, throwsA(isA<StateError>()));
    await warmUp.cancel();

    expect(transport.openCalls, 0);
    expect(
      transport.closeCalls,
      0,
      reason: 'a close with nothing open poisons the next reviewer',
    );
  });

  test(
      'rebind swaps controller listener and detach ignores non-matching controller (T1)',
      () async {
    final transport = _FakeTransport();
    final facade = OfficialAnkiRenderFacade(
      info: await engine.engineInfo(),
      engine: engine,
    );
    final secondController = OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(media),
        player: _SilentAv(),
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
    addTearDown(secondController.dispose);

    engine.renders[7] = const OfficialAnkiRenderedCard(
      cardId: 7,
      questionHtml: 'q7',
      answerHtml: 'a7',
      questionDisplayHtml: 'q7',
      answerDisplayHtml: 'a7',
      css: '',
    );
    engine.renders[8] = const OfficialAnkiRenderedCard(
      cardId: 8,
      questionHtml: 'q8',
      answerHtml: 'a8',
      questionDisplayHtml: 'q8',
      answerDisplayHtml: 'a8',
      css: 'body { background: url("https://anki.local/media/bg.png"); }',
    );
    await controller.loadAndShowQuestion(7);
    await secondController.loadAndShowQuestion(8);

    final binding = await OfficialAnkiOhosReviewerBinding.attach(
      controller: controller,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-7',
      dark: false,
      transport: transport,
    );
    await pumpEventQueue();
    expect(transport.lastPayload?['cardId'], 7);

    // Detaching an unrelated controller must leave the live controller attached.
    binding.detach(secondController);
    await controller.showAnswer();
    await pumpEventQueue();
    expect(transport.calls.last, 'present:answer');

    // Rebinding to secondController detaches controller and presents card 8
    // (including CSS media references).
    transport.calls.clear();
    await OfficialAnkiOhosReviewerBinding.attach(
      controller: secondController,
      grades: const OfficialAnkiCourseGradesBridgeImpl(),
      mediaRoot: media.path,
      resolver: OfficialAnkiMediaResolver(media),
      sourceId: 'source-8',
      dark: true,
      transport: transport,
    );
    await pumpEventQueue();
    expect(transport.lastPayload?['cardId'], 8);
    expect(transport.lastPayload?['mediaNames'], ['bg.png']);

    final countAfterRebind = transport.calls.length;
    await controller.showQuestion();
    await pumpEventQueue();
    expect(
      transport.calls.length,
      countAfterRebind,
      reason: 'detached controller must no longer schedule presents',
    );
  });

  group('card action receipts (D8)', () {
    Future<_FakeTransport> attachWith({
      Future<OfficialNativeMutation> Function()? onRedo,
      Future<OfficialNativeMutation> Function()? onBury,
      Future<OfficialNativeMutation> Function()? onSuspend,
      bool previewOnly = false,
    }) async {
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
        sourceId: 'source-d8',
        dark: false,
        previewOnly: previewOnly,
        transport: transport,
        onRedo: onRedo,
        onBury: onBury,
        onSuspend: onSuspend,
      );
      return transport;
    }

    test('each action word reaches its own host hook', () async {
      final seen = <String>[];
      final transport = await attachWith(
        onRedo: () async {
          seen.add('redo');
          return OfficialNativeMutation.advanced;
        },
        onBury: () async {
          seen.add('bury');
          return OfficialNativeMutation.advanced;
        },
        onSuspend: () async {
          seen.add('suspend');
          return OfficialNativeMutation.advanced;
        },
      );

      expect(await transport.onCardAction?.call('redo'), 'ok');
      expect(await transport.onCardAction?.call('bury'), 'ok');
      expect(await transport.onCardAction?.call('suspend'), 'ok');
      expect(seen, ['redo', 'bury', 'suspend']);
    });

    test('completed answers ok_complete so the page can end the session',
        () async {
      final transport = await attachWith(
        onBury: () async => OfficialNativeMutation.completed,
      );
      expect(await transport.onCardAction?.call('bury'), 'ok_complete');
    });

    test('refused answers scheduler_unavailable, never ok', () async {
      // `ok` here would re-arm the buttons on a card that never moved, which
      // is the one receipt the page cannot recover from.
      final transport = await attachWith(
        onSuspend: () async => OfficialNativeMutation.refused,
      );
      expect(
        await transport.onCardAction?.call('suspend'),
        'scheduler_unavailable',
      );
    });

    test('an unknown action word is answered, not dispatched', () async {
      var called = 0;
      final transport = await attachWith(
        onRedo: () async {
          called += 1;
          return OfficialNativeMutation.advanced;
        },
      );
      expect(
        await transport.onCardAction?.call('buryEverything'),
        'scheduler_unavailable',
      );
      expect(called, 0, reason: 'protocol drift must not mutate the queue');
    });

    test('a throwing host hook answers engine_error instead of escaping',
        () async {
      // Escaping to the channel would read as `channel_error_*` on the page and
      // disable the three entries for the rest of the session.
      final transport = await attachWith(
        onBury: () async => throw StateError('ledger refused'),
      );
      expect(await transport.onCardAction?.call('bury'), 'engine_error');
    });

    test('preview answers unavailable and never touches the host', () async {
      var called = 0;
      final transport = await attachWith(
        previewOnly: true,
        onRedo: () async {
          called += 1;
          return OfficialNativeMutation.advanced;
        },
      );
      expect(
        await transport.onCardAction?.call('redo'),
        'scheduler_unavailable',
      );
      expect(called, 0);
    });

    test('a warm-up reviewer with no host answers unavailable', () async {
      // The P0-1 window: the page is up before any host attached, so the three
      // entries must answer rather than silently do nothing.
      final transport = _FakeTransport();
      OfficialAnkiOhosReviewerBinding.resetForTest();
      await OfficialAnkiOhosReviewerBinding.warmUp(
        mediaRoot: media.path,
        transport: transport,
      );
      await pumpEventQueue();
      expect(
        await transport.onCardAction?.call('bury'),
        'scheduler_unavailable',
      );
    });
  });
}

class _FakeTransport implements OfficialAnkiOhosReviewerTransport {
  final calls = <String>[];
  Map<String, Object?>? lastPayload;
  Future<void> Function(String typed)? onShowAnswer;
  Future<void> Function()? onShowQuestion;
  Future<String> Function(String rating)? onRate;
  Future<String> Function(String rating)? onRetryAdvance;
  Future<void> Function()? onRetryPresent;
  Future<String?> Function()? onReplayAudio;
  Future<String> Function(String action)? onCardAction;
  final reportedFailures = <String>[];
  final _open = Completer<String>();

  /// Names this fake pretends to have failed to read or push. They are absent
  /// from the returned set, which is what the binding records.
  final failNames = <String>{};

  /// A per-name delay, so concurrency can be observed rather than assumed.
  Duration pushDelay = Duration.zero;

  /// In-flight accounting. `maxInFlight` is the peak the binding ever allowed.
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
    void Function()? onShowQuestion,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<void> Function()? onUndo,
    Future<String?> Function()? onReplayAudio,
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String> Function(String action)? onCardAction,
  }) async {
    if (failBind) {
      throw StateError('outbound handlers could not be installed');
    }
    this.onShowAnswer = (typed) async {
      onShowAnswer(typed);
    };
    this.onShowQuestion = onShowQuestion == null
        ? null
        : () async {
            onShowQuestion();
          };
    this.onRate = onRate;
    this.onRetryAdvance = onRetryAdvance;
    this.onRetryPresent = onRetryPresent;
    this.onReplayAudio = onReplayAudio;
    this.onCardAction = onCardAction;
  }  @override
  Future<String> open({required String mediaRoot}) {
    openCalls += 1;
    return _open.future;
  }

  /// P0-1: how many times `open` was invoked. A warm-up that gets adopted must
  /// not add a second one.
  int openCalls = 0;

  /// When true, `waitUntilReady` throws — a shell that never loads.
  bool failReady = false;

  /// When true, installing the outbound handlers throws — a boot that dies
  /// before `open` is ever issued.
  bool failBind = false;

  /// P0-1: how many times the speculative open was abandoned.
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (!_open.isCompleted) {
      // The real channel answers without waiting for the ability; mirror that
      // by completing the open with the warm-cancel verdict.
      _open.complete('warm_canceled');
    }
  }

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
  Future<Set<String>> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  ) async {
    calls.add('push:${names.join(',')}');
    final requested = names.toList(growable: false);
    final delivered = <String>{};
    if (requested.isEmpty) return delivered;

    // Mirror the channel's worker pool so the binding-facing test observes the
    // same concurrency ceiling the production path uses.
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= requested.length) return;
        final name = requested[index];
        inFlight += 1;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        try {
          if (pushDelay > Duration.zero) await Future<void>.delayed(pushDelay);
          if (!failNames.contains(name)) delivered.add(name);
        } finally {
          inFlight -= 1;
        }
      }
    }

    final workers = requested.length < 4 ? requested.length : 4;
    await Future.wait(
      List<Future<void>>.generate(workers, (_) => worker()),
    );
    return delivered;
  }

  @override
  Future<void> waitUntilReady() async {
    if (failReady) {
      throw StateError('reviewer shell did not load');
    }
  }

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
