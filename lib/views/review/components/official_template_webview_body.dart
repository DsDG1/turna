import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_stage.dart';

/// Formal review shares the official renderer, typed-answer comparison and AV
/// pipeline with preview. Only that renderer acknowledges a presented face.
class OfficialTemplateWebViewBody extends StatefulWidget {
  const OfficialTemplateWebViewBody({
    super.key,
    required this.content,
    required this.isRevealed,
    required this.onReveal,
    this.presentation,
    this.generation = 0,
    this.onPresented,
    this.onSpeak,
    this.controller,
    this.paths,
    this.grades,
    this.onNativeReveal,
    this.onNativeRated,
    this.onNativeClosed,
    this.renderedCard,
    this.onNativeUndo,
    this.onNativeSettlement,
    this.onNativeProgress,
  });

  final OfficialTemplateContent content;
  final FidelityCardPresentation? presentation;
  final bool isRevealed;
  final VoidCallback onReveal;
  final VoidCallback? onSpeak;
  final int generation;
  final ValueChanged<PresentationReceipt>? onPresented;
  final OfficialAnkiReviewerController? controller;
  final OfficialAnkiPaths? paths;
  final OfficialAnkiCourseGradesBridge? grades;
  final VoidCallback? onNativeReveal;

  /// `true` = advanced to another card, `false` = queue finished.
  final Future<bool> Function(String rating)? onNativeRated;

  /// The OHOS ability resolved its open — see [OfficialAnkiReviewerStage].
  final void Function(String verdict)? onNativeClosed;

  /// The loader's render of this card, when the host has one (P5): adopting
  /// it skips the controller's own engine render. Must be the render of
  /// [presentation]'s card or it is ignored.
  final OfficialAnkiRenderedCard? renderedCard;

  /// OHOS header hooks — see [OfficialAnkiReviewerStage].
  final Future<void> Function()? onNativeUndo;
  final Future<Map<String, Object?>?> Function()? onNativeSettlement;
  final (int, int)? Function()? onNativeProgress;

  @override
  State<OfficialTemplateWebViewBody> createState() =>
      _OfficialTemplateWebViewBodyState();
}

