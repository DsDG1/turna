import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards for the reviewer's ability / session lifecycle.
///
/// None of this is reachable from Dart: the page is ArkTS, the ability is a
/// HarmonyOS component, and `isHarmonyOsTarget` is a compile-time constant on
/// this side. What *is* checkable is the shape of the files that cooperate —
/// and every defect these pin had the same signature: the chain looked
/// complete, but one branch reloaded the page, cleared the wrong listener, or
/// opened a second ability.
const _pagePath = 'ohos/entry/src/main/ets/pages/AnkiReviewerPage.ets';
const _abilityPath =
    'ohos/entry/src/main/ets/entryability/AnkiReviewerAbility.ets';
const _storePath = 'ohos/entry/src/main/ets/anki/AnkiReviewerSessionStore.ets';
const _sessionPath = 'ohos/entry/src/main/ets/anki/AnkiReviewerSession.ets';
const _pluginPath = 'ohos/entry/src/main/ets/plugins/AnkiReviewerPlugin.ets';
const _bindingPath =
    'lib/application/anki_official/render/official_anki_ohos_reviewer_binding.dart';
const _reviewPagePath = 'lib/views/anki/anki_review_session_page.dart';
const _stagePath = 'lib/views/anki_official/official_anki_reviewer_stage.dart';
const _advancePath =
    'lib/application/anki_official/review/official_review_advance.dart';
const _controllerPath =
    'lib/application/study_session/study_session_controller.dart';

/// Drops `//` and `///` lines before needle-matching.
///
/// Same reason as the sibling chrome guard: a needle must never be satisfied
/// by the comment that explains it.
String _code(String path) => File(path)
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// The brace-balanced block starting at the first `{` at or after [needle].
///
/// Used for `if (…) { … }` arms and for function bodies whose signature has no
/// braces of its own. Returns null when the needle is absent.
String? _block(String source, String needle) {
  final start = source.indexOf(needle);
  if (start < 0) return null;
  final open = source.indexOf('{', start);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return null;
}

