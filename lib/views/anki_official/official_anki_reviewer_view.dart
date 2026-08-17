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
  MethodChannel? _channel;
  var _setCardGeneration = 0;
  late final OfficialAnkiPresentGate _gate =
      widget.presentGate ?? OfficialAnkiPresentGate();

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
        // Shell ready only. The initial present is sent once from _onCreated.
        widget.onReady?.call();
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
        widget.onRenderError?.call(call.arguments?.toString() ?? 'renderError');
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
          'side': widget.showingAnswer ? 'answer' : 'question',
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
    widget.onRenderError?.call(result.code ?? 'renderError');
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
      onCreatePlatformView: (paramsId) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: paramsId.id,
          viewType: officialAnkiReviewerViewType,
          layoutDirection: TextDirection.ltr,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
        );
        controller.addOnPlatformViewCreatedListener((id) {
          paramsId.onPlatformViewCreated(id);
          _onCreated(id);
        });
        return controller..create();
      },
    );
  }
}