class _OfficialTemplateWebViewBodyState
    extends State<OfficialTemplateWebViewBody> {
  OfficialAnkiReviewerController? _controller;
  OfficialAnkiPaths? _paths;
  Object? _error;
  int _request = 0;
  OfficialAnkiReviewerController? _changingController;
  bool _ownsController = false;
  (int, String, bool)? _lastReceipt;

  String? get _unavailable {
    if (widget.presentation == null) return 'official_anki.render_failed';
    if (widget.controller == null &&
        !Platform.isAndroid &&
        !Platform.isIOS &&
        !isHarmonyOsTarget) {
      return 'official_anki.renderer_flag_fail_closed';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant OfficialTemplateWebViewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentation?.cardKey != widget.presentation?.cardKey ||
        oldWidget.generation != widget.generation ||
        oldWidget.controller != widget.controller) {
      unawaited(_boot());
    } else if (oldWidget.isRevealed != widget.isRevealed) {
      unawaited(_syncSide());
    }
  }

  Future<void> _boot() async {
    final request = ++_request;
    _detach();
    _lastReceipt = null;
    _error = null;
    final unavailable = _unavailable;
    if (unavailable != null) {
      _report(ok: false, code: unavailable);
      return;
    }
    try {
      final paths =
          widget.paths ?? await OfficialAnkiCourseEntry.resolveDefaultPaths();
      if (!mounted || request != _request) return;
      final controller = await createOfficialAnkiReviewerController(
        paths: paths,
        controller: widget.controller,
      );
      if (!mounted || request != _request) {
        if (widget.controller == null) await controller.dispose();
        return;
      }
      _controller = controller;
      _ownsController = widget.controller == null;
      _paths = paths;
      controller.addListener(_onChanged);
      // Re-read the complete payload. Shared HTML interactions do not carry
      // typed-answer or AV metadata, which must survive formal review too.
      // When the host already holds the loader's render of THIS card, adopt
      // it (P5) — the engine already produced these exact faces for the
      // batch, and a second render only added latency to every card.
      final seed = widget.renderedCard;
      if (seed != null && seed.cardId == widget.presentation!.cardKey.cardId) {
        await controller.adoptRenderedCard(seed);
      } else {
        await controller.loadAndShowQuestion(widget.presentation!.cardKey.cardId);
      }
      if (!mounted || request != _request) return;
      await _syncSide();
    } catch (error, stack) {
      if (!mounted || request != _request) return;
      logger.w('Official formal-review renderer boot failed',
          error: error, stackTrace: stack);
      _error = error;
      _report(ok: false, code: 'official_anki.render_failed');
    } finally {
      if (mounted && request == _request) setState(() {});
    }
  }

  Future<void> _syncSide() async {
    final controller = _controller;
    if (controller == null || identical(_changingController, controller)) {
      return;
    }
    _changingController = controller;
    try {
      while (mounted &&
          identical(controller, _controller) &&
          controller.card != null &&
          controller.showingAnswer != widget.isRevealed &&
          !controller.ui.isError) {
        if (widget.isRevealed) {
          await controller.showAnswer();
        } else {
          await controller.showQuestion();
        }
      }
    } catch (error, stack) {
      logger.w('Official formal-review face change failed',
          error: error, stackTrace: stack);
      if (mounted && identical(controller, _controller)) {
        _error = error;
        _report(ok: false, code: 'official_anki.render_failed');
      }
    } finally {
      if (identical(_changingController, controller)) {
        _changingController = null;
      }
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final controller = _controller!;
    final ack = controller.lastAck;
    final side = widget.isRevealed ? 'answer' : 'question';
    if (ack != null &&
        ack.cardId == widget.presentation?.cardKey.cardId &&
        ack.generation == controller.presentGeneration &&
        ack.side == side) {
      final identity = (ack.generation, ack.side, ack.ok);
      if (identity != _lastReceipt) {
        _lastReceipt = identity;
        _report(ok: ack.ok, code: ack.code);
      }
    } else if (controller.ui.isError) {
      _report(
          ok: false,
          code: controller.error?.messageKey ?? 'official_anki.render_failed');
    }
    setState(() {});
  }

  void _report({required bool ok, String? code}) {
    final presentation = widget.presentation;
    if (presentation == null) return;
    final generation = widget.generation;
    final request = _request;
    final ack = _controller?.lastAck;
    final side =
        widget.isRevealed ? PresentationSide.answer : PresentationSide.question;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _request ||
          generation != widget.generation ||
          presentation.cardKey != widget.presentation?.cardKey ||
          side !=
              (widget.isRevealed
                  ? PresentationSide.answer
                  : PresentationSide.question)) {
        return;
      }
      if (ok && (ack == null || !identical(ack, _controller?.lastAck))) return;
      widget.onPresented?.call(PresentationReceipt(
        cardKey: presentation.cardKey,
        generation: generation,
        side: side,
        renderer: PresentationRendererKind.officialTemplate,
        presentedAt: DateTime.now(),
        ok: ok,
        code: code,
      ));
    });
  }

  void _detach() {
    final controller = _controller;
    final owned = _ownsController;
    _controller = null;
    _ownsController = false;
    _paths = null;
    if (controller == null) return;
    controller.removeListener(_onChanged);
    if (owned) {
      unawaited(controller.dispose());
    }
  }

  @override
  void dispose() {
    ++_request;
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = _unavailable;
    final error = _error;
    if (unavailable != null || error != null) {
      return OfficialAnkiReviewerErrorView(
        messageKey: unavailable ??
            (error is OfficialAnkiException
                ? error.messageKey
                : 'official_anki.render_failed'),
        onRetry: unavailable == null ? () => unawaited(_boot()) : null,
      );
    }
    final controller = _controller;
    final paths = _paths;
    if (controller == null || paths == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final forceDisableJs = context.select<SettingsProvider?, bool>(
      (settings) => settings?.ankiForceDisableJs ?? false,
    );
    return OfficialAnkiReviewerStage(
      key: ValueKey((widget.presentation!.cardKey, widget.generation)),
      controller: controller,
      allowJs: !forceDisableJs,
      paths: paths,
      sourceId: widget.presentation!.cardKey.sourceId,
      grades: widget.grades,
      onNativeReveal: widget.onNativeReveal,
      onNativeRated: widget.onNativeRated,
      onNativeClosed: widget.onNativeClosed,
      onNativeUndo: widget.onNativeUndo,
      onNativeSettlement: widget.onNativeSettlement,
      onNativeProgress: widget.onNativeProgress,
    );
  }
}
