import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

const officialAnkiReviewerViewType = 'official_anki_reviewer';

class OfficialAnkiReviewerView extends StatefulWidget {
  const OfficialAnkiReviewerView({
    super.key,
    required this.mediaRoot,
    required this.card,
    required this.showingAnswer,
    this.comparisonHtml,
    this.dark = false,
    this.presentGeneration,
    this.presentEpoch = 0,
    this.onReady,
    this.onRenderError,
    this.onRenderComplete,
    this.onHeight,
    this.presentGate,
  });

  final String mediaRoot;
  final OfficialAnkiRenderedCard card;
  final bool showingAnswer;
  final String? comparisonHtml;
  final bool dark;
  final int? presentGeneration;
  final int presentEpoch;
  final VoidCallback? onReady;
  final ValueChanged<String>? onRenderError;
  final ValueChanged<OfficialAnkiPresentResult>? onRenderComplete;
  final ValueChanged<double>? onHeight;
  final OfficialAnkiPresentGate? presentGate;

  @override
  State<OfficialAnkiReviewerView> createState() =>
      OfficialAnkiReviewerViewState();
}

class OfficialAnkiReviewerViewState extends State<OfficialAnkiReviewerView> {
  /// Isolate cache so a later reviewer State does not wait on the HCPP probe.
  static bool? _hcppCached;

  MethodChannel? _channel;
  var _setCardGeneration = 0;
  late final OfficialAnkiPresentGate _gate =
      widget.presentGate ?? OfficialAnkiPresentGate();
  final _deduper = OfficialAnkiPresentDeduper();

  /// Frozen in [initState]. Default HCPP; never flipped after the view exists.
  var _hcpp = true;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) {
      _hcpp = false;
      return;
    }
    final cached = _hcppCached;
    if (cached != null) {
      _hcpp = cached;
      return;
    }
    _hcpp = true;
    HybridAndroidViewController.checkIfSupported().then((supported) {
      _hcppCached = supported;
    });
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiReviewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_channel == null) return;
    if (oldWidget.card.cardId != widget.card.cardId ||
        oldWidget.card.questionDisplayHtml != widget.card.questionDisplayHtml ||
        oldWidget.card.answerDisplayHtml != widget.card.answerDisplayHtml ||
        oldWidget.comparisonHtml != widget.comparisonHtml ||
        oldWidget.dark != widget.dark ||
        oldWidget.showingAnswer != widget.showingAnswer ||
        oldWidget.presentEpoch != widget.presentEpoch ||
        oldWidget.presentGeneration != widget.presentGeneration) {
      _present();
    }
  }

  void _onCreated(int id) {
    _channel = MethodChannel('me.dsdogs.turna/official_anki_reviewer_$id');
    _channel!.setMethodCallHandler(_onNative);
    _present();
  }

  Future<dynamic> _onNative(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        // Shell just became ready. Re-present if the first call raced the
        // iframe/shell (deduper lets a settled generation through again).
        widget.onReady?.call();
        _present();
        return null;
      case 'pageHeightChanged':
        final height = (call.arguments as num?)?.toDouble() ?? 0;
        final generation = widget.presentGeneration ?? _setCardGeneration;
        if (_gate.shouldApplyHeight(generation, height)) {
          widget.onHeight?.call(height);
        }
        return null;
      case 'renderError':
        debugPrint('[OfficialAnkiReviewer] renderError ${call.arguments}');
        final raw = call.arguments?.toString() ?? '';
        final code = raw.isEmpty || raw == 'renderError'
            ? 'UNRENDERABLE_CARD'
            : raw;
        widget.onRenderError?.call(code);
        return null;
      default:
        return null;
    }
  }

  Future<void> _present() async {
    final channel = _channel;
    if (channel == null) return;
    final token = widget.presentGeneration ?? ++_setCardGeneration;
    if (widget.presentGeneration == null) {
      _setCardGeneration = token;
    }
    final side = widget.showingAnswer ? 'answer' : 'question';
    if (_deduper.shouldSkip(
      cardId: widget.card.cardId,
      generation: token,
      side: side,
    )) {
      return;
    }
    try {
      final result = await _gate.run(token, () async {
        try {
          final raw = await channel.invokeMethod<dynamic>('present', <String, Object?>{
            'cardId': widget.card.cardId,
            'generation': token,
            'questionDisplayHtml': widget.card.questionDisplayHtml,
            'answerDisplayHtml': widget.card.answerDisplayHtml,
            'css': widget.card.css,
            'theme': widget.dark ? 'night' : 'day',
            'comparisonHtml': widget.comparisonHtml,
            'side': side,
            'templateOrdinal': widget.card.templateOrdinal,
            'bodyClass': widget.card.bodyClass,
          });
          return OfficialAnkiPresentResult.fromNative(raw);
        } catch (error) {
          debugPrint('[OfficialAnkiReviewer] present failed $error');
          return OfficialAnkiPresentResult(
            ok: false,
            code: 'RENDER_TIMEOUT',
            generation: token,
            recoverable: true,
          );
        }
      });
      if (!mounted) return;
      if (result.ok) {
        widget.onRenderComplete?.call(result);
        return;
      }
      widget.onRenderError?.call(result.code ?? 'RENDER_TIMEOUT');
    } finally {
      _deduper.markSettled();
    }
  }

  @override
  void dispose() {
    _channel?.invokeMethod<void>('dispose');
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const OfficialAnkiReviewerErrorView(
        messageKey: 'official_anki.renderer_flag_fail_closed',
      );
    }
    final params = <String, Object?>{
      'mediaRoot': widget.mediaRoot,
      'diagnostics': kDebugMode &&
          OfficialAnkiFeatureFlags.current.reviewerDiagnostics,
    };
    return PlatformViewLink(
      viewType: officialAnkiReviewerViewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (viewParams) {
        final AndroidViewController controller = _hcpp
            ? PlatformViewsService.initHybridAndroidView(
                id: viewParams.id,
                viewType: officialAnkiReviewerViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => viewParams.onFocusChanged(true),
              )
            : PlatformViewsService.initExpensiveAndroidView(
                id: viewParams.id,
                viewType: officialAnkiReviewerViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => viewParams.onFocusChanged(true),
              );
        return controller
          ..addOnPlatformViewCreatedListener(viewParams.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onCreated)
          ..create();
      },
    );
  }
}
