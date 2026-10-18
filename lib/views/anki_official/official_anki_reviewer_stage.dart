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
import 'package:turna/application/anki_official/render/official_anki_reviewer_protocol.dart';
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
    this.onNativeClosed,
    this.onNativeSettlement,
    this.onNativeProgress,
    this.onNativeChrome,
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

  /// Fired when the OHOS ability resolves its open — the learner left the
  /// native reviewer (back gesture, error exit, system kill). The hosting
  /// page settles the answered part and pops; without this the exposed
  /// Flutter page shows a spinner where the card was (B8).
  final void Function(String verdict)? onNativeClosed;

  /// OHOS completion-row statistics (UI-7): answered/remembered/forgotten/
  /// seconds/xp, delivered to the native page when the queue finishes.
  final Future<Map<String, Object?>?> Function()? onNativeSettlement;

  /// OHOS header progress (UI-4): `(index, total)` for the count and bar.
  final (int, int)? Function()? onNativeProgress;

  /// OHOS chrome state the native page cannot derive (UI-15): the Review All
  /// source badge and which of the four theme variants to paint.
  final OfficialReviewerChromeSnapshot Function()? onNativeChrome;

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
  var _ohosStarting = false;
  var _ohosClosed = false;
  var _dark = false;
  var _chromeTheme = OfficialAnkiReviewerProtocol.chromeLight;
  var _textZoom = 100;

  OfficialAnkiCourseGradesBridge get _grades =>
      widget.grades ??
      OfficialAnkiCourseGradesBridgeImpl(
        flags: OfficialAnkiFeatureFlags.current.copyWith(
          courseGradesScheduler: !widget.showPreviewControls,
        ),
      );

  bool _effectiveAllowJs(BuildContext context) {
    final forceDisableJs = Provider.of<SettingsProvider?>(
          context,
          listen: false,
        )?.ankiForceDisableJs ??
        false;
    return widget.allowJs && !forceDisableJs;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  /// Reads the three chrome values the native page cannot derive.
  ///
  /// Called from `didChangeDependencies` **before** the binding is attached, not
  /// only from `build`. `attach` presents the first card, and the payload for
  /// that present is built from these fields; computing them in `build` alone
  /// meant the first present of every session carried the constructor defaults
  /// (`dark: false`, `chromeTheme: 'light'`). On a dark app that showed as a
  /// dark card inside a light native chrome — or, on a freshly created Stage
  /// that had not built yet, a light card inside a dark app.
  void _syncChrome() {
    _dark = Theme.of(context).brightness == Brightness.dark;
    _textZoom = cardTextScaleOf(context);
    // `accessibilityOf` is the crash-free reader (it falls back to neutral
    // defaults when the provider is absent, which is every widget test).
    _chromeTheme = OfficialAnkiReviewerProtocol.chromeThemeFor(
      dark: _dark,
      highContrast: accessibilityOf(context).highContrast,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncChrome();
    if (isHarmonyOsTarget &&
        _effectiveAllowJs(context) &&
        _ohos == null &&
        !_ohosStarting &&
        _ohosError == null &&
        !_ohosClosed) {
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
    if (_ohosStarting) return;
    _ohosStarting = true;
    final started = DateTime.now();
    logger.w('[OhosReviewer] stage attach card=${_controller.card?.cardId}');
    try {
      final binding = await OfficialAnkiOhosReviewerBinding.attach(
        controller: _controller,
        grades: _grades,
        mediaRoot: widget.paths.mediaFolder.path,
        resolver: OfficialAnkiMediaResolver(widget.paths.mediaFolder),
        sourceId: widget.sourceId,
        dark: _dark,
        textZoom: _textZoom,
        previewOnly: widget.showPreviewControls,
        chromeTheme: _chromeTheme,
        onReveal: widget.onNativeReveal,
        onRated: widget.onNativeRated,
        onClosed: _onAbilityClosed,
        onSettlement: widget.onNativeSettlement,
        onProgress: widget.onNativeProgress,
        onChrome: widget.onNativeChrome,
      );
      if (!mounted || !_effectiveAllowJs(context)) {
        binding.detach(_controller);
        return;
      }
      logger.w('[OhosReviewer] stage attached in '
          '${DateTime.now().difference(started).inMilliseconds}ms');
      setState(() {
        _ohos = binding;
        _ohosError = null;
        _ohosClosed = false;
      });
      _rebindOhos();
    } catch (error, stack) {
      logger.w('[OhosReviewer] failed to open',
          error: error, stackTrace: stack);
      if (!mounted) return;
      setState(() => _ohosError = error);
    } finally {
      _ohosStarting = false;
    }
  }

  /// The ability resolved its open. The page above settles and pops; this
  /// side stops pretending a card is arriving (the pre-fix behaviour was an
  /// forever-spinner where the card had been).
  void _onAbilityClosed(String verdict) {
    if (!mounted) return;
    setState(() => _ohosClosed = true);
    if (widget.onNativeClosed != null) {
      widget.onNativeClosed!(verdict);
    } else if (widget.showPreviewControls) {
      widget.onBack?.call();
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
      textZoom: _textZoom,
      previewOnly: widget.showPreviewControls,
      chromeTheme: _chromeTheme,
      onReveal: widget.onNativeReveal,
      onRated: widget.onNativeRated,
      onClosed: _onAbilityClosed,
      onSettlement: widget.onNativeSettlement,
      onProgress: widget.onNativeProgress,
      onChrome: widget.onNativeChrome,
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
    final flags = OfficialAnkiFeatureFlags.current;
    final controller = _controller;
    final card = controller.card;
    final cardTextScale = cardTextScaleOf(context);
    final forceDisableJs = context.select<SettingsProvider?, bool>(
      (settings) => settings?.ankiForceDisableJs ?? false,
    );
    final allowJs = widget.allowJs && !forceDisableJs;
    _syncChrome();
    _ohos
      ?..setDark(_dark)
      ..setTextZoom(cardTextScale)
      ..setPreviewOnly(widget.showPreviewControls)
      ..setChromeTheme(_chromeTheme);
    if (isHarmonyOsTarget) {
      return _buildOhos(controller, allowJs: allowJs);
    }
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
        Expanded(
            child: _buildSurface(controller, card, cardTextScale,
                allowJs: allowJs)),
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

  void _scheduleBlockedJsFailure(OfficialAnkiReviewerController controller) {
    final generation = controller.presentGeneration;
    final side = controller.currentSide;
    if (_blockedJsGeneration == generation) return;
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
        generation: generation,
      );
    });
  }

  /// The OHOS error screens are full-screen over a Flutter page the learner
  /// can neither see nor reach, so a back entry is the only way out.
  ///
  /// The fallback is not optional: formal review reaches this stage through
  /// `OfficialTemplateWebViewBody`, which does not pass `onBack`. Without the
  /// fallback the button would render (it is also the visibility switch) and
  /// then do nothing — worse than not offering it.
  VoidCallback get _ohosBack =>
      widget.onBack ?? () => Navigator.of(context).maybePop();

  Widget _buildOhos(
    OfficialAnkiReviewerController controller, {
    required bool allowJs,
  }) {
    if (!allowJs) {
      _ohos?.detach(_controller);
      _ohos = null;
      _scheduleBlockedJsFailure(controller);
      // Fail-closed keeps no retry: the JS switch is a user setting, not a
      // transient failure, so re-running the same boot would fail the same
      // way. It still needs an exit.
      return Column(
        key: const Key('official-review-stage'),
        children: [
          Expanded(
            child: OfficialAnkiReviewerErrorView(
              messageKey: 'official_anki.renderer_flag_fail_closed',
              onBack: _ohosBack,
            ),
          ),
        ],
      );
    }
    _blockedJsGeneration = null;
    if (_ohos == null && !_ohosStarting && _ohosError == null && !_ohosClosed) {
      unawaited(_startOhos());
    }
    final error = _ohosError;
    return Column(
      key: const Key('official-review-stage'),
      children: [
        Expanded(
          child: error == null
              ? (_ohosClosed
                  ? const _OhosReviewerInterruptedPanel()
                  : const SizedBox.expand())
              : OfficialAnkiReviewerErrorView(
                  messageKey: 'official_anki.render_failed',
                  onRetry: () {
                    setState(() => _ohosError = null);
                    unawaited(_startOhos());
                  },
                  onBack: _ohosBack,
                ),
        ),
      ],
    );
  }

  Widget _buildSurface(OfficialAnkiReviewerController controller,
      OfficialAnkiRenderedCard? card, int cardTextScale,
      {required bool allowJs}) {
    if (!allowJs) {
      _scheduleBlockedJsFailure(controller);
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

/// Passive closing state for the OHOS branch: the native reviewer resolved
/// its open and the hosting page is settling/popping. It exists so the brief
/// moment before the pop is not an forever-spinner promising a card (B8).
class _OhosReviewerInterruptedPanel extends StatelessWidget {
  const _OhosReviewerInterruptedPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.logout_rounded, size: 40),
          const SizedBox(height: 12),
          Text(
            AppStrings.ankiReviewNativeClosed,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
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
