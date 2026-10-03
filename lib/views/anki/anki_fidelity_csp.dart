/// Content-Security-Policy for the fidelity Anki WebView (`AnkiHtmlCardView`).
///
/// ## Why this exists
///
/// Card HTML reaching that WebView comes from user-imported decks, so the
/// notetype is attacker-controlled input. `loadHtmlString` renders it with
/// `JavaScriptMode.unrestricted`, and the `NavigationDelegate` in
/// `AnkiHtmlCardView` only intercepts **top-level navigations** — it never sees
/// subresource loads. Without a CSP a card could still pull
/// `<script src="https://…">`, `fetch`/XHR/`sendBeacon`, or an `<img>` probe
/// to phone home. The policy below is the layer that actually stops that;
/// the navigation delegate remains the second layer.
///
/// The native review path is the reference for the shape of this policy
/// (`default-src 'none'` plus `connect-src 'none'` and a request-level
/// firewall) — see `OfficialAnkiCsp.kt` / `OfficialAnkiSchemeHandler.swift`.
///
/// ## Fidelity contract
///
/// Inline scripts and inline styles keep working (deck templates rely on
/// both), local `file:` media resolves through the card's `<base href>`, and
/// `data:` media keeps working. Everything that can reach the network from a
/// subresource is denied:
///
/// - `script-src 'unsafe-inline'` — no remote script origin. A template that
///   expects a CDN MathJax will not run it; that is the accepted trade-off
///   (the native reviewer ships its own bundled mathjax assets, the fidelity
///   path does not).
/// - `connect-src 'none'` — no fetch / XHR / beacon egress.
/// - `img-src` / `media-src` / `font-src` limited to `file:` and `data:` — no
///   remote media probe (a remote `<img src>` is itself an exfiltration
///   channel because the query string can carry card data).
///
/// Relaxing any of those is a deliberate product decision, not a bug fix:
/// change the constant, update `test/views/anki/anki_fidelity_csp_test.dart`,
/// and record why in the PR.
abstract final class AnkiFidelityCsp {
  /// The policy itself. Keep the values on one line each: the test asserts
  /// per-directive, so a reformatted policy must stay greppable.
  static const String policy = "default-src 'none'; "
      "script-src 'unsafe-inline'; "
      "style-src 'unsafe-inline' file:; "
      "img-src file: data:; "
      "media-src file: data:; "
      "font-src file: data:; "
      "connect-src 'none'; "
      "object-src 'none'; "
      "form-action 'none'; "
      "frame-src 'none';";

  /// The `<meta http-equiv>` carrier. It must be the first thing in `<head>`
  /// so it governs the whole document (a CSP meta in `<body>` is ignored).
  static const String metaTag =
      '<meta http-equiv="Content-Security-Policy" content="$policy">';

  /// True when [html] already declares a CSP of its own, so re-injection
  /// cannot stack a second policy. Card authors do ship CSPs; a crafted card
  /// must not be able to make us drop ours by re-declaring, and two policies
  /// intersecting in one document is a debugging trap.
  static bool hasCspMeta(String html) =>
      _cspMetaPattern.hasMatch(html) || _cspReportOnlyPattern.hasMatch(html);

  static final RegExp _cspMetaPattern = RegExp(
      r'''<meta[^>]+http-equiv\s*=\s*["']?Content-Security-Policy["'\s>]''',
      caseSensitive: false);
  static final RegExp _cspReportOnlyPattern = RegExp(
      r'''<meta[^>]+http-equiv\s*=\s*["']?Content-Security-Policy-Report-Only''',
      caseSensitive: false);

  /// Return [html] with [metaTag] injected at the top of its `<head>`.
  ///
  /// Placement, in order of preference:
  /// 1. immediately after an opening `<head …>` (covers `<head>`,
  ///    `<head profile=…>`), so the policy precedes every author resource;
  /// 2. immediately before a closing `</head>` when the opening tag is
  ///    missing (a malformed card, not authored by us);
  /// 3. otherwise wrap the fragment in a minimal document whose `<head>` holds
  ///    the policy.
  ///
  /// A fragment with no `<head>` is wrapped rather than patched in place
  /// because a `<meta http-equiv>` that ends up in `<body>` is ignored by the
  /// HTML parser — wrapping is the only way the policy actually applies.
  static String inject(String html) {
    if (hasCspMeta(html)) return html;

    final headOpen = _headOpenPattern.firstMatch(html);
    if (headOpen != null) {
      return html.replaceRange(headOpen.end, headOpen.end, metaTag);
    }

    final headClose = _headClosePattern.firstMatch(html);
    if (headClose != null) {
      return html.replaceRange(headClose.start, headClose.start, metaTag);
    }

    return '<!DOCTYPE html><html><head>$metaTag'
        '<meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
        '</head><body>$html</body></html>';
  }

  static final RegExp _headOpenPattern =
      RegExp(r'<head\b[^>]*>', caseSensitive: false);
  static final RegExp _headClosePattern =
      RegExp(r'</\s*head\s*>', caseSensitive: false);
}
