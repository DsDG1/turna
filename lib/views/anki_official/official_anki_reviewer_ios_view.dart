import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/render/official_anki_local_server.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/core/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// iOS reviewer surface. Renders the same bundled reviewer shell as Android,
/// served by [OfficialAnkiLocalServer] on a loopback origin instead of the
/// intercepted `https://anki.local` virtual origin. The present/ack polling
/// contract mirrors `OfficialAnkiReviewerPlatformView.kt`.
class OfficialAnkiReviewerIosView extends StatefulWidget {
  const OfficialAnkiReviewerIosView({
    super.key,
    required this.mediaRoot,
    required this.card,
    required this.showingAnswer,
    this.comparisonHtml,
    this.dark = false,
    this.textZoom = 100,
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

  /// Mirrors Android `WebSettings.textZoom` (100-200). Forwarded to the card
  /// frame as `-webkit-text-size-adjust` via the `setCard`/`setZoom` payloads.
  final int textZoom;
  final int? presentGeneration;
  final int presentEpoch;
  final VoidCallback? onReady;
  final ValueChanged<String>? onRenderError;
  final ValueChanged<OfficialAnkiPresentResult>? onRenderComplete;
  final ValueChanged<double>? onHeight;
  final OfficialAnkiPresentGate? presentGate;

  @override
  State<OfficialAnkiReviewerIosView> createState() =>
      _OfficialAnkiReviewerIosViewState();
}

class _OfficialAnkiReviewerIosViewState
    extends State<OfficialAnkiReviewerIosView> {
  static const _applyLimit = 200;
  static const _pollLimit = 400;
  static const _applyDelay = Duration(milliseconds: 50);
  static const _presentDeadline = Duration(seconds: 20);

  OfficialAnkiLocalServer? _server;
  WebViewController? _controller;

  var _readySent = false;
  var _disposed = false;
  var _applying = false;
  var _applyAttempts = 0;
  var _pollCount = 0;
  var _deadlineToken = 0;
  var _requestSeq = 0;
  int? _activeRequestId;
  Map<String, Object?>? _pendingPayload;
  var _pendingSide = 'question';
  Completer<OfficialAnkiPresentResult>? _waiting;

  var _setCardGeneration = 0;
  late final OfficialAnkiPresentGate _gate =
      widget.presentGate ?? OfficialAnkiPresentGate();
  final _deduper = OfficialAnkiPresentDeduper();

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final server = await OfficialAnkiLocalServer.start(
        mediaRoot: Directory(widget.mediaRoot),
      );
      if (_disposed || !mounted) {
        await server.dispose();
        return;
      }
      _server = server;
      final controller = WebViewController.fromPlatformCreationParams(
        WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        ),
      );
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(
        widget.dark ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.scheme == 'http' &&
                uri.host == InternetAddress.loopbackIPv4.address &&
                uri.port == server.port) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (url) {
            if (server.isShellUrl(url)) {
              _onShellFinished();
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              logger.w(
                '[OfficialAnkiReviewer] ios webview error ${error.description}',
              );
              widget.onRenderError?.call('WEBVIEW_MAIN_FRAME_ERROR');
            }
          },
        ),
      );
      await controller.loadRequest(Uri.parse(server.shellUrl));
      if (_disposed || !mounted) return;
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      logger.w(
        '[OfficialAnkiReviewer] ios boot failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        widget.onRenderError?.call('SHELL_ASSET_MISSING');
      }
    }
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiReviewerIosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (oldWidget.textZoom != widget.textZoom) {
      unawaited(_setTextZoom(widget.textZoom));
    }
    if (oldWidget.card.cardId != widget.card.cardId ||
        oldWidget.card.questionDisplayHtml != widget.card.questionDisplayHtml ||
        oldWidget.card.answerDisplayHtml != widget.card.answerDisplayHtml ||
        oldWidget.comparisonHtml != widget.comparisonHtml ||
        oldWidget.dark != widget.dark ||
        oldWidget.showingAnswer != widget.showingAnswer ||
        oldWidget.presentEpoch != widget.presentEpoch ||
        oldWidget.presentGeneration != widget.presentGeneration) {
      unawaited(_present());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _deadlineToken += 1;
    _applying = false;
    _activeRequestId = null;
    final waiting = _waiting;
    _waiting = null;
    waiting?.complete(
      const OfficialAnkiPresentResult(
        ok: false,
        code: OfficialAnkiPresentResult.supersededCode,
        recoverable: true,
      ),
    );
    unawaited(_server?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return WebViewWidget(controller: controller);
  }

  void _onShellFinished() {
    if (!_readySent) {
      _readySent = true;
      widget.onReady?.call();
      unawaited(_present());
      return;
    }
    final active = _activeRequestId;
    if (_pendingPayload != null &&
        _waiting != null &&
        active != null &&
        !_applying) {
      unawaited(_applyPending(active));
    }
  }

  Future<String> _eval(String script) async {
    final controller = _controller;
    if (controller == null || _disposed) return '';
    try {
      final raw = await controller.runJavaScriptReturningResult(script);
      var value = raw.toString();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    } catch (error) {
      logger.w('[OfficialAnkiReviewer] ios eval failed', error: error);
      return '';
    }
  }

  Future<void> _setTextZoom(int zoom) {
    return _eval(
      '(function(){ if (window.OfficialReviewer && '
      'OfficialReviewer.setTextZoom) OfficialReviewer.setTextZoom($zoom); '
      'return ""; })()',
    );
  }

  Map<String, Object?> _cardPayload(int generation) => <String, Object?>{
        'cardId': widget.card.cardId,
        'generation': generation,
        'questionDisplayHtml': widget.card.questionDisplayHtml,
        'answerDisplayHtml': widget.card.answerDisplayHtml,
        'css': widget.card.css,
        'theme': widget.dark ? 'night' : 'day',
        'comparisonHtml': widget.comparisonHtml ?? '',
        'templateOrdinal': widget.card.templateOrdinal,
        'bodyClass': widget.card.bodyClass,
        'textZoom': widget.textZoom,
      };

  Future<void> _present() async {
    if (_controller == null || _disposed) return;
    final token = widget.presentGeneration ?? ++_setCardGeneration;
    final side = widget.showingAnswer ? 'answer' : 'question';
    if (_deduper.shouldSkip(
      cardId: widget.card.cardId,
      generation: token,
      side: side,
    )) {
      return;
    }
    try {
      final result = await _gate.run(
        token,
        () => _startPresent(_cardPayload(token), side),
      );
      if (!mounted || _disposed) return;
      if (result.ok) {
        widget.onRenderComplete?.call(result);
        return;
      }
      widget.onRenderError?.call(result.code ?? 'RENDER_TIMEOUT');
    } finally {
      _deduper.markSettled();
    }
  }

  Future<OfficialAnkiPresentResult> _startPresent(
    Map<String, Object?> payload,
    String side,
  ) {
    final requestId = ++_requestSeq;
    final superseded = _waiting;
    _waiting = null;
    superseded?.complete(
      const OfficialAnkiPresentResult(
        ok: false,
        code: OfficialAnkiPresentResult.supersededCode,
        recoverable: true,
      ),
    );
    _activeRequestId = requestId;
    _pendingPayload = payload;
    _pendingSide = side;
    final completer = Completer<OfficialAnkiPresentResult>();
    _waiting = completer;
    _applyAttempts = 0;
    _pollCount = 0;
    _applying = false;
    _armDeadline(requestId);
    unawaited(_applyPending(requestId));
    return completer.future;
  }

  void _armDeadline(int requestId) {
    final token = ++_deadlineToken;
    Timer(_presentDeadline, () {
      if (token != _deadlineToken) return;
      if (_activeRequestId != requestId) return;
      _finishTimeout(requestId, 'RENDER_TIMEOUT');
    });
  }

  Future<void> _applyPending(int requestId) async {
    if (_disposed || _activeRequestId != requestId || _applying) return;
    final payload = _pendingPayload;
    if (payload == null) {
      final raw = await _eval(
        "(function(){ return window.OfficialReviewer ? 'ready' : 'not_ready'; })()",
      );
      if (_disposed || _activeRequestId != requestId) return;
      if (raw != 'ready' && _applyAttempts < _applyLimit) {
        _applyAttempts += 1;
        Timer(_applyDelay, () => _applyPending(requestId));
        return;
      }
      if (raw != 'ready') {
        _finishTimeout(requestId, 'SHELL_NOT_READY');
        return;
      }
      _finishPresent(
        requestId,
        const OfficialAnkiPresentResult(ok: true, side: 'ready'),
      );
      return;
    }
    _applying = true;
    final script =
        '(function(){ if (!window.OfficialReviewer) return "not_ready"; '
        'window.__turnaLastRender = null; '
        'OfficialReviewer.present(${jsonEncode(payload)}, '
        '${jsonEncode(_pendingSide)}); return "started"; })()';
    final raw = await _eval(script);
    if (_disposed || _activeRequestId != requestId) {
      _applying = false;
      return;
    }
    if (raw != 'started') {
      _applying = false;
      if (_applyAttempts < _applyLimit) {
        _applyAttempts += 1;
        Timer(_applyDelay, () => _applyPending(requestId));
      } else {
        _finishTimeout(requestId, 'SHELL_NOT_READY');
      }
      return;
    }
    _pollCount = 0;
    unawaited(_pollCompletion(requestId));
  }

  Future<void> _pollCompletion(int requestId) async {
    if (_disposed) {
      _applying = false;
      return;
    }
    if (_activeRequestId != requestId) {
      _applying = false;
      return;
    }
    final raw = await _eval(
      "(function(){ var a = window.__turnaLastRender; "
      "return a ? JSON.stringify(a) : ''; })()",
    );
    if (_disposed || _activeRequestId != requestId) {
      _applying = false;
      return;
    }
    if (raw.startsWith('{')) {
      Map<String, Object?>? parsed;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        parsed = null;
      }
      final type = parsed?['type'] as String? ?? '';
      if (type == 'cardAccepted' || type == 'frameReady') {
        if (_pollCount < _pollLimit) {
          _pollCount += 1;
          Timer(_applyDelay, () => _pollCompletion(requestId));
          return;
        }
      } else if (type == 'renderComplete' || type == 'renderError') {
        _applying = false;
        _completeFromJs(requestId, parsed!);
        return;
      }
    }
    if (_pollCount < _pollLimit) {
      _pollCount += 1;
      Timer(_applyDelay, () => _pollCompletion(requestId));
    } else {
      _applying = false;
      _finishTimeout(requestId, 'RENDER_TIMEOUT');
    }
  }

  void _completeFromJs(int requestId, Map<String, Object?> parsed) {
    final height = (parsed['height'] as num?)?.toDouble() ?? 0;
    final generation = (parsed['generation'] as num?)?.toInt();
    if (height > 0 &&
        generation != null &&
        _gate.shouldApplyHeight(generation, height)) {
      widget.onHeight?.call(height);
    }
    var code = parsed['stableCode'] as String? ?? '';
    if (code.isEmpty) {
      code = parsed['code'] as String? ?? '';
    }
    final type = parsed['type'] as String? ?? '';
    final ok = type == 'renderComplete';
    if (!ok) {
      widget.onRenderError?.call(code.isEmpty ? 'RENDER_TIMEOUT' : code);
    }
    final side = parsed['side'] as String? ?? '';
    _finishPresent(
      requestId,
      OfficialAnkiPresentResult(
        ok: ok,
        code: code.isEmpty ? (ok ? null : 'RENDER_TIMEOUT') : code,
        generation: generation,
        side: side.isEmpty ? _pendingSide : side,
        height: height,
      ),
    );
  }

  void _finishPresent(int requestId, OfficialAnkiPresentResult result) {
    if (_activeRequestId == requestId) {
      _activeRequestId = null;
    }
    final waiting = _waiting;
    _waiting = null;
    waiting?.complete(result);
  }

  void _finishTimeout(int requestId, String code) {
    _finishPresent(
      requestId,
      OfficialAnkiPresentResult(
        ok: false,
        code: code,
        generation: (_pendingPayload?['generation'] as num?)?.toInt(),
        side: _pendingSide,
        recoverable: true,
      ),
    );
  }
}
