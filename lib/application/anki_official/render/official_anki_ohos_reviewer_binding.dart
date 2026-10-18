import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_channel.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/l10n/app_strings.dart';

/// What a header mutation (redo / bury / suspend) did to the session.
///
/// Three states rather than a bool because the page needs to tell "moved on",
/// "finished" and "refused" apart, and a bool cannot: `true` for both advanced
/// and refused would re-arm the buttons on a card that never moved, and `false`
/// for both finished and refused would show a completion row over a queue that
/// still owes cards.
enum OfficialNativeMutation {
  /// Another card is on screen; the page re-arms its buttons.
  advanced,

  /// The mutation emptied the queue; the page swaps in its completion row.
  completed,

  /// Nothing happened (locked session, empty undo stack, finished queue). The
  /// page keeps the card and reports the refusal.
  refused,
}

/// The calls the HarmonyOS reviewer page can make. The real channel is one
/// implementation; tests supply another so the order of media push and
/// present can be asserted without a device.
abstract class OfficialAnkiOhosReviewerTransport {
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
    Future<void> Function()? onShowQuestion,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,

    /// Redo / bury / suspend from the native header, carrying the action word
    /// (`redo` / `bury` / `suspend`) and answering with a receipt.
    Future<String> Function(String action)? onCardAction,
  });

  Future<String> open({required String mediaRoot});

  /// Abandons a reviewer opened speculatively, before any card was presented.
  ///
  /// Best-effort by contract: the ability may not exist yet (the warm-up starts
  /// before everything else), and the ArkTS side remembers the request so a
  /// late arrival still closes.
  Future<void> close();

  Future<void> waitUntilReady();

  /// Pushes the card's media and reports the names that actually landed.
  ///
  /// The result is a set, not a count: [OfficialAnkiOhosReviewerBinding] keeps
  /// its own ledger of what the native cache holds, and recording a name whose
  /// bytes never arrived would make every later present skip the retry.
  Future<Set<String>> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  );

  Future<Map<String, Object?>?> present({
    required Map<String, Object?> payload,
    required String side,
  });

  /// Best-effort push of a render failure code to the native page.
  Future<void> reportFailure(String code);
}

class OfficialAnkiReviewerChannelTransport
    implements OfficialAnkiOhosReviewerTransport {
  OfficialAnkiReviewerChannelTransport(this.channel);

  final OfficialAnkiReviewerChannel channel;

  @override
  Future<void> bindOutbound({
    required void Function(String typed) onShowAnswer,
    required Future<String> Function(String rating) onRate,
    required void Function(String text) onTypedChanged,
    Future<void> Function()? onShowQuestion,
    Future<String> Function(String rating)? onRetryAdvance,
    Future<void> Function()? onRetryPresent,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,
    Future<String> Function(String action)? onCardAction,
  }) {
    return channel.bindOutbound(
      onShowAnswer: onShowAnswer,
      onRate: onRate,
      onTypedChanged: onTypedChanged,
      onShowQuestion: onShowQuestion,
      onRetryAdvance: onRetryAdvance,
      onRetryPresent: onRetryPresent,
      onUndo: onUndo,
      onSettlement: onSettlement,
      onReplayAudio: onReplayAudio,
      onCardAction: onCardAction,
    );
  }

  @override
  Future<String> open({required String mediaRoot}) =>
      channel.open(mediaRoot: mediaRoot);

  @override
  Future<void> close() => channel.close();

  @override
  Future<void> waitUntilReady() => channel.waitUntilReady();

  @override
  Future<Set<String>> pushMediaForCard(
    OfficialAnkiMediaResolver resolver,
    Iterable<String> names,
  ) {
    return channel.pushMediaForCard(resolver, names);
  }

  @override
  Future<Map<String, Object?>?> present({
    required Map<String, Object?> payload,
    required String side,
  }) {
    return channel.present(payload: payload, side: side);
  }

  @override
  Future<void> reportFailure(String code) => channel.reportFailure(code);
}

