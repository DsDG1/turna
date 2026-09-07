// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:webview_flutter/webview_flutter.dart';

// Project imports:
import 'package:turna/core/html_stripper.dart';

// Package imports:
import 'package:path/path.dart' as p;

/// WebView shell for a single rendered Anki card face (fidelity track,
/// deep-adaptation plan §5.2).
///
/// - Android/iOS: loads [html] in a WebView. [allowJs] gates the
///   `javascriptMode` (decision 3: default disabled; when the notetype's
///   templates contain `<script>` the policy enables JS with a
///   `NavigationDelegate` that blocks external URLs - container isolation,
///   no phoning home).
/// - Other platforms (desktop / web): degrades to a stripped-text
///   view (decision 4). A `WebViewController` is never constructed there, so
///   the missing platform implementation never throws.
///
/// Media: the HTML carries a `<base href="file:///…/">` (set by the
/// official engine's rendered-card payload) so relative `<img>` / `<audio>`
/// resolve. Full
/// file-access wiring per platform is a follow-up; the rendered text/HTML
/// content - the core fidelity goal - works via `loadHtmlString`.
class AnkiHtmlCardView extends StatefulWidget {
  final String html;
  final bool allowJs;
  final bool dark;
  final String allowedMediaBasePath;
  final bool hideEmbeddedAudioControls;

  /// Opt-in card text zoom in percent (100 = leave author CSS untouched,
  /// 150 = inject `html{zoom:1.5}`). Wired from the accessibility
  /// `cardTextScale` setting; 100% injects nothing so the default keeps the
  /// WEBVIEW-UX-2026-08 §5.3 fidelity guarantee.
  final int textZoom;

  /// True when [html] is the answer face. Gates the typing bridge: once the
  /// answer is revealed the face must stop accepting typed input.
  final bool isBack;

  /// True for a `{{type:Field}}` question face. The bridge sends input text
  /// to Flutter before the face is revealed so grading never trusts page JS.
  final bool typeAnswerEnabled;
  final ValueChanged<String>? onTypeAnswerChanged;

  /// Reports the WebView's real content height in CSS pixels, then again
  /// whenever images/fonts/MathJax resize the page. Only wired when the page
  /// already allows JavaScript ([allowJs] or a typing card) - JS-disabled
  /// cards keep their policy and never gain a bridge for measuring.
  final ValueChanged<double>? onContentHeightChanged;

  const AnkiHtmlCardView({
    super.key,
    required this.html,
    this.allowJs = false,
    this.dark = false,
    this.allowedMediaBasePath = '',
    this.hideEmbeddedAudioControls = false,
    this.textZoom = 100,
    this.isBack = false,
    this.typeAnswerEnabled = false,
    this.onTypeAnswerChanged,
    this.onContentHeightChanged,
  });

  @override
  State<AnkiHtmlCardView> createState() => AnkiHtmlCardViewState();
}

class AnkiHtmlCardViewState extends State<AnkiHtmlCardView> {
  WebViewController? _controller;
  bool _loadedIsBack = false;
  bool _pageLoading = true;
  bool _heightChannelInstalled = false;
  double? _lastReportedContentHeight;

  /// Hard cap for heights accepted from the page: large enough for any real
  /// card, small enough that a broken template cannot push nonsense into
  /// layout math.
  static const double _maxReportableContentHeight = 20000;

