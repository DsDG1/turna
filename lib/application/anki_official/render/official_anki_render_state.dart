import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';

enum OfficialAnkiReviewerPhase {
  idle,
  loadingCard,
  questionReady,
  showingQuestion,
  comparingTypedAnswer,
  showingAnswer,
  clearing,
  recoverableError,
  fatalError,
  disposed,
}

enum OfficialAnkiReviewerSurface {
  rendering,
  visible,
  recoverableError,
  fatalError,
}

class OfficialAnkiReviewerUi {
  const OfficialAnkiReviewerUi.rendering({this.side, this.generation})
      : surface = OfficialAnkiReviewerSurface.rendering,
        code = null;

  const OfficialAnkiReviewerUi.visible({this.side, this.generation})
      : surface = OfficialAnkiReviewerSurface.visible,
        code = null;

  const OfficialAnkiReviewerUi.recoverableError({
    required this.code,
    required this.side,
    required this.generation,
  }) : surface = OfficialAnkiReviewerSurface.recoverableError;

  const OfficialAnkiReviewerUi.fatalError({required this.code})
      : surface = OfficialAnkiReviewerSurface.fatalError,
        side = null,
        generation = null;

  final OfficialAnkiReviewerSurface surface;
  final String? code;
  final String? side;
  final int? generation;

  bool get offersRetryCurrentSide =>
      surface == OfficialAnkiReviewerSurface.recoverableError;

  bool get offersBack =>
      surface == OfficialAnkiReviewerSurface.recoverableError ||
      surface == OfficialAnkiReviewerSurface.fatalError;

  bool get isError =>
      surface == OfficialAnkiReviewerSurface.recoverableError ||
      surface == OfficialAnkiReviewerSurface.fatalError;

  static const recoverableCodes = <String>{
    'RENDER_TIMEOUT',
    'RENDER_SUPERSEDED',
    'MATHJAX_ASSET_MISSING',
    'MATHJAX_TYPESET_FAILED',
    'SHELL_ASSET_MISSING',
    'FRAME_ASSET_MISSING',
    'WEBVIEW_MAIN_FRAME_ERROR',
    'SHELL_NOT_READY',
  };

  static const fatalCodes = <String>{
    'UNRENDERABLE_CARD',
    'UNRENDERABLE_TEMPLATE',
    'CARD_NOT_FOUND',
    'FATAL_RENDER_ERROR',
  };

  static bool isRecoverableCode(String code) {
    if (fatalCodes.contains(code)) return false;
    return recoverableCodes.contains(code);
  }
}

class OfficialAnkiReviewerController implements OfficialAnswerPresenter {
  OfficialAnkiReviewerController({
    required this.facade,
    required this.av,
    required OfficialAnkiTypedAnswerController typed,
  }) : _typed = typed;

  final OfficialAnkiRenderFacade facade;
  final OfficialAnkiAvCoordinator av;
  final OfficialAnkiTypedAnswerController _typed;
  final _listeners = <void Function()>[];

  OfficialAnkiReviewerPhase phase = OfficialAnkiReviewerPhase.idle;
  OfficialAnkiReviewerUi ui = const OfficialAnkiReviewerUi.rendering();
  OfficialAnkiRenderedCard? card;
  OfficialAnkiException? error;
  @override
  OfficialPresentAck? lastAck;
  var generation = 0;
  var cardToken = 0;
  @override
  var presentGeneration = 0;
  var presentEpoch = 0;
  var showingAnswer = false;
  var replayBusy = false;
  var _autoplay = false;
  var _avPlayGeneration = 0;
  Duration? lastRenderDuration;

  OfficialAnkiTypedAnswerController get typed => _typed;

  String? get avHint => av.lastError;

  @override
  int get presentedCardId => card?.cardId ?? 0;

  @override
  String get currentSide => showingAnswer ? 'answer' : 'question';

  @override
  bool get hasAnswerPresentAck => _ackMatches(side: 'answer');

  @override
  bool get hasQuestionPresentAck => _ackMatches(side: 'question');