/// One open ArkUI reviewer for the whole study visit.
///
/// The stage that hosts a card is recreated when the card changes. The
/// ability is not: [open] resolves only when the learner closes it, so a
/// second launch per card would stack a page on a page. Stages attach and
/// detach; the first attach opens.
class OfficialAnkiOhosReviewerBinding {
  OfficialAnkiOhosReviewerBinding({
    required this.transport,
    required OfficialAnkiCourseGradesBridge? grades,
    required this.mediaRoot,
    OfficialAnkiMediaResolver? resolver,
    int textZoom = 100,
    bool previewOnly = false,
    DateTime Function()? now,
  })  : _grades = grades,
        // A warm-up has no `OfficialAnkiPaths` in hand — only the media root it
        // was handed. Deriving the resolver here keeps the two callers from
        // having to agree on how to build one.
        _resolver = resolver ?? OfficialAnkiMediaResolver(Directory(mediaRoot)),
        _textZoom = textZoom,
        _previewOnly = previewOnly,
        _now = now ?? DateTime.now;

  static OfficialAnkiOhosReviewerBinding? _live;

  final OfficialAnkiOhosReviewerTransport transport;
  final String mediaRoot;
  OfficialAnkiCourseGradesBridge? _grades;
  OfficialAnkiMediaResolver _resolver;
  final DateTime Function() _now;

  OfficialAnkiReviewerController? _controller;
  String _sourceId = '';
  void Function()? _onReveal;
  Future<bool> Function(String rating)? _onRated;
  void Function(String verdict)? _onClosed;
  Future<void> Function()? _onUndo;
  Future<Map<String, Object?>?> Function()? _onSettlement;
  (int, int)? Function()? _onProgress;

  /// D8: the host owns redo / bury / suspend — it holds the controller, the
  /// official session and the live queue, and it is the only layer that can
  /// rebuild after the queue changed. The binding's job is the receipt.
  Future<OfficialNativeMutation> Function()? _onRedo;
  Future<OfficialNativeMutation> Function()? _onBury;
  Future<OfficialNativeMutation> Function()? _onSuspend;
  var _dark = false;
  var _textZoom = 100;
  var _previewOnly = false;
  var _opened = false;
  var _closed = false;

  /// Whether `transport.open` was actually issued.
  ///
  /// `cancel()` needs this to tell "abandon a reviewer that exists" from "abort
  /// a boot that never reached the ability". Sending `closeReviewer` in the
  /// second case is not harmless: the native side remembers a cancel that
  /// arrives with no session (`cancelPending`) and the NEXT reviewer consumes
  /// it — the learner would see the page they just opened flash and vanish.
  var _openIssued = false;

  /// The boot sequence: [open] transport, bind callbacks, wait for the shell.
  ///
  /// A warm-up resolves this before any controller exists; [attach] awaits the
  /// same future instead of opening a second ability.
  late Future<void> _ready;

  /// How long a speculative open may sit with no card before it closes itself.
  ///
  /// 20 s is deliberately generous: the batch load plus the first render can
  /// legitimately take several seconds on a cold collection, and closing a
  /// warm-up that was about to be adopted would turn a slow start into a
  /// flash-and-vanish. It is short enough that a failed path does not leave
  /// the learner staring at an empty reviewer.
  static const defaultWarmUpIdleLimit = Duration(seconds: 20);

  Timer? _idleDeadline;

  void _armIdleDeadline(Duration limit) {
    _idleDeadline?.cancel();
    _idleDeadline = Timer(limit, () {
      if (_closed) return;
      logger.w('[OhosReviewer] warm-up deadline hit; closing an unused '
          'reviewer (no card was presented in ${limit.inSeconds}s)');
      unawaited(_abandon());
    });
  }

  void _disarmIdleDeadline() {
    _idleDeadline?.cancel();
    _idleDeadline = null;
  }

  /// Closes a reviewer nobody adopted: marks it closed, drops it from the live
  /// slot, and asks ArkTS to close the ability — but only if one was actually
  /// opened (see [_openIssued]).
  Future<void> _abandon() async {
    _disarmIdleDeadline();
    if (_closed) return;
    _closed = true;
    if (identical(OfficialAnkiOhosReviewerBinding._live, this)) {
      OfficialAnkiOhosReviewerBinding._live = null;
    }
    if (!_openIssued) return;
    try {
      await transport.close();
    } catch (error) {
      // Best-effort: the ability may already be gone, and the page closes
      // itself on the pending-cancel flag.
      logger.w('[OhosReviewer] warm-up cancel dropped', error: error);
    }
  }
  DateTime? _answerShownAt;
  (int, String, int)? _pending;
  (int, String, int)? _scheduled;
  (String, int)? _reportedFailure;
  Future<void> _queue = Future<void>.value();

