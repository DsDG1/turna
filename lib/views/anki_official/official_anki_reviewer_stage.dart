import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_view.dart';

/// Card surface without Scaffold/AppBar. Formal review embeds this; preview
/// wraps it and optionally keeps flip/replay chrome.
class OfficialAnkiReviewerStage extends StatefulWidget {
  const OfficialAnkiReviewerStage({
    super.key,
    required this.controller,
    required this.paths,
    required this.sourceId,
    this.showPreviewControls = false,
    this.onBack,
  });

  final OfficialAnkiReviewerController controller;
  final OfficialAnkiPaths paths;
  final String sourceId;
  final bool showPreviewControls;
  final VoidCallback? onBack;

  @override
  State<OfficialAnkiReviewerStage> createState() =>
      _OfficialAnkiReviewerStageState();
}

class _OfficialAnkiReviewerStageState extends State<OfficialAnkiReviewerStage> {
  OfficialAnkiReviewerController get _controller => widget.controller;
  OfficialAnkiRenderedCard? _heldCard;
  var _surfaceReleased = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiReviewerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _flip() async {
    try {
      if (_controller.showingAnswer) {
        await _controller.showQuestion();
      } else {
        await _controller.showAnswer();
      }
    } catch (error) {
      debugPrint('[OfficialAnkiReviewer] flip error $error');
    }
  }

  Future<void> _retry() async {
    await _controller.retryCurrentSide();
  }

  Future<void> _replay() async {
    if (_controller.replayBusy) return;
    await _controller.replay();
  }

  @override
  Widget build(BuildContext context) {
    final flags = OfficialAnkiFeatureFlags.current;
    final controller = _controller;
    final card = controller.card;
    final cardTextScale = cardTextScaleOf(context);
    // The replay button replays the card author's own AV tags; hide it on
    // cards without media instead of offering a no-op "system read aloud".
    final hasReplayableAv = card != null &&
        (controller.showingAnswer
            ? card.answerAvTags.isNotEmpty
            : card.questionAvTags.isNotEmpty);
    return Column(
      key: const Key('official-review-stage'),
      children: [
        if (widget.showPreviewControls &&
            (flags.reviewerDiagnostics || kDebugMode))
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'source=${widget.sourceId} card=${controller.presentedCardId} '
              'mode=${OfficialAnkiCompositionRoot.executionMode.name} '
              'backend=${controller.facade.info.backendCommit} '
              'caps=${controller.facade.info.has('RENDER_CARD')} '
              'renderMs=${controller.lastRenderDuration?.inMilliseconds ?? "-"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(child: _buildSurface(controller, card, cardTextScale)),
        if (controller.avHint != null && !controller.ui.isError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              OfficialAnkiReviewerErrorView.localize(controller.avHint!),
              textAlign: TextAlign.center,
            ),
          ),
        if (controller.typed.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              OfficialAnkiReviewerErrorView.localize(
                controller.typed.error!.messageKey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        if (card?.typedAnswer != null && !controller.showingAnswer)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            // fontSizePx is the notetype's own field size: scale it by the
            // card zoom only (the WebView comparison HTML scales the same
            // way via textZoom) and freeze the root textScaler so it is not
            // multiplied on top.
            child: MediaQuery.withNoTextScaling(
              child: TextField(
                enabled: !controller.typed.frozen,
                decoration: InputDecoration(
                  labelText: '输入答案',
                  hintText: card!.typedAnswer!.marker,
                ),
                style: TextStyle(
                  fontFamily: card.typedAnswer!.fontFamily,
                  fontSize:
                      card.typedAnswer!.fontSizePx * cardTextScale / 100.0,
                ),
                onChanged: controller.typed.updateProvided,
              ),
            ),
          ),
        if (widget.showPreviewControls)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _flip,
                    child: Text(controller.showingAnswer ? '正面' : '显示答案'),
                  ),
                ),
                if (hasReplayableAv) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: controller.replayBusy ? null : _replay,
                    icon: const Icon(Icons.replay),
                  ),
                ],
              ],
            ),
          )
        else if (hasReplayableAv)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: controller.replayBusy ? null : _replay,
              icon: const Icon(Icons.replay),
            ),
          ),
      ],
    );
  }

  Widget _buildSurface(
    OfficialAnkiReviewerController controller,
    OfficialAnkiRenderedCard? card,
    int cardTextScale,
  ) {
    if (card != null) {
      _heldCard = card;
      _surfaceReleased = true;
    }
    final surfaceCard = card ?? _heldCard;
    if (surfaceCard == null) {
      assert(!_surfaceReleased);
      return const Center(child: CircularProgressIndicator());
    }
    _surfaceReleased = true;
    final recoverable =
        controller.ui.surface == OfficialAnkiReviewerSurface.recoverableError;
    return Stack(
      fit: StackFit.expand,
      children: [
        OfficialAnkiReviewerView(
          key: const Key('official-anki-reviewer-view'),
          mediaRoot: widget.paths.mediaFolder.path,
          card: surfaceCard,
          showingAnswer: controller.showingAnswer,
          comparisonHtml: controller.typed.comparison?.comparisonHtml,
          dark: Theme.of(context).brightness == Brightness.dark,
          textZoom: cardTextScale,
          presentGeneration: controller.presentGeneration,
          presentEpoch: controller.presentEpoch,
          onRenderComplete: (result) {
            controller.onRenderComplete(
              generation: result.generation ?? controller.presentGeneration,
              side: result.side ?? controller.currentSide,
            );
          },
          onRenderError: (message) {
            controller.onRenderFailure(
              code: message,
              side: controller.currentSide,
              generation: controller.presentGeneration,
            );
          },
        ),
        if (controller.ui.isError && recoverable)
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(
                    alpha: 0.94,
                  ),
              child: OfficialAnkiReviewerErrorView.fromUi(
                ui: controller.ui,
                error: controller.error,
                onRetry: _retry,
                onBack: widget.onBack,
              ),
            ),
          )
        else if (controller.ui.isError)
          // Alpha < 1 keeps the Android PlatformView from being disposed as occluded.
          ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(
                  alpha: 0.92,
                ),
            child: OfficialAnkiReviewerErrorView.fromUi(
              ui: controller.ui,
              error: controller.error,
              onRetry: _retry,
              onBack: widget.onBack,
            ),
          ),
      ],
    );
  }
}

/// Host/test surface. Does not replace the presenter; tests drive ACK on it.
class OfficialAnswerPresenterHostSurface extends StatelessWidget {
  const OfficialAnswerPresenterHostSurface({
    super.key,
    required this.presenter,
  });

  final OfficialAnswerPresenter presenter;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('official-review-stage'),
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'card=${presenter.presentedCardId} '
              'side=${presenter.currentSide} '
              'gen=${presenter.presentGeneration}',
            ),
            if (presenter.isRenderError)
              Text(
                presenter.renderErrorCode ?? 'render-error',
                key: const Key('official-review-render-error'),
              ),
          ],
        ),
      ),
    );
  }
}