  @override
  bool get isRenderError => ui.isError;

  @override
  String? get renderErrorCode => ui.code;

  bool _ackMatches({required String side}) {
    final ack = lastAck;
    final current = card;
    return ack != null &&
        ack.ok &&
        ack.side == side &&
        current != null &&
        ack.cardId == current.cardId &&
        ack.generation == presentGeneration;
  }

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  @override
  Future<void> loadAndShowQuestion(int cardId) async {
    lastAck = null;
    // Do not notify with a card while presentGeneration is still the previous
    // side. That would create the PlatformView and present once, then
    // showQuestion() would bump generation and present again (SUPERSEDED).
    await loadCard(cardId, notify: false);
    if (phase == OfficialAnkiReviewerPhase.questionReady) {
      await showQuestion();
      return;
    }
    _notify();
  }

  Future<void> loadCard(int cardId, {bool notify = true}) async {
    final token = ++generation;
    cardToken = token;
    phase = OfficialAnkiReviewerPhase.loadingCard;
    ui = OfficialAnkiReviewerUi.rendering(side: 'question', generation: token);
    showingAnswer = false;
    error = null;
    lastAck = null;
    await av.nextCard();
    final started = DateTime.now();
    try {
      final rendered = await facade.renderCard(cardId: cardId, browser: false);
      if (token != generation) return;
      card = rendered;
      lastRenderDuration = DateTime.now().difference(started);
      _typed.attach(rendered.typedAnswer);
      av.attachCard(rendered);
      phase = OfficialAnkiReviewerPhase.questionReady;
      if (notify) _notify();
    } on OfficialAnkiException catch (caught) {
      if (token != generation) return;
      error = caught;
      phase = caught.recoverable
          ? OfficialAnkiReviewerPhase.recoverableError
          : OfficialAnkiReviewerPhase.fatalError;
      ui = caught.recoverable
          ? OfficialAnkiReviewerUi.recoverableError(
              code: caught.code.name.toUpperCase(),
              side: 'question',
              generation: token,
            )
          : OfficialAnkiReviewerUi.fatalError(
              code: caught.code.name.toUpperCase(),
            );
      if (notify) _notify();
    }
  }

  Future<void> showQuestion({bool autoplay = true}) async {
    if (card == null) return;
    await av.stop();
    phase = OfficialAnkiReviewerPhase.showingQuestion;
    showingAnswer = false;
    _typed.restoreInputOnQuestion();
    _beginPresent(autoplay: autoplay);
    _notify();
  }

  @override
  Future<void> showAnswer({bool autoplay = true}) async {
    final current = card;
    if (current == null) return;
    final token = generation;
    if (current.typedAnswer != null && _typed.comparison == null) {
      phase = OfficialAnkiReviewerPhase.comparingTypedAnswer;
      try {
        await _typed.compare(
          cardId: current.cardId,
          generation: _typed.generation,
        );
      } on OfficialAnkiException catch (caught) {
        if (token != generation) return;
        error = OfficialAnkiException(
          code: caught.code,
          messageKey: caught.messageKey,
          recoverable: true,
          debugDetails: caught.debugDetails,
        );
        phase = OfficialAnkiReviewerPhase.recoverableError;
        ui = OfficialAnkiReviewerUi.recoverableError(
          code: 'TYPED_COMPARE_FAILED',
          side: 'answer',
          generation: presentGeneration,
        );
        _notify();
        return;
      }
      if (token != generation) return;
      if (_typed.phase == OfficialAnkiTypedPhase.recoverableError) {
        error = _typed.error;
        phase = OfficialAnkiReviewerPhase.recoverableError;
        ui = OfficialAnkiReviewerUi.recoverableError(
          code: 'TYPED_COMPARE_FAILED',
          side: 'answer',
          generation: presentGeneration,
        );
        _notify();
        return;
      }
    }
    await av.stop();
    phase = OfficialAnkiReviewerPhase.showingAnswer;
    showingAnswer = true;
    _beginPresent(autoplay: autoplay);
    _notify();
  }

