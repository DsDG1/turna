import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/application/anki_official/render/official_anki_body_class.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';

void main() {
  test('official source never routes to the Legacy renderer', () {
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      renderer: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
    );
    expect(
      OfficialAnkiReviewerRouter.resolve(
        kind: OfficialAnkiSourceKind.official,
        flags: flags,
      ),
      OfficialAnkiReviewTarget.officialReviewer,
    );
    expect(
      OfficialAnkiReviewerRouter.resolve(
        kind: OfficialAnkiSourceKind.official,
        flags: const OfficialAnkiFeatureFlags(),
      ),
      OfficialAnkiReviewTarget.error,
    );
    expect(
      OfficialAnkiReviewerRouter.officialMayUseLegacyRenderer(
        OfficialAnkiSourceKind.official,
      ),
      isFalse,
    );
    expect(
      OfficialAnkiReviewerRouter.resolve(
        kind: OfficialAnkiSourceKind.legacy,
        flags: const OfficialAnkiFeatureFlags(),
      ),
      OfficialAnkiReviewTarget.legacyRenderer,
    );
  });

  test('state machine ignores stale render and compare generations', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    fake.renders[1] = const OfficialAnkiRenderedCard(
      cardId: 1,
      questionHtml: 'Q1 [[type:Back]]',
      answerHtml: 'A1 [[type:Back]]',
      questionDisplayHtml: 'Q1',
      answerDisplayHtml: 'A1',
      css: '',
      typedAnswer: OfficialAnkiTypedAnswerHint(marker: '[[type:Back]]'),
    );
    fake.renders[2] = const OfficialAnkiRenderedCard(
      cardId: 2,
      questionHtml: 'Q2',
      answerHtml: 'A2',
      questionDisplayHtml: 'Q2',
      answerDisplayHtml: 'A2',
      css: '',
    );
    final facade = OfficialAnkiRenderFacade(
      info: await fake.engineInfo(),
      engine: fake,
    );
    final root = Directory.systemTemp.createTempSync('turna-av-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    final player = RecordingOfficialAnkiAvPlayer();
    final controller = OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(root),
        player: player,
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
    await controller.loadCard(1);
    expect(controller.phase, OfficialAnkiReviewerPhase.questionReady);
    controller.typed.updateProvided('typed-back');
    final stale = controller.loadCard(2);
    await stale;
    expect(controller.card?.cardId, 2);
    expect(controller.typed.hint, isNull);
  });

  test('loadAndShowQuestion does not expose a card before present generation is reserved',
      () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    fake.renders[1] = const OfficialAnkiRenderedCard(
      cardId: 1,
      questionHtml: 'Q',
      answerHtml: 'A',
      questionDisplayHtml: 'Q',
      answerDisplayHtml: 'A',
      css: '',
    );
    final facade = OfficialAnkiRenderFacade(
      info: await fake.engineInfo(),
      engine: fake,
    );
    final root = Directory.systemTemp.createTempSync('turna-present-once-');
    addTearDown(() => root.deleteSync(recursive: true));
    final controller = OfficialAnkiReviewerController(
      facade: facade,
      av: OfficialAnkiAvCoordinator(
        resolver: OfficialAnkiMediaResolver(root),
        player: RecordingOfficialAnkiAvPlayer(),
      ),
      typed: OfficialAnkiTypedAnswerController(facade),
    );
    final seen = <({int? cardId, int gen, OfficialAnkiReviewerPhase phase})>[];
    controller.addListener(() {
      seen.add((
        cardId: controller.card?.cardId,
        gen: controller.presentGeneration,
        phase: controller.phase,
      ));
    });
    await controller.loadAndShowQuestion(1);
    expect(seen, isNotEmpty);
    final firstWithCard = seen.firstWhere((n) => n.cardId != null);
    expect(firstWithCard.gen, greaterThan(0));
    expect(firstWithCard.phase, OfficialAnkiReviewerPhase.showingQuestion);
    expect(controller.presentGeneration, firstWithCard.gen);
    expect(
      seen.where((n) => n.cardId != null && n.gen == 0),
      isEmpty,
    );
  });

  test('AV coordinator stops on flip even when autoplay is false', () async {
    final root = Directory.systemTemp.createTempSync('turna-av-flip-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    final player = RecordingOfficialAnkiAvPlayer();
    final av = OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: player,
    );
    av.attachCard(
      OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: '[sound:a.mp3]',
        answerHtml: 'A',
        questionDisplayHtml: '',
        answerDisplayHtml: '',
        css: '',
        questionAvTags: const [OfficialAnkiAvTag.sound('a.mp3')],
      ),
    );
    await av.showQuestion();
    await av.showAnswer(autoplay: false);
    await av.showQuestion(autoplay: false);
    expect(player.events.where((e) => e == 'stop').length, greaterThanOrEqualTo(2));
  });

  test('showAnswer during multi-tag question does not resume the next question tag', () async {
    final root = Directory.systemTemp.createTempSync('turna-av-flip-gen-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/q1.mp3').writeAsBytesSync([1]);
    File('${root.path}/q2.mp3').writeAsBytesSync([2]);
    File('${root.path}/a1.mp3').writeAsBytesSync([3]);
    final player = _GatedRecordingPlayer();
    final av = OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: player,
    );
    av.attachCard(
      OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: '',
        answerHtml: '',
        questionDisplayHtml: '',
        answerDisplayHtml: '',
        css: '',
        questionAvTags: const [
          OfficialAnkiAvTag.sound('q1.mp3'),
          OfficialAnkiAvTag.sound('q2.mp3'),
        ],
        answerAvTags: const [OfficialAnkiAvTag.sound('a1.mp3')],
      ),
    );
    final question = av.showQuestion();
    await player.firstPlayStarted.future;
    expect(player.events.where((e) => e.startsWith('play:')), [
      'play:${root.path}/q1.mp3',
    ]);
    final answer = av.showAnswer();
    await player.stopAfterFirstPlay.future;
    player.releaseFirstPlay.complete();
    await question;
    await answer;
    final plays = player.events.where((e) => e.startsWith('play:')).toList();
    expect(plays, isNot(contains('play:${root.path}/q2.mp3')));
    expect(plays, contains('play:${root.path}/a1.mp3'));
    expect(player.events, contains('stop'));
  });

  test('AV coordinator drops stale generation before the next tag', () async {
    final root = Directory.systemTemp.createTempSync('turna-av-gen-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    File('${root.path}/b.mp3').writeAsBytesSync([2]);
    final player = _SlowRecordingPlayer();
    final av = OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: player,
    );
    av.attachCard(
      OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: '',
        answerHtml: '',
        questionDisplayHtml: '',
        answerDisplayHtml: '',
        css: '',
        questionAvTags: const [
          OfficialAnkiAvTag.sound('a.mp3'),
          OfficialAnkiAvTag.sound('b.mp3'),
        ],
      ),
    );
    final playing = av.showQuestion();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await av.nextCard();
    await playing;
    expect(player.events.where((e) => e.startsWith('play:')).length, lessThan(2));
    expect(player.events, contains('stop'));
  });

  test('AV coordinator plays official tags and stops on next card', () async {
    final root = Directory.systemTemp.createTempSync('turna-av2-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.mp3').writeAsBytesSync([1]);
    final player = RecordingOfficialAnkiAvPlayer();
    final av = OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: player,
    );
    av.attachCard(
      OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: '[sound:a.mp3]',
        answerHtml: '[anki:tts lang=en]Hi[/anki:tts]',
        questionDisplayHtml: '',
        answerDisplayHtml: '',
        css: '',
        questionAvTags: const [OfficialAnkiAvTag.sound('a.mp3')],
        answerAvTags: const [OfficialAnkiAvTag.tts(fieldText: 'Hi', lang: 'en')],
      ),
    );
    await av.showQuestion();
    await av.showQuestion();
    await av.showAnswer();
    await av.nextCard();
    expect(player.events.where((e) => e.startsWith('play:')).length, 1);
    expect(player.events.where((e) => e.startsWith('tts:')).length, 1);
    expect(player.events.where((e) => e == 'stop').length, greaterThanOrEqualTo(2));

    final limited = RecordingOfficialAnkiAvPlayer();
    await limited.speak(
      text: 'Hi',
      lang: 'en',
      voices: const ['Alice'],
      otherArgs: const ['speed=2'],
    );
    expect(limited.events, contains('tts:en:Hi'));
    expect(limited.events, contains('tts-voice-limited:Alice'));
    expect(limited.events, contains('tts-args-limited:speed=2'));
    expect(limited.events.where((e) => e.startsWith('tts:en:')).single, 'tts:en:Hi');
  });

  test('typed controller freezes input and calls official compare', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final facade = OfficialAnkiRenderFacade(
      info: await fake.engineInfo(),
      engine: fake,
    );
    final typed = OfficialAnkiTypedAnswerController(facade);
    typed.attach(const OfficialAnkiTypedAnswerHint(marker: '[[type:Back]]'));
    typed.updateProvided('typed-back');
    final result = await typed.compare(cardId: 1, generation: typed.generation);
    expect(result?.hasExpected, isTrue);
    expect(result?.comparisonHtml, contains('typeans'));
    typed.updateProvided('changed');
    expect(typed.provided, 'typed-back');
    expect(fake.compareCount, 1);
  });

  test('typed unknown and compare failures stay recoverable', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final facade = OfficialAnkiRenderFacade(
      info: await fake.engineInfo(),
      engine: fake,
    );
    final typed = OfficialAnkiTypedAnswerController(facade);
    typed.attach(const OfficialAnkiTypedAnswerHint(marker: ''));
    expect(typed.phase, OfficialAnkiTypedPhase.recoverableError);
    expect(typed.frozen, isFalse);

    typed.attach(const OfficialAnkiTypedAnswerHint(marker: '[[type:NoSuchField]]'));
    typed.updateProvided('x');
    final failed = await typed.compare(cardId: 1, generation: typed.generation);
    expect(failed, isNull);
    expect(typed.phase, OfficialAnkiTypedPhase.recoverableError);
    expect(typed.frozen, isFalse);
    typed.updateProvided('retry');
    expect(typed.provided, 'retry');
  });

  test('FrontSide answer rule stays before comparison HTML', () {
    const html = 'Front text<hr id=answer>Back [[type:Back]]';
    final applied = OfficialAnkiTypedAnswerHtml.apply(
      html: html,
      comparisonHtml: '<code id=typeans>ok</code>',
    );
    expect(OfficialAnkiTypedAnswerHtml.hasFrontSideAnswerRule(html), isTrue);
    expect(applied.indexOf('<hr id=answer>'), lessThan(applied.indexOf('typeans')));
    expect(applied.contains('[[type:'), isFalse);
  });

  test('body class replaces previous cardN and never adds desktop platform classes', () {
    final first = OfficialAnkiBodyClass.apply(
      current: {'stale', 'card', 'card1'},
      templateOrdinal: 1,
      night: true,
    );
    expect(first, containsAll(<String>['card', 'card2', 'nightMode', 'night_mode', 'stale']));
    expect(first.contains('card1'), isFalse);
    expect(first.contains('isWin'), isFalse);
    expect(OfficialAnkiBodyClass.fromNative(templateOrdinal: 0), 'card card1');
  });

  test('reviewer view uses HCPP then HC for Android platform views', () {
    final source = File(
      'lib/views/anki_official/official_anki_reviewer_view.dart',
    ).readAsStringSync();
    expect(source.contains('initHybridAndroidView'), isTrue);
    expect(source.contains('initExpensiveAndroidView'), isTrue);
    expect(source.contains('return AndroidView('), isFalse);
    expect(
      source.contains('if (_hcpp == null)'),
      isFalse,
      reason: 'HCPP probe must not swap CircularProgressIndicator for PlatformViewLink',
    );
    expect(source.contains('CircularProgressIndicator'), isFalse);
    expect(source.contains('_hcppCached'), isTrue);
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('io.flutter.embedding.android.EnableHcpp'), isTrue);
    expect(
      manifest.contains('android.permission.INTERNET'),
      isTrue,
      reason: 'release WebView setBlockNetworkLoads(false) needs INTERNET',
    );
    final platform = File(
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerPlatformView.kt',
    ).readAsStringSync();
    expect(platform.contains('PRESENT_DEADLINE_MS'), isTrue);
    expect(platform.contains("return 'started'"), isTrue);
    expect(platform.contains('if (applying) return'), isTrue);
    expect(platform.contains('POLL_LIMIT'), isTrue);
    expect(
      platform.contains('cardAccepted / frameReady are mid-present'),
      isTrue,
      reason: 'poll must not treat cardAccepted as RENDER_TIMEOUT',
    );
    expect(platform.contains('type == "renderComplete"'), isTrue);
    final client = File(
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerClient.kt',
    ).readAsStringSync();
    expect(client.contains('OfficialAnkiCsp.ORIGIN_HOST'), isTrue);
    expect(
      client.contains('!OfficialAnkiWebPolicy.isShellUrl'),
      isFalse,
      reason: 'iframe card-frame.html is not the shell URL',
    );
  });

  test('production reviewer page does not construct the recording AV player', () {
    final page = File('lib/views/anki_official/official_anki_reviewer_page.dart')
        .readAsStringSync();
    expect(page.contains('RecordingOfficialAnkiAvPlayer('), isFalse);
    expect(page.contains('OfficialAnkiAvPlayerAdapter('), isTrue);
  });

  test('renderer flags stay off by default', () {
    expect(const OfficialAnkiFeatureFlags().renderer, isFalse);
    expect(const OfficialAnkiFeatureFlags().reviewerDiagnostics, isFalse);
    expect(const OfficialAnkiFeatureFlags().projection, isFalse);
    expect(const OfficialAnkiFeatureFlags().courseEntry, isFalse);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialRenderer, isTrue);
    expect(OfficialAnkiFeatureFlags.current.allowsProjection, isFalse);
  });
}