  /// Media already sitting in the origin server, keyed by the card it was
  /// pushed for (P2). Flipping a card used to re-push its whole media set —
  /// a 3 MB audio meant another read + base64 + channel trip just to show
  /// the back of the same card. The memory is dropped when the presented
  /// card changes because the origin server evicts exactly then (P1): a
  /// revisit of an evicted card re-pushes rather than 503s.
  final Set<String> _pushedMediaNames = <String>{};
  int? _pushedMediaCardId;

  static Future<OfficialAnkiOhosReviewerBinding> attach({
    required OfficialAnkiReviewerController controller,
    required OfficialAnkiCourseGradesBridge grades,
    required String mediaRoot,
    required OfficialAnkiMediaResolver resolver,
    required String sourceId,
    required bool dark,
    int textZoom = 100,
    bool previewOnly = false,
    void Function()? onReveal,
    Future<bool> Function(String rating)? onRated,
    void Function(String verdict)? onClosed,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
    (int, int)? Function()? onProgress,
    Future<OfficialNativeMutation> Function()? onRedo,
    Future<OfficialNativeMutation> Function()? onBury,
    Future<OfficialNativeMutation> Function()? onSuspend,
    OfficialAnkiOhosReviewerTransport? transport,
    DateTime Function()? now,
  }) async {
    final existing = _live;
    if (existing != null && !existing._closed) {
      // A P0-1 warm-up may still be booting. Attaching before it settles would
      // present into a shell that does not exist yet; awaiting the same future
      // is what makes the warm-up free rather than merely early.
      await existing._ready;
      existing.rebind(
        controller: controller,
        grades: grades,
        resolver: resolver,
        sourceId: sourceId,
        dark: dark,
        textZoom: textZoom,
        previewOnly: previewOnly,
        onReveal: onReveal,
        onRated: onRated,
        onClosed: onClosed,
        onUndo: onUndo,
        onSettlement: onSettlement,
        onProgress: onProgress,
        onRedo: onRedo,
        onBury: onBury,
        onSuspend: onSuspend,
      );
      return existing;
    }
    final binding = OfficialAnkiOhosReviewerBinding(
      transport: transport ??
          OfficialAnkiReviewerChannelTransport(
            OfficialAnkiReviewerChannel.instance,
          ),
      grades: grades,
      mediaRoot: mediaRoot,
      resolver: resolver,
      textZoom: textZoom,
      previewOnly: previewOnly,
      now: now,
    );
    binding._ready = binding._open(controller);
    try {
      await binding._ready;
    } catch (error) {
      _live = null;
      rethrow;
    }
    _live = binding;
    binding.rebind(
      controller: controller,
      grades: grades,
      resolver: resolver,
      sourceId: sourceId,
      dark: dark,
      textZoom: textZoom,
      previewOnly: previewOnly,
      onReveal: onReveal,
      onRated: onRated,
      onClosed: onClosed,
      onUndo: onUndo,
      onSettlement: onSettlement,
      onProgress: onProgress,
      onRedo: onRedo,
      onBury: onBury,
      onSuspend: onSuspend,
    );
    return binding;
  }

