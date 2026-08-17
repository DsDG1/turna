import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_av_player_adapter.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_view.dart';

/// Internal official card preview. Does not write grades or schedules.
class OfficialAnkiReviewerPage extends StatefulWidget {
  const OfficialAnkiReviewerPage({
    super.key,
    required this.sourceId,
    required this.cardId,
    required this.paths,
    this.facade,
    this.controller,
  });

  final String sourceId;
  final int cardId;
  final OfficialAnkiPaths paths;
  final OfficialAnkiRenderFacade? facade;
  final OfficialAnkiReviewerController? controller;

  @override
  State<OfficialAnkiReviewerPage> createState() =>
      _OfficialAnkiReviewerPageState();
}

class _OfficialAnkiReviewerPageState extends State<OfficialAnkiReviewerPage> {
  OfficialAnkiReviewerController? _controller;
  Object? _bootError;
  var _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (widget.controller != null) {
        _controller = widget.controller;
      } else {
        final facade = widget.facade ?? await OfficialAnkiRenderFacade.fromWorker();
        _controller = OfficialAnkiReviewerController(
          facade: facade,
          av: OfficialAnkiAvCoordinator(
            resolver: OfficialAnkiMediaResolver(widget.paths.mediaFolder),
            player: OfficialAnkiAvPlayerAdapter(audio: getIt<AudioController>()),
          ),
          typed: OfficialAnkiTypedAnswerController(facade),
        );
      }
      await _controller!.loadCard(widget.cardId);
      if (_controller!.phase == OfficialAnkiReviewerPhase.questionReady) {
        await _controller!.showQuestion();
      }
    } catch (error, stack) {
      debugPrint('[OfficialAnkiReviewer] boot error $error\n$stack');
      _bootError = error;
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  Future<void> _flip() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (controller.showingAnswer) {
        await controller.showQuestion();
      } else {
        await controller.showAnswer();
      }
    } catch (error) {
      debugPrint('[OfficialAnkiReviewer] flip error $error');
    }
    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.retryCurrentSide();
    if (mounted) setState(() {});
  }

  Future<void> _replay() async {
    final controller = _controller;
    if (controller == null || controller.replayBusy) return;
    await controller.replay();
    if (mounted) setState(() {});
  }

  Widget _buildStage(
    OfficialAnkiReviewerController controller,
    OfficialAnkiRenderedCard? card,
  ) {
    if (controller.ui.isError) {
      return OfficialAnkiReviewerErrorView.fromUi(
        ui: controller.ui,
        error: controller.error,
        onRetry: _retry,
        onBack: () => Navigator.of(context).maybePop(),
      );
    }
    if (card == null) {
      return const SizedBox.shrink();
    }
    return OfficialAnkiReviewerView(
      mediaRoot: widget.paths.mediaFolder.path,
      card: card,
      showingAnswer: controller.showingAnswer,
      comparisonHtml: controller.typed.comparison?.comparisonHtml,
      dark: Theme.of(context).brightness == Brightness.dark,
      presentGeneration: controller.presentGeneration,
      presentEpoch: controller.presentEpoch,
      onRenderComplete: (result) {
        controller.onRenderComplete(
          generation: result.generation ?? controller.presentGeneration,
          side: result.side ?? controller.currentSide,
        );
        if (mounted) setState(() {});
      },
      onRenderError: (message) {
        controller.onRenderFailure(
          code: message,
          side: controller.currentSide,
          generation: controller.presentGeneration,
        );
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final flags = OfficialAnkiFeatureFlags.current;
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bootError != null) {
      final error = _bootError;
      return Scaffold(
        appBar: AppBar(title: const Text('官方卡片')),
        body: OfficialAnkiReviewerErrorView(
          messageKey: error is OfficialAnkiException
              ? error.messageKey
              : 'official_anki.render_failed',
          debugDetails: kDebugMode ? error.toString() : null,
        ),
      );
    }
    final controller = _controller!;
    if (controller.card == null &&
        (controller.phase == OfficialAnkiReviewerPhase.fatalError ||
            controller.phase == OfficialAnkiReviewerPhase.recoverableError)) {
      return Scaffold(
        appBar: AppBar(title: const Text('官方卡片')),
        body: OfficialAnkiReviewerErrorView.fromException(
          controller.error ??
              const OfficialAnkiException(
                code: OfficialAnkiErrorCode.renderFailed,
                messageKey: 'official_anki.render_failed',
              ),
        ),
      );
    }
    final card = controller.card;
    return Scaffold(
      appBar: AppBar(title: const Text('官方卡片预览')),
      body: Column(
        children: [
          if (flags.reviewerDiagnostics || kDebugMode)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'source=${widget.sourceId} card=${widget.cardId} '
                'mode=${OfficialAnkiCompositionRoot.executionMode.name} '
                'backend=${controller.facade.info.backendCommit} '
                'caps=${controller.facade.info.has('RENDER_CARD')} '
                'renderMs=${controller.lastRenderDuration?.inMilliseconds ?? "-"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: _buildStage(controller, card),
          ),
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
                OfficialAnkiReviewerErrorView.localize(controller.typed.error!.messageKey),
                textAlign: TextAlign.center,
              ),
            ),
          if (card?.typedAnswer != null && !controller.showingAnswer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                enabled: !controller.typed.frozen,
                decoration: InputDecoration(
                  labelText: '输入答案',
                  hintText: card!.typedAnswer!.marker,
                ),
                style: TextStyle(
                  fontFamily: card.typedAnswer!.fontFamily,
                  fontSize: card.typedAnswer!.fontSizePx.toDouble(),
                ),
                onChanged: controller.typed.updateProvided,
              ),
            ),
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
                const SizedBox(width: 8),
                IconButton(
                  onPressed: controller.replayBusy ? null : _replay,
                  icon: const Icon(Icons.replay),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
