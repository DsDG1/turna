import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_stage.dart';

/// Formal Official Review. Separate from preview/`canonicalLink`.
class OfficialAnkiReviewPage extends StatefulWidget {
  const OfficialAnkiReviewPage({
    super.key,
    required this.engine,
    required this.paths,
    this.deckId,
    this.allowedCardIds,
    this.flags,
    this.session,
    this.presenter,
  });

  static const routeName = '/official-anki/review';

  final OfficialAnkiEngine engine;
  final OfficialAnkiPaths paths;
  final int? deckId;
  final Set<int>? allowedCardIds;
  final OfficialAnkiFeatureFlags? flags;
  final OfficialReviewSession? session;
  final OfficialAnswerPresenter? presenter;

  @override
  State<OfficialAnkiReviewPage> createState() => _OfficialAnkiReviewPageState();
}

class _OfficialAnkiReviewPageState extends State<OfficialAnkiReviewPage> {
  late final OfficialReviewSession _session;
  OfficialAnswerPresenter? _presenter;
  OfficialAnkiReviewerController? _reviewerController;
  var _ownsPresenter = false;
  var _busy = true;
  var _awaitingAnswerAck = false;
  var _keepReviewerSurface = false;
  OfficialReviewQueueCard? _heldReviewCard;

  @override
  void initState() {
    super.initState();
    _session = widget.session ??
        OfficialReviewSession(
          engine: widget.engine,
          flags: widget.flags ?? OfficialAnkiFeatureFlags.current,
          allowedCardIds: widget.allowedCardIds,
        );
    final injected = widget.presenter;
    if (injected != null) {
      _presenter = injected;
      if (injected is OfficialAnkiReviewerController) {
        _reviewerController = injected;
      }
      injected.addListener(_onPresenterChanged);
    }
    _start();
  }