  /// Opens the reviewer before a card exists (P0-1).
  ///
  /// The ability, its window, the shell preload and the Web's first navigation
  /// do not depend on the card, but they used to start only after the batch had
  /// loaded and rendered. Starting them at the click collapses that wait into
  /// whatever the loader is doing anyway.
  ///
  /// **Returns without waiting for the shell.** Awaiting here would put the
  /// boot back on the loader's critical path and defeat the point; the handle
  /// exposes [OfficialAnkiOhosReviewerWarmUp.ready] for callers that need it,
  /// and [attach] awaits the same future before presenting.
  ///
  /// The caller owns the handle: if the batch turns out empty or fails, it must
  /// [OfficialAnkiOhosReviewerWarmUp.cancel] — otherwise the learner is left on
  /// a full-screen reviewer with nothing to show, which is worse than the
  /// spinner this replaces.
  ///
  /// **The deadline is the net under that contract.** On device, a warm-up that
  /// nothing adopted was left on screen as an empty reviewer (`progress —`,
  /// "正在加载…"): the page was up, the ability alive, and no card was ever
  /// sent, because the only thing that closes a stranded warm-up is a caller
  /// remembering to. A path that throws before reaching `attach` has no such
  /// caller, so the binding closes itself after [idleLimit].
  static Future<OfficialAnkiOhosReviewerWarmUp> warmUp({
    required String mediaRoot,
    OfficialAnkiOhosReviewerTransport? transport,
    int textZoom = 100,
    Duration idleLimit = defaultWarmUpIdleLimit,
  }) async {
    final existing = _live;
    if (existing != null && !existing._closed) {
      return OfficialAnkiOhosReviewerWarmUp._(existing, existing._ready);
    }
    final binding = OfficialAnkiOhosReviewerBinding(
      transport: transport ??
          OfficialAnkiReviewerChannelTransport(
            OfficialAnkiReviewerChannel.instance,
          ),
      // No grades yet: nothing can be rated before a card exists, and a null
      // bridge makes that path answer `scheduler_unavailable` instead of
      // dereferencing an absent host.
      grades: null,
      mediaRoot: mediaRoot,
      textZoom: textZoom,
    );
    binding._ready = binding._openWarm();
    // Claim the slot immediately so a concurrent attach or a second warm-up
    // joins this boot instead of launching a second ability.
    _live = binding;
    unawaited(binding._ready.then<void>((_) {}, onError: (
      Object error,
      StackTrace stack,
    ) {
      // A boot that failed must not stay adoptable. The stage will open the
      // reviewer itself and surface the real error there.
      if (identical(_live, binding)) {
        _live = null;
      }
      logger.w('[OhosReviewer] warm-up boot failed',
          error: error, stackTrace: stack);
    }));
    binding._armIdleDeadline(idleLimit);
    return OfficialAnkiOhosReviewerWarmUp._(binding, binding._ready);
  }

  static void resetForTest() {
    final live = _live;
    final controller = live?._controller;
    if (live != null && controller != null) {
      live.detach(controller);
    }
    _live = null;
  }

  void setDark(bool value) {
    _dark = value;
  }

  void setTextZoom(int value) {
    _textZoom = value;
  }

  void setPreviewOnly(bool value) {
    _previewOnly = value;
  }

