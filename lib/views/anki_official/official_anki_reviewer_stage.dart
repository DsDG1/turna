import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_answer_presenter.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_ohos_reviewer_binding.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/l10n/app_strings.dart';
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
    this.allowJs = true,
    this.grades,
    this.onNativeReveal,
    this.onNativeRated,
  });

  final OfficialAnkiReviewerController controller;
  final OfficialAnkiPaths paths;
  final String sourceId;
  final bool showPreviewControls;
  final VoidCallback? onBack;
  final bool allowJs;
  final OfficialAnkiCourseGradesBridge? grades;
  final VoidCallback? onNativeReveal;

  /// Returns whether the session advanced to another card (`true`) or the
  /// queue finished (`false`); the OHOS page swaps the rating row for a
  /// completion row on `false`.
  final Future<bool> Function(String rating)? onNativeRated;

  @override
  State<OfficialAnkiReviewerStage> createState() =>
      _OfficialAnkiReviewerStageState();
}

class _OfficialAnkiReviewerStageState extends State<OfficialAnkiReviewerStage> {
  OfficialAnkiReviewerController get _controller => widget.controller;
  OfficialAnkiRenderedCard? _heldCard;
  var _surfaceReleased = false;
  int? _blockedJsGeneration;
  OfficialAnkiOhosReviewerBinding? _ohos;
  Object? _ohosError;
  var _dark = false;

  OfficialAnkiCourseGradesBridge get _grades =>
      widget.grades ??
      OfficialAnkiCourseGradesBridgeImpl(
        flags: OfficialAnkiFeatureFlags.current
            .copyWith(courseGradesScheduler: true),
      );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    if (isHarmonyOsTarget) {
      unawaited(_startOhos());
    }
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiReviewerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      _rebindOhos();
      return;
    }
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
    _rebindOhos();
  }

  @override
  void dispose() {
    _ohos?.detach(_controller);
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _startOhos() async {
    try {
      final binding = await OfficialAnkiOhosReviewerBinding.attach(
        controller: _controller,
        grades: _grades,
        mediaRoot: widget.paths.mediaFolder.path,
        resolver: OfficialAnkiMediaResolver(widget.paths.mediaFolder),
        sourceId: widget.sourceId,
        dark: _dark,
        onReveal: widget.onNativeReveal,
        onRated: widget.onNativeRated,
      );
      if (!mounted) {
        binding.detach(_controller);
        return;
      }
      setState(() {
        _ohos = binding;
        _ohosError = null;
      });
      _rebindOhos();
    } catch (error, stack) {
      logger.w('[OhosReviewer] failed to open',
          error: error, stackTrace: stack);
      if (!mounted) return;
      setState(() => _ohosError = error);
    }
  }

  void _rebindOhos() {
    final binding = _ohos;
    if (!isHarmonyOsTarget || binding == null) return;
    binding.rebind(
      controller: _controller,
      grades: _grades,
      resolver: OfficialAnkiMediaResolver(widget.paths.mediaFolder),
      sourceId: widget.sourceId,
      dark: _dark,
      onReveal: widget.onNativeReveal,
      onRated: widget.onNativeRated,
    );
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
      logger.w('[OfficialAnkiReviewer] flip error $error');
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
    _dark = Theme.of(context).brightness == Brightness.dark;
    _ohos?.setDark(_dark);
    if (isHarmonyOsTarget) {
      return _buildOhos();
    }
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
    final forceDisableJs = context.select<SettingsProvider?, bool>(
      (settings) => settings?.ankiForceDisableJs ?? false,
    );
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
        Expanded(
            child: _buildSurface(controller, card, cardTextScale,
                allowJs: widget.allowJs && !forceDisableJs)),
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
                  labelText: AppStrings.ankiTypedAnswerLabel,
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
                    child: Text(controller.showingAnswer
                        ? AppStrings.ankiShowFront
                        : AppStrings.ankiShowAnswer),
                  ),
                ),
                if (hasReplayableAv) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: AppStrings.commonReplayAudio,
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
              tooltip: AppStrings.commonReplayAudio,
              onPressed: controller.replayBusy ? null : _replay,
              icon: const Icon(Icons.replay),
            ),
          ),
      ],
    );
  }

  Widget _buildOhos() {
    final error = _ohosError;
    return Column(
      key: const Key('official-review-stage'),
      children: [
        Expanded(
          child: error == null
              ? const Center(child: CircularProgressIndicator())
              : OfficialAnkiReviewerErrorView(
                  messageKey: 'official_anki.render_failed',
                  onRetry: () {
                    setState(() => _ohosError = null);
                    unawaited(_startOhos());
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSurface(OfficialAnkiReviewerController controller,
      OfficialAnkiRenderedCard? card, int cardTextScale,
      {required bool allowJs}) {
    if (!allowJs) {
      final generation = controller.presentGeneration;
      final side = controller.currentSide;
      if (_blockedJsGeneration != generation) {
        _blockedJsGeneration = generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !identical(controller, _controller) ||
              generation != controller.presentGeneration ||
              side != controller.currentSide) {
            return;
          }
          controller.onRenderFailure(
              code: 'official_anki.renderer_flag_fail_closed',
              side: side,
              generation: generation);
        });
      }
      // The official shell needs JavaScript for its render ACK. Until it has
      // a script-free contract, honour the user's hard off-switch by failing
      // closed instead of executing imported scripts or issuing a fake ACK.
      return const OfficialAnkiReviewerErrorView(
          messageKey: 'official_anki.renderer_flag_fail_closed');
    }
    _blockedJsGeneration = null;
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
            final generation = result.generation;
            final side = result.side;
            if (generation == null || side == null) return;
            controller.onRenderComplete(
              generation: generation,
              side: side,
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
