import 'dart:async';

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
    Future<void> Function()? onUndo,
    Future<Map<String, Object?>?> Function()? onSettlement,
    Future<String?> Function()? onReplayAudio,
  });

  Future<String> open({required String mediaRoot});

  Future<void> waitUntilReady();

  Future<void> pushMediaForCard(
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
    );
  }

  @override
  Future<String> open({required String mediaRoot}) =>
      channel.open(mediaRoot: mediaRoot);

  @override
  Future<void> waitUntilReady() => channel.waitUntilReady();

  @override
  Future<void> pushMediaForCard(
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
    required OfficialAnkiCourseGradesBridge grades,
    required this.mediaRoot,
    required OfficialAnkiMediaResolver resolver,
    int textZoom = 100,
    bool previewOnly = false,
    DateTime Function()? now,
  })  : _grades = grades,
        _resolver = resolver,
        _textZoom = textZoom,
        _previewOnly = previewOnly,
        _now = now ?? DateTime.now;

  static OfficialAnkiOhosReviewerBinding? _live;

  final OfficialAnkiOhosReviewerTransport transport;
  final String mediaRoot;
  OfficialAnkiCourseGradesBridge _grades;
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
  var _dark = false;
  var _textZoom = 100;
  var _previewOnly = false;
  var _opened = false;
  var _closed = false;
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
    OfficialAnkiOhosReviewerTransport? transport,
    DateTime Function()? now,
  }) async {
    final existing = _live;
    if (existing != null && !existing._closed) {
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
    try {
      await binding._open(controller);
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
  }) {
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
    if (_opened && !_closed) {
      _onController();
    }
  }

  void detach(OfficialAnkiReviewerController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_onController);
    _controller = null;
  }

  Future<void> _open(OfficialAnkiReviewerController controller) async {
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
    );
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

  /// Pushes the card's media, then presents. A present that runs first
  /// answers the shell's media request with 503 `MEDIA_NOT_PUSHED`.
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
          await transport.pushMediaForCard(_resolver, toPush);
          _pushedMediaNames.addAll(toPush);
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
    if (controller == null || card == null) {
      return OfficialAnkiReviewerProtocol.receiptNoCard;
    }
    final started = _answerShownAt;
    final elapsed =
        started == null ? 0 : _now().difference(started).inMilliseconds;
    final bool committed;
    try {
      committed = await _grades.answerOfficialCard(
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
    final code = ack?[OfficialAnkiReviewerProtocol.ackFieldStableCode]
        ?.toString();
    controller.onRenderFailure(
      code: code == null || code.isEmpty
          ? OfficialAnkiReviewerProtocol.renderTimeout
          : code,
      side: ackSide,
      generation: ackGeneration,
    );
  }
}