  /// WebView platform implementations exist only for Android/iOS. Use
  /// Flutter's target platform guard, together with [kIsWeb], so this file
  /// remains compilable for web and desktop builds. The platform test binding
  /// may override [defaultTargetPlatform], but WebView construction is still
  /// kept behind the runtime guard in production builds.
  static bool get _supported =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    if (!_supported) return;
    final c = WebViewController()
      ..setJavaScriptMode(widget.allowJs || widget.typeAnswerEnabled
          ? JavaScriptMode.unrestricted
          : JavaScriptMode.disabled);
    _controller = c;
    _loadedIsBack = widget.isBack;
    // Sync the native surface with the themed body background so face swaps
    // and dark mode never flash white.
    c.setBackgroundColor(
        widget.dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF));
    // Container isolation: allow only local/file/data/about navigations;
    // block everything else so template JS cannot phone home.
    c.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) {
        if (!mounted) return;
        setState(() {
          _pageLoading = false;
        });
        _installTypeAnswerBridge();
        _installHeightObserver();
      },
      onNavigationRequest: (req) {
        final u = req.url;
        return (_isAllowedFileUrl(u) ||
                u.startsWith('data:') ||
                u.startsWith('about:'))
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      },
    ));
    if (widget.typeAnswerEnabled) {
      c.addJavaScriptChannel(
        'ankiTypeAnswer',
        onMessageReceived: (message) {
          if (mounted) widget.onTypeAnswerChanged?.call(message.message);
        },
      );
    }
    _ensureHeightChannel();
    c.loadHtmlString(_themedHtml());
  }

  /// Register the height-reporting channel. Never called for JS-disabled
  /// cards: the channel exists only when the page already runs JavaScript,
  /// and measuring alone never flips [JavaScriptMode].
  void _ensureHeightChannel() {
    final c = _controller;
    if (c == null || _heightChannelInstalled) return;
    if (widget.onContentHeightChanged == null) return;
    if (!(widget.allowJs || widget.typeAnswerEnabled)) return;
    c.addJavaScriptChannel(
      'ankiCardHeight',
      onMessageReceived: (message) => _onHeightMessage(message.message),
    );
    _heightChannelInstalled = true;
  }

  /// Accept only finite, positive, bounded numbers from the page.
  void _onHeightMessage(String raw) {
    final callback = widget.onContentHeightChanged;
    if (callback == null) return;
    final value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite) return;
    if (value <= 0 || value > _maxReportableContentHeight) return;
    final last = _lastReportedContentHeight;
    if (last != null && (value - last).abs() < 1) return;
    _lastReportedContentHeight = value;
    callback(value);
  }

  /// Inject a self-contained height observer: measures
  /// `max(documentElement, body).scrollHeight`, then reports changes through
  /// a ResizeObserver (images, fonts, MathJax) with a ~80ms debounce.
  Future<void> _installHeightObserver() async {
    final c = _controller;
    if (c == null || widget.onContentHeightChanged == null) return;
    if (!(widget.allowJs || widget.typeAnswerEnabled)) return;
    try {
      await c.runJavaScript('''
        (function() {
          if (window.__ankiHeightWatch) return;
          window.__ankiHeightWatch = true;
          function measure() {
            var de = document.documentElement, b = document.body;
            var h = Math.max(de ? de.scrollHeight : 0, b ? b.scrollHeight : 0);
            return isFinite(h) ? h : 0;
          }
          var last = -1, timer = null;
          function report() {
            timer = null;
            var h = measure();
            if (h <= 0) return;
            if (Math.abs(h - last) < 1) return;
            last = h;
            if (window.ankiCardHeight) {
              window.ankiCardHeight.postMessage(String(Math.round(h)));
            }
          }
          function schedule() {
            if (timer == null) timer = setTimeout(report, 80);
          }
          if (typeof ResizeObserver !== 'undefined') {
            try {
              var ro = new ResizeObserver(schedule);
              if (document.documentElement) ro.observe(document.documentElement);
              if (document.body) ro.observe(document.body);
            } catch (e) {}
          }
          window.addEventListener('load', schedule);
          report();
        })();
      ''');
    } on Exception {
      // The page may have torn down its JS context; height tracking is
      // best-effort and must never break rendering.
    }
  }

  bool _isAllowedFileUrl(String rawUrl) {
    if (!rawUrl.startsWith('file://') || widget.allowedMediaBasePath.isEmpty) {
      return false;
    }
    try {
      final requested = p.normalize(Uri.parse(rawUrl).toFilePath());
      final root = p.normalize(widget.allowedMediaBasePath);
      return p.equals(requested, root) || p.isWithin(root, requested);
    } catch (suppressed) {
      debugPrint('[AnkiHtmlCardView] suppressed error: $suppressed');
      return false;
    }
  }

  Future<void> _installTypeAnswerBridge() async {
    if (!widget.typeAnswerEnabled || _controller == null || _loadedIsBack) {
      return;
    }
    try {
      await _controller!.runJavaScript('''
        (function() {
          var input = document.getElementById('typeans');
          if (!input || input.dataset.ankiBridgeInstalled === '1') return;
          input.dataset.ankiBridgeInstalled = '1';
          input.addEventListener('input', function() {
            if (window.ankiTypeAnswer) {
              window.ankiTypeAnswer.postMessage(input.value || '');
            }
          });
        })();
      ''');
    } on Exception {
      // The page can finish before the input exists on exotic templates; the
      // next load/reveal retries the bridge and the native fallback remains.
    }
  }

  /// Viewport-protection CSS appended after the notetype styles. It only
  /// constrains overflow (media, tables, long words, form controls) and never
  /// touches author-defined font, size, alignment or colors, so fidelity is
  /// preserved (WEBVIEW-UX-2026-08 §5.3). The one sanctioned exception is the
  /// opt-in card zoom layer in [_themedHtml]: when the user's cardTextScale
  /// exceeds 100% an `html{zoom:…}` rule is injected on top of this base.
  static const String _baseViewportCss =
      '*,*::before,*::after{box-sizing:border-box;}'
      'img,video,svg,canvas,audio{max-width:100%;}'
      'video{height:auto;}'
      'table{max-width:100%;display:block;overflow-x:auto;}'
      'body{overflow-wrap:break-word;}'
      'input,textarea,select,button{max-width:100%;}';

  /// The HTML with the viewport base layer plus dark-mode/hidden-audio
  /// overrides appended when needed. Notetype css targets light mode; the
  /// dark layer overrides background/text colors so fidelity cards match the
  /// app theme (deep-adaptation plan §6).
  String _themedHtml() {
    final css = StringBuffer(_baseViewportCss);
    if (widget.textZoom != 100) {
      // Opt-in magnification for card content. `zoom` (not font-size) so
      // rem/px/em and inline styles all scale; the ResizeObserver height
      // reports follow the zoomed layout automatically.
      css.write('html{zoom:${widget.textZoom / 100};}');
    }
    css.write(
        widget.dark ? ':root{color-scheme:dark;}' : ':root{color-scheme:light;}');
    if (widget.dark) {
      css.write(
        'body{background:#1e1e1e !important;color:#e0e0e0 !important;}'
        '.cloze{color:#9aa0a6 !important;}'
        'hr#answer{border-color:#444 !important;}'
        'a{color:#66d9ef !important;}',
      );
    }
    if (widget.hideEmbeddedAudioControls) {
      css.write('audio{display:none!important;}');
    }
    if (widget.html.contains('</style>')) {
      return widget.html.replaceFirst('</style>', '$css</style>');
    }
    if (widget.html.contains('</head>')) {
      return widget.html.replaceFirst('</head>', '<style>$css</style></head>');
    }
    // Fragment without a head: wrap so the protections still apply.
    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '<style>$css</style></head><body>${widget.html}</body></html>';
  }

  @override
  void didUpdateWidget(covariant AnkiHtmlCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.allowJs != widget.allowJs ||
        oldWidget.typeAnswerEnabled != widget.typeAnswerEnabled ||
        oldWidget.dark != widget.dark ||
        oldWidget.hideEmbeddedAudioControls !=
            widget.hideEmbeddedAudioControls ||
        oldWidget.allowedMediaBasePath != widget.allowedMediaBasePath ||
        oldWidget.isBack != widget.isBack ||
        oldWidget.textZoom != widget.textZoom) {
      if (_supported && _controller != null) {
        _controller!.setJavaScriptMode(
            widget.allowJs || widget.typeAnswerEnabled
                ? JavaScriptMode.unrestricted
                : JavaScriptMode.disabled);
        // Face swap: the new page reports its own height even when it equals
        // the previous one, so clear the dedupe state before reloading.
        _lastReportedContentHeight = null;
        _ensureHeightChannel();
        setState(() => _pageLoading = true);
        _controller!.loadHtmlString(_themedHtml());
        _loadedIsBack = widget.isBack;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _controller == null) {
      return _HtmlTextFallback(
        html: widget.html,
        typeAnswerEnabled: widget.typeAnswerEnabled,
        onTypeAnswerChanged: widget.onTypeAnswerChanged,
      );
    }
    // The controller instance never changes here, so height-driven rebuilds
    // resize the surface without reloading the current card.
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        // Lightweight top progress only; the previous face stays visible
        // underneath instead of being covered by a blocking spinner.
        if (_pageLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
      ],
    );
  }
}

/// Stripped-text fallback used on platforms without a WebView implementation
/// (desktop / web). Shows the card's visible text without HTML, sharing
/// [stripHtml] with the TTS pipeline so both read the same text.
class _HtmlTextFallback extends StatelessWidget {
  final String html;
  final bool typeAnswerEnabled;
  final ValueChanged<String>? onTypeAnswerChanged;

  const _HtmlTextFallback({
    required this.html,
    this.typeAnswerEnabled = false,
    this.onTypeAnswerChanged,
  });

  String get _text => stripHtml(html);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            _text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (typeAnswerEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              autocorrect: false,
              onChanged: onTypeAnswerChanged,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入答案',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
