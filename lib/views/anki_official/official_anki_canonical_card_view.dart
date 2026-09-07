import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_stage.dart';
import 'package:turna/views/theme.dart';

/// Inline interaction surface for official `canonicalLink` items — the card
/// renders inside the lesson itself instead of pushing the reviewer page.
///
/// Completion contract: the in-card continue button unlocks only after the
/// user has flipped to the answer side once. Boot/render failures stay in
/// place (retry plus a release hatch that keeps continue tappable) so the
/// lesson can never stall on a broken card. Preview only: no
/// Again/Hard/Good/Easy, official Scheduler writes stay 0.
class OfficialAnkiCanonicalCardView extends StatefulWidget {
  const OfficialAnkiCanonicalCardView({
    super.key,
    required this.contextToken,
    this.rendererAvailable = true,
    this.submitted = false,
    this.onSubmit,
    this.controller,
    this.paths,
  });

  final String contextToken;
  final bool rendererAvailable;

  /// Mirrors the lesson's [InteractionState.submitted]: after submit the
  /// auto-advance swaps this card out, but until then the button is replaced
  /// by an acknowledgement so it cannot be double-tapped.
  final bool submitted;
  final void Function(bool correct)? onSubmit;

  /// Test injection: skips boot and drives the stage directly. Inject
  /// [paths] too when the default path resolution is unavailable.
  final OfficialAnkiReviewerController? controller;
  final OfficialAnkiPaths? paths;

  @override
  State<OfficialAnkiCanonicalCardView> createState() =>
      _OfficialAnkiCanonicalCardViewState();
}

class _OfficialAnkiCanonicalCardViewState
    extends State<OfficialAnkiCanonicalCardView> {
  OfficialAnkiReviewerController? _controller;
  OfficialAnkiPaths? _paths;
  Object? _bootError;
  var _booting = true;
  var _hasSeenAnswer = false;
  var _ownsController = false;

  OfficialAnkiCanonicalRef? get _ref =>
      OfficialAnkiCourseEntry.parseCanonicalLink(widget.contextToken);

  bool get _failClosed {
    return OfficialAnkiCourseEntry.resolveCanonicalLink(
          context: widget.contextToken,
          rendererAvailable: widget.rendererAvailable,
        ) !=
        OfficialAnkiReviewTarget.officialReviewer;
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Same boot shape as [OfficialAnkiReviewerPage]: resolve paths, build the
  /// controller, load the card. Every failure becomes an in-place error view
  /// — never a pushed route.
  Future<void> _boot() async {
    final ref = _ref;
    if (ref == null || _failClosed) return;
    if (!mounted) return;
    _detachController();
    setState(() {
      _booting = true;
      _bootError = null;
    });
    try {
      final paths =
          widget.paths ?? await OfficialAnkiCourseEntry.resolveDefaultPaths();
      if (!mounted) return;
      final controller = widget.controller ??
          await createOfficialAnkiReviewerController(paths: paths);
      if (!mounted) {
        if (widget.controller == null) await controller.dispose();
        return;
      }
      _controller = controller;
      _ownsController = widget.controller == null;
      _paths = paths;
      controller.addListener(_onControllerChanged);
      await controller.loadAndShowQuestion(ref.cardId);
    } catch (error, stack) {
      debugPrint('[OfficialAnkiCanonicalCardView] boot error $error\n$stack');
      _bootError = error;
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  void _detachController() {
    final controller = _controller;
    final owned = _ownsController;
    _controller = null;
    _ownsController = false;
    _hasSeenAnswer = false;
    if (controller == null) return;
    controller.removeListener(_onControllerChanged);
    if (owned) controller.dispose();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.showingAnswer) _hasSeenAnswer = true;
    if (mounted) setState(() {});
  }

  /// Release hatch: a card that failed to boot or render must never block
  /// lesson progression — the flip requirement only applies to live cards.
  bool get _canContinue {
    if (_bootError != null) return true;
    if (_controller?.ui.isError ?? false) return true;
    return _hasSeenAnswer;
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ref;
    if (_failClosed || ref == null) {
      return const OfficialAnkiReviewerErrorView(
        key: Key('official-canonical-fail-closed'),
        messageKey: 'official_anki.renderer_flag_fail_closed',
      );
    }
    if (_booting) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final bootError = _bootError;
    if (bootError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OfficialAnkiReviewerErrorView(
            key: const Key('official-canonical-boot-failed'),
            messageKey: bootError is OfficialAnkiException
                ? bootError.messageKey
                : 'official_anki.render_failed',
            onRetry: _boot,
          ),
          _buildContinue(),
        ],
      );
    }
    final controller = _controller;
    final paths = _paths;
    if (controller == null || paths == null) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // The lesson hosts renderers under a SingleChildScrollView (unbounded
    // height), but the stage is a Column+Expanded over a platform view —
    // give it an explicit height slice of the screen.
    final stageHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(280.0, 520.0);
    return Column(
      key: const Key('official-canonical-card'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: stageHeight,
          width: double.infinity,
          child: OfficialAnkiReviewerStage(
            controller: controller,
            paths: paths,
            sourceId: ref.sourceId,
            showPreviewControls: true,
          ),
        ),
        const SizedBox(height: 12),
        _buildContinue(),
      ],
    );
  }

  Widget _buildContinue() {
    if (widget.submitted) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          AppStrings.officialAnkiCanonicalViewed,
          style: TextStyle(
            fontSize: 13,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
      );
    }
    final canContinue = _canContinue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('official-canonical-continue'),
            onPressed: canContinue ? () => widget.onSubmit?.call(true) : null,
            child: Text(AppStrings.lessonContinueUpper),
          ),
        ),
        if (!canContinue)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppStrings.officialAnkiCanonicalFlipHint,
              style: TextStyle(
                fontSize: 13,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ),
      ],
    );
  }
}