void main() {
  group('reviewer ability relaunch', () {
    late final String ability;

    setUpAll(() {
      ability = _code(_abilityPath);
    });

    test('a same-root relaunch keeps the live session and its page', () {
      final onNewWant = _block(ability, 'onNewWant(');
      expect(onNewWant, isNotNull,
          reason: 'onNewWant is gone from $_abilityPath');
      expect(
        onNewWant!
            .contains('given === this.mediaRoot && session !== undefined'),
        isTrue,
        reason: 'the reuse branch is what keeps a duplicate openReviewer from '
            'rebuilding the session under a live Web controller',
      );
      final reuse = _block(
        onNewWant,
        'if (given === this.mediaRoot && session !== undefined)',
      );
      expect(reuse, isNotNull, reason: 'the same-root branch is gone');
      expect(
        reuse!.contains('loadReviewerPage'),
        isFalse,
        reason: 'reloading the page on a same-root relaunch is the "page jumps '
            'again" report: the ability is a singleton, so this branch runs on '
            'every duplicate open and a full reload flashes white',
      );
      expect(
        reuse.contains('noteReviewerWantDelivered'),
        isTrue,
        reason: 'without this the duplicate open\'s awaitReviewerReady waits '
            'for a session that will never be created and times out after 8 s',
      );
      // A genuinely different collection still has to rebuild.
      expect(
        onNewWant.contains('beginReviewerSession(given)'),
        isTrue,
        reason: 'the different-root path must still begin a session; keeping '
            'the old one would serve the previous collection\'s media',
      );
    });

    test('the want epoch counts served requests, not session objects', () {
      final store = _code(_storePath);
      final begin = _block(store, 'export function beginReviewerSession(');
      expect(begin, isNotNull);
      expect(
        begin!.contains('wantEpoch += 1'),
        isTrue,
        reason: 'a new session serves its want too; without the bump the '
            'waiter for that want never sees the epoch move',
      );
      final delivered =
          _block(store, 'export function noteReviewerWantDelivered(');
      expect(delivered, isNotNull,
          reason: 'the reuse path needs its own way to say "this want was '
              'served"');
      expect(delivered!.contains('wantEpoch += 1'), isTrue);
      final ready = _block(store, 'export function shellReadyAfter(');
      expect(ready, isNotNull);
      expect(
        ready!.contains('wantEpoch > want'),
        isTrue,
        reason: 'B3 is a strict comparison: an epoch captured before the '
            'launch must not be satisfied by the previous session',
      );
    });

    test('the epoch is captured before the launch, not after it', () {
      final plugin = _code(_pluginPath);
      final open = _block(plugin, 'private openReviewer(');
      expect(open, isNotNull, reason: 'openReviewer is gone from $_pluginPath');
      final capture = open!.indexOf('reviewerWantEpoch()');
      final launch = open.indexOf('startAbilityForResult(want)');
      expect(capture, greaterThanOrEqualTo(0),
          reason: 'openReviewer must capture the pre-launch epoch');
      expect(launch, greaterThan(capture),
          reason: 'onNewWant serves the want on this same thread and bumps the '
              'counter; a capture taken after the launch is already past the '
              'value it waits for');
      final ready = _block(plugin, 'private awaitReviewerReady(');
      expect(
        ready!.contains('this.pendingReadyEpoch'),
        isTrue,
        reason: 'awaitReviewerReady must use the captured epoch rather than a '
            'fresh read',
      );
    });
  });

  group('reviewer page session identity', () {
    late final String page;

    setUpAll(() {
      page = _code(_pagePath);
    });

    test('the page binds a session object and can rebind a different one', () {
      expect(
        page.contains('private boundSession: AnkiReviewerSession | undefined'),
        isTrue,
        reason: 'without an identity field the page cannot tell "already '
            'bound" from "the store swapped the session under me"',
      );
      final boot = _block(page, 'private bootWhenSessionArrives(');
      expect(boot, isNotNull);
      expect(
        boot!.contains('this.booted && previous === session'),
        isTrue,
        reason: 'the same session must not boot twice, and a different one '
            'must — that is the whole point of the identity check',
      );
      final disappear = _block(page, 'aboutToDisappear(');
      expect(disappear, isNotNull);
      expect(
        disappear!.contains('reviewerSession()'),
        isFalse,
        reason: 'clearing the store\'s current session can reach the *new* '
            'page\'s listeners; only the object this page bound may be unbound',
      );
      expect(disappear.contains('unbindSession(bound)'), isTrue);
    });

    test('a cancel that arrives before subscription is remembered', () {
      final session = _code(_sessionPath);
      final cancel = _block(session, 'public requestCancel(');
      expect(cancel, isNotNull);
      expect(
        cancel!.contains('this.cancelPending = true'),
        isTrue,
        reason: 'the session exists from onWindowStageCreate but the page '
            'subscribes a moment later; a cancel in that window used to be '
            'dropped, leaving an unwanted reviewer on screen',
      );
      expect(
        session.contains('public consumeCancelRequest('),
        isTrue,
        reason: 'the page needs a way to read the cached cancel once its '
            'listener is installed',
      );
      final boot = _block(page, 'private bootWhenSessionArrives(');
      expect(
        boot!.contains('consumeCancelRequest()'),
        isTrue,
        reason: 'the page never reads the cached cancel, so caching it changes '
            'nothing',
      );
    });
  });

  group('reviewer binding lifecycle', () {
    late final String binding;

    setUpAll(() {
      binding = _code(_bindingPath);
    });

    test('attach claims the live slot before awaiting its boot', () {
      final attachStart = binding.indexOf(
        'static Future<OfficialAnkiOhosReviewerBinding> attach(',
      );
      expect(attachStart, greaterThanOrEqualTo(0));
      final claim = binding.indexOf('_live = binding;', attachStart);
      final wait = binding.indexOf('await binding._ready;', attachStart);
      expect(claim, greaterThanOrEqualTo(0),
          reason: 'attach must claim _live synchronously, before the boot');
      expect(
        claim,
        lessThan(wait),
        reason: 'claiming after the boot leaves a window where a second '
            'attach opens a second ability; on a singleton ability that '
            'lands in onNewWant and reloads the page',
      );
      expect(
        binding.contains('binding._adopted = true;'),
        isTrue,
        reason: 'an attaching stage is an adopter: its reviewer must outlive '
            'the loader handle that started it',
      );
    });

    test('a boot that fails closes the ability it already launched', () {
      final attachStart = binding.indexOf(
        'static Future<OfficialAnkiOhosReviewerBinding> attach(',
      );
      final attach = binding.substring(attachStart);
      final wait = attach.indexOf('await binding._ready;');
      final abandon = attach.indexOf('await binding._abandon();', wait);
      expect(abandon, greaterThan(wait),
          reason: 'clearing _live alone leaves the ability on screen; the next '
              'attach then stacks a second page on top of it');
    });

    test('adopted reviewers are only closed by shutdown', () {
      // Matched as a flat assertion rather than a brace-balanced block: the
      // signature carries a named parameter `{bool force = false}`, so the
      // first `{` after `_abandon(` is not the body.
      expect(
        binding.contains('Future<void> _abandon({bool force = false}) async {'),
        isTrue,
        reason: '_abandon lost its force parameter',
      );
      expect(
        binding.contains('if (!force && _adopted)'),
        isTrue,
        reason: 'a loader failure (blocked source, empty batch) must not close '
            'the reviewer a stage is currently showing',
      );
      expect(
        binding.contains('static Future<void> shutdown() async {'),
        isTrue,
        reason: 'the page needs a forced exit after it has dropped its warm-up '
            'handle',
      );
      expect(
        binding.contains('_abandon(force: true)'),
        isTrue,
        reason: 'shutdown must bypass the adopted guard',
      );
    });
  });

  group('review page close is once', () {
    test('one ability close pops once', () {
      final page = _code(_reviewPagePath);
      final closed = _block(page, 'void _onNativeAbilityClosed(');
      expect(closed, isNotNull);
      final guard = closed!.indexOf('_nativeClosedHandled');
      final pop = closed.indexOf('maybePop()');
      expect(guard, greaterThanOrEqualTo(0),
          reason: 'two bindings can resolve on one ability close (a failed '
              'warm-up plus the stage\'s own attach) and walk the navigator '
              'back twice');
      expect(pop, greaterThan(guard),
          reason: 'the guard must run before the pop');
    });
  });

  // The first present of every session is built from the binding's chrome
  // fields, and on device (CMM-AL10, 2026-10-18) they were still the
  // constructor defaults at that moment: a dark app showed a dark card inside a
  // light native chrome, and a freshly created stage showed a light card in a
  // dark app. Both come from computing the values in `build` and nowhere else.
  group('chrome values exist before the first present', () {
    test('the stage reads them before it attaches', () {
      final stage = _code(_stagePath);
      final deps = _block(stage, 'void didChangeDependencies() {');
      expect(deps, isNotNull);
      final sync = deps!.indexOf('_syncChrome()');
      final start = deps.indexOf('_startOhos()');
      expect(sync, greaterThanOrEqualTo(0),
          reason: '`dark` and `chromeTheme` must be read from the theme and '
              'the accessibility scope before the binding is created');
      expect(sync, lessThan(start),
          reason: 'attach presents the first card; computing the values after '
              'it hands that present the defaults');
      expect(
        stage.contains('chromeTheme: _chromeTheme,'),
        isTrue,
        reason: 'attach must receive the palette variant, not just the '
            'day/night boolean',
      );
    });

    test('the binding applies it before the ability opens', () {
      final binding = _code(_bindingPath);
      final theme = binding.indexOf('binding._chromeTheme = chromeTheme;');
      final open =
          binding.indexOf('binding._ready = binding._open(controller);');
      expect(theme, greaterThanOrEqualTo(0));
      expect(open, greaterThan(theme),
          reason: 'the first present can happen inside `_open`; a theme set '
              'after it only fixes the second card');
    });
  });

  // Device run 2026-10-18: rating a card committed the answer, advanced the
  // session, and then nothing happened — "已提交，加载中…" until the watchdog.
  // Two independent causes, both invisible without a native device.
  group('native rating advance', () {
    test('the batch is rebuilt before the target is resolved', () {
      final advance = _code(_advancePath);
      final rebuild =
          advance.indexOf('await liveQueue.rebuildFromLiveQueue();');
      final lookup = advance.indexOf('for (final item in controller.items)');
      expect(rebuild, greaterThanOrEqualTo(0),
          reason: 'the live queue owns rendering; the host must ask it for a '
              'batch after every commit, exactly like the Flutter session view');
      expect(rebuild, lessThan(lookup),
          reason: 'the rebuild replaces `controller.items` with a batch that '
              'STARTS at the scheduler current, so resolving the target first '
              'leaves the index pointing into a list that just shifted');
    });

    test('a retry re-arms any stale phase, not just recoverableError', () {
      final controller = _code(_controllerPath);
      final start = controller.indexOf('void acceptExternalOfficialCommit({');
      final end = controller.indexOf('Future<void> continueNext(', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(
        controller.substring(start, end).contains(
              'phase != StudyCardPhase.readyForNext',
            ),
        isTrue,
        reason: 'an advance that resolves to the card already on screen leaves '
            '`loadingQuestion`, not `recoverableError`; resetting only the '
            'latter made every retry answer advance_failed for a rating that '
            'had committed',
      );
    });
  });

  // The reviewer is its own ability, so the Flutter page under it produces no
  // frames. Everything the next card needs — new body boot, new render
  // controller, present — hung off that page rebuilding, which on device never
  // happened: the advance answered `ok` and no present was ever sent
  // (2026-10-18, rating then `rating_stalled`).
  group('advance presents without a Flutter frame', () {
    test('the binding can drive a present in place', () {
      final binding = _code(_bindingPath);
      expect(binding.contains('static Future<bool> presentInPlace(int cardId)'),
          isTrue,
          reason: 'the covered Flutter page cannot carry the next card, so the '
              'binding has to load and present it itself');
      final start = binding.indexOf('static Future<bool> presentInPlace(');
      final end = binding.indexOf('\n  }', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(
          binding.substring(start, end).contains('loadAndShowQuestion'), isTrue,
          reason: 'without loading the face there is nothing to present');
    });

    test('the rating path calls it after a successful advance', () {
      final page = _code(_reviewPagePath);
      final rated = page.indexOf('onNativeRated: session == null');
      final end = page.indexOf('onReveal: () {', rated);
      expect(rated, greaterThanOrEqualTo(0));
      expect(end, greaterThan(rated));
      final arm = page.substring(rated, end);
      expect(arm.contains('advanceAndPresentAfterNativeRating'), isTrue,
          reason: 'a rating that advanced must put the next card on the native '
              'reviewer without waiting for a rebuild that never comes');

      // The ordering lives in the advance helper, next to the rating move.
      final advance = _code(_advancePath);
      final helper = advance.indexOf(
        'Future<bool> advanceAndPresentAfterNativeRating({',
      );
      expect(helper, greaterThanOrEqualTo(0),
          reason: 'the native-rating present helper lives with the advance');
      final helperEnd = advance.indexOf('\n}\n', helper);
      expect(helperEnd, greaterThan(helper));
      final body = advance.substring(helper, helperEnd);
      expect(
        body.indexOf('advanceFromNativeRating'),
        lessThan(body.indexOf('presentSessionCardInPlace')),
        reason: 'presenting before the advance would show the card the '
            'session has not moved to yet',
      );
    });

    test('the page does not open the reviewer before the batch is loaded', () {
      // The 2026-10-19 report: tapping review showed a full-screen white
      // reviewer with only 「显示答案」, and nothing on it responded. Opening
      // the ability before the batch existed covered the page, Flutter
      // produced no frames, and the stage that presents card 1 was never
      // built. The warm-up API is gone; the stage is the opener.
      final page = _code(_reviewPagePath);
      expect(page.contains('_warmOhosReviewer'), isFalse,
          reason: 'a warm-up opened ahead of the batch leaves the first card '
              'waiting for a frame that cannot arrive under the ability');
      expect(page.contains('OfficialAnkiOhosReviewerBinding.warmUp'), isFalse,
          reason: 'the warm-up API is gone; the stage is the only opener that '
              'can present card 1 without waiting for a new frame');
    });
  });
}