  void _beginPresent({required bool autoplay}) {
    presentGeneration += 1;
    presentEpoch += 1;
    lastAck = null;
    _autoplay = autoplay;
    _avPlayGeneration = av.generation;
    ui = OfficialAnkiReviewerUi.rendering(
      side: currentSide,
      generation: presentGeneration,
    );
  }

  void onRenderComplete({
    required int generation,
    required String side,
  }) {
    if (generation != presentGeneration) return;
    if (side != currentSide) return;
    lastAck = OfficialPresentAck(
      cardId: presentedCardId,
      generation: generation,
      side: side,
      ok: true,
    );
    ui = OfficialAnkiReviewerUi.visible(side: side, generation: generation);
    _notify();
    if (!_autoplay) return;
    final avSide =
        side == 'answer' ? OfficialAnkiAvSide.answer : OfficialAnkiAvSide.question;
    // Flip must not wait for AV/TTS. Old-generation completion is ignored.
    av.startAutoplay(side: avSide, token: _avPlayGeneration);
  }

  void onRenderFailure({
    required String code,
    required String side,
    required int generation,
  }) {
    if (generation != presentGeneration && generation != 0) return;
    lastAck = OfficialPresentAck(
      cardId: presentedCardId,
      generation: generation == 0 ? presentGeneration : generation,
      side: side,
      ok: false,
      code: code,
    );
    if (OfficialAnkiReviewerUi.isRecoverableCode(code)) {
      error = OfficialAnkiException(
        code: OfficialAnkiErrorCode.renderFailed,
        messageKey: 'official_anki.render_failed',
        recoverable: true,
        debugDetails: code,
      );
      phase = OfficialAnkiReviewerPhase.recoverableError;
      ui = OfficialAnkiReviewerUi.recoverableError(
        code: code,
        side: side,
        generation: generation == 0 ? presentGeneration : generation,
      );
      _notify();
      return;
    }
    error = OfficialAnkiException(
      code: OfficialAnkiErrorCode.renderFailed,
      messageKey: 'official_anki.render_failed',
      debugDetails: code,
    );
    phase = OfficialAnkiReviewerPhase.fatalError;
    ui = OfficialAnkiReviewerUi.fatalError(code: code);
    _notify();
  }

  @override
  OfficialPresentAck? acceptPresent(OfficialPresentAck ack) {
    if (ack.cardId != presentedCardId) return null;
    if (ack.generation != presentGeneration) return null;
    if (ack.side != currentSide) return null;
    if (ack.ok) {
      onRenderComplete(generation: ack.generation, side: ack.side);
    } else {
      onRenderFailure(
        code: ack.code ?? 'RENDER_TIMEOUT',
        side: ack.side,
        generation: ack.generation,
      );
    }
    return lastAck;
  }

  @override
  void invalidateGeneration() {
    generation += 1;
    presentGeneration += 1;
    lastAck = null;
    _notify();
  }

  Future<void> retryCurrentSide() async {
    if (!ui.offersRetryCurrentSide) return;
    error = null;
    if (showingAnswer) {
      await showAnswer(autoplay: _autoplay);
    } else {
      await showQuestion(autoplay: _autoplay);
    }
  }

  Future<void> replay() async {
    replayBusy = true;
    _notify();
    try {
      await av.replay();
    } finally {
      replayBusy = false;
      _notify();
    }
  }

  Future<void> clear() async {
    phase = OfficialAnkiReviewerPhase.clearing;
    await av.nextCard();
    card = null;
    showingAnswer = false;
    lastAck = null;
    phase = OfficialAnkiReviewerPhase.idle;
    ui = const OfficialAnkiReviewerUi.rendering();
    _notify();
  }

  @override
  Future<void> dispose() async {
    generation += 1;
    presentGeneration += 1;
    lastAck = null;
    phase = OfficialAnkiReviewerPhase.disposed;
    await av.dispose();
    _listeners.clear();
  }
}