  void rebind({
    required OfficialAnkiReviewerController controller,
    required OfficialAnkiCourseGradesBridge grades,
    required OfficialAnkiMediaResolver resolver,
    required String sourceId,
    required bool dark,
    int? textZoom,
    bool? previewOnly,
    void Function()? onReveal,
    Future<bool> Function(String rating)? onRated,
    void Function(String verdict)? onClosed,
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
    (int, int)? Function()? onProgress,
    Future<OfficialNativeMutation> Function()? onRedo,
    Future<OfficialNativeMutation> Function()? onBury,
    Future<OfficialNativeMutation> Function()? onSuspend,
  }) {
    // Someone adopted this reviewer. That is the ownership signal the idle
    // deadline was waiting for: from here on, closing it is the stage's call.
    // Presenting also disarms it, but a card can legitimately take a while to
    // load, and a warm-up that is adopted just before the deadline would
    // otherwise be torn down between rebind and the first present.
    _disarmIdleDeadline();
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_onController);
      _controller = controller;
      _scheduled = null;
      controller.addListener(_onController);
    }
    _grades = grades;
    _resolver = resolver;
    _sourceId = sourceId;
    _dark = dark;
    if (textZoom != null) _textZoom = textZoom;
    if (previewOnly != null) _previewOnly = previewOnly;
    _onReveal = onReveal;
    _onRated = onRated;
    _onClosed = onClosed;
    _onUndo = onUndo;
    _onSettlement = onSettlement;
    _onProgress = onProgress;
    _onRedo = onRedo;
    _onBury = onBury;
    _onSuspend = onSuspend;
    if (_opened && !_closed) {
      _onController();
    }
  }

  void detach(OfficialAnkiReviewerController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_onController);
    _controller = null;
  }

  /// Boots the transport. Split from [_open] so a warm-up can run it without a
  /// controller — that is the entire point of warming up.
  Future<void> _openWarm() async {
    await transport.bindOutbound(
      onShowAnswer: (typed) {
        unawaited(_flip(typed));
      },
      onShowQuestion: _showQuestion,
      onRate: _rate,
      onTypedChanged: (text) {
        _controller?.typed.updateProvided(text);
      },
      onRetryAdvance: _retryAdvance,
      onRetryPresent: _retryPresent,
      onUndo: () async {
        await _onUndo?.call();
      },
      onSettlement: _onSettlement,
      onReplayAudio: _replayAudio,
      onCardAction: _cardAction,
    );
    // Cancelled while the outbound handlers were being installed: nothing was
    // opened, so there is nothing to close and nothing to leave on screen.
    if (_closed) return;
    _openIssued = true;
    final opened = transport.open(mediaRoot: mediaRoot);
    unawaited(opened.then((verdict) {
      _closed = true;
      // B8: the Flutter page under the ability only learns the learner left
      // through this callback — without it the exposed page keeps a spinner
      // where the card was and toolbar actions that present into nothing.
      _onClosed?.call(verdict);
    }, onError: (Object error, StackTrace stack) {
      _closed = true;
      logger.w('[OhosReviewer] ability closed with error',
          error: error, stackTrace: stack);
      _onClosed?.call('');
    }));
    await transport.waitUntilReady();
    _opened = true;
  }

  Future<void> _open(OfficialAnkiReviewerController controller) async {
    await _openWarm();
    controller.addListener(_onController);
    _controller = controller;
  }

  void _onController() {
    final controller = _controller;
    if (controller == null || _closed) return;
    // Failures must reach the native page before the card-null early return
    // below: a card whose load failed has no card to present, and the page
    // would otherwise sit on its shell forever (B2).
    _maybeReportFailure(controller);
    final card = controller.card;
    if (card == null) return;
    final side = controller.showingAnswer
        ? OfficialAnkiReviewerProtocol.sideAnswer
        : OfficialAnkiReviewerProtocol.sideQuestion;
    final key = (card.cardId, side, controller.presentGeneration);
    // A render ack notifies this same controller. Scheduling that face again
    // would present twice and, on a failed ack, retry without bound.
    if (_scheduled == key) return;
    _scheduled = key;
    unawaited(presentCard(
      controller: controller,
      card: card,
      showingAnswer: controller.showingAnswer,
      generation: controller.presentGeneration,
      comparisonHtml: controller.typed.comparison?.comparisonHtml,
      dark: _dark,
      textZoom: _textZoom,
      previewOnly: _previewOnly,
    ));
  }

  /// Pushes the card's small media, then presents. Names that were not pushed
  /// are read from the media folder by the origin server. A failed read is
  /// 500 `MEDIA_READ_FAILED`.
  Future<void> presentCard({
    required OfficialAnkiReviewerController controller,
    required OfficialAnkiRenderedCard card,
    required bool showingAnswer,
    required int generation,
    required bool dark,
    String? comparisonHtml,
    int? textZoom,
    bool? previewOnly,
  }) {
    final side = showingAnswer
        ? OfficialAnkiReviewerProtocol.sideAnswer
        : OfficialAnkiReviewerProtocol.sideQuestion;
    final key = (card.cardId, side, generation);
    _pending = key;
    // A card is being sent: this warm-up was adopted, so the idle deadline has
    // done its job and must not close the reviewer mid-present.
    _disarmIdleDeadline();
    _queue = _queue.catchError((Object _) {}).then((_) async {
      if (_pending != key || _closed) return;
      try {
        final names = mediaNamesIn(
          '${card.questionDisplayHtml}\n${card.answerDisplayHtml}\n${card.css}\n${comparisonHtml ?? ''}',
        ).toSet();
        if (_pushedMediaCardId != card.cardId) {
          // The origin server evicts the previous card's media on this
          // present; mirror that here or a revisit would skip pushing bytes
          // the server no longer holds.
          _pushedMediaCardId = card.cardId;
          _pushedMediaNames.clear();
        }
        final toPush = names.difference(_pushedMediaNames);
        if (toPush.isNotEmpty) {
          // Record what is settled, not what was attempted. A name whose read
          // or channel trip threw stays out of the ledger so the next present
          // retries it; names that are pointless to resend (missing file,
          // oversized) come back settled and are not retried.
          final settled = await transport.pushMediaForCard(_resolver, toPush);
          _pushedMediaNames.addAll(settled);
        }
        if (_pending != key || _closed) return;
        final progress = _onProgress?.call();
        final payload = ohosReviewerPayload(
          card: card,
          generation: generation,
          showingAnswer: showingAnswer,
          dark: dark,
          comparisonHtml: comparisonHtml,
          mediaNames: names,
          progressIndex: progress?.$1,
          progressTotal: progress?.$2,
          debug: kDebugMode,
          textZoom: textZoom ?? _textZoom,
          previewOnly: previewOnly ?? _previewOnly,
          avHint: _resolveAvHint(
            controller,
            card,
            showingAnswer: showingAnswer,
          ),
        );
        final ack = await transport.present(payload: payload, side: side);
        if (_pending != key || _closed) return;
        _applyAck(
          controller: controller,
          ack: ack,
          side: side,
          generation: generation,
        );
      } catch (error, stack) {
        logger.w('[OhosReviewer] present failed',
            error: error, stackTrace: stack);
        if (_pending != key || _closed) return;
        controller.onRenderFailure(
          code: OfficialAnkiReviewerProtocol.renderTimeout,
          side: side,
          generation: generation,
        );
      }
    });
    return _queue;
  }

  Future<void> _flip(String typed) async {
    final controller = _controller;
    if (controller == null || _closed) return;
    controller.typed.updateProvided(typed);
    await controller.showAnswer();
    _answerShownAt = _now();
    _onReveal?.call();
  }

  Future<void> _showQuestion() async {
    final controller = _controller;
    if (controller == null || _closed) return;
    _answerShownAt = null;
    await controller.showQuestion();
  }

  Future<String> _replayAudio() async {
    final controller = _controller;
    if (controller == null || _closed || controller.replayBusy) return '';
    await controller.replay();
    return _localizeAvHint(controller.avHint);
  }

  String _resolveAvHint(
    OfficialAnkiReviewerController controller,
    OfficialAnkiRenderedCard card, {
    required bool showingAnswer,
  }) {
    final existing = controller.avHint;
    if (existing != null && existing.isNotEmpty) {
      return _localizeAvHint(existing);
    }
    final tags = showingAnswer ? card.answerAvTags : card.questionAvTags;
    for (final tag in tags) {
      if (tag.kind == OfficialAnkiAvKind.soundOrVideo) {
        final name = tag.filename ?? '';
        final decision = _resolver.resolveRelativeName(name);
        if (!decision.allowed || decision.file == null) {
          return _localizeAvHint('official_anki.media_missing:$name');
        }
      } else if ((tag.fieldText ?? '').isEmpty) {
        return _localizeAvHint('official_anki.tts_empty');
      }
    }
    return '';
  }

  static String _localizeAvHint(String? key) {
    if (key == null || key.isEmpty) return '';
    return AppStrings.officialAnkiError(key);
  }

  Future<String> _rate(String rating) async {
    final controller = _controller;
    final card = controller?.card;
    if (_closed) return OfficialAnkiReviewerProtocol.receiptSessionClosed;
    if (_previewOnly) {
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    final grades = _grades;
    if (grades == null) {
      // Warm-up state: the reviewer is up but no host has attached, so there is
      // nowhere for a rating to go. Answering honestly keeps the page's four
      // buttons from reading as dead.
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    if (controller == null || card == null) {
      return OfficialAnkiReviewerProtocol.receiptNoCard;
    }
    final started = _answerShownAt;
    final elapsed =
        started == null ? 0 : _now().difference(started).inMilliseconds;
    final bool committed;
    try {
      committed = await grades.answerOfficialCard(
        wordId: officialAnkiWordId(sourceId: _sourceId, cardId: card.cardId),
        rating: rating,
        millisecondsTaken: elapsed < 0 ? 0 : elapsed,
      );
    } on OfficialAnkiException catch (error) {
      logger.w('[OhosReviewer] rating rejected: ${error.messageKey}'
          '${error.debugDetails == null ? '' : ' ${error.debugDetails}'}');
      final code = _receiptCodeFor(error.messageKey);
      if (code == OfficialAnkiReviewerProtocol.receiptAnswerNotReady) {
        // The answer face is on screen while the session still thinks it owes
        // a question (reveal state that survived a card switch). Rather than
        // leave four permanently inert buttons, put the card back to the
        // question face: the present that follows re-syncs the page and the
        // learner reveals again.
        _answerShownAt = null;
        unawaited(_resyncToQuestion(controller));
      }
      return code;
    }
    if (!committed) {
      logger.w('[OhosReviewer] rating was not committed: $rating');
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    final rated = _onRated;
    if (rated == null) {
      return OfficialAnkiReviewerProtocol.receiptOk;
    }
    return _runAdvance(rated, rating);
  }

  /// D8: the header's redo / bury / suspend entries.
  ///
  /// Mirrors [_rate]'s gating and receipt shape, but the mutation itself lives
  /// in the host: only it can rebuild the live queue and re-derive the batch,
  /// and doing it here would duplicate the controller/session plumbing the
  /// session page already owns.
  ///
  /// No new receipt vocabulary: `refused` answers `scheduler_unavailable`
  /// (which is literally true — the scheduler will not take this action right
  /// now) and a throw answers `engine_error`. How the page words those is the
  /// page's business; inventing two more codes would mean two more branches on
  /// both sides of the channel for the same three states.
  Future<String> _cardAction(String action) async {
    if (_closed) return OfficialAnkiReviewerProtocol.receiptSessionClosed;
    if (_previewOnly) {
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    final Future<OfficialNativeMutation> Function()? run;
    if (action == OfficialAnkiReviewerProtocol.cardActionRedo) {
      run = _onRedo;
    } else if (action == OfficialAnkiReviewerProtocol.cardActionBury) {
      run = _onBury;
    } else if (action == OfficialAnkiReviewerProtocol.cardActionSuspend) {
      run = _onSuspend;
    } else {
      // Protocol drift, not a user mistake: answer instead of throwing so the
      // page's button stack survives an unknown verb from a newer shell.
      logger.w('[OhosReviewer] unknown card action: $action');
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    if (run == null || _controller == null) {
      // Warm-up: the page is up but no host has attached, exactly like the
      // rating path. There is no session to mutate.
      return OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    }
    try {
      final outcome = await run();
      if (outcome == OfficialNativeMutation.completed) {
        return OfficialAnkiReviewerProtocol.receiptOkComplete;
      }
      return outcome == OfficialNativeMutation.advanced
          ? OfficialAnkiReviewerProtocol.receiptOk
          : OfficialAnkiReviewerProtocol.receiptSchedulerUnavailable;
    } catch (error, stack) {
      // The mutation may or may not have landed in the engine. Claiming
      // progress would be a lie the page cannot recover from; a failure
      // receipt leaves the card on screen and the button armed for a retry.
      logger.w('[OhosReviewer] card action failed: $action',
          error: error, stackTrace: stack);
      return OfficialAnkiReviewerProtocol.receiptEngineError;
    }
  }

  /// Runs the host's advance callback, translating any throw into the
  /// retryable `advance_failed` receipt.
  ///
  /// The commit has already happened when this runs, so an exception here
  /// must neither escape to the channel (the page would read
  /// `channel_error_*` and disable its row forever) nor invite a re-rate.
  Future<String> _runAdvance(
    Future<bool> Function(String rating) rated,
    String rating,
  ) async {
    try {
      final advanced = await rated(rating);
      return advanced
          ? OfficialAnkiReviewerProtocol.receiptOk
          : OfficialAnkiReviewerProtocol.receiptOkComplete;
    } catch (error, stack) {
      logger.w('[OhosReviewer] advance after rating failed; retryable',
          error: error, stackTrace: stack);
      return OfficialAnkiReviewerProtocol.receiptAdvanceFailed;
    }
  }

  /// The page's explicit "retry the advance" entry. Re-runs only the advance
  /// half of [_rate] — the scheduler already holds the rating.
  Future<String> _retryAdvance(String rating) async {
    final rated = _onRated;
    if (_closed) return OfficialAnkiReviewerProtocol.receiptSessionClosed;
    if (rated == null) return OfficialAnkiReviewerProtocol.receiptNoCard;
    return _runAdvance(rated, rating);
  }

  /// The page's error-state retry: re-presents the failed side through the
  /// controller's own retry path. Fatal codes no-op here and the page keeps
  /// its exit entry — that is the honest outcome for an unrenderable card.
  Future<void> _retryPresent() async {
    final controller = _controller;
    if (controller == null || _closed) return;
    await controller.retryCurrentSide();
  }

  /// Dart-side render failures never cross the `present` promise (that
  /// carries only acks the ArkTS side saw itself), so they are pushed as a
  /// code the page can show next to its retry/exit entries.
  void _maybeReportFailure(OfficialAnkiReviewerController controller) {
    if (!controller.ui.isError) {
      _reportedFailure = null;
      return;
    }
    final code =
        controller.ui.code ?? controller.error?.messageKey ?? 'render_failed';
    final signature = (code, controller.presentGeneration);
    if (_reportedFailure == signature) return;
    _reportedFailure = signature;
    unawaited(
      transport.reportFailure(code).catchError((Object error, StackTrace st) {
        // Best-effort surfacing only: the ability may already be gone.
        logger.w('[OhosReviewer] failure report dropped', error: error);
      }),
    );
  }

  static String _receiptCodeFor(String messageKey) {
    switch (messageKey) {
      case 'official_anki.answer_not_ready':
        return OfficialAnkiReviewerProtocol.receiptAnswerNotReady;
      case 'official_anki.scheduler_busy':
        return OfficialAnkiReviewerProtocol.receiptSchedulerBusy;
      case 'official_anki.scheduling_context_stale':
        return OfficialAnkiReviewerProtocol.receiptCardMismatch;
      case 'official_anki.queue_empty':
      case 'official_anki.review_session_disposed':
        return OfficialAnkiReviewerProtocol.receiptSessionClosed;
      default:
        return OfficialAnkiReviewerProtocol.receiptEngineError;
    }
  }

  Future<void> _resyncToQuestion(OfficialAnkiReviewerController controller) {
    return controller.showQuestion().catchError((Object error, StackTrace st) {
      logger.w('[OhosReviewer] answer_not_ready resync failed',
          error: error, stackTrace: st);
    });
  }

  void _applyAck({
    required OfficialAnkiReviewerController controller,
    required Map<String, Object?>? ack,
    required String side,
    required int generation,
  }) {
    final type = ack?[OfficialAnkiReviewerProtocol.ackFieldType]?.toString();
    final ackSide =
        ack?[OfficialAnkiReviewerProtocol.ackFieldSide]?.toString() ?? side;
    final ackGeneration =
        (ack?[OfficialAnkiReviewerProtocol.ackFieldGeneration] as num?)
                ?.toInt() ??
            generation;
    if (type == OfficialAnkiReviewerProtocol.ackTypeRenderComplete) {
      controller.onRenderComplete(generation: ackGeneration, side: ackSide);
      return;
    }
    final code =
        ack?[OfficialAnkiReviewerProtocol.ackFieldStableCode]?.toString();
    controller.onRenderFailure(
      code: code == null || code.isEmpty
          ? OfficialAnkiReviewerProtocol.renderTimeout
          : code,
      side: ackSide,
      generation: ackGeneration,
    );
  }
}

/// Handle on a speculative reviewer open (P0-1).
///
/// Deliberately not a `Future`: the batch loader keeps working while the
/// reviewer boots, and it needs one place to say "never mind". [cancel] is the
/// only required call, and it must be safe to skip — a warm-up that gets
/// attached is simply adopted by the stage.
class OfficialAnkiOhosReviewerWarmUp {
  OfficialAnkiOhosReviewerWarmUp._(this._binding, this._ready);

  final OfficialAnkiOhosReviewerBinding _binding;
  final Future<void> _ready;

  /// Resolves when the shell has loaded (or the boot threw).
  Future<void> get ready => _ready;

  /// Abandons the speculative open. Idempotent and best-effort.
  ///
  /// Sets `_closed` before talking to ArkTS so a concurrent [attach] cannot
  /// adopt a reviewer that is already being torn down — the worst outcome here
  /// would be presenting a card into a page that is closing.
  ///
  /// **No `close` when the boot never issued an `open`.** The native side
  /// remembers a cancel that arrives with no session and the next reviewer
  /// consumes it, which would close a session the learner had just started.
  /// Delegates to the binding's own abandon path so the caller-driven cancel
  /// and the idle-deadline cancel cannot drift apart — two copies of "close it,
  /// but only if it was opened" is exactly how one of them ends up sending a
  /// `close` for an ability that never existed.
  Future<void> cancel() => _binding._abandon();
}
