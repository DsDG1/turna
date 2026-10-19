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
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,
  });

  Future<String> open({required String mediaRoot});

  /// Closes the reviewer ability.
  ///
  /// Best-effort by contract: the ability may not exist yet, and the ArkTS
  /// side remembers the request so a late arrival still closes.
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
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,
  }) {
    return channel.bindOutbound(
      onShowAnswer: onShowAnswer,
      onRate: onRate,
      onTypedChanged: onTypedChanged,
      onShowQuestion: onShowQuestion,
      onRetryAdvance: onRetryAdvance,
      onRetryPresent: onRetryPresent,
      onSettlement: onSettlement,
      onReplayAudio: onReplayAudio,
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
        // Deriving the resolver from the media root keeps callers that do not
        // pass one from having to agree on how to build it.
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
  Future<Map<String, Object?>?> Function()? _onSettlement;
  (int, int)? Function()? _onProgress;

  /// The chrome values the native page cannot derive (source badge, which
  /// undo is possible, whether the queue may be mutated, which theme variant
  /// to paint). Read on every present, exactly like [_onProgress] — the page
  /// holds the controller, the binding does not.
  OfficialReviewerChromeSnapshot Function()? _onChrome;
  var _dark = false;
  var _textZoom = 100;
  var _previewOnly = false;

  /// Which of the four Flutter theme variants the page sits on (UI-15).
  ///
  /// `_dark` alone cannot express this: Turna ships high-contrast light and
  /// high-contrast dark as separate `ThemeData`s, and collapsing them into
  /// day/night is how the native chrome used to lose high contrast entirely.
  /// Stage-owned, because only the widget layer can read the accessibility
  /// scope; the binding just carries it into the payload.
  var _chromeTheme = OfficialAnkiReviewerProtocol.chromeLight;
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

  /// A stage has rebound to this binding — it is the reviewer the learner is
  /// looking at.
  ///
  /// Once adopted, a failed boot must not close it. The one forced exit is
  /// [shutdown], called when the review page itself goes away.
  var _adopted = false;

  /// The boot sequence: open the transport, bind callbacks, wait for the shell.
  ///
  /// A second [attach] awaits this same future instead of opening another
  /// ability.
  late Future<void> _ready;

  /// Closes a reviewer nobody adopted: marks it closed, drops it from the live
  /// slot, and asks ArkTS to close the ability — but only if one was actually
  /// opened (see [_openIssued]).
  ///
  /// **Adopted reviewers are left alone** unless [force] is set. See [_adopted]
  /// for why: a loader failure must never close the page the learner is
  /// reading. The one forced exit is [shutdown], called when the review page
  /// itself goes away.
  Future<void> _abandon({bool force = false}) async {
    if (!force && _adopted) {
      return;
    }
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

  /// Closes the live reviewer no matter who adopted it — the review page's
  /// exit path.
  ///
  /// Deliberately a static on the binding. A `force` flag reachable from a
  /// loader handle would hand every failing loader a one-argument way to close
  /// a live session.
  ///
  /// Idempotent: a second call finds no live binding, and a binding that has
  /// already closed itself short-circuits on [_closed].
  static Future<void> shutdown() async {
    final live = _live;
    _live = null;
    if (live == null) return;
    await live._abandon(force: true);
  }

  DateTime? _answerShownAt;
  (int, String, int)? _pending;
  (int, String, int)? _scheduled;
  (String, int)? _reportedFailure;

  /// `generation/presentGeneration` of the last "advanced but nothing to
  /// present" state, so the warning fires once per move instead of on every
  /// controller notification.
  var _waitingFaceAt = '';
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
    String? chromeTheme,
    void Function()? onReveal,
    Future<bool> Function(String rating)? onRated,
    void Function(String verdict)? onClosed,
    Future<Map<String, Object?>?> Function()? onSettlement,
    (int, int)? Function()? onProgress,
    OfficialReviewerChromeSnapshot Function()? onChrome,
    OfficialAnkiOhosReviewerTransport? transport,
    DateTime Function()? now,
  }) async {
    final existing = _live;
    if (existing != null && !existing._closed) {
      logger.w('[OhosReviewer] attach joins the live binding '
          '(ready already awaited=${existing._opened})');
      // Claim it before awaiting. A boot that fails in this window must not
      // close a reviewer that is being adopted right now.
      existing._adopted = true;
      // The first attach may still be booting. Attaching before it settles
      // would present into a shell that does not exist yet.
      try {
        await existing._ready;
      } catch (_) {
        existing._adopted = false;
        rethrow;
      }
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
        onSettlement: onSettlement,
        onProgress: onProgress,
        onChrome: onChrome,
      );
      logger.w(
          '[OhosReviewer] attach rebound to card=${controller.card?.cardId}');
      return existing;
    }
    logger.w('[OhosReviewer] attach opens a fresh binding');
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
    if (chromeTheme != null && chromeTheme.isNotEmpty) {
      // Set before `_open`: the first present of a fresh binding happens inside
      // that await, and it would otherwise carry the field's default.
      binding._chromeTheme = chromeTheme;
    }
    // Same reason for the card frame's day/night: `rebind` is below `_open`.
    binding._dark = dark;
    binding._ready = binding._open(controller);
    binding._adopted = true;
    // Claim the slot synchronously, before the boot. Two attaches that both
    // waited for their own boot would each call `openReviewer`, and a second
    // `startAbilityForResult` on a singleton ability lands in `onNewWant` —
    // which rebuilds the session and reloads the page under the learner.
    // That reload is the "page jumps again" report.
    _live = binding;
    try {
      await binding._ready;
    } catch (error) {
      binding._adopted = false;
      // Dropping the slot alone leaves the ability this boot already launched
      // on screen with no card; the next attach would then open a second one.
      // `_abandon` still guards on `_openIssued`, so a failure before `open`
      // never sends a close (which the native side would cache for the *next*
      // reviewer).
      await binding._abandon();
      rethrow;
    }
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
      onSettlement: onSettlement,
      onProgress: onProgress,
      onChrome: onChrome,
    );
    return binding;
  }

  static void resetForTest() {
    final live = _live;
    final controller = live?._controller;
    if (live != null && controller != null) {
      live.detach(controller);
    }
    _live = null;
  }

  /// Loads [cardId] into the reviewer that is currently on screen and presents
  /// it, without waiting for a Flutter rebuild.
  ///
  /// The reviewer is its own ability (route E), so while it is on top the
  /// Flutter page below stops producing frames. Everything the next card needs
  /// — a new `OfficialTemplateWebViewBody` boot, a new render controller, a
  /// `present` — used to hang off that page rebuilding. After a rating the
  /// session advanced, the receipt answered `ok`, and then nothing was ever
  /// loaded: no rebuild, no present, and the page sat on "已提交，加载中…"
  /// until its watchdog turned that into `rating_stalled` (device, 2026-10-18;
  /// the frame that would have carried card 2 never arrived).
  ///
  /// Returns whether a present was issued. A no-op when nothing is attached, or
  /// when the face is already the one that should be on screen.
  static Future<bool> presentInPlace(int cardId) async {
    final live = _live;
    if (live == null || live._closed) return false;
    final controller = live._controller;
    if (controller == null || cardId <= 0) return false;
    if (controller.card?.cardId == cardId && !controller.showingAnswer) {
      logger.w('[OhosReviewer] in-place present skipped: card $cardId is '
          'already showing its question face');
      return false;
    }
    logger.w('[OhosReviewer] in-place present card=$cardId '
        '(was ${controller.card?.cardId})');
    try {
      await controller.loadAndShowQuestion(cardId);
      // `loadAndShowQuestion` returns normally on a render failure too: it
      // parks the controller in `recoverableError` and notifies, and
      // `_maybeReportFailure` has already told the page. Only a card object for
      // [cardId] proves a face reached the reviewer, and only then may the
      // caller record an acknowledgement for it.
      return controller.card?.cardId == cardId && !controller.ui.isError;
    } catch (error, stack) {
      // A render failure already reached the page through
      // `_maybeReportFailure`; a throw here would turn a committed rating into
      // `advance_failed` and re-run an advance that has nothing left to do.
      logger.w('[OhosReviewer] in-place present failed for card $cardId',
          error: error, stackTrace: stack);
      return false;
    }
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

  void setChromeTheme(String value) {
    if (value.isEmpty || value == _chromeTheme) return;
    _chromeTheme = value;
  }

  void rebind({
    required OfficialAnkiReviewerController controller,
    required OfficialAnkiCourseGradesBridge grades,
    required OfficialAnkiMediaResolver resolver,
    required String sourceId,
    required bool dark,
    int? textZoom,
    bool? previewOnly,
    String? chromeTheme,
    void Function()? onReveal,
    Future<bool> Function(String rating)? onRated,
    void Function(String verdict)? onClosed,
    Future<Map<String, Object?>?> Function()? onSettlement,
    (int, int)? Function()? onProgress,
    OfficialReviewerChromeSnapshot Function()? onChrome,
  }) {
    _adopted = true;
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
    if (chromeTheme != null && chromeTheme.isNotEmpty) {
      _chromeTheme = chromeTheme;
    }
    _onReveal = onReveal;
    _onRated = onRated;
    _onClosed = onClosed;
    _onSettlement = onSettlement;
    _onProgress = onProgress;
    _onChrome = onChrome;
    if (_opened && !_closed) {
      _onController();
    }
  }

  void detach(OfficialAnkiReviewerController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_onController);
    _controller = null;
  }

  /// Boots the transport. [_open] adds the controller once this returns.
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
      onSettlement: _onSettlement,
      onReplayAudio: _replayAudio,
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
    if (card == null) {
      // The controller moved (a rating advanced the session) but no face is
      // attached to the new item yet, so there is nothing to push. Without this
      // line the page simply keeps the previous card and the rating interlock
      // never releases — on device that read as "已提交，加载中…" until the
      // watchdog fired, with no error anywhere.
      final stamp = '${controller.generation}/${controller.presentGeneration}';
      if (stamp != _waitingFaceAt) {
        _waitingFaceAt = stamp;
        logger.w('[OhosReviewer] no card to present at generation $stamp '
            '(renderError=${controller.isRenderError})');
      }
      return;
    }
    _waitingFaceAt = '';
    final side = controller.showingAnswer
        ? OfficialAnkiReviewerProtocol.sideAnswer
        : OfficialAnkiReviewerProtocol.sideQuestion;
    final key = (card.cardId, side, controller.presentGeneration);
    // A render ack notifies this same controller. Scheduling that face again
    // would present twice and, on a failed ack, retry without bound.
    if (_scheduled == key) {
      logger.w('[OhosReviewer] present suppressed as a duplicate: $key');
      return;
    }
    _scheduled = key;
    logger.w('[OhosReviewer] present card=$key');
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
        final chrome = _onChrome?.call();
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
          sourceProgress: chrome?.sourceProgress,
          canRedo: chrome?.canRedo ?? false,
          canMutate: chrome?.canMutate ?? false,
          autoComplete: chrome?.autoComplete ?? false,
          chromeTheme: _chromeTheme,
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