class RecordingOfficialAnkiAvPlayer implements OfficialAnkiAvPlayer {
  final events = <String>[];
  var speakSucceeds = true;

  @override
  Future<void> playFile(String path) async {
    events.add('play:$path');
  }

  @override
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices = const <String>[],
    double? speed,
    List<String> otherArgs = const <String>[],
  }) async {
    events.add('tts:$lang:$text');
    if (voices.isNotEmpty) {
      events.add('tts-voice-limited:${voices.join(",")}');
    }
    if (otherArgs.isNotEmpty) {
      events.add('tts-args-limited:${otherArgs.join(",")}');
    }
    return speakSucceeds;
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

class _GatedRecordingPlayer implements OfficialAnkiAvPlayer {
  final events = <String>[];
  final firstPlayStarted = Completer<void>();
  final releaseFirstPlay = Completer<void>();
  final stopAfterFirstPlay = Completer<void>();

  @override
  Future<void> playFile(String path) async {
    events.add('play:$path');
    if (!firstPlayStarted.isCompleted) {
      firstPlayStarted.complete();
      await releaseFirstPlay.future;
    }
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
    if (firstPlayStarted.isCompleted && !stopAfterFirstPlay.isCompleted) {
      stopAfterFirstPlay.complete();
    }
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}

class _SlowRecordingPlayer implements OfficialAnkiAvPlayer {
  final events = <String>[];

  @override
  Future<void> playFile(String path) async {
    events.add('play:$path');
    await Future<void>.delayed(const Duration(milliseconds: 40));
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