  Future<void> _start() async {
    try {
      final deckId = widget.deckId;
      if (deckId == null) {
        await _session.openDueDeck();
      } else {
        await _session.openDeck(deckId);
      }
      await _ensurePresenter();
      await _syncPresenter();
    } catch (error) {
      _session.applyFailure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensurePresenter() async {
    if (_presenter != null) return;
    final controller = await createOfficialAnkiReviewerController(
      paths: widget.paths,
    );
    _reviewerController = controller;
    _presenter = controller;
    _ownsPresenter = true;
    controller.addListener(_onPresenterChanged);
  }

  Future<void> _syncPresenter() async {
    final presenter = _presenter;
    final card = _session.current;
    if (presenter == null) return;
    if (_session.phase != OfficialReviewPhase.showingQuestion) {
      return;
    }
    if (card == null) {
      presenter.invalidateGeneration();
      return;
    }
    _awaitingAnswerAck = false;
    await presenter.loadAndShowQuestion(card.cardId);
  }

  void _onPresenterChanged() {
    if (!mounted || _session.disposed) return;
    final presenter = _presenter;
    if (presenter == null) return;
    if (_session.phase == OfficialReviewPhase.showingQuestion &&
        presenter.hasAnswerPresentAck) {
      _session.showAnswer();
      _awaitingAnswerAck = false;
    } else if (presenter.isRenderError) {
      _awaitingAnswerAck = false;
    }
    setState(() {});
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_session.disposed || _session.inFlight) return;
    setState(() => _busy = true);
    try {
      await work();
      if (!_session.disposed) {
        await _syncPresenter();
      }
    } catch (error) {
      _session.applyFailure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onShowAnswer() async {
    final presenter = _presenter;
    if (presenter == null || _busy || _awaitingAnswerAck) return;
    if (_session.phase != OfficialReviewPhase.showingQuestion) return;
    if (!presenter.hasQuestionPresentAck) return;
    setState(() => _awaitingAnswerAck = true);
    try {
      await presenter.showAnswer();
    } catch (error) {
      _awaitingAnswerAck = false;
      _session.applyFailure(error);
    }
    if (mounted) setState(() {});
  }

  Future<void> _retryQueue() {
    return _run(_session.refreshQueue);
  }

  @override
  void dispose() {
    _session.dispose();
    final presenter = _presenter;
    presenter?.removeListener(_onPresenterChanged);
    presenter?.invalidateGeneration();
    if (_ownsPresenter) {
      unawaited(presenter?.dispose() ?? Future<void>.value());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flags = widget.flags ?? OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialScheduler) {
      return const Scaffold(
        body: OfficialAnkiReviewerErrorView(
          key: Key('official-review-flag-fail-closed'),
          messageKey: 'official_anki.scheduler_flag_fail_closed',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Official Review'),
        actions: [
          IconButton(
            key: const Key('official-review-undo'),
            tooltip: 'Undo',
            onPressed: _actionsEnabled && _session.canUndo
                ? () => _run(_session.undo)
                : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const Key('official-review-redo'),
            tooltip: 'Redo',
            onPressed: _actionsEnabled && _session.canRedo
                ? () => _run(_session.redo)
                : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: _buildPhaseBody(),
    );
  }

  bool get _actionsEnabled =>
      !_busy && !_session.inFlight && !_session.disposed;

  bool get _canShowAnswer {
    final presenter = _presenter;
    return _actionsEnabled &&
        !_awaitingAnswerAck &&
        _session.phase == OfficialReviewPhase.showingQuestion &&
        presenter != null &&
        presenter.hasQuestionPresentAck &&
        !presenter.isRenderError;
  }

  bool get _canRate {
    final presenter = _presenter;
    return _actionsEnabled &&
        _session.phase == OfficialReviewPhase.showingAnswer &&
        presenter != null &&
        presenter.hasAnswerPresentAck &&
        !presenter.isRenderError;
  }

  bool get _canBury =>
      _actionsEnabled &&
      !_session.isFilteredDeck &&
      _session.current != null;

  Widget _buildPhaseBody() {
    switch (_session.phase) {
      case OfficialReviewPhase.idle:
      case OfficialReviewPhase.opening:
      case OfficialReviewPhase.loadingQueue:
        if (_keepReviewerSurface) return _reviewerColumn();
        return const Center(
          key: Key('official-review-loading'),
          child: CircularProgressIndicator(),
        );
      case OfficialReviewPhase.committingAnswer:
      case OfficialReviewPhase.refreshingQueue:
        if (_session.current != null || _keepReviewerSurface) {
          return _reviewerColumn();
        }
        return const Center(
          key: Key('official-review-loading'),
          child: CircularProgressIndicator(),
        );
      case OfficialReviewPhase.showingQuestion:
      case OfficialReviewPhase.showingAnswer:
        if (_session.current == null && _heldReviewCard == null) {
          return const _InvalidStateView();
        }
        return _reviewerColumn();
      case OfficialReviewPhase.reconciling:
        return _StatusView(
          key: const Key('official-review-reconciling'),
          messageKey: _session.lastError?.messageKey ??
              'official_anki.answer_commit_unknown',
          onRetry: _retryQueue,
          onBack: () => Navigator.of(context).maybePop(),
        );
      case OfficialReviewPhase.recoverableError:
      case OfficialReviewPhase.staleContext:
        return _StatusView(
          key: const Key('official-review-retry'),
          messageKey: _session.lastError?.messageKey ??
              'official_anki.scheduling_context_stale',
          onRetry: _retryQueue,
          onBack: () => Navigator.of(context).maybePop(),
        );
      case OfficialReviewPhase.fatalError:
        return _StatusView(
          key: const Key('official-review-fatal'),
          messageKey:
              _session.lastError?.messageKey ?? 'official_anki.internal_error',
          onBack: () => Navigator.of(context).maybePop(),
        );
      case OfficialReviewPhase.completed:
        if (_session.congrats != null && _session.current == null) {
          return _CongratsView(info: _session.congrats);
        }
        return const _InvalidStateView();
    }
  }

  Widget _reviewerColumn() {
    final card = _session.current;
    if (card != null) {
      _heldReviewCard = card;
    }
    final surfaceCard = card ?? _heldReviewCard;
    if (surfaceCard == null) {
      return const Center(
        key: Key('official-review-loading'),
        child: CircularProgressIndicator(),
      );
    }
    _keepReviewerSurface = true;
    final presenter = _presenter;
    return Column(
      children: [
        Expanded(child: _reviewerSurface()),
        if (presenter != null && presenter.isRenderError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              presenter.renderErrorCode ?? 'RENDER_ERROR',
              key: const Key('official-review-render-error'),
              textAlign: TextAlign.center,
            ),
          ),
        if (_session.phase == OfficialReviewPhase.showingQuestion)
          FilledButton(
            key: const Key('official-review-show-answer'),
            onPressed: _canShowAnswer ? _onShowAnswer : null,
            child: const Text('Show Answer'),
          ),
        if (_session.phase == OfficialReviewPhase.showingAnswer)
          _RatingRow(
            labels: surfaceCard.labels,
            enabled: _canRate,
            onRate: (rating) => _run(() => _session.answer(rating)),
          ),
        if (_session.isFilteredDeck)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              key: Key('official-review-filtered-unsupported'),
              'Bury/Suspend is not supported in this filtered deck.',
              textAlign: TextAlign.center,
            ),
          ),
        OverflowBar(
          children: [
            TextButton(
              key: const Key('official-review-bury'),
              onPressed: _canBury
                  ? () => _run(
                        () => _session.buryOrSuspend(
                          OfficialBuryOrSuspendAction.buryUser,
                        ),
                      )
                  : null,
              child: const Text('Bury card'),
            ),
            TextButton(
              key: const Key('official-review-bury-siblings'),
              onPressed: _canBury
                  ? () => _run(
                        () => _session.buryOrSuspend(
                          OfficialBuryOrSuspendAction.burySched,
                        ),
                      )
                  : null,
              child: const Text('Bury siblings'),
            ),
            TextButton(
              key: const Key('official-review-suspend'),
              onPressed: _canBury
                  ? () => _run(
                        () => _session.buryOrSuspend(
                          OfficialBuryOrSuspendAction.suspend,
                        ),
                      )
                  : null,
              child: const Text('Suspend card'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reviewerSurface() {
    final controller = _reviewerController;
    if (controller != null && Platform.isAndroid) {
      return OfficialAnkiReviewerStage(
        key: const Key('official-review-stage-host'),
        controller: controller,
        paths: widget.paths,
        sourceId: 'review',
        onBack: () => Navigator.of(context).maybePop(),
      );
    }
    final presenter = _presenter;
    if (presenter == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (Platform.isAndroid) {
      return const Center(child: CircularProgressIndicator());
    }
    return OfficialAnswerPresenterHostSurface(presenter: presenter);
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.labels,
    required this.enabled,
    required this.onRate,
  });

  final OfficialReviewIntervalLabels labels;
  final bool enabled;
  final ValueChanged<String> onRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final entry in [
            ('again', 'Again', labels.again),
            ('hard', 'Hard', labels.hard),
            ('good', 'Good', labels.good),
            ('easy', 'Easy', labels.easy),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton(
                  key: Key('official-review-${entry.$1}'),
                  onPressed: enabled ? () => onRate(entry.$1) : null,
                  child: Text('${entry.$2}\n${entry.$3}', textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CongratsView extends StatelessWidget {
  const _CongratsView({this.info});

  final OfficialCongratsInfo? info;

  @override
  Widget build(BuildContext context) {
    final data = info;
    return Center(
      child: Text(
        key: const Key('official-review-congrats'),
        data == null
            ? 'Congrats'
            : 'Congrats · new=${data.newRemaining} review=${data.reviewRemaining}',
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    super.key,
    required this.messageKey,
    this.onRetry,
    this.onBack,
  });

  final String messageKey;
  final Future<void> Function()? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return OfficialAnkiReviewerErrorView(
      messageKey: messageKey,
      onRetry: onRetry == null ? null : () { onRetry!(); },
      onBack: onBack,
    );
  }
}

class _InvalidStateView extends StatelessWidget {
  const _InvalidStateView();

  @override
  Widget build(BuildContext context) {
    return const OfficialAnkiReviewerErrorView(
      key: Key('official-review-invalid-state'),
      messageKey: 'official_anki.invalid_review_state',
    );
  }
}
